#!/bin/bash

# Peter Bortas, 2017-2019

# Security consideration: This should not be run on multi user
# machines. At a minimum /tmp-files are handled insecurely and auth
# tokens are shown in the process environment.

# Usually started via runcov.sh in crontab

#set -e
set -o pipefail
set -x

SCRIPTDIR=$(readlink -f $(dirname $0))
cd $SCRIPTDIR

# TODO: The xenofarm logging parts of the code requires failures to
# happend, so remove -e

# TODO: Put full Xenofarm support back in

# Environment needs to contain COV_ACCOUNT, SECRET_TOKEN, S3BUCKET and
# S3PUBLICURL and S3DESC. Furthermore s3cmd for the user running this
# needs to be setup to access said S3BUCKET if S3 proxy is used.
# Used for all projects and contains sensitive information
# FIXME: The build user should not have read access to much of this
source /etc/scan-env

# Config needs to contain PROJECT, MAKE_ARGS, MAKE_PAR and
# IRCNOTIFY. It may contain SUBMITMETHOD and/or PUBLICURL depending on
# the upload type choosen. It may also contain a MAKE_PREPARE
# containing bash code that will be run before the coverity build is
# started.
#
# SUBMITMETHOD settings:
#     s3proxy:  Upload to S3 bucket and tell Scan to pull from that bucket
#     localweb: Put file on local webserver and tell scan to pull from it
#     formsubmit: Upload via form submission (recommended for small projects)
#     nosubmit: Do not submit the result. For running tests of the process
source cov-config.sh
# PROJECT names can contain /, which is often unpractical
PROJ_FILENAME=$(echo $PROJECT | sed 's,/,_,')
PROJ_HTTPNAME=$(echo $PROJECT | sed 's,/,%2F,')

make_machineid() {
    local covversion=`cov-build --help 2>/dev/null | head -1 | sed -e 's/.* version \(.*\) on Linux.*/\1/'`
    if [ x$covversion = x ]; then
	echo >&2 "FATAL: Unable to get cov-build version!"
	exit 1
    fi
    echo "sysname: Coverity"  >  machineid.txt &&
	echo "release: scan-${covversion}"  >> machineid.txt &&
	#       echo "version: $unamev"  >> machineid.txt &&
	echo "machine: `uname -m`"  >> machineid.txt &&
	echo "nodename: cov-scan-zino"   >> machineid.txt &&
	echo "testname: $PROJECT-$COVSTREAM"   >> machineid.txt &&
	echo "command: $MAKE_ARGS" >> machineid.txt &&
	echo "clientversion: covsubmit 1.2" >> machineid.txt &&
	echo "contact: bortas@gmail.com" >> machineid.txt
}

mainlog() {
    echo "$1" >> xenofarm_result/mainlog.txt
}

logindex=0
irclog() {
    logindex=$(($logindex + 1))
    local hash=$(cat $SCRIPTDIR/lasthash)
    local prefix="[analysis ${PROJECT}#$hash]"
    if [ $IRCNOTIFY -eq 1 ]; then
	# NOTE: Do not run this on a multi-user machine
	mkdir -p /tmp/ircexport
	chmod 777 /tmp/ircexport
	local ircfile=/tmp/ircexport/$HASH-$log-$logindex
	echo "$prefix $1" | tee $ircfile
    else
	echo "WARNING: IRC notifications turned off"
	echo "$prefix $1"
    fi
}

populate_xenofarm_result() {
    make_machineid
    mv machineid.txt xenofarm_result/
    cp $BUILDIDFILE xenofarm_result/ || exit 1
}

init_xenofarm() {
    mkdir xenofarm_result || exit 1

    mainlog "FORMAT 2" &&
    rm -rf cov-int &&
    mainlog "BEGIN cov-build" &&
    mainlog "`date`" &&
    irclog "Starting build"
}

# Avoid building if nothing has changed
check_new_source() {
    local HASHFILE=$SCRIPTDIR/lasthash
    [ -f $HASHFILE ] || touch $HASHFILE
    local OLDHASH=$(cat ${HASHFILE})
    local NEWHASH=$(git rev-parse --short HEAD)
    if [ x$NEWHASH = x$OLDHASH ]; then
	echo "Nothing has changed in git. Exiting."
	exit 0
    fi
    echo -n $NEWHASH > $HASHFILE
}

# push
upload_to_scan_form() {
    # 	 --fail also fails on code 100 Continue?
    local CURLOPTS="--speed-time 3600 --max-time 43200 --connect-timeout 60 --progress-bar"
    # The -o is required to get a progress bar
    time curl $CURLOPTS \
	 -D xenofarm_result/upload_log.head \
	 -o xenofarm_result/upload_log.data \
	 --form token=$SECRET_TOKEN \
	 --form email=$COV_ACCOUNT \
	 --form file=@$COVPACKAGE \
	 --form version="$(git describe --dirty)" \
	 --form description="Latest HEAD as of $PULL_DATE, short hash: $(git rev-parse --short HEAD)" \
	 https://scan.coverity.com/builds?project=$PROJ_HTTPNAME
}

# let Scan pull it from a webserver. Works better for large files
upload_for_scan_pull() {
    local CURLOPTS="--speed-time 1800 --max-time 3600 --connect-timeout 60 --fail"
    if [ "$1" = "s3proxy" ]; then
	irclog "DEBUG: proxing via S3"
	URL=$S3PUBLICURL/$(basename $COVPACKAGE)
    else
	URL=$PUBLICURL/$(basename $COVPACKAGE)
    fi
    time curl $CURLOPTS \
	 -D xenofarm_result/upload_log.head \
	 -o xenofarm_result/upload_log.data \
	 --data "project=${PROJ_HTTPNAME}&token=${SECRET_TOKEN}&email=${COV_ACCOUNT}&url=${URL}&version=$(git describe --dirty)&description=$(git describe --dirty)-pushed" \
	 https://scan.coverity.com/builds
}

