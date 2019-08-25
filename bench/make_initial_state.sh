#!/bin/bash

# Starts the game given as argument while pointing all config difrs to
# the initial state storage repository. Used to make calibration and
# other setups for games that need it.

if [ -z $1 ]; then
    echo "Usage: $1 <game>"
fi

# So far always done with a 0.212 compiled from git
MAME=$HOME/hack/mame-upstream/mame64
BASE=/mametest/mame-tools/bench/initial_state/$1
mkdir -p $BASE

# Just for testing bench
#EXTRA="-str 90 -nothrottle"
#EXTRA="-bench 90"

$MAME $EXTRA \
      -rompath /mametest/roms/0.212 \
      -cfg_directory $BASE/cfg \
      -nvram_directory $BASE/nvram \
      -snapshot_directory $BASE/snap \
      -diff_directory $BASE/diff $1


#/mametest/stored-mames/pie-mame0212-gcc8-1182bd9325/mame -str 90 -nothrottle -rompath /mametest/roms/0.212 -cfg_directory runstate/pie-mame0212-gcc8-1182bd9325-2019-08-25T06:25:46/cfg -nvram_directory runstate/pie-mame0212-gcc8-1182bd9325-2019-08-25T06:25:46/nvram -snapshot_directory runstate/pie-mame0212-gcc8-1182bd9325-2019-08-25T06:25:46/snap -diff_directory runstate/pie-mame0212-gcc8-1182bd9325-2019-08-25T06:25:46/diff 1943
#/mametest/stored-mames/pie-mame0212-gcc8-1182bd9325/mame -bench 90 -rompath /mametest/roms/0.212 -cfg_directory runstate/pie-mame0212-gcc8-1182bd9325-2019-08-25T06:25:46/cfg -nvram_directory runstate/pie-mame0212-gcc8-1182bd9325-2019-08-25T06:25:46/nvram -snapshot_directory runstate/pie-mame0212-gcc8-1182bd9325-2019-08-25T06:25:46/snap -diff_directory runstate/pie-mame0212-gcc8-1182bd9325-2019-08-25T06:25:46/diff 1943
