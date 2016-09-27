#!/usr/bin/env bash
set -e

# bits of this were adapted from lxc-checkconfig
# see also https://github.com/lxc/lxc/blob/lxc-1.0.2/src/lxc/lxc-checkconfig.in

possibleConfigs=(
	'/proc/config.gz'
	"/boot/config-$(uname -r)"
	"/usr/src/linux-$(uname -r)/.config"
	'/usr/src/linux/.config'
)

if [ $# -gt 0 ]; then
	CONFIG="$1"
else
	: ${CONFIG:="${possibleConfigs[0]}"}
fi

if ! command -v zgrep &> /dev/null; then
	zgrep() {
		zcat "$2" | grep "$1"
	}
fi

kernelVersion="$(uname -r)"
kernelMajor="${kernelVersion%%.*}"
kernelMinor="${kernelVersion#$kernelMajor.}"
kernelMinor="${kernelMinor%%.*}"

is_set() {
	zgrep "CONFIG_$1=[y|m]" "$CONFIG" > /dev/null
}
is_set_in_kernel() {
	zgrep "CONFIG_$1=y" "$CONFIG" > /dev/null
}
is_set_as_module() {
	zgrep "CONFIG_$1=m" "$CONFIG" > /dev/null
}

color() {
	local codes=()
	if [ "$1" = 'bold' ]; then
		codes=( "${codes[@]}" '1' )
		shift
	fi
	if [ "$#" -gt 0 ]; then
		local code=
		case "$1" in
			# see https://en.wikipedia.org/wiki/ANSI_escape_code#Colors
			black) code=30 ;;
			red) code=31 ;;
			green) code=32 ;;
			yellow) code=33 ;;
			blue) code=34 ;;
			magenta) code=35 ;;
			cyan) code=36 ;;
			white) code=37 ;;
		esac
		if [ "$code" ]; then
			codes=( "${codes[@]}" "$code" )
		fi
	fi
	local IFS=';'
	echo -en '\033['"${codes[*]}"'m'
}
wrap_color() {
	text="$1"
	shift
	color "$@"
	echo -n "$text"
	color reset
	echo
}

wrap_good() {
	echo "$(wrap_color "$1" white): $(wrap_color "$2" green)"
}
wrap_bad() {
	echo "$(wrap_color "$1" bold): $(wrap_color "$2" bold red)"
}
wrap_warning() {
	wrap_color >&2 "$*" red
}

check_flag() {
	if is_set_in_kernel "$1"; then
		wrap_good "CONFIG_$1" 'enabled'
	elif is_set_as_module "$1"; then
		wrap_good "CONFIG_$1" 'enabled (as module)'
	else
		wrap_bad "CONFIG_$1" 'missing'
	fi
}

check_flags() {
	for flag in "$@"; do
		echo "- $(check_flag "$flag")"
	done
}

check_command() {
	if command -v "$1" >/dev/null 2>&1; then
		wrap_good "$1 command" 'available'
	else
		wrap_bad "$1 command" 'missing'
	fi
}

check_device() {
	if [ -c "$1" ]; then
		wrap_good "$1" 'present'
	else
		wrap_bad "$1" 'missing'
	fi
}

if [ ! -e "$CONFIG" ]; then
	wrap_warning "warning: $CONFIG does not exist, searching other paths for kernel config ..."
	for tryConfig in "${possibleConfigs[@]}"; do
		if [ -e "$tryConfig" ]; then
			CONFIG="$tryConfig"
			break
		fi
	done
	if [ ! -e "$CONFIG" ]; then
		wrap_warning "error: cannot find kernel config"
		wrap_warning "  try running this script again, specifying the kernel config:"
		wrap_warning "    CONFIG=/path/to/kernel/.config $0 or $0 /path/to/kernel/.config"
		exit 1
	fi
fi

wrap_color "info: reading kernel config from $CONFIG ..." white
echo


wrap_color 'HW settings:' bold yellow
wrap_color 'smartctl for SCSI device' blue
check_flags CHR_DEV_SG
wrap_color 'Network tuning' blue
check_flags PCI_MSI
wrap_color 'AES_NI' blue
check_flags CRYPTO_AES_NI_INTEL
echo

wrap_color 'Monitoring:' bold yellow
wrap_color 'iotop/dstat --top-io' blue
check_flags TASKSTATS TASK_IO_ACCOUNTING
wrap_color 'systemtap' blue
check_flags RELAY DEBUG_FS DEBUG_INFO KPROBES
wrap_color 'ktap' blue
check_flags FTRACE CONTEXT_SWITCH_TRACER EVENT_TRACING FTRACE_SYSCALLS
echo

wrap_color 'CRIU:' bold yellow
# https://criu.org/Installation#Configuring_the_kernel
wrap_color 'General setup options:' blue
flags=(
    CHECKPOINT_RESTORE # Checkpoint/restore support
    NAMESPACES         # Namespaces support
    UTS_NS             # Namespaces support -> UTS namespace
    IPC_NS             # Namespaces support -> IPC namespace
    PID_NS             # Namespaces support -> PID namespaces
    NET_NS             # Namespaces support -> Network namespace
    FHANDLE            # Open by fhandle syscalls
    EVENTFD            # Enable eventfd() system call
    EPOLL              # Enable eventpoll support
)
check_flags "${flags[@]}"
wrap_color 'Networking support:' blue
flags=(
    UNIX_DIAG     # Unix domain sockets -> UNIX: socket monitoring interface
    INET_DIAG     # TCP/IP networking -> INET: socket monitoring interface
    INET_UDP_DIAG # TCP/IP networking -> INET: socket monitoring interface -> UDP: socket monitoring interface
    PACKET_DIAG   # Packet socket -> Packet: sockets monitoring interface
    NETLINK_DIAG  # Netlink socket -> Netlink: sockets monitoring interface
)
check_flags "${flags[@]}"
wrap_color 'Other options:' blue
check_flags INOTIFY_USER IA32_EMULATION MEM_SOFT_DIRTY
echo

wrap_color 'Etc:' bold yellow
wrap_color 'Blkio-Controller:' blue
check_flags BLK_DEV_THROTTLING CFQ_GROUP_IOSCHED
wrap_color '/proc/config.gz:' blue
check_flags IKCONFIG_PROC
echo

