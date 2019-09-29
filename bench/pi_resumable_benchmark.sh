#!/bin/bash

# Highly Raspberry Pi specific benchmarks that completes a run even if
# there is a reboot in the middle of it.

# Version of mame to benchmark (can be omitted to continue an aborted run)
VER=$1
FORCE=$2  # --force will ignore CURRENT_VERSION and not set
	  # CURRENT_VERSION, for when running on parallel nodes in the
	  # same dir.

BENCHDIR=$(dirname $0)
MAMEBASE="/mametest"
CC=gcc8
ONLYONCE=0  # should games be skipped if a benchmark already exists?
TESTREAL=0  # should the very slow real performance test be run?

LOCKFILE="/run/lock/`basename $0`"
LOCKFD=17

source ${BENCHDIR}/../functions.sh

# Avoid running multiple instances of script.
_prepare_locking
exlock_now || exit 0  # Locking cleanup is handled by a trap

# Install cronjob if missing
if crontab -l | grep pi_resumable_benchmark >/dev/null 2>&1; then
    : # cronjob already installed
else
    echo "Installing cronjob..."
    (crontab -l ; \
     echo "*/5 * * * * cd $HOME/mame-tools/bench && ./pi_resumable_benchmark.sh") | crontab -
fi

# Get Mame version to benchmark either from argv[1] or runstate/CURRENT_VERSION
# side effect; sets VER and TAG
set_mame_version $VER $FORCE

# Fail before starting to create dirs and cruft if any throttling flags have been triggered
reboot_if_throttled

if [ $(getconf LONG_BIT) -eq 64 ]; then
    EXE64=64
fi
MAME=$(ls -d $MAMEBASE/arch/$(uname -m)-$(getconf LONG_BIT)/stored-mames/mame${TAG}-$CC-*/mame$EXE64)
RUNID=$(basename $(dirname $MAME))-$(date '+%Y-%m-%dT%H:%M:%S')
LOGFILE=logs/$RUNID.log
STATEDIR=runstate/$RUNID
mkdir -p logs
mkdir -p $STATEDIR
# Redirect everything to the log file
exec >$LOGFILE 2>&1
set -x

ROMPATH=$(get_mame_romdir $VER)

export DISPLAY=:0

# SDL defaults to OpenGL renderer if it exists, but it's not
# accellerated on the Pi, force EGL. (Not tested, requires mame to
# use the render-target code)
export SDL_RENDER_DRIVER=opengles2

if $BENCHDIR/pi-bins/sdl2test-zino; then
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

turn_off_screensavers

# Make sure we don't start the test accidentally while something else is running
wait_for_load 0.5

# FIXME: Before the below message can be removed and actual
# benchmarks can be done the following must be automatically
# checked:
# [/] Make sure SDL is using hardware accel for scaling (SDL_RENDER_DRIVER _should_ do that)

# echo "This file does not contain a valid publishable benchmark" >> $LOGFILE

# TODO: Nice things to have
# [ ] Log any sdram overclock on RPi[1-3]
# [ ] -str saves the final frame in the snap dir. Do something with it

echo "ARM overclock status: $(get_freq_arm) kHz" >> $LOGFILE
echo "GPU overclock status: $(get_freq_gpu) kHz" >> $LOGFILE
echo "RAM overclock status: $(get_freq_sdram) kHz" >> $LOGFILE

GAMEARGS="-rompath $ROMPATH -cfg_directory $STATEDIR/cfg -nvram_directory $STATEDIR/nvram -snapshot_directory $STATEDIR/snap -diff_directory $STATEDIR/diff"

# Don't allow benchmarks to run for more than 10 x test time, aka 15min
TIMEOUT_WAIT=900
TIMEOUT="timeout --kill-after=5 $TIMEOUT_WAIT"

# Where needed, install game state as created by make_initial_state.sh
setup_initial_state $STATEDIR

# Randomize the order games are benchmarked to suss out thermal or
# other side effects from earlier runs.
RANDGAMELST=$(get_randomized_games)

while read -r game; do
    case $game in
    *#*)
	echo "Note: Skipping $game"
	continue
    esac
    gamelog=$(get_gamelog_name $game $CC $VER $ONLYONCE)
    if [ $? -eq 1 ]; then
	echo "NOTE: Skipping $game, $gamelog already exists"
	continue
    fi
    echo "Starting $game at $(date)"
    $MAME -listfull           $GAMEARGS $game >> $gamelog 2>&1
    write_benchmark_header $gamelog
    echo "ARM overclock status: $(get_freq_arm) kHz" >> $gamelog
    echo "GPU overclock status: $(get_freq_gpu) kHz" >> $gamelog
    echo "RAM overclock status: $(get_freq_sdram) kHz" >> $gamelog
    wait_for_cooldown
    echo "Before run: $(get_temp) $(vcgencmd get_throttled)" >> $gamelog
    if [ $TESTREAL -eq 1 ]; then
	echo "Running real emulation benchmark" >> $gamelog
	$TIMEOUT $MAME -str 90 -nothrottle $GAMEARGS $game >> $gamelog 2>&1
	check_timeout $? >> $gamelog
	wait_for_cooldown
    fi
    echo "Running built in benchmark" >> $gamelog
    $TIMEOUT $MAME -bench 90           $GAMEARGS $game >> $gamelog 2>&1
    check_timeout $? >> $gamelog
    echo "After run: $(get_temp) $(vcgencmd get_throttled)" >> $gamelog
    echo "Completed $game at $(date)"
    reboot_if_throttled
done < $RANDGAMELST

echo "Completed run of $VER-$(get_system_idname)-$CC at $(date)"

# Pull a new version from the queue and let cron take care of starting it
queue_next_version $FORCE

# Uncomment if screensaver should be reactivated
#xscreensaver-command -restart
