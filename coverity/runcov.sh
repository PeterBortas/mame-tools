#!/bin/bash

echo "Build started $(date)" >> build.log
cd $(dirname $0)
./covbuild.sh >> build.log 2>&1
echo "Build ended $(date)" >> build.log
