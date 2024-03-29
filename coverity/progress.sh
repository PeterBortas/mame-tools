#!/bin/bash

# Rough estimate of current build progress
# use "watch -n20" or so

cd $(dirname $0)

GOOD_BUILD_LINES=9765

cur_build_lines=$(tac build.log | grep -m 1 "Build started " -n | awk -F: '{print $1}')
last_line=$(tail -1 build.log)

echo "Progress: $cur_build_lines/$GOOD_BUILD_LINES"
case $last_line in
    "Build ended *")
	echo "Build completed" ;;
    *)
	echo $last_line ;;
esac
