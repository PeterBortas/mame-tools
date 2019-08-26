#!/bin/bash

# Based on ChoccyHobNob's benchmarking script
# Ref: http://web.archive.org/web/20170924001029/http://choccyhobnob.com:80/mame/benchmarks-for-mame-on-raspberry-pi/

BR='\033[0;33m'
NC='\033[0m' # No Color

# Fail early if any throttling flags have been triggered
if [ $(vcgencmd get_throttled) != "throttled=0x0" ]; then
    echo "FATAL: Pi has been throttled, please restart it to reset flags"
    exit 1
fi

if [ -z $1 ]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 0.212"
    exit 1
fi

VER=$1
TAG=$(echo $VER | sed 's/\.//')
MAME=$(ls -d /mametest/stored-mames/pie-mame${TAG}-gcc8-*/mame)
RUNID=$(basename $(dirname $MAME))-$(date '+%Y-%m-%dT%H:%M:%S')
LOGFILE=logs/$RUNID.log
STATEDIR=runstate/$RUNID
mkdir -p logs
mkdir -p $STATEDIR

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

# Hardcode mame.ini
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

# X doesn't start if not connected to a screen at startup
if ! xset q >/dev/null; then
    echo "FATAL: Unable to connect to the X server"
#    exit 1
fi

# Make sure we have booted the Pie in the 640x480 benchmark resolution
# TODO: Why does this make so much differance? Scaling should be free.
# NOTE: Pie4 does not seem to support extracting the enumerated HDMI ports by name, so grep
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
# [ ] Something that reboots and resumes to clear throttle flag
# [ ] Log any sdram and GPU overclock
# [ ] Detect if the DISPLAY is forwarded. grep localhost: on $DISPLAY is probably enough
# [ ] -str saves the final frame in the snap dir. Do something with it
# [X] Clean up nvram state between runs (or make separate dirs per run (separate dirs)

echo "Overclock status: $(vcgencmd get_config arm_freq)" >> $LOGFILE

GAMEARGS="-rompath $ROMPATH -cfg_directory $STATEDIR/cfg -nvram_directory $STATEDIR/nvram -snapshot_directory $STATEDIR/snap -diff_directory $STATEDIR/diff"

# Don't allow benchmarks to run for more than 10min
TIMEOUT="timeout --kill-after=20 600"

# Some games need initial setup to not be stuck forever on some setup
# screen. These are created manually by starting the game with
# make_initial_state.sh
echo "Installing initial state in test environment..."
for x in initial_state/*; do
    echo $x...
    (cd $x && tar cf - * | (cd ../../$STATEDIR && tar xvf -))
done

cat games.lst | while read game; do
    echo -e "${BR}Starting: $game ${NC} at $(date)"
    $MAME -listfull           $GAMEARGS $game >> $LOGFILE
    wait_for_cooldown
    echo "Before run: $(get_temp) $(vcgencmd get_throttled)" >> $LOGFILE
    echo "Running real emulation benchmark" >> $LOGFILE
    $TIMEOUT $MAME -str 90 -nothrottle $GAMEARGS $game >> $LOGFILE
    wait_for_cooldown
    echo "Running built in benchmark" >> $LOGFILE
    $TIMEOUT $MAME -bench 90           $GAMEARGS $game >> $LOGFILE
    echo "After run: $(get_temp) $(vcgencmd get_throttled)" >> $LOGFILE
done

# Uncomment if screensaver should be reactivated
#xscreensaver-command -restart
