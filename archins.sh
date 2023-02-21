# Loading Keys
loadkeys uk

# Zapping Partition Table
wipefs -af /dev/nvme0n1 
sgdisk -Zo /dev/nvme0n1

# Creating New Partition Table
parted -s /dev/nvme0n1 \
    mklabel gpt \
    mkpart ESP fat32 1MiB 513MiB \
    set 1 ESP on \
    mkpart ROOT 513MiB 100% \
partprobe /dev/nvme0n1

# Formatting Partitions
mkfs.vfat -F32 -n ESP /dev/nvme0n1p1
mkfs.btrfs -f -L ROOT /dev/nvme0n1p2

# Mounting Root Partition
mount /dev/nvme0n1p2 /mnt

# Creating BTRFS Sub-Volumes
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@snapshots
btrfs subvolume create /mnt/@cache
btrfs subvolume create /mnt/@libvirt
btrfs subvolume create /mnt/@log
btrfs subvolume create /mnt/@tmp

# Mounting BTRFS Sub-Volumes
umount /mnt
volopts="rw,noatime,compress-force=zstd:1,space_cache=v2"
mount -o ${volopts},subvol=@ /dev/nvme0n1p2 /mnt
mkdir -p /mnt/{home,.snapshots,var/cache,var/lib/libvirt,var/log,var/tmp}
mount -o ${volopts},subvol=@home /dev/nvme0n1p2 /mnt/home
mount -o ${volopts},subvol=@snapshots /dev/nvme0n1p2 /mnt/.snapshots
mount -o ${volopts},subvol=@cache /dev/nvme0n1p2 /mnt/var/cache
mount -o ${volopts},subvol=@libvirt /dev/nvme0n1p2 /mnt/var/lib/libvirt
mount -o ${volopts},subvol=@log /dev/nvme0n1p2 /mnt/var/log
mount -o ${volopts},subvol=@tmp /dev/nvme0n1p2 /mnt/var/tmp

# Package Mirrors Selection
pacman -Syy
reflector -c "GB" -f 12 -l 10 -n 12 --save /etc/pacman.d/mirrorlist

# Pacstraping Base System
pacstrap /mnt base base-devel linux-firmware linux linux-headers intel-ucode btrfs-progs efibootmgr snapper reflector snap-pac zram-generator sudo nano konsole neovim networkmanager

# Generating /etc/fstab
genfstab -U -p /mnt >> /mnt/etc/fstab

# Root Password Setup
echo "root:testpass" | arch-chroot /mnt chpasswd

# Hostname Setup
echo hostarch > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   hostarch.localdomain   hostarch
EOF

# Username & Password Setup
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel
arch-chroot /mnt useradd -m -G wheel archuser
echo "archuser:testpass" | arch-chroot /mnt chpasswd

# Configuring Locale and Keymap
sed -i "s/^#\(en_GB.UTF-8\)/\1/" /etc/locale.gen
echo "LANG=en_GB.UTF-8" > /etc/locale.conf
arch-chroot /mnt locale-gen
echo "KEYMAP=uk" > /etc/vconsole.conf

# Configuring /etc/mkinitcpio.conf
cat > /mnt/etc/mkinitcpio.conf <<EOF
MODULES=(btrfs)
HOOKS=(base udev keyboard autodetect keymap consolefont modconf block filesystems fsck)
EOF

# Generating a new initramfs
arch-chroot /mnt mkinitcpio -P

# Time Zone Setup
arch-chroot /mnt ln -sf /usr/share/zoneinfo/Europe/London /etc/localtime

# Clock Setup
arch-chroot /mnt hwclock --systohc

# Mounting Boot Partition and Installing Bootloader
mkdir -p /mnt/boot
mount /dev/nvme0n1p1 /mnt/boot
bootctl --path=/mnt/boot install
cat > /mnt/boot/loader/loader.conf <<EOF
default arch.conf
timeout 4
console-mode max
editor no
EOF
cat > /mnt/boot/loader/entries/arch.conf <<EOF
title   Arch Linux
linux   /vmlinuz-linux
initrd  /intel-ucode.img
initrd  /initramfs-linux.img
options root=/dev/nvme0n1p1 zswap.enabled=0 rootflags=subvol=@ rw intel_pstate=no_hwp rootfstype=btrfs
EOF

# Boot Backup Hook When Pacman Transactions are Made
mkdir -p /etc/pacman.d/hooks
cat > /etc/pacman.d/hooks/95-systemd-boot.hook <<EOF
[Trigger]
Type = Package
Operation = Upgrade
Target = systemd

[Action]
Description = Gracefully upgrading systemd-boot...
When = PostTransaction
Exec = /usr/bin/systemctl restart systemd-boot-update.service
EOF

exit