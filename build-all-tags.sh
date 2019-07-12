#!/bin/bash

# NOTE: This script will permanently murder local changes in the mame
#       checkout it's run

shopt -s nullglob  # Do not return the glob itself if no files matches

ZTOOLDIR=$(dirname $0)

# before mame0189 there is no dist.mak
# use src/mame/machine/amiga.c{pp} as an indicator
if [ ! -f src/mame/machine/amiga.cpp -a ! -f src/mame/machine/amiga.c ]; then
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

# drop and diffs caused by applying patches
function cleanup_patches {
    if git diff-index --quiet HEAD --; then
	echo "NOTE: No git state to clean up"
    else
	echo "NOTE: Removing applied patches"
	git stash
	git stash drop
    fi
}

if [ -z "$1" ]; then
    tags="$(git tag | grep -v u | sort -r)"
else
    tags="$1"
fi

for tag in $tags; do
    disk_sentinel
    echo -en "\033[0;32m"
    echo "Checking out and building tag $tag"
    echo -en "\033[0m"
    git checkout $tag || exit 1
    git clean -dfqx # this will murder local changes
    make clean # not needed with the above, but...
    if [ ! -f dist.mak ]; then
	echo "WARNING: No dist.mak, using one based on mame0211"
	cp -v "$ZTOOLDIR/dist.mak" .
    fi
    "$ZTOOLDIR/pie-build_and_store.sh"
    cleanup_failed_builds
    cleanup_patches
done
