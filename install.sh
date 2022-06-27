#!/usr/bin/env bash

# A best practices Bash script template with many useful functions. This file
# sources in the bulk of the functions from the source.sh file which it expects
# to be in the same directory. Only those functions which are likely to need
# modification are present in this file. This is a great combination if you're
# writing several scripts! By pulling in the common functions you'll minimise
# code duplication, as well as ease any potential updates to shared functions.

# A better class of script...
set -o errexit          # Exit on most errors (see the manual)
set -o errtrace         # Make sure any error trap is inherited
set -o nounset          # Disallow expansion of unset variables
set -o pipefail         # Use last non-zero exit code in a pipeline
#set -o xtrace          # Trace the execution of the script (debug)

# DESC: Usage help
# ARGS: None
# OUTS: None
function script_usage() {
    cat << EOF
Usage:
     -h|--help                  Displays this help
     -p|--pause                 Pauses after each section
     --no-color                 Disables color output
     -n|--hostname              Hostname to use (default: mortis-arch)
     -w|--wipe                  Securely wipe disk before partitioning
     -y|--encrypt               Encrypt disk
     -s|--swap                  Swap size in GB (default: 0 = no swap)
     -v|--device                Device for installation (default: /dev/sda)
     -o|--os-size               Size of root partition in GB. (default: all free)
     -u|--user                  Optional user to setup. (default: none)
     -c|--clean                 Clean up disks for compaction
     --no-input                 Automaitcally use defaults for everything
     -d|--dry-run               Only print final variables, do not proceed
EOF
}


# DESC: Main control flow
# ARGS: $@ (optional): Arguments provided to the script
# OUTS: None
function main() {
    source "$(dirname "${BASH_SOURCE[0]}")/script/lib.sh"
    source "$(dirname "${BASH_SOURCE[0]}")/script/base.sh"

    trap script_trap_err ERR
    trap script_trap_exit EXIT

    script_init "$@"
    var_init "$@"
    parse_params "$@"
    cron_init
    color_init

    if [ "$no_input" = false ]; then
        run_section "Configure" "get_params $script_params"
    fi

    run_section "Variables" "print_vars"

    if [ "$dry_run" = false ]; then
        run_section "Syncing Time" "timedatectl set-ntp true"
        run_section "Cleaning Disk" "clean_disk"
        if [ "$do_wipe" = true ]; then
            run_section "Wiping Disk" "wipe_disk"
        fi
        run_section "Paritioning Disk" "partition_disks"
        run_section "Updating Mirrorlist" "update_mirrors"
        run_section "Bootstrapping Arch" "bootstrap_arch"
        run_section "Running Chroot Install" "do_chroot"
        if [ "$do_cleanup" = true ]; then
            run_section "Cleaning Up" "clean_up"
        fi
        run_section "Rebooting" "shutdown -r now"
    fi
}


# Make it rain
main "$@"

# vim: syntax=sh cc=80 tw=79 ts=4 sw=4 sts=4 et sr
