#!/bin/bash

# Benchmarks whatever needs benchmarking continues to do so even if there is a reboot.

LOCKFILE="/run/lock/`basename $0`"
LOCKFD=17

# PRIVATE
_lock()             { flock -$1 $LOCKFD; }
_no_more_locking()  { _lock u; _lock xn && rm -f $LOCKFILE; }
_prepare_locking()  { eval "exec $LOCKFD>\"$LOCKFILE\""; trap _no_more_locking EXIT; }

# PUBLIC
exlock_now()        { _lock xn; }  # obtain an exclusive lock immediately or fail
unlock()            { _lock u; }   # drop a lock

# Avoid running multiple instances of script.
_prepare_locking
exlock_now || exit 0

# Install cronjob if missing
if crontab -l | grep resumable_benchmark >/dev/null 1>&2; then
    : # cronjob already installed
else
    echo "Installing cronjob..."
    (crontab -l ; \
     echo "*/10 * * * * cd $HOME/mame-tools/bench && ./resumable_benchmark.sh") | crontab -
fi

function was_throttled {
    if [ $(vcgencmd get_throttled) != "throttled=0x0" ]; then
	true
    else
	false
    fi
}

function reboot_if_throttled {
    if was_throttled; then
	echo "FATAL: Pi has been throttled, will reboot at $(date)" >> runstate/reboot.log
	./parse_throttle.py >> runstate/reboot.log
	sudo reboot
    fi
}

#TODO: use an external queue for versions
if [ -z $1 ]; then
    if [ ! -f runstate/CURRENT_VERSION ]; then
	echo "Usage: $0 <version>"
	echo "Example: $0 0.212"
	exit 1
    else
	VER=$(cat runstate/CURRENT_VERSION)
    fi
else
    if [ -f runstate/CURRENT_VERSION ]; then
	echo "FATAL: There is already an automatic benchmark of $(cat runstate/CURRENT_VERSION) in progress!"
	exit 1
    else
	VER=$1
	echo $VER > runstate/CURRENT_VERSION
    fi
fi

# Fail before starting to create dirs and cruft if any throttling flags have been triggered
reboot_if_throttled

TAG=$(echo $VER | sed 's/\.//')
CC=gcc8
MAME=$(ls -d /mametest/stored-mames/pie-mame${TAG}-$CC-*/mame)
RUNID=$(basename $(dirname $MAME))-$(date '+%Y-%m-%dT%H:%M:%S')
LOGFILE=logs/$RUNID.log
STATEDIR=runstate/$RUNID
# Redirect everything to the log file
mkdir -p logs
mkdir -p $STATEDIR
exec >$LOGFILE 2>&1

ROMPATH=/mametest/roms/internetarchive
if [ -e /mametest/roms/0.212 ]; then
    ROMPATH=/mametest/roms/0.212
fi
if [ -e /mametest/roms/$VER ]; then
    ROMPATH=/mametest/roms/$VER
fi

export DISPLAY=:0

# SDL defaults to OpenGL renderer if it exists, but it's not
# accellerated on the Pie, force EGL. (Not tested, requires mame to
# use the render-target code)
export SDL_RENDER_DRIVER=opengles2

# Hardcode mame.ini, verified to be picked up even if -cfg_directory is used
# Note: All the artwork options are probably useless in ~0.212+
cat > ~/.mame/mame.ini <<EOF
#
# CORE ARTWORK OPTIONS
#
artwork_crop  0
use_backdrops 0
use_overlays  0
use_bezels    0
use_cpanels   0
use_marquees  0
#
# CORE SOUND OPTIONS
#
samplerate    22050
#
# OSD ACCELERATED VIDEO OPTIONS
#
filter        0
EOF

# X doesn't start if not connected to a screen at startup, can be
# worked around by hardcoding setup in /boot/config.txt
if ! xset q >/dev/null; then
    echo "FATAL: Unable to connect to the X server"
    exit 1
fi

# Make sure we have booted the RPi in the 640x480 benchmark resolution
# TODO: Why does this make so much differance? Scaling should be free.
# NOTE: RPi4 does not seem to support extracting the enumerated HDMI ports by name, so grep
if [ "$(sudo vcgencmd get_config int | grep hdmi_group)" != "hdmi_group:0=2" ]; then
    echo "FATAL: hdmi_group != 2"
    exit 1
