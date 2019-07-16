#!/bin/bash

export MAME_EXEC=/mametest/stored-mames/pie-mame0211-gcc8-1b969a8acb/mame
export ROMPATH=/mametest/roms
export PATH=~/ia-rcade:$PATH

sort gameset-*.lst | uniq > games.lst

cat games.lst | while read game; do
    # NOTE: ia-cade does not return any error codes, so it needs manual monitoring
    ia-rcade -rompath $ROMPATH -noexecmame $game
done
