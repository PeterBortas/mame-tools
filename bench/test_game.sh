#!/bin/bash

set -x

# Starts the game in a separate environment and copies initial state if needed

if [ -z $1 -o -z $2 ]; then
    echo "Usage: $0 <version> <game>"
    echo "Example: $0 0.212 sfiii"
    echo "Note: If version is set to git, $HOME/hack/mame-upstream/mame64 will be used"
    exit 1
fi

VER=$1
GAME=$2


TAG=$(echo $VER | sed 's/\.//')
if [ $(getconf LONG_BIT) -eq 64 ]; then
    EXE64=64
fi
if [ VER = "git" ]; then
    MAME=$HOME/hack/mame-upstream/mame64
else
    MAME=$(ls -d /mametest/arch/$(uname -m)-$(getconf LONG_BIT)/stored-mames/mame${TAG}-gcc8-*/mame$EXE64)
fi
BASE=$(mktemp -d -t mame$TAG-$GAME-XXXXXXXXXX)

echo "Setting up and running in $BASE"

if [ -d initial_state/$GAME ]; then
    (cd initial_state/$GAME && tar cf - * | (cd $BASE && tar xvf -))
fi

# For testing bench
#EXTRA="-str 90 -nothrottle"
#EXTRA="-bench 90"

$MAME $EXTRA \
      -window -nomax \
      -rompath /mametest/roms/0.212 \
      -cfg_directory $BASE/cfg \
      -nvram_directory $BASE/nvram \
      -snapshot_directory $BASE/snap \
      -diff_directory $BASE/diff \
      $GAME
