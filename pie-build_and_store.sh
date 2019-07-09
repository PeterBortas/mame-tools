#!/bin/bash

set -x

if [ ! -f dist.mak ]; then
    echo "FATAL: Needs to be run from mame base dir!"
    exit 1
fi

GCCVER=8

CC=gcc-$GCCVER
CXX=g++-$GCCVER

CCNAME=$(echo $CC | sed 's/\-//')
HASH=$(git rev-parse --short HEAD)
GITNAME=$(git describe --dirty)

STORENAME=pie-$GITNAME-$CCNAME-$HASH
STOREDIR=../stored-mames

if [ -e $STOREDIR/$STORENAME ]; then
    echo "FATAL: $STOREDIR/$STORENAME already exists!"
    exit 1
fi

mkdir -p $STOREDIR
time make -j3 REGENIE=1 TOOLS=1 DEPRECATED=0 NOWERROR=1 OVERRIDE_CC=$(which $CC) OVERRIDE_CXX=$(which $CXX) >$STORENAME.log 2>&1 &&
    make -f dist.mak PTR64=0 >>$STORENAME.log 2>&1 &&
    mv build/release/x32/Release/mame $STOREDIR/$STORENAME &&
    mv $STORENAME.log $STOREDIR/$STORENAME/
