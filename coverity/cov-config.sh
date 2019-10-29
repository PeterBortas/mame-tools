# Scan times out analysis with no error messages if their downloader
# takes too long. To minimize the chance of that the package can be
# pushed to an S3 datacenter close to Scan before telling Scan to
# fetch it.
#SUBMITMETHOD=s3proxy
SUBMITMETHOD=nosubmit

# Project specific settings
PUBLICURL=http://mame-test.lysator.liu.se

# Name of project on scan.coverity.com
PROJECT=mame_partial
# Directory name for checked out project, allows several checkouts of same repo
PROJDIR=mame-partial
# Git repo to clone
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

# IRC notifications requires separate irc client that picks up the
# logg messages and post them to IRC
IRCNOTIFY=0

# Project specific environment that needs to be set up before running make
export QT_SELECT=qt5 
