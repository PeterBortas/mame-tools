#!/bin/bash

# Based on ChoccyHobNob's benchmarking script
# Ref: http://web.archive.org/web/20170924001029/http://choccyhobnob.com:80/mame/benchmarks-for-mame-on-raspberry-pi/

set -x

BR='\033[0;33m'
NC='\033[0m' # No Color

TAG=0211
MAME=$(ls -d /mametest/stored-mames/pie-mame${TAG}-gcc8-*/mame)
ROMPATH=/mametest/roms
LOGFILE=logs/$(basename $(dirname $MAME)).log
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

# This might disable the screen saver but will not turn it off if already running
xset s noblank
xset s off
xset -dpms
# But this is probably the only thing useful on a "modern" desktop:
xscreensaver-command -exit

cat games.lst | while read game; do
    echo -e "${BR}Starting: $game ${NC} at $(date)"
    # FIXME: Before the below message can be removed and actual
    # benchmarks can be done the following must be automatically
    # checked:
    # [ ] all swap should be turned off (including zram)  FATAL
    # [ ] load should be below 1                          FATAL
    # [X] Verify screen resolution                        FATAL
    # [ ] Temperature should be 65(?) or lower            busywait
    # [ ] Temperature should be meassured at least before and after
    # [ ] throttling indicator should be monitored (later make something that reboots to clear the flag)
    # [X] Make sure the screensaver is disabled
    # [ ] Make sure SDL is using hardware accel for scaling
    echo "This file does not contain a valid publishable benchmark" >> $LOGFILE
    $MAME -listfull           -rompath $ROMPATH $game >> $LOGFILE
    $MAME -str 90 -nothrottle -rompath $ROMPATH $game >> $LOGFILE
    $MAME -bench 90           -rompath $ROMPATH $game >> $LOGFILE
done

# Uncomment if screensaver should be reactivated
#xscreensaver-command -restart
