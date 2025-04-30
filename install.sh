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
vgcreate rpiroot /dev/mapper/rpiroot
lvcreate --name swap -L 1G rpiroot
lvcreate --name root -l 100%FREE rpiroot

#Create filesystems 
mkfs.fat /dev/mmcblk0p1
mkfs.btrfs /dev/rpiroot/root
mkswap /dev/rpiroot/swap

#Mount partitions for installation
mount /dev/rpiroot/root /mnt
mkdir /mnt/boot
mount /dev/mmcblk0p1 /mnt/boot

tar xvfp ArchLinuxARM-rpi-aarch64-latest.tar.gz -C /mnt #install system
rm ArchLinuxARM-rpi-aarch64-latest.tar.gz

#Update fstab
echo $(lsblk -o uuid /dev/rpiroot/swap | sed -n '2p')	/              	btrfs      	rw        	0 1 >> /mnt/etc/fstab
echo $(lsblk -o uuid /dev/rpiroot/root | sed -n '2p')	none           	swap      	defaults  	0 0 >> /mnt/etc/fstab


#Update crypttab
touch /mnt/etc/crypttab
echo rpiroot	$(lsblk -o uuid /dev/mmcblk0p2 | sed -n '2p')	none        luks >> /mnt/etc/crypttab

#Cant overwrite resolv.conf so have to remove it
rm /mnt/etc/resolv.conf

#Copy resolv.conf so chroot has internet
cp /etc/resolv.conf /mnt/etc/

#Give hooks to mkinitcpio
cp configs/mkinitcpio.conf /mnt/etc/mkinitcpio.conf

#replace Uboots default envs so vg root partition is used
sed -i '6s/.*/setenv bootargs console=ttyS1,115200 console=tty0 cryptdevice=PARTUUID=$(lsblk -o uuid /dev/mmcblk0p2 | sed -n '2p') root=/dev/mapper/rpiroot-root rw rootwait smsc95xx.macaddr="${usbethaddr}"/' /mnt/boot/boot.scr
sed -i '6s/.*/setenv bootargs console=ttyS1,115200 console=tty0 cryptdevice=PARTUUID=$(lsblk -o uuid /dev/mmcblk0p2 | sed -n '2p') root=root=/dev/mapper/rpiroot-root rw rootwait smsc95xx.macaddr="${usbethaddr}"/' /mnt/boot/boot.txt

#Setup arch arm repos
xchroot /mnt pacman-key --init
xchroot /mnt pacman-key --populate archlinuxarm

#Install requirements on the encrypted system
xchroot /mnt pacman -Syu cryptsetup lvm2 uboot-tools wget

#Manually get mirror list to avoid script breaking timeout errors
xchroot wget http://mirror.archlinuxarm.org/aarch64/community/community.db -O /var/lib/pacman/sync/community.db


#Setup initramfs
xchroot mkinitcpio -P

#Run script to regenerate Uboot
xchroot bash /boot/mkscr

#replace Uboots default envs so vg root partition is used
cp configs/boot.txt /mnt/boot/boot.txt

#Unmount partitions
umount /mnt/boot
umount -l /mnt


#Close luks partition
cryptsetup luksClose /dev/mapper/rpiroot
