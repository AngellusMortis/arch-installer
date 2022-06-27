function var_init() {
    readonly mirrorlist_url="https://archlinux.org/mirrorlist/?country=US&protocol=http&protocol=https&ip_version=4&use_mirror_status=on"

    hostname="mortis-arch"
    do_pause=false
    swap=0
    no_input=false
    do_cleanup=false
    dry_run=false
    devices=()
    prefix=""
    do_wipe=false
    do_encrypt=false
    is_raid=false
    os_size=0
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
            -c|--clean)
                shift
                do_cleanup=true
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
            --no-input)
                shift
                no_input=true
                ;;
            -v|--device)
                shift
                devices+=($1)
                shift
                ;;
            -d|--dry-run)
                shift
                dry_run=true
                ;;
            -o|--os-size)
                shift
                os_size=$1
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

    if [[ ${devices[0]} = /dev/nvme* ]]; then
        prefix="p"
    fi
}


function get_params() {
    if [ `contains "$*" -v` -eq 0 ]; then
        prompt_param "$devices" "Disk(s) to Install to (space sperated)?"
        IFS=' '
        read -ra devices <<< "$prompt_result"
    fi

    if [ `contains "$*" -w` -eq 0 ]; then
        prompt_bool "$do_wipe" "Securely Wipe Disk"
        do_wipe=$prompt_result
    fi

    if [ `contains "$*" -y` -eq 0 ]; then
        prompt_bool "$do_encrypt" "Encrypt Disk"
        do_encrypt=$prompt_result
    fi

    if [ `contains "$*" -n` -eq 0 ]; then
        prompt_param "$hostname" "Hostname"
        hostname="$prompt_result"
    fi

    if [ `contains "$*" -s` -eq 0 ]; then
        prompt_param "$swap" "Swap space to allocate in GB"
        swap="$prompt_result"
    fi

    if [ `contains "$*" -s` -eq 0 ]; then
        prompt_param "$swap" "OS partition size in GB (0 = rest of disk)"
        os_size="$prompt_result"
    fi

    if [ `contains "$*" -s` -eq 0 ]; then
        prompt_param "$user" "Extra user to set up"
        user="$prompt_result"
    fi

    if [ `contains "$*" -c` -eq 0 ]; then
        prompt_bool "$do_cleanup" "Clean up for disk compaction?"
        do_cleanup=$prompt_result
    fi
}


function print_vars() {
    pretty_print "Hostname" $fg_magenta 1
    pretty_print ": $hostname" $fg_white

    pretty_print "Install Disk(s)" $fg_magenta 1
    pretty_print ": " $fg_white 1
    pretty_print " ${devices[@]}" $fg_white
    pretty_print ""

    pretty_print "Parition Prefix" $fg_magenta 1
    pretty_print ": $prefix" $fg_white

    pretty_print "Wipe Disk" $fg_magenta 1
    pretty_print ": $do_wipe" $fg_white

    pretty_print "Encrypt Disk" $fg_magenta 1
    pretty_print ": $do_encrypt" $fg_white

    pretty_print "Swap" $fg_magenta 1
    pretty_print ": ${swap}GB" $fg_white

    os_str="rest of disk"
    if [[ $os_size -gt 0 ]]; then
        os_str="${os_size}GB"
    fi
    pretty_print "OS" $fg_magenta 1
    pretty_print ": ${os_str}" $fg_white

    user_str="none (root only)"
    if [[ -n $user ]]; then
        user_str="${user}"
    fi
    pretty_print "User" $fg_magenta 1
    pretty_print ": ${user}" $fg_white

    pretty_print "Do Clean Up" $fg_magenta 1
    pretty_print ": $do_cleanup" $fg_white
}


# DESC: Cleans any existing partitions for disk
# ARGS: None
# OUTS: None
function clean_disk() {
    swapoff -a
    umount /mnt/boot/efi || true
    umount /mnt || true
    lvremove -An OS -y || true
    vgremove OS -y || true
    pvremove /dev/mapper/cryptlvm -y || true
    cryptsetup close /dev/mapper/cryptlvm || true
    mdadm --stop /dev/md/os || true

    for device in "${devices[@]}"; do
        echo "Clean disk: $device"
        mdadm --misc --zero-superblock $device || true
        mdadm --misc --zero-superblock "${device}${prefix}1" || true
        mdadm --misc --zero-superblock "${device}${prefix}2" || true
        wipefs -a $device
        dd if=/dev/zero of=$device bs=512 count=1 conv=notrunc
    done
}


# DESC: Securely wipes a disk
# ARGS: None
# OUTS: None
function wipe_disk() {
    for device in "${devices[@]}"; do
        echo "Wipe disk: $device"
        cryptsetup open --type plain -d /dev/urandom $device to_be_wiped
        dd if=/dev/zero of=/dev/mapper/to_be_wiped status=progress || true
        cryptsetup close to_be_wiped
    done
}


