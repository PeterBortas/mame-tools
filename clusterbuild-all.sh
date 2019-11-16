#!/bin/bash

MAMEDIR=/home/zino/mame-stuff/arch/x86_64-64/mame

tags="$(cd $MAMEDIR && git tag | sort -r)"
for tag in $tags; do
    case $tag in
	mame01*|mame020[0-1])
	    echo Skipping $tag; continue ;;
    esac
    sbatch -J $tag clusterbuild.sh $tag
done
