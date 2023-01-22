#!/usr/bin/env bash

clear
loadkeys uk

#PREFERENCES
HOSTNAME="HomeArch"
SUDO_USER="arch"
IN_DEVICE=/dev/nvme0n1
DISKLABEL='GPT'
EFI_MTPT=/mnt/boot/efi
EFI_DEVICE=/dev/nvme0n1p1
ROOT_DEVICE=/dev/nvme0n1p2
HOME_DEVICE=/dev/nvme0n1p3
SWAP_DEVICE=/dev/nvme0n1p4
EFI_SIZE=512M
SWAP_SIZE=4096M
ROOT_SIZE=102400M
HOME_SIZE=381273M
TIME_ZONE="Europe/London"
LOCALE="en_GB.UTF-8"
FILESYSTEM=ext4
BASE_SYSTEM=( base linux linux-firmware dkms )
ESSENTIAL_PKGS=( base-devel linux-headers nano konsole dolphin dolphin-plugins ntfs-3g thunderbird vlc libreoffice okular gimp firefox conky nvidia nvidia-utils nomacs xf86-video-intel kodi flameshot shotcut qbittorrent p7zip kate )
PLASMA_PKGS=( xorg plasma-desktop sddm sddm-kcm systemsettings plasma-nm kmenuedit discover kde-cli-tools kdecoration kdeplasma-addons kinfocenter kscreen kwin libkscreen libksysguard oxygen plasma-pa plasma-systemmonitor )
BOOTLOADER_PKGS=( grub efibootmgr os-prober)

# ALL PURPOSE ERROR
error(){ echo "Error: $1" && exit 1; }

# VERIFY BOOT MODE
efi_boot_mode(){
    [[ -d /sys/firmware/efi/efivars ]] && return 0
    return 1
}

# FORMATTING ROUTINE
format_it(){
    device=$1; fstype=$2
    mkfs."$fstype" "$device" || error "format_it(): Can't format device $device with $fstype"
}

# MOUNTING ROUTINE
mount_it(){
    device=$1; mt_pt=$2
    mount "$device" "$mt_pt" || error "mount_it(): Can't mount $device to $mt_pt"
}

# CREATING PARTITIONS
create_partitions(){
    sgdisk -Z "$IN_DEVICE"
    sgdisk -n 1::+"$EFI_SIZE" -t 1:ef00 -c 1:EFI "$IN_DEVICE"
    sgdisk -n 2::+"$ROOT_SIZE" -t 2:8300 -c 2:ROOT "$IN_DEVICE"
    sgdisk -n 3 -c 4:HOME "$IN_DEVICE"
    # sgdisk -n 4::+"$SWAP_SIZE" -t 3:8200 -c 3:SWAP "$IN_DEVICE"

    # Format and mount slices for EFI
    format_it "$ROOT_DEVICE" "$FILESYSTEM"
    mount_it "$ROOT_DEVICE" /mnt
    mkfs.fat -F32 "$EFI_DEVICE"
    mkdir /mnt/boot && mkdir /mnt/boot/efi
    mount_it "$EFI_DEVICE" "$EFI_MTPT"
    format_it "$HOME_DEVICE" "$FILESYSTEM"
    mkdir /mnt/home
    mount_it "$HOME_DEVICE" /mnt/home
    # mkswap "$SWAP_DEVICE" && swapon "$SWAP_DEVICE"
    lsblk "$IN_DEVICE"
    echo "Type any key to continue..."; read empty
}

# FIND GRAPHICS CARD
find_card(){
    card=$(lspci | grep VGA | sed 's/^.*: //g')
    echo "You're using a $card" && echo
}

# PREFERENCE RECAPE
show_prefs(){
    echo "Here are your preferences that will be installed: "
    echo -e "\n\n"
    echo "HOSTNAME: ${HOSTNAME}  INSTALLATION DRIVE: ${IN_DEVICE}  DISKLABEL: ${DISKLABEL}"
    echo "TIMEZONE: ${TIME_ZONE}   LOCALE:  ${LOCALE}"
    echo "KEYBOARD: ${default_keymap}"
    echo "ROOT_SIZE: ${ROOT_SIZE} on ${ROOT_DEVICE}"
    echo "EFI_SIZE: ${EFI_SIZE} on ${EFI_DEVICE}"
    echo "SWAP_SIZE: ${SWAP_SIZE} on ${SWAP_DEVICE}"
    echo "HOME_SIZE: Occupying rest of ${HOME_DEVICE}"
    find_card
    echo "Type any key to continue or CTRL-C to exit..."
    read empty
}

# VALIDATE PKG NAMES IN SCRIPT
validate_pkgs(){
    echo "Updating pacman pkg database."
    pacman -Sy
    echo && echo -n "    Validating pkg names..."
    for pkg_arr in "${all_pkgs[@]}"; do
        declare -n arr_name=$pkg_arr
        for pkg_name in "${arr_name[@]}"; do
            if $( pacman -Sp $pkg_name &>/dev/null ); then
                echo -n .
            else
                echo -n "$pkg_name from $pkg_arr not in repos."
            fi
        done
    done
    echo -e "\n" && read -p "Press any key to continue or Ctl-C to check for problem." empty
}

sleep 4
count=5
while true; do
    [[ "$count" -lt 1 ]] && break
    echo -e  "\e[1A\e[K Launching install in $count seconds"
    count=$(( count - 1 ))
    sleep 1
done

echo -e "\n\nWaiting until reflector has finished updating mirrorlist..."
while true; do
    pgrep -x reflector &>/dev/null || break
    echo -n '.'
    sleep 2