function setup_encrypt() {
    encrypt_partition=$os_partition
    os_partition=/dev/OS/root

    echo "Setup LUKS: $encrypt_partition"
    cryptsetup luksFormat -q --type luks1 $encrypt_partition
    echo "Open volume"
    cryptsetup open $encrypt_partition cryptlvm

    echo "Create LVM group"
    pvcreate /dev/mapper/cryptlvm
    vgcreate OS /dev/mapper/cryptlvm

    if (( $swap > 0 )); then
        echo "Create LVM: /dev/OS/swap"
        lvcreate -L ${swap}G OS -n swap -An
        swap_partition=/dev/OS/swap
    fi
    echo "Create LVM: /dev/OS/root"
    lvcreate -l 100%FREE OS -n root -An
}


# DESC: Partitions, formats and mounts disk
# ARGS: None
# OUTS: None
function partition_disk() {
    device=$1

    echo "Partition disk: $device"
    os_partition="${device}${prefix}2"
    encrypt_partition=""
    swap_partition=""
    os_part_arg=""
    if [[ $os_size -gt 0 ]]; then
        os_part_arg="+${os_size}G"
        os_swap_part_arg="+$(($os_size + $swap))G"
    fi

    # set boot partition
    partition_commands="
n
1

+550M
ef00
"


    if [[ "${#devices[@]}" -gt 1 ]]; then
        # create RAID partition
        partition_commands="
$partition_commands
n
2

${os_part_arg}
fd00
w
y
"
    else
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

${os_part_arg}
8304
w
y
"
        else
            os_partition_type="8304"
            if [[ "$do_encrypt" = true ]]; then
                os_partition_type="8309"
                os_part_arg="${os_swap_part_arg}"
            fi


            partition_commands="
$partition_commands
n
2

${os_part_arg}
$os_partition_type
w
y
"
        fi
    fi

    echo "$partition_commands" | gdisk $device
}

# DESC: Partitions, formats and mounts disk
# ARGS: None
# OUTS: None
function partition_disks() {
    raid_members=()
    for device in "${devices[@]}"; do
        raid_members+=("${device}${prefix}2")
        partition_disk $device
    done

    if [[ "${#devices[@]}" -gt 1 ]]; then
        os_partition=/dev/md/os
        mdadm --create --verbose -R --level=10 --metadata=1.2 --chunk=512 --raid-devices="${#raid_members[@]}" --layout=f2 $os_partition "${raid_members[@]}"
        dd if=/dev/zero of=$os_partition bs=8M count=4
    fi

    if [[ "$do_encrypt" = true ]]; then
        setup_encrypt
    fi

    if (( $swap > 0 )); then
        mkswap $swap_partition
        swapon $swap_partition
    fi

    mkfs.ext4 $os_partition
    mount $os_partition /mnt
    for device in "${devices[@]}"; do
        mkfs.fat -F32 "${device}${prefix}1"
    done
    mkdir /mnt/boot/efi -p
    mount "${devices[0]}${prefix}1" /mnt/boot/efi
}


function update_mirrors() {
    curl -s "$mirrorlist_url" |  sed 's/^#Server/Server/' > /etc/pacman.d/mirrorlist
}


# DESC: Initalizes /mnt so it can be chroot
# ARGS: None
# OUTS: None
function bootstrap_arch() {
    pacstrap /mnt base base-devel
    genfstab -U /mnt > /mnt/etc/fstab
    if [[ "${#devices[@]}" -gt 1 ]]; then
        mdadm --detail --scan >> /mnt/etc/mdadm.conf
    fi

    cp $script_dir /mnt/root/arch-installer -R
    chmod +x /mnt/root/arch-installer/script/chroot.sh

    mkdir /mnt/root/.ssh -p
    chmod 700 /mnt/root/.ssh
    cp authorized_keys /mnt/root/.ssh/authorized_keys
    chmod 600 /mnt/root/.ssh/authorized_keys
}



function do_chroot() {
    extra_args=""

    if [[ -z ${no_color-} ]]; then
        extra_args="$extra_args --no-color"
    fi
    if [[ "$do_pause" = true ]]; then
        extra_args="$extra_args -p"
    fi
    if [[ "$do_encrypt" = true ]]; then
        extra_args="$extra_args -y"
    fi
    if [[ -n "$user"  ]]; then
        extra_args="$extra_args -u $user"
    fi

    device_args=""
    for device in "${devices[@]}"; do
        device_args="${device_args} -v $device"
    done

    if [[ "$is_raid" = true ]]; then
        os_partition=/dev/md/os
    fi
    arch-chroot /mnt /root/arch-installer/script/chroot.sh$extra_args -n $hostname -r $os_partition $device_args

    rm /mnt/root/arch-installer -rf
    if [[ "$is_raid" = true ]]; then
        echo "Installing bootloader on extra RAID disks..."
        index=0
        for device in "${devices[@]}"; do
            index=$((index + 1))
            if [[ "$index" -gt 1 ]]; then
                umount /mnt/boot/efi
                mount "${device}${prefix}1" /mnt/boot/efi
                arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB${index} --recheck
            fi
        done
    fi
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
