#!/bin/bash

# Based on ChoccyHobNob's benchmarking script
# Ref: http://web.archive.org/web/20170924001029/http://choccyhobnob.com:80/mame/benchmarks-for-mame-on-raspberry-pi/

BR='\033[0;33m'
NC='\033[0m' # No Color

TAG=0211
MAME=$(ls -d /mametest/stored-mames/pie-mame${TAG}-gcc8-*/mame)
ROMPATH=/mametest/roms
LOGFILE=logs/$(basename $(dirname $MAME))-$(date '+%Y-%m-%dT%H:%M:%S').log
mkdir -p logs

export DISPLAY=:0

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
samplerate    22000
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

# Throttling sets in at 80C, so leave at least a 15C envelope to work in
function wait_for_cooldown {
    init_cool=1
    while [ $(vcgencmd measure_temp | sed 's/temp=\(.*\)\..*/\1/') -gt 64 ]; do
	if [ $init_cool -eq 1 ]; then
	    echo -n "Waiting for CPU to cool down before next run.."
	    init_cool=0
	fi
	sleep 1
	echo -n "."
    done
    if [ $init_cool -eq 0 ]; then
	echo " OK"
    fi
}

# This might disable the the default X11 screen saver:
xset s noblank
xset s off
xset -dpms
# But this is probably the only thing useful on a "modern" desktop:
xscreensaver-command -exit

# FIXME: Before the below message can be removed and actual
# benchmarks can be done the following must be automatically
# checked:
# [ ] Make sure SDL is using hardware accel for scaling

echo "This file does not contain a valid publishable benchmark" >> $LOGFILE

# TODO: Nice things to have
# [ ] Something that reboots to clear throttle flag
# [ ] Log any sdram and GPU overclock

echo "Overclock status: $(vcgencmd get_config arm_freq)" >> $LOGFILE

cat games.lst | while read game; do
    echo -e "${BR}Starting: $game ${NC} at $(date)"
    $MAME -listfull           -rompath $ROMPATH $game >> $LOGFILE
    wait_for_cooldown
    echo "Before run: $(vcgencmd measure_temp) $(vcgencmd get_throttled)" >> $LOGFILE
    $MAME -str 90 -nothrottle -rompath $ROMPATH $game >> $LOGFILE
    wait_for_cooldown
    $MAME -bench 90           -rompath $ROMPATH $game >> $LOGFILE
    echo "After run: $(vcgencmd measure_temp) $(vcgencmd get_throttled)" >> $LOGFILE
done

# Uncomment if screensaver should be reactivated
#xscreensaver-command -restart
