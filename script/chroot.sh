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
    -nc|--no-colour             Disables colour output
     -n|--hostname              Hostname to use (default: mortis-arch)
     -e|--efi                   Use UEFI instead of BIOS boot
     -v|--device                Device for installation (default: /dev/sda)
     -f|--prefix                Extra partition prefix
     -y|--encrypt               Encrypt disk
EOF
}


function var_init() {
    readonly mirrorlist_url="https://www.archlinux.org/mirrorlist/?country=US&protocol=http&protocol=https&ip_version=4&use_mirror_status=on"

    hostname="mortis-arch"
    do_efi=false
    do_pause=false
    do_encrypt=false
    device="/dev/sda"
    prefix=""
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
            -p|--pause)
                shift
                do_pause=true
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
            -y|--encrypt)
                shift
                do_encrypt=true
                ;;
            -e|--efi)
                shift
                do_efi=true
                ;;
            -v|--device)
                shift
                device=$1
                shift
                ;;
            -f|--prefix)
                shift
                prefix=$1
                shift
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
}


function init_locales() {
    ln -sf /usr/share/zoneinfo/US/Eastern /etc/localtime
    hwclock --systohc
    echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
    locale-gen
    echo "LANG=en_US.UTF-8" > /etc/locale.conf
}


function init_host() {
    echo $hostname > /etc/hostname
    echo "
127.0.0.1       localhost
::1             localhost
127.0.1.1       $hostname.localdomain $hostname.local $hostname
" > /etc/hosts
}


function install_bootloader() {
    if [ "$do_encrypt" = true ]; then
        pacman -S lvm2 linux mkinitcpio grub --noconfirm
        
        dd bs=512 count=4 if=/dev/random of=/root/cryptlvm.keyfile iflag=fullblock
        chmod 000 /root/cryptlvm.keyfile
        cryptsetup -v luksAddKey ${device}${prefix}2 /root/cryptlvm.keyfile

        mkinitcpio -p linux
        cp /etc/mkinitcpio.conf{,.orig}
        cat /etc/mkinitcpio.conf.orig | sed 's/FILES=()/FILES=\(\/root\/cryptlvm.keyfile\)/' > /etc/mkinitcpio.conf
        cp /etc/mkinitcpio.conf{,.part1}
        cat /etc/mkinitcpio.conf.part1 | sed 's/HOOKS=.*/HOOKS=\(base udev autodetect keyboard keymap modconf block encrypt lvm2 filesystems fsck\)/' > /etc/mkinitcpio.conf
        mkinitcpio -p linux

        cp /etc/default/grub{,.orig}
        device_uuid=$(lsblk -f | grep ${device//\/dev\/}${prefix}2 | awk '{print $3}')
        cat /etc/default/grub.orig | sed "s/GRUB_CMDLINE_LINUX=\"\"/GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=$device_uuid:cryptlvm cryptkey=rootfs:\/root\/cryptlvm.keyfile\"/" > /etc/default/grub
        echo "GRUB_ENABLE_CRYPTODISK=y" >> /etc/default/grub
        
        # TODO: https://wiki.archlinux.org/index.php/Silent_boot
        # GRUB_DEFAULT="0"
        # GRUB_TIMEOUT="0"
        # GRUB_DISTRIBUTOR="Arch"
        # GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=3 udev.log_priority=3 vt.global_cursor_default=0"
        # GRUB_CMDLINE_LINUX="cryptdevice=UUID=567ade56-49a8-42b7-a453-a1324f4f2a5a:cryptlvm cryptkey=rootfs:/root/cryptlvm.keyfile"

        # Preload both GPT and MBR modules so that they are not missed
        # GRUB_PRELOAD_MODULES="part_gpt part_msdos"

        # Uncomment to enable Hidden Menu, and optionally hide the timeout count
        # GRUB_HIDDEN_TIMEOUT="3"
        # GRUB_HIDDEN_TIMEOUT_QUIET="true"
        # GRUB_RECORDFAIL_TIMEOUT=$GRUB_HIDDEN_TIMEOUT

        # The resolution used on graphical terminal
        # note that you can use only modes which your graphic card supports via VBE
        # you can see them in real GRUB with the command `vbeinfo'
        # GRUB_GFXMODE="1920x1080x32,auto"

        # Uncomment to disable generation of recovery mode menu entries
        # GRUB_DISABLE_RECOVERY="false"
    else
        pacman -S linux mkinitcpio grub --noconfirm
    fi

    if [ "$do_efi" = true ]; then
        pacman -S efibootmgr --noconfirm
        grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --recheck
        grub-mkconfig -o /boot/grub/grub.cfg
    else
        grub-install --target=i386-pc $device
        grub-mkconfig -o /boot/grub/grub.cfg
    fi
}


function init_root() {
    passwd=`date +%s | sha256sum | base64 | head -c 32`
    echo "root:$passwd" | chpasswd
}


function clean_pacman() {
    pacman -Rs gcc groff man-db git make guile binutils man-pages nano --noconfirm
    echo "y\ny" | pacman -Scc
    echo "ILoveCandy" >> /etc/pacman.cfg
}


# DESC: Main control flow
# ARGS: $@ (optional): Arguments provided to the script
# OUTS: None
function main() {
    source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

    trap script_trap_err ERR
    trap script_trap_exit EXIT

    script_init "$@"
    var_init "$@"
    parse_params "$@"
    cron_init
    colour_init

    run_section "Initalizing locales" "init_locales"
    run_section "Setting Hostname" "init_host"
    run_section "Installing Bootloader" "install_bootloader"
    run_section "Initaling root User" "init_root"
    run_section "Installing Core Packages" "pacman -S vim base-devel openssh git python dhcpcd --noconfirm"
    run_section "Enabling Core Services" "systemctl enable sshd dhcpcd"
    run_section "Cleaning Up Pacman" "clean_pacman"
}


# Make it rain
main "$@"

# vim: syntax=sh cc=80 tw=79 ts=4 sw=4 sts=4 et sr
