#!/bin/bash
#
#SBATCH -J MameBuild
#--SBATCH -n 8 # Number of cores
#SBATCH -N 1 # Ensure that all cores are on one machine
#SBATCH --exclusive
#SBATCH -t 0-01:00 # Runtime in D-HH:MM
#SBATCH -p compute # Partition to submit to
#--SBATCH --mail-type=END # Type of email notification- BEGIN,END,FAIL,ALL
#SBATCH --mail-user=zino@lysator.liu.se # Email to which notifications will be sent

# This script uses slurm to allocate a cluster node and use all cores
# on it to compile the Mame tag sent as $1

# NOTE: The SBATCH comment directive must be at the top before any code
# TODO: the job should lock to prevent more than one job per
#       node. --exclusive should handle that, but just to make sure.
# TODO: This is currently more or less hardcoded for zino

set -x

TAG=$1
if [ -z $TAG ]; then
    echo "Usage: $0 <git tag>"
    echo "(fex mame0215)"
    exit 1
fi

# Used to get a quicker compile of the central filesystem is a
# limiter, but also needed to make sure each node gets it's own build
# direcotory. 
SHM_BASE=/dev/shm/$USER

if [ ! -e $SHM_BASE ]; then
    mkdir -p $SHM_BASE/
fi
if [ ! -e $SHM_BASE/failed-builds ]; then
    ln -s /home/$USER/mame-stuff/arch/x86_64-64/failed-builds $SHM_BASE
fi
if [ ! -e $SHM_BASE/stored-mames ]; then
    ln -s /home/$USER/mame-stuff/arch/x86_64-64/stored-mames $SHM_BASE
fi
if [ ! -d $SHM_BASE/mame ]; then
    cd $SHM_BASE 
    time tar xzf /home/$USER/mame-stuff/arch/x86_64-64/mame-for-copying.tar.gz
fi
cd $SHM_BASE/mame

source $HOME/mame-stuff/mame-tools/config.sh # Get GCC version
source $HOME/mame-stuff/mame-tools/analysator-env.sh
time $HOME/mame-stuff/mame-tools/build-all-tags.sh $TAG

# Comment this out to avoid unpacking the source each run
rm -rf $SHM_BASE/mame
