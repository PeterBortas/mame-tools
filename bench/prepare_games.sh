#!/bin/bash

BENCHDIR=$(dirname $0)
source ${BENCHDIR}/../functions.sh

if [ $(getconf LONG_BIT) -eq 64 ]; then
    EXE64=64
fi
export MAME_EXEC=$MAMEBASE/arch/$(uname -m)-$(getconf LONG_BIT)/stored-mames/mame0211-gcc8-1b969a8acb/mame$EXE64
export ROMPATH="$(get_mame_romdir 0.212)"
export PATH=~/ia-rcade:$PATH

sort gameset-*.lst | uniq > games.lst

if [ -e "$ROMPATH" ]; then
    mkdir -p /mametest/roms/internetarchive

    cat games.lst | while read game; do
	# NOTE: ia-cade does not return any error codes, so it needs manual monitoring
	ia-rcade -rompath $ROMPATH -noexecmame $game
    done
else
    echo "NOTE: Skipping rom download, $ROMPATH exists"
fi