done

# CHECK CONNECTION TO INTERNET
echo -e "\n\nTesting internet connection..."
$(ping -c 3 archlinux.org &>/dev/null) || (echo "Couldn't establish connection..." && exit 1)
echo "Connection established..." && sleep 3

# SHOW THE PREFERENCES BEFORE STARTING INSTALLATION
show_prefs

# MAKE SURE CURRENT PKG NAMES ARE CORRECT
validate_pkgs

# CHECK TIME AND DATE BEFORE INSTALLATION
timedatectl set-ntp true
echo && echo -e "\n\nDate/Time service Status is . . . "
timedatectl status
sleep 4

# PARTITION AND FORMAT AND MOUNT
echo -e "\n\nPartitioning Hard Drive!! Press any key to continue..." ; read empty
create_partitions

# INSTALL BASE SYSTEM
pacstrap /mnt archlinux-keyring
pacstrap /mnt "${BASE_SYSTEM[@]}"
echo && echo -e "\n\nBase system installed."

# GENERATE FSTAB
echo -e "\n\nGenerating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# SET UP TIMEZONE AND LOCALE
echo && echo -e "\n\nsetting timezone to $TIME_ZONE..."
arch-chroot /mnt ln -sf /usr/share/zoneinfo/"$TIME_ZONE" /etc/localtime
arch-chroot /mnt hwclock --systohc --utc
arch-chroot /mnt date
echo && echo -e "\n\nHere's the date info, hit any key to continue..."; read td_yn

# SET UP LOCALE
echo && echo -e "\nsetting locale to $LOCALE ..."
arch-chroot /mnt sed -i "s/#$LOCALE/$LOCALE/g" /etc/locale.gen
arch-chroot /mnt locale-gen
echo "LANG=$LOCALE" > /mnt/etc/locale.conf
export LANG="$LOCALE"

# HOSTNAME
echo && echo -e "\n\nSetting hostname..."; sleep 3
echo "$HOSTNAME" > /mnt/etc/hostname
cat > /mnt/etc/hosts <<HOSTS
127.0.0.1      localhost
::1            localhost
127.0.1.1      $HOSTNAME.localdomain     $HOSTNAME
HOSTS
echo && echo -e "\n\n/etc/hostname and /etc/hosts files configured..."
echo -e "/etc/hostname . . . \n"
cat /mnt/etc/hostname
echo -e "\n/etc/hosts . . .\n"
cat /mnt/etc/hosts
echo && echo -e "\n\nHere are /etc/hostname and /etc/hosts. Type any key to continue "; read empty

# SET ROOT PASSWORD
echo "Enter ROOT password..."
arch-chroot /mnt passwd

# INSTALLING MORE ESSENTIALS
echo && echo -e "\n\nEnabling dhcpcd, pambase, sshd and NetworkManager services..." && echo
arch-chroot /mnt pacman -S git openssh networkmanager dhcpcd man-db man-pages pambase
arch-chroot /mnt systemctl enable dhcpcd.service
arch-chroot /mnt systemctl enable sshd.service
arch-chroot /mnt systemctl enable NetworkManager.service
arch-chroot /mnt systemctl enable systemd-homed

# CREATING USER ACCOUNT
echo && echo -e "\n\nAdding sudo + user account..."
sleep 2
pacman -Sy
arch-chroot /mnt pacman -S sudo bash-completion sshpass
arch-chroot /mnt sed -i 's/# %wheel/%wheel/g' /etc/sudoers
arch-chroot /mnt sed -i 's/%wheel ALL=(ALL) NOPASSWD: ALL/# %wheel ALL=(ALL) NOPASSWD: ALL/g' /etc/sudoers
echo && echo -e "\n\nCreating $SUDO_USER user and adding to sudoers..."
arch-chroot /mnt useradd -m -G wheel "$SUDO_USER"
echo && echo -e "\n\nEnter password for $SUDO_USER?"
arch-chroot /mnt passwd "$SUDO_USER"

# INSTALL ESSENTIAL_PKGS
echo -e "\n\nInstalling essential packages."
arch-chroot /mnt pacman -S "${ESSENTIAL_PKGS[@]}"

# INSTALL DESKTOP ENVIRONMENT
echo -e "\n\nInstalling Plasma Desktop Environment."
arch-chroot /mnt pacman -S "${PLASMA_PKGS[@]}"
echo -e "\n\nEnabling SDDM service..."
arch-chroot /mnt systemctl enable sddm.service
echo && echo -e "\n\nEnabled..."
sleep 5

# INSTALL GRUB
echo -e "\n\nInstalling GRUB..." && sleep 4
if $(efi_boot_mode) ; then
    arch-chroot /mnt pacman -S "${BOOTLOADER_PKGS[@]}"
    [[ ! -d /mnt/boot/efi ]] && error "Grub Install: No /mnt/boot/efi directory!!!"
    arch-chroot /mnt grub-install "$IN_DEVICE" --target=x86_64-efi --bootloader-id=GRUB --efi-directory=/boot/efi
    echo -e "\n\nEFI GRUB bootloader installed..."
else
    arch-chroot /mnt grub-install "$IN_DEVICE"
    echo -e "\n\MBR bootloader installed..."
fi

echo -e "\n\nConfiguring /boot/grub/grub.cfg..."
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

echo -e "\n\nSystem installed."
echo && echo -e "\nType 'shutdown -h now', remove installation media and reboot"
echo && echo
