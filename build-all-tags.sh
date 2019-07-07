#!/bin/bash

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

for tag in $(git tag | grep -v u | sort -r); do
    disk_sentinel
    echo "Checking out and building tag $tag"
    git checkout $tag
    ../mame-tools/pie-build_and_store.sh
done
