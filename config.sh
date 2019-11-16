# Compilation setup
GCCVER=8
COMP_CC=gcc-$GCCVER
COMP_CXX=g++-$GCCVER

# default is -O3 with no archopts
#COMP_OPTIMIZE=4
#COMP_ARCHOPTS="-march=native -fomit-frame-pointer"

#COMP_OPTIMIZE=s
#COMP_ARCHOPTS="-march=native -fomit-frame-pointer"

# <cuavas> I usually set ARCHOPTS=-msse4.2 -fomit-frame-pointer
# <cuavas> (for personal builds, I don't set it for release)
# <cuavas> although, perhaps -fomit-frame-pointer should be set for release

# Generic benchmark setup
GEN_BENCH_CC=gcc$GCCVER
GEN_ONLYONCE=0

# Raspberry Pi benchmark setup
PI_BENCH_CC=gcc$GCCVER
PI_ONLYONCE=0
PI_TESTREAL=1
