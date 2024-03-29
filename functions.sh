# Requires bash, will not work with sh

# TODO: Change loadorder in the scripts so MAMEBASE can be moved to config.sh
MAMEBASE="$HOME/mame-stuff"
shopt -s extglob  # Extended globing needed for the mame binary locator

# Locking primitives taken from https://stackoverflow.com/questions/1715137/what-is-the-best-way-to-ensure-only-one-instance-of-a-bash-script-is-running

# No one follows the Linux FHS, hunt for a usable dir
# TODO: Move directory hunt to lock preparation function
for lockdir in /run/user/$UID /run/lock /var/lock /dev/shm /tmp; do
    if [ -w $lockdir ]; then
	LOCKFILE="${lockdir}/$(basename $0)"
	break
    fi
done
LOCKFD=17

# PRIVATE
_lock()             { flock -$1 $LOCKFD; }
_no_more_locking()  { _lock u; _lock xn && rm -f $LOCKFILE; rm -f $RANDGAMELST; }
_prepare_locking()  { eval "exec $LOCKFD>\"$LOCKFILE\""; trap _no_more_locking EXIT; }

# PUBLIC
exlock_now()        { _lock xn; }  # obtain an exclusive lock immediately or fail
unlock()            { _lock u; }   # drop a lock

# RPi specific throttle check
function was_throttled {
    local throttled=$(vcgencmd get_throttled)
    # Do not report throttling on pure undervoltage events
    if [ $throttled = "throttled=0x0" -o $throttled = "throttled=0x50000" ]; then
	false
    else
	true
    fi
}

# RPi specific
function reboot_if_throttled {
    if was_throttled; then
	echo "FATAL: Pi has been throttled, will reboot at $(date)" >> runstate/reboot.log
	./parse_throttle.py >> runstate/reboot.log
	sync
	sudo reboot
	exit 1 # reboot does not block
    fi
}

# RPi specific
function get_freq_arm {
    vcgencmd get_config arm_freq | awk -F= '{print $2}'
}

# RPi specific
function get_freq_gpu {
    vcgencmd get_config gpu_freq | awk -F= '{print $2}'
}

# RPi specific (Note: not applicable on RPi4)
function get_freq_sdram {
    vcgencmd get_config sdram_freq | awk -F= '{print $2}'
}

# RPi specific
function get_temp {
    vcgencmd measure_temp | sed 's/temp=\(.*\)\..*/\1/'
}

# RPi specific
# Throttling sets in at 80C, so leave at least a 15C envelope to work in
function wait_for_cooldown {
    local init_cool=1
    while [ $(get_temp) -gt 60 ]; do
	if [ $init_cool -eq 1 ]; then
	    echo "Waiting for CPU to cool down before next run..."
	    init_cool=0
	fi
	sleep 1
	echo -ne "$(get_temp)C  \r"
    done
    echo
    if [ $init_cool -eq 0 ]; then
	echo " OK"
    fi
}

# Bail if there isn't enough disk space available
function verify_free_disk {
    local min_avail=$1

    local avail=$(df . | awk 'NR==2 { print $4 }')
    if (( avail < $min_avail )); then
	echo "FATAL: Not anoung space available!"
	exit 1
    fi
}

function verify_mame_checkout {
    # before mame0189 there is no dist.mak
    # use src/mame/machine/amiga.c{pp} as an indicator
    if [ ! -f src/mame/machine/amiga.cpp -a ! -f src/mame/machine/amiga.c -a ! -g .git ]; then
	echo "FATAL: Needs to be run from mame base dir!"
	exit 1
    fi
}

function verify_ram_size {
    local ram=$(free -m | grep Mem: | awk '{print $2}')
    if [ $ram -lt 3500 ]; then
	if lsmod | grep zram >/dev/null 2>&1; then
	    echo "NOTE: zram loaded"
	else
	    echo "FATAL: zram needs to be loaded if you have <4G RAM"
	    exit 1
	fi
    fi
}

# Get Mame version to benchmark either from argv[1] or runstate/CURRENT_VERSION
# side effect; sets VER and TAG
function set_mame_version {
    local ver=$1
    local force=$2

    local id=$(get_system_idname)
    mkdir -p runstate
    if [ -z $ver ]; then
	if [ ! -f runstate/CURRENT_VERSION-$id ]; then
	    echo "Usage: $0 <version>"
	    echo "Example: $0 0.212"
	    exit 1
	else
	    VER=$(cat runstate/CURRENT_VERSION-$id)
	fi
    else
	if [ -f runstate/CURRENT_VERSION -a x"$force" != "x--force" ]; then
	    echo "FATAL: There is already an automatic benchmark of $(cat runstate/CURRENT_VERSION-$id) in progress!"
	    exit 1
	else
	    VER=$ver
	    if [ x"$force" != "x--force" ]; then
	       echo $VER > runstate/CURRENT_VERSION-$id
	    fi
	fi
    fi
    TAG=$(echo $VER | sed 's/\.//')
}