upload_to_s3() {
    # acl-public would be a good idea, if the user was set up to handle ACL changes, results in 403 without
    # time s3cmd put --acl-public $COVPACKAGE $S3BUCKET
    time s3cmd put $COVPACKAGE $S3BUCKET
}

function setup_fastdisk {
    local dir=$1
    local repo=$2
    
    if [ -d /fastdisk/$dir/.git ]; then
	echo /fastdisk/$dir already prepped
    else
	cd /fastdisk
	git clone $repo $dir
    fi
}

# MAIN:

setup_fastdisk $PROJDIR $PROJREPO

cd /fastdisk/$PROJDIR || exit 1
rm -rf build
WEBDIR=/fastdisk/webexport
# Let the files linger for a one day in case Scan is slow to download them
find $WEBDIR/cov-$PROJ_FILENAME-* -mtime +0 -exec rm -v "{}" \; || :
git pull
# This will forcibly removed anything not tracked by git, even if it's
# in .gitignore
git clean -dfqx

PULL_DATE="$(date)"

echo "Starting build $(date)"

check_new_source
init_xenofarm

# export the build via the web since it's too large
if [ ! -d $WEBDIR ]; then
    mkdir $WEBDIR
    echo > $WEBDIR/index.html
    mkdir $WEBDIR/logs
    echo > $WEBDIR/logs/index.html
fi

BUILDNR=$(git rev-parse --short HEAD)
EXTLOG=$WEBDIR/logs/$PROJ_FILENAME-${BUILDNR}.txt
LOGURL=$PUBLICURL/logs/$(basename $EXTLOG)

# Do pre-analysis setup, f.ex. build things that should not be
# included in analysis
time bash -xc "$MAKE_PREPARE"
if [ $? != 0 ]; then
    # TODO: This breaks Xenofarm log compatibility. Entire thing needs rewrite
    mainlog "FAIL"
    mainlog "`date`"
    irclog "Preparation step failed"
    exit 1
fi

# FIXME: remove this debug printf
echo "Relese dir files:"
ls build/linux_gcc/obj/x64/Release/ || echo "WARNING: No release dir"

if cov-build --dir cov-int make -j$MAKE_PAR $MAKE_ARGS 2>&1 | tee $EXTLOG; then
    mainlog "PASS"
    mainlog "`date`"
    irclog "Compile completed"
    
    mainlog "BEGIN response_assembly"
    mainlog "`date`"
    echo "Uploading cov-build result to SCAN for analysis"
    COVPACKAGE=$WEBDIR/cov-$PROJ_FILENAME-$COVSTREAM-${BUILDNR}.tar.gz
    # FIXME: Check that there is enough space (~15G) before packing
    export GZIP=-9 # Very slow, but essential to get large project submitted
    if tar czf $COVPACKAGE cov-int; then
	ls -lh $COVPACKAGE

	# TODO: Make sure 85%+ of compilation units are ready as per
	# https://scan.coverity.com/download
	mainlog "PASS"
	mainlog "`date`"
	mainlog "BEGIN cov-scan-upload"
	mainlog "`date`"

	case $SUBMITMETHOD in
	nosubmit)
	    echo "WARNING: nosubmit specified, no results submitted to Scan"
	    false
	    ;;
	s3proxy)
	    echo "Uploading to $S3DESC"
	    upload_to_s3
	    upload_for_scan_pull s3proxy
	    ;;
	localweb)
	    upload_for_scan_pull
	    ;;
        formsubmit)
	    upload_to_scan_form
	    # This is a kludge for Scans flaky uploading of large archives
	    # TODO: Make retries and sleep configurable
	    if grep -q "502 Bad Gateway" xenofarm_result/upload_log.head; then
	 	echo "upload failed with code 502. Retrying upload in 30min"
	 	sleep 1800
	 	upload_to_scan_form
	    fi
	    if grep -q "502 Bad Gateway" xenofarm_result/upload_log.head; then
	 	echo "upload failed with code 502. Giving up"
	 	mainlog "FAIL"
	 	echo "head:"
	 	cat xenofarm_result/upload_log.head
	 	echo "data:"
	 	cat xenofarm_result/upload_log.data
		false
	    fi
	    ;;
	*)
	    echo "WARNING: Unknown SUBMITMETHOD $SUBMITMETHOD, will not submit"
	    false
	    ;;
	esac
	
	if [ $? != 0 ]; then
     	    mainlog "FAIL"
	    irclog "Build OK. Upload to Scan using $SUBMITMETHOD failed ($LOGURL)"
     	    echo "head:"
     	    cat xenofarm_result/upload_log.head
     	    echo "data:"
     	    cat xenofarm_result/upload_log.data
	else
	    mainlog "PASS"	
	    irclog "Upload to Scan completed ($LOGURL)"
	fi     
	mainlog "`date`"
    else
	mainlog "FAIL"
	mainlog "`date`"
	irclog "Build OK. Archiving failed. Probably full disk, ping zino ($LOGURL)"
    fi
else
    mainlog "FAIL"
    mainlog "`date`"
    irclog "Build failed. ($LOGURL)"
fi

mainlog "END"

echo "Finished $VERSION at `date`"

