#!/usr/bin/env bash

# A best practices Bash script template with many useful functions. This file
# combines the source.sh & script.sh files into a single script. If you want
# your script to be entirely self-contained then this should be what you want!

# A better class of script...
set -o errexit          # Exit on most errors (see the manual)
set -o errtrace         # Make sure any error trap is inherited
set -o nounset          # Disallow expansion of unset variables
set -o pipefail         # Use last non-zero exit code in a pipeline
#set -o xtrace          # Trace the execution of the script (debug)

# DESC: Handler for unexpected errors
# ARGS: $1 (optional): Exit code (defaults to 1)
# OUTS: None
function script_trap_err() {
    local exit_code=1

    # Disable the error trap handler to prevent potential recursion
    trap - ERR

    # Consider any further errors non-fatal to ensure we run to completion
    set +o errexit
    set +o pipefail

    # Validate any provided exit code
    if [[ ${1-} =~ ^[0-9]+$ ]]; then
        exit_code="$1"
    fi

    # Exit with failure status
    exit "$exit_code"
}


# DESC: Handler for exiting the script
# ARGS: None
# OUTS: None
function script_trap_exit() {
    cd "$orig_cwd"

    # Restore terminal colours
    printf '%b' "$ta_none"
}


# DESC: Exit script with the given message
# ARGS: $1 (required): Message to print on exit
#       $2 (optional): Exit code (defaults to 0)
# OUTS: None
function script_exit() {
    if [[ $# -eq 1 ]]; then
        printf '%s\n' "$1"
        exit 0
    fi

    if [[ ${2-} =~ ^[0-9]+$ ]]; then
        printf '%b\n' "$1"
        # If we've been provided a non-zero exit code run the error trap
        if [[ $2 -ne 0 ]]; then
            script_trap_err "$2"
        else
            exit 0
        fi
    fi

    script_exit 'Missing required argument to script_exit()!' 2
}


# DESC: Generic script initialisation
# ARGS: $@ (optional): Arguments provided to the script
# OUTS: $orig_cwd: The current working directory when the script was run
#       $script_path: The full path to the script
#       $script_dir: The directory path of the script
#       $script_name: The file name of the script
#       $script_params: The original parameters provided to the script
#       $ta_none: The ANSI control code to reset all text attributes
# NOTE: $script_path only contains the path that was used to call the script
#       and will not resolve any symlinks which may be present in the path.
#       You can use a tool like realpath to obtain the "true" path. The same
#       caveat applies to both the $script_dir and $script_name variables.
function script_init() {
    # Useful paths
    readonly orig_cwd="$PWD"
    readonly script_path="${BASH_SOURCE[0]}"
    readonly script_dir="$(dirname "$script_path")"
    readonly script_name="$(basename "$script_path")"
    readonly script_params="$*"

    # Important to always set as we use it in the exit handler
    readonly ta_none="$(tput sgr0 2> /dev/null || true)"

    readonly allowed_types=("hyperv-iso" "virtualbox-iso")
    readonly mirrorlist_url="https://www.archlinux.org/mirrorlist/?country=US&protocol=http&protocol=https&ip_version=4&use_mirror_status=on"
    hostname="mortis-arch"
    do_swap=false
    do_efi=false
    do_cleanup=false
    do_pause=false
    do_azure=false
}


# DESC: Initialise colour variables
# ARGS: None
# OUTS: Read-only variables with ANSI control codes
# NOTE: If --no-colour was set the variables will be empty
function colour_init() {
    if [[ -z ${no_colour-} ]]; then
        # Text attributes
        readonly ta_bold="$(tput bold 2> /dev/null || true)"
        printf '%b' "$ta_none"
        readonly ta_uscore="$(tput smul 2> /dev/null || true)"
        printf '%b' "$ta_none"
        readonly ta_blink="$(tput blink 2> /dev/null || true)"
        printf '%b' "$ta_none"
        readonly ta_reverse="$(tput rev 2> /dev/null || true)"
        printf '%b' "$ta_none"
        readonly ta_conceal="$(tput invis 2> /dev/null || true)"
        printf '%b' "$ta_none"

        # Foreground codes
        readonly fg_black="$(tput setaf 0 2> /dev/null || true)"
        printf '%b' "$ta_none"
        readonly fg_blue="$(tput setaf 4 2> /dev/null || true)"
        printf '%b' "$ta_none"
        readonly fg_cyan="$(tput setaf 6 2> /dev/null || true)"
        printf '%b' "$ta_none"
        readonly fg_green="$(tput setaf 2 2> /dev/null || true)"
        printf '%b' "$ta_none"
        readonly fg_magenta="$(tput setaf 5 2> /dev/null || true)"
        printf '%b' "$ta_none"
        readonly fg_red="$(tput setaf 1 2> /dev/null || true)"
        printf '%b' "$ta_none"
        readonly fg_white="$(tput setaf 7 2> /dev/null || true)"
        printf '%b' "$ta_none"
        readonly fg_yellow="$(tput setaf 3 2> /dev/null || true)"
        printf '%b' "$ta_none"

        # Background codes
        readonly bg_black="$(tput setab 0 2> /dev/null || true)"
        printf '%b' "$ta_none"
        readonly bg_blue="$(tput setab 4 2> /dev/null || true)"
        printf '%b' "$ta_none"
        readonly bg_cyan="$(tput setab 6 2> /dev/null || true)"
        printf '%b' "$ta_none"
        readonly bg_green="$(tput setab 2 2> /dev/null || true)"
        printf '%b' "$ta_none"
        readonly bg_magenta="$(tput setab 5 2> /dev/null || true)"
        printf '%b' "$ta_none"
        readonly bg_red="$(tput setab 1 2> /dev/null || true)"
        printf '%b' "$ta_none"
        readonly bg_white="$(tput setab 7 2> /dev/null || true)"
        printf '%b' "$ta_none"
        readonly bg_yellow="$(tput setab 3 2> /dev/null || true)"
        printf '%b' "$ta_none"
    else
        # Text attributes
        readonly ta_bold=''
        readonly ta_uscore=''
        readonly ta_blink=''
        readonly ta_reverse=''
        readonly ta_conceal=''

        # Foreground codes
        readonly fg_black=''
        readonly fg_blue=''
        readonly fg_cyan=''
        readonly fg_green=''
        readonly fg_magenta=''
        readonly fg_red=''
        readonly fg_white=''
        readonly fg_yellow=''

        # Background codes
        readonly bg_black=''
        readonly bg_blue=''
        readonly bg_cyan=''
        readonly bg_green=''
        readonly bg_magenta=''
        readonly bg_red=''
        readonly bg_white=''
        readonly bg_yellow=''
    fi
}


# DESC: Pretty print the provided string
# ARGS: $1 (required): Message to print (defaults to a bold cyan foreground)
#       $2 (optional): Colour to print the message with. This can be an ANSI
#                      escape code or one of the prepopulated colour variables.
#       $3 (optional): Set to any value to not append a new line to the message
# OUTS: None
function pretty_print() {
    if [[ $# -lt 1 ]]; then
        script_exit 'Missing required argument to pretty_print()!' 2
    fi

    if [[ -z ${no_colour-} ]]; then
        if [[ -n ${2-} ]]; then
            printf '%b' "$2"
        else
            printf '%b' "$ta_bold$fg_cyan"
        fi
    fi

    # Print message & reset text attributes
    if [[ -n ${3-} ]]; then
        printf '%s%b' "$1" "$ta_none"
    else
        printf '%s%b\n' "$1" "$ta_none"
    fi
}


# DESC: Usage help
# ARGS: None
# OUTS: None
function script_usage() {
    cat << EOF
Usage:
    $script_name [OPTIONS] BUILD_TYPE:(${allowed_types[@]})

     -h|--help                  Displays this help
    -nc|--no-colour             Disables colour output
     -n|--hostname              Hostname to configure inital image with (default: mortis-arch)
     -s|--swap                  Include swap partition
     -e|--efi                   Use UEFI instead of BIOS boot
     -c|--clean                 Clean up disks for compaction
     -p|--pause                 Pause after each main step
     -a|--azure                 Install walinuxagent for Azure upload, build_type must be hyperv-iso
EOF
}


# DESC: Determines if string is in array or not
# ARGS: $1 (required): Array to use
#       $2 (required): String to use
# OUTS: echos "1" string in array, or "0" if it is not
contains() {
    [[ $1 =~ (^|[[:space:]])$2($|[[:space:]]) ]] && echo -e 1 || echo -e 0
}


# DESC: Parameter parser
# ARGS: $@ (optional): Arguments provided to the script
# OUTS: Variables indicating command-line parameters and options
function parse_params() {
    local param
    while [[ $# -gt 0 ]]; do
        param="$1"
        case $param in
            -h|--help)
                shift
                script_usage
                exit 0
                ;;
            -nc|--no-colour)
                shift
                no_colour=true
                ;;
            -n|--hostname)
                shift
                hostname=$1
                shift
                ;;
            -s|--swap)
                shift
                do_swap=true
                ;;
            -e|--efi)
                shift
                do_efi=true
                ;;
            -c|--clean)
                shift
                do_cleanup=true
                ;;
            -p|--pause)
                shift
                do_pause=true
                ;;
            -a|--azure)
                shift
                do_azure=true
                ;;
            --)
                shift
                break
                ;;
            -*)
                script_exit "Invalid parameter was provided: $param" 2
                ;;
            *)
                break;
        esac
    done

    if [ $# -lt 1 ] || [ `contains $allowed_types $1` -eq 0 ] ; then
        script_usage
        exit 2
    else
        build_type=$1
    fi
}


