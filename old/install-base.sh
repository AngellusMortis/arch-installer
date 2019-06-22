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
    hostname="mortis-arch"
    do_efi=false
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
     -e|--efi                   Use UEFI instead of BIOS boot
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
                swap=true
                ;;
            -e|--efi)
                shift
                do_efi=true
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
    if [ "$do_efi" = true ]; then
        pacman -S grub efibootmgr --noconfirm
        grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=grub
        grub-mkconfig -o /boot/grub/grub.cfg
        if [ "$build_type" = "virtualbox-iso" ]; then
            echo "\EFI\grub\grubx64.efi" > /boot/efi/startup.nsh
        fi
    else
        pacman -S grub --noconfirm
        grub-install --target=i386-pc /dev/sda

        if [ "$do_azure" = true ]; then
            cp /etc/default/grub{,.orig}
            cat /etc/default/grub.orig | sed 's/GRUB_CMDLINE_LINUX_DEFAULT="quiet"/GRUB_CMDLINE_LINUX_DEFAULT="console=ttyS0,115200n8 earlyprintk=ttyS0,115200 rootdelay=300"/' > /etc/default/grub
        fi
        grub-mkconfig -o /boot/grub/grub.cfg
    fi

    if [ "$build_type" = "hyperv-iso" ]; then
        cp /etc/mkinitcpio.conf{,.orig}
        cat /etc/mkinitcpio.conf.orig | sed 's/MODULES=()/MODULES=\("hv_storvsc" "hv_vmbus"\)/' > /etc/mkinitcpio.conf
        mkinitcpio -p linux
    fi
}


function init_root() {
    passwd=`date +%s | sha256sum | base64 | head -c 32`
    echo "root:$passwd" | chpasswd
}


function install_aur() {
    pushd /tmp > /dev/null
    git clone https://aur.archlinux.org/$1.git
    chown nobody $1 -R
    cd $1
    sudo -u nobody makepkg --cleanbuild --noconfirm --syncdeps
    pacman -U $1-* --noconfirm
    cd ..
    rm $1 -rf
    popd > /dev/null
}


function install_hyperv() {
    mount -o remount,size=4G,noatime /tmp

    install_aur hypervkvpd
    install_aur hypervvssd
    install_aur hypervfcopyd

    mount -o remount,size=500M,noatime /tmp
    systemctl enable hypervkvpd hypervvssd
}


function install_azure() {
    mount -o remount,size=4G,noatime /tmp

    pacman -S net-tools openssh openssl parted python python-setuptools --noconfirm
    install_aur walinuxagent
    cp /etc/waagent.conf{,.orig}
    cat /etc/waagent.conf.orig | sed 's/# AutoUpdate.Enabled=y/AutoUpdate.Enabled=n/' > /etc/waagent.conf

    mount -o remount,size=500M,noatime /tmp
    systemctl enable waagent
}


function install_virtalbox() {
    pacman -S virtualbox-guest-modules-arch virtualbox-guest-utils-nox --noconfirm
    modprobe -a vboxguest vboxsf vboxvideo
    systemctl enable vboxservice systemd-modules-load
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
    trap script_trap_err ERR
    trap script_trap_exit EXIT

    script_init "$@"
    parse_params "$@"
    colour_init

    run_section "Initalizing locales" "init_locales"
    run_section "Setting Hostname" "init_host"
    run_section "Installing Bootloader" "install_bootloader"
    run_section "Initaling root User" "init_root"
    run_section "Installing Core Packages" "pacman -S vim base-devel openssh git --noconfirm"
    if [ "$build_type" = "hyperv-iso" ]; then
        run_section "Installing Hyper-V Daemons" "install_hyperv"
        if [ "$do_azure" = true ]; then
           run_section "Installing Azure Guest Agent" "install_azure"
        fi
    elif [ "$build_type" = "virtualbox-iso" ]; then
        run_section "Installing Virtualbox Daemons" "install_virtalbox"
    fi
    run_section "Enabling Core Services" "systemctl enable sshd dhcpcd"
    run_section "Cleaning Up Pacman" "clean_pacman"
}


# Make it rain
main "$@"

# vim: syntax=sh cc=80 tw=79 ts=4 sw=4 sts=4 et sr
