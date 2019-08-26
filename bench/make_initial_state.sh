#!/bin/bash

# Starts the game given as argument while pointing all config dirs to
# the initial state storage repository. Used to make calibration and
# other setups for games that need it.

if [ -z $1 ]; then
    echo "Usage: $0 <game>"
    exit 1
fi

GAME=$1

# So far always done with a 0.212 compiled from git
MAME=$HOME/hack/mame-upstream/mame64
BASE=/mametest/mame-tools/bench/initial_state/$1
mkdir -p $BASE

$MAME $EXTRA \
      -window -nomax \
      -rompath /mametest/roms/0.212 \
      -cfg_directory $BASE/cfg \
      -nvram_directory $BASE/nvram \
      -snapshot_directory $BASE/snap \
      -diff_directory $BASE/diff \
      $GAME
