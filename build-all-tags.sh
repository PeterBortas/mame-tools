#!/bin/bash

# NOTE: This script will permanently murder local changes in the mame
#       checkout it's run

set -x
shopt -s nullglob  # Do not return the glob itself if no files matches

if [ ! -f dist.mak ]; then
    echo "FATAL: Needs to be run from mame base dir!"
    exit 1
fi

function disk_sentinel {
    avail=$(df . | awk 'NR==2 { print $4 }')
    if (( avail < 4000000 )); then
	echo "FATAL: Not anoung space available!"
	exit 1
    fi
}

function cleanup_failed_builds {
    for x in pie-mame0*.log; do
	mkdir ../stored-mames/$(echo $x | sed 's/\.log//') &&
	    mv -iv $x ../stored-mames/$(echo $x | sed 's/\.log//')/;
    done
}

for tag in $(git tag | grep -v u | sort -r); do
    disk_sentinel
    echo "Checking out and building tag $tag"
    git checkout $tag || exit 1
    git clean -dfqx # this will murder local changes
    make clean # not needed with the above, but...
    ../mame-tools/pie-build_and_store.sh
    cleanup_failed_builds
done
