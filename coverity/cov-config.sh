# Scan times out analysis with no error messages if their downloader
# takes too long. To minimize the chance of that the package can be
# pushed to an S3 datacenter close to Scan before telling Scan to
# fetch it.
PROXYCONF=s3proxy

# Project specific settings
PUBLICURL=http://mame-test.lysator.liu.se

# PROJECT not set in env to allow parallel installations
PROJECT=mamedev%2Fmame
PROJDIR=mame
PROJREPO=https://github.com/mamedev/mame.git

MAKE_ARGS="REGENIE=1 TOOLS=1 DEPRECATED=0 NOWERROR=1"

# Specify "1" for very slow serial compile
MAKE_PAR=$(grep -c '^processor' /proc/cpuinfo)

# COVSTREAM no longer in use, set to "default" or anything descriptive
# that can be used are part of filename and URL.
COVSTREAM=default
