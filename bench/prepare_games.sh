#!/bin/bash

if [ $(getconf LONG_BIT) -eq 64 ]; then
    EXE64=64
fi
export MAME_EXEC=/mametest/arch/$(uname -m)-$(getconf LONG_BIT)/stored-mames/mame0211-gcc8-1b969a8acb/mame$EXE64
export ROMPATH=/mametest/roms/internetarchive
export PATH=~/ia-rcade:$PATH

mkdir -p /mametest/roms/internetarchive

sort gameset-*.lst | uniq > games.lst

cat games.lst | while read game; do
    # NOTE: ia-cade does not return any error codes, so it needs manual monitoring
    ia-rcade -rompath $ROMPATH -noexecmame $game
done