# DESC: Wrapper for printing a "section" header and then running a command
# ARGS: None
# OUTS: None
function run_section() {
    pretty_print "==> $1"
    $2
    echo

    if [ "$do_pause" = true ]; then
        pretty_print "Paused" $fg_green
        read -n 1 -s
    fi
}


# DESC: Partitions, formats and mounts disk
# ARGS: None
# OUTS: None
function partition_disk() {
    # set boot partition
    if [ "$do_efi" = true ]; then
        partition_commands="
n
1

+550M
ef00
"
    else
        partition_commands="
n
1

+1M
ef02
"
    fi

    # set swap/root partition
    if [ "$do_swap" = true ]; then
        os_partition="/dev/sda3"
        partition_commands="
$partition_commands
n
2

+1G
8200
n
3


8304
w
y
"
    else
        os_partition="/dev/sda2"
        partition_commands="
$partition_commands
n
2


8304
w
y
"
    fi
    echo "$partition_commands" | gdisk /dev/sda

    if [ "$do_swap" = true ]; then
        mkswap /dev/sda2
        swapon /dev/sda2
    fi
    mkfs.ext4 $os_partition
    mount $os_partition /mnt
    if [ "$do_efi" = true ]; then
        mkfs.fat -F32 /dev/sda1
        mkdir /mnt/boot/efi -p
        mount /dev/sda1 /mnt/boot/efi
    fi
}


