#!/bin/bash

# Runs Mame benchmarks that can be killed and resumed

# Version of mame to benchmark (can be omitted to continue an aborted run)
VER=$1
FORCE=$2  # --force will ignore CURRENT_VERSION and not set
	  # CURRENT_VERSION, for when running on parallel nodes in the
	  # same dir.

BENCHDIR=$(dirname $0)
CC=gcc8
CFLAGS="" # Should include extra optimization flags, not actual CFLAGS
ONLYONCE=0  # should games be skipped if a benchmark already exists?

source ${BENCHDIR}/../functions.sh

# Avoid running multiple instances of script.
_prepare_locking
exlock_now || exit 0  # Locking cleanup is handled by a trap

# Get Mame version to benchmark either from argv[1] or runstate/CURRENT_VERSION
# side effect; sets VER and TAG
set_mame_version $VER $FORCE

# side effect: Sets MAME
set_mame_binary $TAG $CC $CFLAGS
echo "Using $MAME"

RUNID=$(basename $(dirname $MAME))-$(date '+%Y-%m-%dT%H:%M:%S')
# Hostname specific dirs used as a rudimentary way of avoiding
# conflicts when running many benchmarks in parallel
LOGFILE=logs/$(uname -n)/$RUNID.log
STATEDIR=runstate/$(uname -n)/$RUNID
mkdir -p $(dirname $LOGFILE)
mkdir -p $STATEDIR
# Redirect everything to the log file
exec >$LOGFILE 2>&1
set -x

ROMPATH=$(get_mame_romdir $VER)

# Hardcode mame.ini, verified to be picked up even if -cfg_directory is used
# Note: All the artwork options are probably useless in ~0.212+
cat > ~/.mame/mame.ini <<EOF
#
# CORE ARTWORK OPTIONS
#
artwork_crop  0
use_backdrops 0
use_overlays  0
use_bezels    0
use_cpanels   0
use_marquees  0
#
# CORE SOUND OPTIONS
#
samplerate    22050
#
# OSD ACCELERATED VIDEO OPTIONS
#
filter        0
EOF

# Make sure we don't start the test accidentally while something else is running
# FIXME: Lower to 0.5
wait_for_load 30

GAMEARGS="-rompath $ROMPATH -cfg_directory $STATEDIR/cfg -nvram_directory $STATEDIR/nvram -snapshot_directory $STATEDIR/snap -diff_directory $STATEDIR/diff"

# Don't allow benchmarks to run for more than 10 x test time, aka 15min
TIMEOUT_WAIT=900
TIMEOUT="timeout --kill-after=5 $TIMEOUT_WAIT"

# Where needed, install game state as created by make_initial_state.sh
setup_initial_state $STATEDIR

# No display should be needed for these tests
unset DISPLAY
# But even with "-video none" implied by "-bench" the SDL driver opens an window, unless:
export SDL_VIDEODRIVER=dummy
# FIXME: The dummy driver trick did not start working until 0.203, and
# this RENDER_DRIVER extra made no differance. Remove when examined
export SDL_RENDER_DRIVER=software
# TODO: Check why this does not stop Mame from trying to open /dev/snd/seq.
export SDL_AUDIODRIVER=dummy

# TODO: Temp note; this is what's used for driver on the RPi
#    export SDL_RENDER_DRIVER=opengles2

# TODO: Have a look at if this is called for at any point
#    export SDL_AUDIODRIVER=disk; export SDL_DISKAUDIOFILE=/dev/null
#    SDL_VIDEO_GL_DRIVER (default is libGL.so.1)
#    SDL_VIDEO_YUV_HWACCEL (If not set or set to a nonzero value, SDL will attempt to use hardware YUV acceleration for video playback)

# If set, causes every call to SDL_SetError to also print an error message on stderr
export SDL_DEBUG=1

# Randomize the order games are benchmarked to suss out thermal or
# other side effects from earlier runs.
RANDGAMELST=$(get_randomized_games)

while read -r game; do
    case $game in
    *#*)
	echo "Note: Skipping $game"
	continue
    esac
    gamelog=$(get_gamelog_name $game $CC $VER $ONLYONCE)
    if [ $? -eq 1 ]; then
	echo "NOTE: Skipping $game, $gamelog already exists"
	continue
    fi
    echo "Starting $game at $(date)"
    $MAME -listfull           $GAMEARGS $game >> $gamelog 2>&1
    write_benchmark_header $gamelog
    echo "Before run: $(uptime)" >> $gamelog
    echo "Running built in benchmark" >> $gamelog
    $TIMEOUT $MAME -bench 90           $GAMEARGS $game >> $gamelog 2>&1
    check_timeout $? >> $gamelog
    echo "After run: $(uptime)" >> $gamelog
    echo "Completed $game at $(date)"
done < $RANDGAMELST

echo "Completed run of $VER-$(get_system_idname)-$CC at $(date)"
queue_next_version $FORCE
