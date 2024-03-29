#!/bin/bash

set -e

# FIXME: needlessly hardcoded in general

arch=xeon_e5_2660
gamelist=../games-all.lst
mkdir -p output

MYDIR=$(dirname $0)
source ${MYDIR}/../../config.sh
source ${MYDIR}/../../analysator-env.sh # all this to be able to run mame to get driver names

# make a graph page combining all games for each optimization type
for opts in "" Os O4marchnativefomitframepointer; do
    echo "Creating combined graph for $arch $opts"
    ./create_graph.pike $gamelist $arch $opts
done

# make a separate graph page for each game comparing diffrent compiler
# versions also makes an index page
# FIXME: Will create broken pages for games missing results and link them in the index
# TODO: Make arrows to rump beween results for easy navigation

echo "Generating individual pages per game:"

indexpage=output/cc-compare-$arch.html

echo "<h3>game specific graphs comparing compilers and compiler options</h3>" > $indexpage
echo "<ul>" >> $indexpage

while read -r game; do
    case $game in
    *#*)
	echo "Note: Skipping $game"
	continue
    esac
    link=${arch}-gcc8-${game}-bench.html
    ./opt_create_graph.pike $game $arch &&
        echo "<li><a href=$link>$game</a>" >> $indexpage
done < $gamelist

echo "</ul>" >> $indexpage