function get_num_sockets {
    local numsock=$(cat /proc/cpuinfo  | grep "physical id" | sort | uniq | wc -l)
    if [ $numsock -eq 0 ]; then
	echo 1
    else
	echo $numsock
    fi
}

function get_cpu_type {
    cat /proc/cpuinfo  | grep "model name" | head -1 | awk -F: '{print $2}' | awk '$1=$1'
}

function get_mem_gigs {
    # system never gets the last few megs, so lets integer this and add 1
    echo $(( $(free -m | grep Mem: | awk '{print $2}') / 1024 +1 ))
}

# FIXME: Normally used in subshells, so fatal "exit" will not work
function get_system_type {
    if [ -f /sys/firmware/devicetree/base/model ]; then
	case $(tr -d '\0' </sys/firmware/devicetree/base/model) in
	"Raspberry Pi 4"*)
	    echo "Raspberry Pi 4"
	    return ;;
	*)
	    echo "FATAL: Unknown system type"
	    exit 1
	esac
    fi

    # dmidecode needs sudo, so hardcoding here we go!
    case $(uname -n) in
    "crux")
	echo "ProLiant DL160 G6"
	return ;;
    "analysator-system.lysator.liu.se")
	echo "ProLiant DL180 G6"
	return ;;
    n159[4-6]*|n1600*)
	echo "ProLiant SL250s G8"
	return ;;
    n16[0-9][0-9]*)
	echo "Proliant DL980 G7"
	return ;;
    n[0-9]*)
	echo "ProLiant SL230s G8"
	return ;;
    esac
}

function get_system_shortname {
    if [ "$(get_system_type)" = "Raspberry Pi 4" ]; then
	echo "rpi4"
	return
    fi

    local cpu=$(get_cpu_type | sed 's/(R)//g')
    case $cpu in
    "Intel Xeon CPU"*)
	local id=$(echo $cpu | awk '{print tolower($4)}' | sed 's/-/_/')
	echo "xeon_$id"
	return ;;
    *)
        echo "FATAL: Unable to produce CPU id"
	exit 1
    esac
}

# Something that identifies the hardware and it's configuration,
# suitable as substring in a filename.
#
# FIXME: Normally used in subshells, so fatal "exit" will not work
function get_system_idname {
    local extra=""
    case $(get_system_shortname) in
    "rpi4")
	# TODO: Handle frequencies generically
	case $(get_freq_arm) in
	    1500) ;; # default frequency
	    1750) extra="_1.75" ;;
	    2000) extra="_2.0" ;;
	    *)
		echo "FATAL: unhandled CPU frequency $(get_freq_arm)" 1>&2
		exit 1
	esac
	case $(get_freq_gpu) in
	    500) ;; # default frequency
	    600) extra="${extra}_G600" ;;
	    *)
		echo "FATAL: unhandled GPU frequency $(get_freq_gpu)" 1>&2
		exit 1
	esac
	echo $(get_system_shortname)$extra
	return
	;;
    *)
	echo $(get_system_shortname)
	return ;;
    esac
}

function get_mame_romdir {
    local ver=$1

    local romdir=$MAMEBASE/roms/internetarchive
    if [ -e $MAMEBASE/roms/0.212 ]; then
	romdir=$MAMEBASE/roms/0.212
    fi
    if [ -e $MAMEBASE/roms/$ver ]; then
	romdir=$MAMEBASE/roms/$ver
    fi
    echo $romdir
}

# Locate the mame binary to use
# side effect: Sets MAME
function set_mame_binary {
    local tag=$1
    local cc=$2
    local opt_id=$3

    local exe64=""
    if [ $(getconf LONG_BIT) -eq 64 ]; then
	exe64=64
    fi

    if [ ! -z $opt_id ]; then
	opt_id="-${opt_id}"
    fi
    MAME=$(ls -d $MAMEBASE/arch/$(uname -m)-$(getconf LONG_BIT)/stored-mames/mame${tag}-${cc}-+([0-9a-f])${opt_id}/mame${exe64})
    if [ ! -e "$MAME" ]; then
	echo "FATAL: Could not find mame binary"
	exit 1
    fi
    # echo "Using $MAME"
}

