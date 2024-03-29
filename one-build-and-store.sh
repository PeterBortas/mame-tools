#!/bin/bash

# Builds a mame "dist" in the current directory and stores it in ../stored-mames
# Usually not called manually but from build-all-tags.sh

set -x

ZTOOLDIR="$(dirname $0)"
source ${ZTOOLDIR}/functions.sh
source ${ZTOOLDIR}/config.sh
CC=$COMP_CC
CXX=$COMP_CXX
OPT_ID=$(get_optimization_id)
if [ ! -z $COMP_OPTIMIZE ]; then
    GENIE_OPTIMIZE="OPTIMIZE=$COMP_OPTIMIZE"
fi

# Bail if CWD isn't a mame git checkout
verify_mame_checkout

# If < 4G RAM, require zram to be used
verify_ram_size

if which $CXX && which $CC; then
    echo "NOTE: compilers exist"
else
    echo "FATAL: compilers not found"
    exit 1
fi

CCNAME=$(echo $CC | sed 's/\-//')
HASH=$(git rev-parse --short HEAD)
GITNAME=$(git describe --tags)

STORENAME=$GITNAME-$CCNAME-$HASH
if [ ! -z $OPT_ID ]; then
    STORENAME=$STORENAME-$OPT_ID
fi
STOREDIR=../stored-mames
VERSION=$(echo $GITNAME | sed 's/mame0\([0-9]*\).*/\1/')

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

# Make sure we have a dist.mak before starting so we don't fail after
# all that compiling
if [ ! -f dist.mak ]; then
    echo "FATAL: Missing dist.mak"
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

# Pre mame0149 will fail due to missing -lpthread in the final linking stage
if [ $VERSION -gt 146 -a $VERSION -lt 149 ]; then
    patch -p1 < "$ZTOOLDIR/patches/buildfix-pthread.patch"
fi
if [ $VERSION -gt 144 -a $VERSION -lt 147 ]; then
    patch -p1 < "$ZTOOLDIR/patches/buildfix-pthread-older.patch"
fi
if [ $VERSION -eq 144 ]; then
    patch -p1 < "$ZTOOLDIR/patches/buildfix-pthread-older2.patch"
fi
#if [ $VERSION -gt 139 -a $VERSION -lt 144 ]; then
#    patch -p1 < "$ZTOOLDIR/patches/buildfix-pthread-older3.patch"
#fi
# generic patch that should work better
if [ $VERSION -gt 136 -a $VERSION -lt 145 ]; then
    patch -p1 < "$ZTOOLDIR/patches/buildfix-pthread-older4.patch"
fi
# NOTE: sdl.mak does not exist in mame0136

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
    for tool in castool chdman floptool imgtool jedutil ldresample ldverify nltool nlwav romcmp unidasm; do
	if [ ! -f $tool ]; then
	    echo "WARNING: No $tool, faking one"
	    touch $tool
	fi
    done
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

echo "Reinit log" > $STORENAME.log
failed=0
GENIE_ARGS="TOOLS=1 DEPRECATED=0 NOWERROR=1 OVERRIDE_CC=$(which $CC) OVERRIDE_CXX=$(which $CXX) $GENIE_OPTIMIZE"

echo $GENIE_ARGS
echo $COMP_ARCHOPTS

# NOTE: tags older than mame0162 has a separate "mess" target
# NOTE: tags older than mame0147 has mess in a separate mess repo
# TODO: build mess from separate repo
if [ $VERSION -lt 162 -a $VERSION -gt 146 ]; then
    echo "mess build starting on $(date)" >> $STORENAME.log
    (time make -k -j$(grep -c '^processor' /proc/cpuinfo) REGENIE=1 $GENIE_ARGS ARCHOPTS="$COMP_ARCHOPTS" TARGET=mess >>$STORENAME.log 2>&1 ||
	 time make -j1 $GENIE_ARGS TARGET=mess >>$STORENAME.log 2>&1) \
	     || failed="mess"
fi

if [ $failed = 0 ]; then
    mkdir -p $STOREDIR
    echo "mame build starting on $(date)" >> $STORENAME.log
    time make -k -j$(grep -c '^processor' /proc/cpuinfo) REGENIE=1 $GENIE_ARGS ARCHOPTS="$COMP_ARCHOPTS" >>$STORENAME.log 2>&1 ||
	time make -j1 $GENIE_ARGS >>$STORENAME.log 2>&1 &&
	fake_missing_files &&
	make -f dist.mak PTR64=$PTR64 >>$STORENAME.log 2>&1 &&
	echo "Build completed on $(date)" >>$STORENAME.log &&
	mv build/release/$ARCHDIR/Release/mame $STOREDIR/$STORENAME \
	    || failed="mame"
fi

if [ $failed = 0 ]; then
    if [ $VERSION -lt 162 -a $VERSION -gt 146 ]; then
	cp mess$(getconf LONG_BIT) $STOREDIR/$STORENAME/
	touch BUILT_OK_MESS
    fi
    echo "All build steps OK" >>$STORENAME.log
    mv $STORENAME.log $STOREDIR/$STORENAME/
    touch BUILT_OK_MAME
else
    echo "Build failed in $failed step" >>$STORENAME.log
    cp -a $(readlink -f ../mame) ../failed-builds/$STORENAME
fi
