#!/bin/bash

cd $(dirname $0)

echo "Build started $(date)" >> build.log
./covbuild.sh                >> build.log 2>&1
echo "Build ended $(date)"   >> build.log
