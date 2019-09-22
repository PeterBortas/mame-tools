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

BENCHDIR=$(dirname $0)
source ${BENCHDIR}/../functions.sh

TAG=$(echo $VER | sed 's/\.//')
if [ $(getconf LONG_BIT) -eq 64 ]; then
    EXE64=64
fi
if [ VER = "git" ]; then
    MAME=$HOME/hack/mame-upstream/mame64
else
    MAME=$(ls -d /mametest/arch/$(uname -m)-$(getconf LONG_BIT)/stored-mames/mame${TAG}-gcc*-*/mame$EXE64)
fi
BASE=$(mktemp -d -t mame$TAG-$GAME-XXXXXXXXXX)

ROMPATH="$(get_mame_romdir $VER)

echo "Setting up and running in $BASE"

if [ -d initial_state/$GAME ]; then
    (cd initial_state/$GAME && tar cf - * | (cd $BASE && tar xvf -))
fi

# For testing bench
#EXTRA="-str 90 -nothrottle"
#EXTRA="-bench 90"

MAMECMD="$MAME $EXTRA \
      -window -nomax \
      -rompath $ROMPATH \
      -cfg_directory $BASE/cfg \
      -nvram_directory $BASE/nvram \
      -snapshot_directory $BASE/snap \
      -diff_directory $BASE/diff \
      $GAME"

if [ "$3" = "-strace" ]; then
    strace -e open \
	   $MAMECMD \
	   2>&1 | grep -v ENOENT | grep roms
else
    $MAMECMD
fi
