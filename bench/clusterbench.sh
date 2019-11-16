#!/bin/bash
#
#SBATCH -J MameBench
#--SBATCH -n 8 # Number of cores
#SBATCH -N 1 # Ensure that all cores are on one machine
#SBATCH --exclusive
#SBATCH -t 0-06:00 # Runtime in D-HH:MM
#SBATCH -p compute # Partition to submit to
#--SBATCH --mail-type=END # Type of email notification- BEGIN,END,FAIL,ALL
#--SBATCH --mail-user=disabled@lysator.liu.se # Email to which notifications will be sent

# This script uses slurm to allocate a cluster node and use all cores
# on it to run a set of benchmarks with the Mame version set as $1

# NOTE: The SBATCH comment directive must be at the top before any code
# TODO: the job should lock to prevent more than one job per
#       node. --exclusive should handle that, but just to make sure.
# TODO: This is currently more or less hardcoded for zino

set -x

VER=$1
if [ -z $VER ]; then
    echo "Usage: $0 <mame version>"
    exit 1
fi

# Easybuilds stupid GCC requires LD_LIBRARY_PATH set for everything it
# builds
module load GCC/8.2.0-2.31.1 
./resumable_benchmark.sh $VER --force