function update_mirrors() {
    curl -s "$mirrorlist_url" |  sed 's/^#Server/Server/' > /etc/pacman.d/mirrorlist
}


# DESC: Initalizes /mnt so it can be chroot
# ARGS: None
# OUTS: None
function bootstrap_arch() {
    pacstrap /mnt base
    genfstab -U /mnt >> /mnt/etc/fstab
    chmod +x install-base.sh
    cp install-base.sh /mnt/root
    mkdir /mnt/root/.ssh
    chmod 700 /mnt/root/.ssh
    cp id_rsa.pub /mnt/root/.ssh/authorized_keys
    chmod 600 /mnt/root/.ssh/authorized_keys
}


function do_chroot() {
    extra_args=""
    if [ "$do_efi" = true ]; then
        extra_args="$extra_args -e"
    fi
    if [ "$do_pause" = true ]; then
        extra_args="$extra_args -p"
    fi
    if [ "$do_azure" = true ]; then
        extra_args="$extra_args -a"
    fi
    arch-chroot /mnt /root/install-base.sh$extra_args -n $hostname $build_type
    rm /mnt/root/install-base.sh
}


# DESC: Removes cleans up disk to help compact (defrag/write 0)
# ARGS: None
# OUTS: None
function clean_up() {
    e4defrag $os_partition
    dd if=/dev/zero of=/mnt/zero.small.file bs=1024 count=102400
    cat /dev/zero > /mnt/zero.file || true
    sync
    rm /mnt/zero.small.file
    rm /mnt/zero.file
    if [ "$do_swap" = true ]; then
        swapoff /dev/sda2
    fi
}


function eject_install() {
    umount -d -l -f /run/archiso/bootmnt/ && eject /dev/cdrom
}


# DESC: Main control flow
# ARGS: $@ (optional): Arguments provided to the script
# OUTS: None
function main() {
    trap script_trap_err ERR
    trap script_trap_exit EXIT

    script_init "$@"
    parse_params "$@"
    colour_init

    run_section "Syncing Time" "timedatectl set-ntp true"
    run_section "Paritioning Disk" "partition_disk"
    run_section "Updating Mirrorlist" "update_mirrors"
    run_section "Bootstrapping Arch" "bootstrap_arch"
    run_section "Running Base Install" "do_chroot"
    if [ "$do_cleanup" = true ]; then
        run_section "Cleaning Up" "clean_up"
    fi
    if [ "$do_efi" = false ]; then
        run_section "Ejecting Installation Media" "eject_install"
    fi
    run_section "Rebooting" "shutdown -r now"
}


# Make it rain
main "$@"

# vim: syntax=sh cc=80 tw=79 ts=4 sw=4 sts=4 et sr
