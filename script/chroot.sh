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
     -e|--efi                   Use UEFI instead of BIOS boot
     -v|--device                Device for installation (default: /dev/sda)
     -f|--prefix                Extra partition prefix
     -y|--encrypt               Encrypt disk
EOF
}


function var_init() {
    readonly mirrorlist_url="https://archlinux.org/mirrorlist/?country=US&protocol=http&protocol=https&ip_version=4&use_mirror_status=on"

    hostname="mortis-arch"
    do_pause=false
    do_encrypt=false
    root_partition="/dev/sda2"
    devices=()
    is_raid=false
    user=""
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
            --no-color)
                shift
                no_color=true
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
            -r|--root-partition)
                shift
                root_partition=$1
                shift
                ;;
            -v|--device)
                shift
                devices+=($1)
                shift
                ;;
            -u|--user)
                shift
                user=$1
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

    if [[ "${#devices[@]}" -eq 0 ]]; then
        devices+=("/dev/sda")
    elif [[ "${#devices[@]}" -gt 1 ]]; then
        is_raid=true
    fi
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
    packages="linux linux-firmware mkinitcpio grub efibootmgr"
    if [[ "$is_raid" = true ]]; then
        packages="${packages} mdadm"
    fi
    if [[ "$do_encrypt" = true ]]; then
        packages="${packages} lvm2"
    fi

    echo "Installing packages: ${packages}"
    pacman -S ${packages} --noconfirm

    if [[ "$do_encrypt" = true ]]; then
        dd bs=512 count=4 if=/dev/random of=/root/cryptlvm.keyfile iflag=fullblock
        chmod 000 /root/cryptlvm.keyfile
        cryptsetup -v luksAddKey ${root_partition} /root/cryptlvm.keyfile
    fi

    mkinitcpio -p linux
    cp /etc/mkinitcpio.conf{,.orig}
    hooks="base udev autodetect keyboard keymap modconf block filesystems fsck"

    if [[ "$do_encrypt" = true ]]; then
        cp /etc/mkinitcpio.conf{,.tmp}
        cat /etc/mkinitcpio.conf.tmp | sed 's/FILES=()/FILES=\(\/root\/cryptlvm.keyfile\)/' > /etc/mkinitcpio.conf
        rm /etc/mkinitcpio.conf.tmp

        if [[ "$is_raid" = true ]]; then
            hooks="base udev autodetect keyboard keymap modconf block mdadm_udev encrypt lvm2 filesystems fsck"
        else
            hooks="base udev autodetect keyboard keymap modconf block encrypt lvm2 filesystems fsck"
        fi
    elif [[ "$is_raid" = true ]]; then
        hooks="base udev autodetect keyboard keymap modconf block filesystems fsck"
    fi

    cp /etc/mkinitcpio.conf{,.tmp}
    cat /etc/mkinitcpio.conf.tmp | sed "s/HOOKS=.*/HOOKS=\(${hooks}\)/" > /etc/mkinitcpio.conf
    rm /etc/mkinitcpio.conf.tmp
    mkinitcpio -p linux

    cp /etc/default/grub{,.orig}
    modules="part_gpt part_msdos"
    if [[ "$is_raid" = true ]]; then
        modules="${modules} mdraid09 mdraid1x"
    fi

    if [[ "$do_encrypt" = true ]]; then
        modules="${modules} lvm"
        cmdline=""
        if [[ "$is_raid" = true ]]; then
            cmdline="cryptdevice=\/dev\/md\/os:cryptlvm cryptkey=rootfs:\/root\/cryptlvm.keyfile"
        else
            device_uuid=$(lsblk -f | grep ${root_partition} | awk '{print $3}')
            cmdline="cryptdevice=UUID=$device_uuid:cryptlvm cryptkey=rootfs:\/root\/cryptlvm.keyfile"
        fi
        cp /etc/default/grub{,.tmp}
        cat /etc/default/grub.tmp | sed "s/GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX=\"${cmdline}\"/" > /etc/default/grub
        rm /etc/default/grub.tmp
        echo "GRUB_ENABLE_CRYPTODISK=y" >> /etc/default/grub
    fi

    cp /etc/default/grub{,.tmp}
    cat /etc/default/grub.tmp | sed "s/GRUB_PRELOAD_MODULES=.*/GRUB_PRELOAD_MODULES=\"${modules}\"/" > /etc/default/grub
    rm /etc/default/grub.tmp

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

    grub_name=GRUB
    if [[ "$is_raid" = true ]]; then
        grub_name=GRUB1
    fi
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=${grub_name} --recheck
    grub-mkconfig -o /boot/grub/grub.cfg
}


function init_root() {
    passwd=`date +%s | sha256sum | base64 | head -c 32`
    echo "root:$passwd" | chpasswd

    if [[ -n "$user" ]]; then
        useradd -m $user
        echo "$user ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/01-admin
        mkdir /home/$user/.ssh/
        chmod 700 /home/$user/.ssh/
        cp /root/.ssh/authorized_keys /home/$user/.ssh/authorized_keys
        chmod 600 /home/$user/.ssh/authorized_keys
        chown -R $user:$user /home/$user/.ssh/
    fi
}


function clean_pacman() {
    pacman -Rs gcc groff git make guile --noconfirm
    echo "y\ny" | pacman -Scc
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
    color_init

    run_section "Initalizing locales" "init_locales"
    run_section "Setting Hostname" "init_host"
    run_section "Installing Bootloader" "install_bootloader"
    run_section "Initaling User" "init_root"
    run_section "Installing Core Packages" "pacman -S vim base-devel openssh git python dhcpcd --noconfirm"
    run_section "Enabling Core Services" "systemctl enable sshd dhcpcd systemd systemd-timesyncd"
    run_section "Cleaning Up Pacman" "clean_pacman"
}


# Make it rain
main "$@"

# vim: syntax=sh cc=80 tw=79 ts=4 sw=4 sts=4 et sr
