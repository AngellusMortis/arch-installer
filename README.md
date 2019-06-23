# Arch Installer

Set of bash scripts to automate an Arch Installation, tailored to my preferences and use cases.

## Usage

```bash
curl -sL http://mort.is/arch > d
cat d
source d
cd arch-installer-master
./install.sh
```

## Clean up

For testing to make sure everything is cleaned up

```bash
umount /mnt/boot
umount /mnt/boot/efi
umount /mnt
vgchange -a n OS
cryptsetup close OS
```
