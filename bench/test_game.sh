#!/bin/bash

# set -x

# Starts the game in a separate environment and copies initial state if needed

if [ -z "$1" -o -z "$2" ]; then
    echo "Usage: $0 <version> <game> [extra args for mame|-strace]"
    echo "Example: $0 0.212 sfiii"
    echo
    echo "Useful extra arguments: -v, -sdlvideofps"
    exit 1
fi

VER=$1
GAME=$2
MAMEBASE="/mametest"

CC=gcc8
CFLAGS="" # Should include extra optimization flags, not actual CFLAGS

if [ ! -z "$3" ]; then
     if [ "x$3" = x-strace ]; then
	 STRACE=1
     else
	 EXTRAARGS="$3"
     fi
fi

BENCHDIR=$(dirname $0)
source ${BENCHDIR}/../functions.sh

TAG=$(echo $VER | sed 's/\.//')

# side effect: Sets MAME
set_mame_binary $TAG $CC $CFLAGS

BASE=$(mktemp -d -t mame${TAG}-${GAME}-XXXXXXXXXX)
ROMPATH="$(get_mame_romdir $VER)"
echo "rompath = $ROMPATH"

setup_initial_state $BASE $GAME

# For testing bench
#EXTRA="-str 90 -nothrottle"
#EXTRA="-str 90 -nothrottle -video accel"
#EXTRA="-bench 90"

# If not running benchmark tests, run windowed
if [ -z "$EXTRA" ]; then
    USEWINDOW="-window -nomax"
else
    case $DISPLAY in
    localhost:*)
	if [ $(get_system_shortname) = rpi4 ]; then
	    echo "RPi4 benchmark test mode"
	    export DISPLAY=:0
	    export SDL_RENDER_DRIVER=opengles2
	fi
	;;
    *)
	echo "Non-RPi test mode"
    esac
fi

MAMECMD="$MAME $EXTRA $USEWINDOW $EXTRAARGS \
      -rompath $ROMPATH \
      -cfg_directory $BASE/cfg \
      -nvram_directory $BASE/nvram \
      -snapshot_directory $BASE/snap \
      -diff_directory $BASE/diff \
      $GAME"

if [ "x$3" = "x-strace" ]; then
    strace -e open \
	   $MAMECMD \
	   2>&1 | grep -v ENOENT | grep roms
else
    $MAMECMD
fi
