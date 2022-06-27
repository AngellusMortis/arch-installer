# Arch Installer

Set of bash scripts to automate an Arch Installation, tailored to my preferences and use cases.

## Usage

```bash
curl -sL https://github.com/AngellusMortis/arch-installer/archive/master.tar.gz | tar xz
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
