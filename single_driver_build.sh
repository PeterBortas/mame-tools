#!/bin/bash

set -e
set -x

# NOTE: will not work with mame versions that require patches. If that
# becomes a requirement it should be intergrated with
# one-build-and-store

if [ -z "$1" ]; then
    echo "Usage: $0 <driver>"
    echo "  Will build single driver mame in the current git tree"
    echo 
    echo "Example: $0 pacman"
    exit 1
fi

DRIVER=$1

CFLAGS="" # Should include extra optimization flags, not actual CFLAGS

ZTOOLDIR="$(dirname $0)"
source ${ZTOOLDIR}/functions.sh
source ${ZTOOLDIR}/config.sh
CC=$COMP_CC
CXX=$COMP_CXX

VER=$(git describe --tags | sed 's/mame0\([0-9]*\)/0.\1/')
TAG=$(echo $VER | sed 's/\.//')

postfix=""
if [ $(getconf LONG_BIT) -eq 64 ]; then
    postfix=64
fi

# side effect: Sets MAME (used to extract source dependecies for driver)
set_mame_binary $TAG $GEN_BENCH_CC $CFLAGS

# TODO: make this whole file extraction in a less horrid way
FILES=$($MAME -listxml $DRIVER | grep sourcefile | grep -v CDATA | sort | uniq | sed 's/.*sourcefile=\"\([^"]*\).*/\1/')

driver_args=""
for file in $FILES; do
    if [[ $file =~ "/" ]]; then
	:
    else
	# driver file does not contain full path
	file="src/mame/drivers/$file"
    fi
    driver_args="${file},${driver_args}"
done
driver_args=$(echo "${driver_args}" | sed 's/,$//')
driver_args="SUBTARGET=${DRIVER} SOURCES=${driver_args}"

GENIE_ARGS="DEPRECATED=0 NOWERROR=1 OVERRIDE_CC=$(which $CC) OVERRIDE_CXX=$(which $CXX) $driver_args"

echo $driver_args
echo

# FIXME: probably make clean
# make clean
# FIXME: probably Add  REGENIE=1 to first make

# FIXME: Or better; write down current hash when compiling and only
#        clean up/REGENIE when the hash has changed

function needs_cleaning {
    last_hash=$(cat last_build_hash)
    cur_hash=$(git rev-parse --short HEAD)
    if [ $cur_hash != "$last_hash" ]; then
	echo $cur_hash > last_build_hash
	return 0
    fi
    return 1
}


if needs_cleaning; then
    echo "NOTE: Source has changed, cleaning up"
    make clean
    REGENIE="REGENIE=1"
fi

time make -k -j$(grep -c '^processor' /proc/cpuinfo) $GENIE_ARGS $REGENIE ||
    time make -j1 $GENIE_ARGS

mv -iv $DRIVER${postfix} $(dirname $MAME)/mame${postfix}-$DRIVER
