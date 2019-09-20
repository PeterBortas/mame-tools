#!/bin/bash

# Benchmarks whatever needs benchmarking continues to do so even if there is a reboot.

BENCHDIR=$(dirname $0)

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
exlock_now || exit 0  # Locking cleanup is handled by a trap

# Install cronjob if missing
if crontab -l | grep resumable_benchmark >/dev/null 2>&1; then
    : # cronjob already installed
else
    echo "Installing cronjob..."
    (crontab -l ; \
     echo "*/5 * * * * cd $HOME/mame-tools/bench && ./resumable_benchmark.sh") | crontab -
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
	exit 1 # reboot does not block
    fi
}

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
if [ $(getconf LONG_BIT) -eq 64 ]; then
    EXE64=64
fi
MAME=$(ls -d /mametest/arch/$(uname -m)-$(getconf LONG_BIT)/stored-mames/mame${TAG}-$CC-*/mame$EXE64)
RUNID=$(basename $(dirname $MAME))-$(date '+%Y-%m-%dT%H:%M:%S')
LOGFILE=logs/$RUNID.log
STATEDIR=runstate/$RUNID
mkdir -p logs
mkdir -p $STATEDIR
# Redirect everything to the log file
exec >$LOGFILE 2>&1
set -x

ROMPATH=/mametest/roms/internetarchive
if [ -e /mametest/roms/0.212 ]; then
    ROMPATH=/mametest/roms/0.212
fi
if [ -e /mametest/roms/$VER ]; then
    ROMPATH=/mametest/roms/$VER
fi

export DISPLAY=:0

# SDL defaults to OpenGL renderer if it exists, but it's not
# accellerated on the Pi, force EGL. (Not tested, requires mame to
# use the render-target code)
export SDL_RENDER_DRIVER=opengles2

if $BENCHDIR/sdl2test-zino; then
    : # echo "NOTE: Renderer tested OK"
else
    echo "FATAL: Renderer not available"
    exit 1
fi

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
if [ $(/sbin/swapon | wc -l) -gt 0 ]; then
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
# [ ] Log any sdram and GPU overclock
# [ ] -str saves the final frame in the snap dir. Do something with it

FREQ=$(vcgencmd get_config arm_freq | awk -F= '{print $2}')
echo "ARM overclock status: $(vcgencmd get_config arm_freq) kHz" >> $LOGFILE

GAMEARGS="-rompath $ROMPATH -cfg_directory $STATEDIR/cfg -nvram_directory $STATEDIR/nvram -snapshot_directory $STATEDIR/snap -diff_directory $STATEDIR/diff"

# Don't allow benchmarks to run for more than 10 x test time, aka 15min
TIMEOUT_WAIT=900
TIMEOUT="timeout --kill-after=5 $TIMEOUT_WAIT"

# Some games need initial setup to not be stuck forever on some setup
# screen. These are created manually by starting the game with
# make_initial_state.sh
echo "Installing initial state in test environment..."
for x in initial_state/*; do
    echo $x...
    (cd $x && tar cf - * | (cd ../../$STATEDIR && tar xvf -))
done

mkdir -p runstate/gameresults

while read -r game; do
    case $game in
    *#*)
	echo "Note: Skipping $game"
	continue
    esac
    gamelog=runstate/gameresults/$game-$VER-$FREQ-$CC.result
    if [ -f $gamelog ]; then
	echo "NOTE: Skipping $game, $gamelog already exists"
	continue
    fi
    echo "Starting $game at $(date)"
    $MAME -listfull           $GAMEARGS $game >> $gamelog 2>&1
    wait_for_cooldown
    echo "Before run: $(get_temp) $(vcgencmd get_throttled)" >> $gamelog
    echo "Running real emulation benchmark" >> $gamelog
    $TIMEOUT $MAME -str 90 -nothrottle $GAMEARGS $game >> $gamelog 2>&1
    if [ $? -eq 124 ]; then
	echo "Timed out after ${TIMEOUT_WAIT}s" >> $gamelog
    fi
    wait_for_cooldown
    echo "Running built in benchmark" >> $gamelog
    $TIMEOUT $MAME -bench 90           $GAMEARGS $game >> $gamelog 2>&1
    echo "After run: $(get_temp) $(vcgencmd get_throttled)" >> $gamelog
    if [ $? -eq 124 ]; then
	echo "Timed out after ${TIMEOUT_WAIT}s" >> $gamelog
    fi
    echo "Completed $game at $(date)"
    reboot_if_throttled
done < games.lst

echo "Completed run of $VER-$FREQ-$CC at $(date), removing from automatic queue"
rm runstate/CURRENT_VERSION

# Pull a new version from the queue and let cron take care of starting it
while read -r x; do
    case $x in
    0.[0-9]*)
	echo "Queueing up $x"
	echo $x > runstate/CURRENT_VERSION
	sed -i 's/'$x'//' runstate/queue
	exit 0
	;;
    esac
done < runstate/queue

# Uncomment if screensaver should be reactivated
#xscreensaver-command -restart