fi
if [ "$(sudo vcgencmd get_config int | grep hdmi_mod)" != "hdmi_mode:0=4" ]; then
    echo "FATAL: hdmi_group != 2"
    exit 1
fi

# Avoid variability due to SD card swapping or zram overhead
if [ $(swapon | wc -l) -gt 0 ]; then
    echo "FATAL: swap is enabled"
    exit 1
fi

# This might disable the the default X11 screen saver:
xset s noblank
xset s off
xset -dpms
# But this is probably the only thing useful on a "modern" desktop:
xscreensaver-command -exit

# Make sure we don't start the test accidentally while something else is running
init_load=1
while (( $(echo "$(awk '{print $1}' /proc/loadavg) > 0.5" |bc -l) )); do
    if [ $init_load -eq 1 ]; then
	echo -n "Waiting for load to go down before starting test.."
	init_load=0
    fi
    sleep 2
    echo -n "."
done
if [ $init_load -eq 0 ]; then
    echo " OK"
fi

function get_temp {
    vcgencmd measure_temp | sed 's/temp=\(.*\)\..*/\1/'
}

# Throttling sets in at 80C, so leave at least a 15C envelope to work in
function wait_for_cooldown {
    init_cool=1
    while [ $(get_temp) -gt 64 ]; do
	if [ $init_cool -eq 1 ]; then
	    echo "Waiting for CPU to cool down before next run..."
	    init_cool=0
	fi
	sleep 1
	echo -ne "$(get_temp)C  \r"
    done
    echo
    if [ $init_cool -eq 0 ]; then
	echo " OK"
    fi
}

# FIXME: Before the below message can be removed and actual
# benchmarks can be done the following must be automatically
# checked:
# [/] Make sure SDL is using hardware accel for scaling (SDL_RENDER_DRIVER _should_ do that)

# echo "This file does not contain a valid publishable benchmark" >> $LOGFILE

# TODO: Nice things to have
# [/] Something that reboots and resumes to clear throttle flag
# [ ] Log any sdram and GPU overclock
# [ ] -str saves the final frame in the snap dir. Do something with it
# [X] Clean up nvram state between runs (or make separate dirs per run (separate dirs)

FREQ=$(vcgencmd get_config arm_freq | awk -F= '{print $2}')
echo "ARM overclock status: $(vcgencmd get_config arm_freq) kHz" >> $LOGFILE

GAMEARGS="-rompath $ROMPATH -cfg_directory $STATEDIR/cfg -nvram_directory $STATEDIR/nvram -snapshot_directory $STATEDIR/snap -diff_directory $STATEDIR/diff"

# Don't allow benchmarks to run for more than 10 x test time, aka 15min
TIMEOUT="timeout --kill-after=20 900"

# Some games need initial setup to not be stuck forever on some setup
# screen. These are created manually by starting the game with
# make_initial_state.sh
echo "Installing initial state in test environment..."
for x in initial_state/*; do
    echo $x...
    (cd $x && tar cf - * | (cd ../../$STATEDIR && tar xvf -))
done

mkdir -p runstate/gameresults

cat games.lst | while read game; do
    gamelog=runstate/gameresults/$game-$VER-$FREQ-$CC.result
    if [ -f $gamelog ]; then
	echo "NOTE: Skipping $game, $gamelog already exists"
	continue
    fi
    echo "Starting: $game at $(date)"
    $MAME -listfull           $GAMEARGS $game >> $gamelog 2>&1
    wait_for_cooldown
    echo "Before run: $(get_temp) $(vcgencmd get_throttled)" >> $gamelog
    echo "Running real emulation benchmark" >> $gamelog
    $TIMEOUT $MAME -str 90 -nothrottle $GAMEARGS $game >> $gamelog 2>&1
    wait_for_cooldown
    echo "Running built in benchmark" >> $gamelog
    $TIMEOUT $MAME -bench 90           $GAMEARGS $game >> $gamelog 2>&1
    echo "After run: $(get_temp) $(vcgencmd get_throttled)" >> $gamelog
    echo "Completed: $game at $(date)"
    reboot_if_throttled
done

echo "Completed run of $VER-$FREQ-$CC at $(date), removing from automatic queue"
#TODO: pull next version from queue here and restart with that
rm runstate/CURRENT_VERSION

# Uncomment if screensaver should be reactivated
#xscreensaver-command -restart
