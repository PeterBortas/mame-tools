# Scan times out analysis with no error messages if their downloader
# takes too long. To minimize the chance of that the package can be
# pushed to an S3 datacenter close to Scan before telling Scan to
# fetch it.
#PROXYCONF=s3proxy
PROXYCONF=nosubmit

# Project specific settings
PUBLICURL=http://mame-test.lysator.liu.se

# PROJECT not set in env to allow parallel installations
PROJECT=mame_partial
PROJDIR=mame-partial
PROJREPO=https://github.com/mamedev/mame.git

# TODO: TOOLS=1
MAKE_ARGS="DEPRECATED=0 NOWERROR=1 SOURCES=src/mame/drivers/pacman.cpp"

# Specify "1" for very slow serial compile
#MAKE_PAR=$(grep -c '^processor' /proc/cpuinfo)
MAKE_PAR=1

MAKE_PREPARE="make -j$(grep -c '^processor' /proc/cpuinfo) REGENIE=1 DEPRECATED=0 NOWERROR=1 SOURCES=src/mame/drivers/pacman.cpp ; echo Removing non-3rdparty objects ; find build/linux_gcc/obj/x64/Release/ -mindepth 1 -maxdepth 1 | grep -v 3rdparty | xargs rm -rfv"

# COVSTREAM no longer in use, set to "default" or anything descriptive
# that can be used are part of filename and URL.
COVSTREAM=zinotest
