function var_init() {
    readonly mirrorlist_url="https://www.archlinux.org/mirrorlist/?country=US&protocol=http&protocol=https&ip_version=4&use_mirror_status=on"

    hostname="mortis-arch"
    do_efi=false
    do_pause=false
    swap=0
    no_input=false
    prompt_result=""
    do_cleanup=false
    dry_run=false
    device="/dev/sda"
    prefix=""
    do_wipe=false
    do_encrypt=false
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
            -c|--clean)
                shift
                do_cleanup=true
                ;;
            -e|--efi)
                shift
                do_efi=true
                ;;
            -w|--wipe)
                shift
                do_wipe=true
                ;;
            -s|--swap)
                shift
                swap=$1
                shift
                ;;
            -ni|--no-input)
                shift
                no_input=true
                ;;
            -f|--prefix)
                shift
                prefix=$1
                shift
                ;;
            -v|--device)
                shift
                device=$1
                shift
                ;;
            -d|--dry-run)
                shift
                dry_run=true
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


function get_params() {
    if [ `contains "$*" -v` -eq 0 ]; then
        prompt_param "$device" "Disk to Install to?"
        prefix="$prompt_result"
    fi

    if [ `contains "$*" -f` -eq 0 ]; then
        prompt_param "$prefix" "Extra prefix for partitions?"
        prefix="$prompt_result"
    fi

    if [ `contains "$*" -w` -eq 0 ]; then
        prompt_bool "$do_wipe" "Securely Wipe Disk"
        do_efi=$prompt_result
    fi

    if [ `contains "$*" -y` -eq 0 ]; then
        prompt_bool "$do_encrypt" "Encrypt Disk"
        do_efi=$prompt_result
    fi

    if [ `contains "$*" -n` -eq 0 ]; then
        prompt_param "$hostname" "Hostname"
        hostname="$prompt_result"
    fi

    if [ `contains "$*" -s` -eq 0 ]; then
        prompt_param "$swap" "Swap space to allocate in GB"
        swap="$prompt_result"
    fi

    if [ `contains "$*" -e` -eq 0 ]; then
        prompt_bool "$do_efi" "Use EFI"
        do_efi=$prompt_result
    fi

    if [ `contains "$*" -c` -eq 0 ]; then
        prompt_bool "$do_cleanup" "Clean up for disk compaction?"
        do_cleanup=$prompt_result
    fi
}


function print_vars() {
    pretty_print "Hostname" $fg_magenta 1
    pretty_print ": $hostname" $fg_white

    pretty_print "Install Disk" $fg_magenta 1
    pretty_print ": $device" $fg_white

    pretty_print "Parition Prefix" $fg_magenta 1
    pretty_print ": $prefix" $fg_white

    pretty_print "Wipe Disk" $fg_magenta 1
    pretty_print ": $do_wipe" $fg_white

    pretty_print "Encrypt Disk" $fg_magenta 1
    pretty_print ": $do_encrypt" $fg_white

    pretty_print "Swap" $fg_magenta 1
    pretty_print ": ${swap}GB" $fg_white

    pretty_print "Using EFI" $fg_magenta 1
    pretty_print ": $do_efi" $fg_white

    pretty_print "Do Clean Up" $fg_magenta 1
    pretty_print ": $do_cleanup" $fg_white
}


# DESC: Cleans any existing partitions for disk
# ARGS: None
# OUTS: None
function clean_disk() {
    swapoff -a
    wipefs -a $device
    dd if=/dev/zero of=$device bs=512 count=1 conv=notrunc
}


# DESC: Securely wipes a disk
# ARGS: None
# OUTS: None
function wipe_disk() {
    cryptsetup open --type plain -d /dev/urandom $device to_be_wiped
    dd if=/dev/zero of=/dev/mapper/to_be_wiped status=progress || true
    cryptsetup close to_be_wiped
}


function setup_encrypt() {
    encrypt_partition=$os_partition
    os_partition=/dev/OS/root

    cryptsetup luksFormat --type luks1 $encrypt_partition
    cryptsetup open $encrypt_partition cryptlvm

    pvcreate /dev/mapper/cryptlvm
    vgcreate OS /dev/mapper/cryptlvm

    if (( $swap > 0 )); then
        lvcreate -L ${swap}G OS -n swap
        swap_partition=/dev/OS/swap
    fi
    lvcreate -l 100%FREE OS -n root
}


# DESC: Partitions, formats and mounts disk
# ARGS: None
# OUTS: None
function partition_disk() {
    os_partition="${device}${prefix}2"
    encrypt_partition=""
    swap_partition=""

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
    if [ "$do_encrypt" = false ] && (( $swap > 0 )); then
        swap_partition="${device}${prefix}2"
        os_partition="${device}${prefix}3"

        partition_commands="
$partition_commands
n
2

+${swap}G
8200
n
3


8304
w
y
"
    else
        os_partition_type="8304"
        if [ "$do_encrypt" = true ]; then
            os_partition_type="8309"
        fi


        partition_commands="
$partition_commands
n
2


$os_partition_type
w
y
"
    fi

    echo "$partition_commands" | gdisk $device

    if [ "$do_encrypt" = true ]; then
        setup_encrypt
    fi

    if (( $swap > 0 )); then
        mkswap $swap_partition
        swapon $swap_partition
    fi

    mkfs.ext4 $os_partition
    mount $os_partition /mnt
    if [ "$do_efi" = true ]; then
        mkfs.fat -F32 "${device}${prefix}1"
        mkdir /mnt/boot/efi -p
        mount "${device}${prefix}1" /mnt/boot/efi
    fi
}


function update_mirrors() {
    curl -s "$mirrorlist_url" |  sed 's/^#Server/Server/' > /etc/pacman.d/mirrorlist
}


# DESC: Initalizes /mnt so it can be chroot
# ARGS: None
# OUTS: None
function bootstrap_arch() {
    pacstrap /mnt base base-devel
    genfstab -U /mnt >> /mnt/etc/fstab

    cp . /mnt/root/arch-installer -R

    mkdir /mnt/root/.ssh
    chmod 700 /mnt/root/.ssh
    cp authorized_keys /mnt/root/.ssh/authorized_keys
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