function turn_off_screensavers {
    # This might disable the the default X11 screen saver:
    xset s noblank
    xset s off
    xset -dpms
    # But this is probably the only thing useful on a "modern" desktop:
    xscreensaver-command -exit
}

function wait_for_load {
    local target_load=$1

    local init_load=1
    while (( $(echo "$(awk '{print $1}' /proc/loadavg) > $target_load" |bc -l) )); do
	if [ $init_load -eq 1 ]; then
	    echo -n "Waiting for load to go down before starting test.."
	    init_load=0
	fi
	sleep 2
	echo -n "."
    done
    if [ $init_load -eq 0 ]; then
	echo " OK"
    fi
}

function queue_next_version {
    if [ x"$1" = "x--force" ]; then
	return
    fi
    local id=$(get_system_idname)
    local queue_file=runstate/CURRENT_VERSION-$id
    if [ ! -f $queue_file ]; then
	echo "NOTE: No queue file found"
	return
    fi
    local found_next=0
    # FIXME: Test this, looks like I changed it to non-subshell but am still using exit.
    while read -r x; do
	case $x in
	0.[0-9]*)
	    found_next=1
	    echo "Queueing up $x"
	    echo $x > $queue_file
	    sed -i '/^'$x'$/d' $queue_file # NOTE: GNU sed specific
	    exit 0
	    ;;
	esac
    done < $queue_file
    if [ $found_next -eq 0 ]; then
	echo "No queued version found. Stopping queue."
	rm runstate/CURRENT_VERSION-$id
    fi
}

function get_gamelog_name {
    local game=$1
    local cc=$2
    local ver=$3
    local once=$4
    local opt_id=$5

    if [ ! -z $opt_id ]; then
	opt_id="-${opt_id}"
    fi
    local base="benchresult/$(get_system_idname)/$game-$(get_system_idname)-$ver-$cc$opt_id.result"
    local i=1
    if [ $once -ne 1 ]; then
	# FIXME: seed random from PID? (RANDOM=$$)
	i=$RANDOM # Try to avoid TOCTOU problems on cluster
    fi
    local log=$base.$i
    if [ -f $log ]; then
	if [ $once -eq 1 ]; then
	    return 1
	fi
    fi
    while [ -f $log ]; do
	i=$(( i+1 ))
	log=$base.$i
    done
    mkdir -p $(dirname $log)
    echo $log
    return 0
}

function get_randomized_games {
    local target=$(mktemp -t mamebench.XXXXXXX)
    cat games.lst | sort -R > $target
    echo $target
}

# Some games need initial setup to not be stuck forever on some setup
# screen. These are created manually by starting the game with
# make_initial_state.sh
function setup_initial_state {
    local statedir=$1
    local game=$2

    # Default is to install all states
    if [ -z $2 ]; then
	echo "Installing initial state in test environment..."
	for x in initial_state/*; do
	    echo $x...
	    (cd $x && tar cf - * | (cd ../../$statedir && tar xvf -))
	done
    else
	if [ -d initial_state/$game ]; then
	    echo "Installing initial state in $statedir..."
	    (cd initial_state/$game && tar cf - * | (cd $statedir && tar xvf -))
	fi
    fi
}

function write_benchmark_header {
    local log=$1

    echo "CC: $CC" >> $log
    echo "OPTIMIZE: $COMP_OPTIMIZE" >> $log
    echo "ARCHOPTS: $COMP_ARCHOPTS" >> $log
    echo "Optimization ID: $OPT_ID" >> $log
    echo "Mame: $VER" >> $log
    echo "Node: $(uname -n)" >> $log
    echo "System: $(get_system_idname)" >> $log
    echo "System type: $(get_system_type)" >> $log
    echo "System RAM: $(get_mem_gigs)GiB" >> $log
    echo "Num CPU: $(get_num_sockets)" >> $log
    echo "Date: $(date --iso=seconds)" >> $log
}

function check_timeout {
    local rcode=$1

    if [ $rcode -eq 124 ]; then
	echo "Timed out after ${TIMEOUT_WAIT}s"
    fi
}

function get_optimization_id {
    local id=""
    local default_opt=3 # FIXME: Verify that 0 is default
    if [ ! -z "$COMP_OPTIMIZE" -a x"$COMP_OPTIMIZE" != x$default_opt ]; then
	id="O$COMP_OPTIMIZE"
    fi
    id="$id$COMP_ARCHOPTS"
    echo $id | sed 's/[ =\-]//g'
}
