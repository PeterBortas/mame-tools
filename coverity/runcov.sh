#!/bin/bash

echo "Build started $(date)" >> mame.log
cd $(dirname $0)
./covbuild.sh >> mame.log 2>&1
echo "Build ended $(date)" >> mame.log
