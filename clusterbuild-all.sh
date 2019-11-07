#!/bin/bash

MAMEDIR=/home/zino/mame-stuff/arch/x86_64-64/mame

tags="$(cd $MAMEDIR && git tag | sort -r)"
for tag in $tags; do
    sbatch -J $tag clusterbuild.sh $tag
done
