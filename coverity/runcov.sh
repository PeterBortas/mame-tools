#!/bin/bash

cd $(dirname $0)
mkdir -p oldlogs

# FIXME: This needs a lock, the log will be moved under any running
# build, and they don't keep an fd
if [ -f build.log ]; then
    mv -v build.log oldlogs/build.log.$(date --iso-8601=seconds)
fi

echo "Build started $(date)" >> build.log
./covbuild.sh                >> build.log 2>&1
echo "Build ended $(date)"   >> build.log
