#!/bin/sh

#Install dependencies on host system
xbps-install parted wget cryptsetup xtools binfmt-support

ln -s /etc/sv/binfmt-support /var/service/

wget http://os.archlinuxarm.org/os/ArchLinuxARM-rpi-aarch64-latest.tar.gz

#Need total wipe
wipefs --all /dev/mmcblk0

parted /dev/mmcblk0 mklabel msdos #Create disk label
parted /dev/mmcblk0 mkpart primary fat32 1M 257M #Create boot partition, 1M should be a suitable offset for most discs
parted /dev/mmcblk0 mkpart primary ext4 257M 100%


#Setup encrypted root
#cryptsetup luksFormat /dev/mmcblk0p2
cryptsetup --type luks2 --cipher xchacha20,aes-adiantum-plain64 luksFormat /dev/mmcblk0p2
cryptsetup luksOpen /dev/mmcblk0p2 rpiroot

#Setup logical volumes
#vgcreate rpiroot /dev/mapper/rpiroot
#lvcreate --name swap -L 1G rpiroot
#lvcreate --name root -l 100%FREE rpiroot

#Create filesystems 
mkfs.fat /dev/mmcblk0p1

mkfs.btrfs /dev/mapper/rpiroot

#Mount partitions for installation
mount /dev/mapper/rpiroot /mnt
mkdir /mnt/boot
mount /dev/mmcblk0p1 /mnt/boot

tar xvfp ArchLinuxARM-rpi-aarch64-latest.tar.gz -C /mnt #install system
rm ArchLinuxARM-rpi-aarch64-latest.tar.gz

#Create fstab
cp configs/fstab-no-vg /mnt/etc/fstab

#Setup crypttab
cp configs/crypttab /mnt/etc/crypttab

#Cant overwrite resolv.conf so have to remove it
rm /mnt/etc/resolv.conf

#Copy resolv.conf so chroot has internet
cp /etc/resolv.conf /mnt/etc/

#Give hooks to mkinitcpio
cp configs/mkinitcpio.conf /mnt/etc/mkinitcpio.conf

#Setup arch arm repos
xchroot /mnt pacman-key --init
xchroot /mnt pacman-key --populate archlinuxarm


#Install requirements on the encrypted system
xchroot /mnt pacman -Syu cryptsetup lvm2

#Setup initramfs
xchroot mkinitcpio -P

#Setup boot options
echo "initramfs initrd.img followkernel" >> /mnt/boot/config.txt



#Unmount partitions
umount /mnt/boot
umount /mnt


#Close luks partition
cryptsetup luksClose /dev/mapper/rpiroot
