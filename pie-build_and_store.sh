#!/bin/bash

# before mame0189 there is no dist.mak
# use src/mame/machine/amiga.c{pp} as an indicator
if [ ! -f src/mame/machine/amiga.cpp -a ! -f src/mame/machine/amiga.c ]; then
    echo "FATAL: Needs to be run from mame base dir!"
    exit 1
fi

PIERAM=$(free -m | grep Mem: | awk '{print $2}')
if [ $PIERAM -lt 3500 ]; then
    if lsmod | grep zram >/dev/null 2>&1; then
	echo "NOTE: zram loaded"
    else
	echo "FATAL: zram needs to be loaded unless you have the 4G model"
	exit 1
    fi
fi

GCCVER=8

CC=gcc-$GCCVER
CXX=g++-$GCCVER

CCNAME=$(echo $CC | sed 's/\-//')
HASH=$(git rev-parse --short HEAD)
GITNAME=$(git describe --dirty)

STORENAME=pie-$GITNAME-$CCNAME-$HASH
STOREDIR=../stored-mames
ZTOOLDIR=$(dirname $0)

if [ -e $STOREDIR/$STORENAME ]; then
    echo "FATAL: $STOREDIR/$STORENAME already exists!"
    exit 1
fi

### Minimally patch old revisions to build on a modern Linux
# Example build that breaks without this: mame0176
if [ -f 3rdparty/bgfx/include/bgfx/bgfxplatform.h ]; then
    if grep 'if defined(_SDL_syswm_h) || defined(SDL_syswm_h_)' 3rdparty/bgfx/include/bgfx/bgfxplatform.h >/dev/null 2>&1; then
	:;
    else
	patch -p1 < $ZTOOLDIR/patches/buildfix-bgfx-sdlwindow.patch
    fi
fi

# dist.mak needs a static set of files, and some of them are missing
# in older mames. Create empty dummies
function fake_missing_files {
    if [ ! -f roms/dir.txt ]; then
	echo "NOTE: Faking roms/dir.txt"
	mkdir roms
	touch roms/dir.txt
    fi
    return 0
}

mkdir -p $STOREDIR
time make -k -j4 REGENIE=1 TOOLS=1 DEPRECATED=0 NOWERROR=1 OVERRIDE_CC=$(which $CC) OVERRIDE_CXX=$(which $CXX) >$STORENAME.log 2>&1 ||
    time make -j1 REGENIE=1 TOOLS=1 DEPRECATED=0 NOWERROR=1 OVERRIDE_CC=$(which $CC) OVERRIDE_CXX=$(which $CXX) >$STORENAME.log 2>&1 ||
    fake_missing_files &&
    make -f dist.mak PTR64=0 >>$STORENAME.log 2>&1 &&
    mv build/release/x32/Release/mame $STOREDIR/$STORENAME &&
    mv $STORENAME.log $STOREDIR/$STORENAME/
