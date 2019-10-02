#!/bin/bash

# set -x

# Starts the game in a separate environment and copies initial state if needed

if [ -z $1 -o -z $2 ]; then
    echo "Usage: $0 <version> <game> [extra args for mame|-strace]"
    echo "Example: $0 0.212 sfiii"
    echo "Note: If version is set to git, $HOME/hack/mame-upstream/mame64 will be used"
    exit 1
fi

VER=$1
GAME=$2
MAMEBASE="/mametest"

if [ ! -z $3 ]; then
     if [ x$3 = x-strace ]; then
	 STRACE=1
     else
	 EXTRAARGS="$3"
     fi
fi

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

ROMPATH="$(get_mame_romdir $VER)"
echo "rompath = $ROMPATH"

echo "Setting up and running in $BASE"

if [ -d initial_state/$GAME ]; then
    (cd initial_state/$GAME && tar cf - * | (cd $BASE && tar xvf -))
fi

# For testing bench
#EXTRA="-str 90 -nothrottle"
#EXTRA="-str 90 -nothrottle -video accel"
#EXTRA="-bench 90"
#export DISPLAY=:0
#unset SDL_RENDER_DRIVER
#export SDL_RENDER_DRIVER=opengles2

# If not running benchmark tests, run windowed
if [ -z $EXTRA ]; then
    USEWINDOW="-window -nomax"
fi

MAMECMD="$MAME $EXTRA $USEWINDOW $EXTRAARGS\
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
