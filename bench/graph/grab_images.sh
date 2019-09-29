#!/bin/bash

# Populates the output dir with a screenshot of the last frame of each
# run. Not guaranteed to be from any of the runs in the benchmark,
# just one from the correct game and Mame version

list=$1
if [ -z $list ]; then
    echo "Usage: $0 <games.lst>"
    exit 1
fi

find ../runstate/ -name final.png > snapshots.deleteme

mkdir -p output/screenshots
cat $list | while read game; do
    for ver in {175..230}; do
	image=$(grep "/$game/" snapshots.deleteme | grep mame0${ver}- | tail -1)
	if [ ! -z "$image" ]; then
	    cp -v "$image" output/screenshots/${game}-0.${ver}.png
	fi
    done
done
