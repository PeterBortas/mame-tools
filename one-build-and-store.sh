#!/bin/bash

# Builds a mame "dist" in the current directory and stores it in ../stored-mames
# Usually not called manually but from build-all-tags.sh

set -x

# before mame0189 there is no dist.mak
# use src/mame/machine/amiga.c{pp} as an indicator
if [ ! -f src/mame/machine/amiga.cpp -a ! -f src/mame/machine/amiga.c ]; then
    echo "FATAL: Needs to be run from mame base dir!"
    exit 1
fi

FREERAM=$(free -m | grep Mem: | awk '{print $2}')
if [ $FREERAM -lt 3500 ]; then
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

if which $CXX && which $CC; then
    echo "NOTE: compilers exist"
else
    echo "FATAL: compilers not found"
    exit 1
fi

CCNAME=$(echo $CC | sed 's/\-//')
HASH=$(git rev-parse --short HEAD)
# GITNAME=$(git describe --dirty)
GITNAME=$(git describe --tags)

STORENAME=$GITNAME-$CCNAME-$HASH
STOREDIR=../stored-mames
ZTOOLDIR="$(dirname $0)"

case $(getconf LONG_BIT) in
    32)
	ARCHDIR=x32
	PTR64=0 ;;
    64)
	ARCHDIR=x64
	PTR64=1 ;;
    *)
	echo "FATAL: pdp11 is not supported"
	exit 1
esac

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
	patch -p1 < "$ZTOOLDIR/patches/buildfix-bgfx-sdlwindow.patch"
    fi
fi

# 0.198-199 will not build on arm, see https://github.com/mamedev/mame/issues/3639
if [ $GITNAME = mame0198 -o $GITNAME = mame0199 ]; then
    patch -p1 < "$ZTOOLDIR/patches/buildfix-multiple_inst_def_templ.patch"
fi

# dist.mak needs a static set of files, and some of them are missing
# in older mames. Create empty dummies
function fake_missing_files {
    if [ ! -f roms/dir.txt ]; then
	echo "NOTE: Faking roms/dir.txt"
	mkdir roms
	touch roms/dir.txt
    fi
    if [ ! -f uismall.bdf ]; then
	echo "WARNING: No uismall.bdf, using one based on mame0211"
	cp -v "$ZTOOLDIR/missing/uismall.bdf" .
    fi
    if [ ! -d language ]; then
	mkdir -p language
    fi
    if [ ! -f language/LICENSE ]; then
	echo "WARNING: No language/LICENSE, faking one"
	echo "Unknown, make no assumtions about how you can use or distribute these files" > language/LICENSE
    fi
    if [ ! -f language/README.md ]; then
	echo "WARNING: No language/README.md, faking one"
	echo "dummy file" > language/README.md
    fi
    return 0
}

mkdir -p ../failed-builds
if [ -d ../failed-builds/$STORENAME ]; then
    echo "WARNING: a failed build of $STORENAME already exists. Delete it if you want to rebuild."
    exit 0
fi

mkdir -p $STOREDIR
echo "Build starting on $(date)" > $STORENAME.log
time make -k -j$(grep -c '^processor' /proc/cpuinfo) REGENIE=1 TOOLS=1 DEPRECATED=0 NOWERROR=1 OVERRIDE_CC=$(which $CC) OVERRIDE_CXX=$(which $CXX) >>$STORENAME.log 2>&1 ||
    time make -j1 TOOLS=1 DEPRECATED=0 NOWERROR=1 OVERRIDE_CC=$(which $CC) OVERRIDE_CXX=$(which $CXX) >>$STORENAME.log 2>&1 &&
    fake_missing_files &&
    make -f dist.mak PTR64=$PTR64 >>$STORENAME.log 2>&1 &&
    echo "Build completed on $(date)" >>$STORENAME.log &&
    mv build/release/$ARCHDIR/Release/mame $STOREDIR/$STORENAME &&
    mv $STORENAME.log $STOREDIR/$STORENAME/ ||
	cp -a $(readlink -f ../mame) ../failed-builds/$STORENAME
