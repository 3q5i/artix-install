#!/bin/bash
set -e
set -o pipefail

# Must run as root
if [ "$EUID" -ne 0 ]; then
    echo "Run this script as root."
    exit 1
fi

TITLE="Artix Linux Installer"

# Helper to validate input
validate_input() {
    local input="$1"
    if [ -z "$input" ]; then
        whiptail --title "$TITLE" --msgbox "Input cannot be empty. Installation cancelled." 10 60
        exit 1
    fi
    echo "$input"
}

# Select disk
DISK=$(lsblk -dpnoNAME,SIZE | grep -v loop | whiptail \
--title "$TITLE" \
--menu "Select installation disk" 20 70 10 \
$(lsblk -dpnoNAME,SIZE | grep -v loop | awk '{print $1 " " $2}') \
3>&1 1>&2 2>&3)
[ -z "$DISK" ] && exit 1

# Confirm
whiptail --title "$TITLE" --yesno "ALL DATA ON $DISK WILL BE DESTROYED" 10 60 || exit 1

# Cleanup previous mounts/swap
swapoff -a 2>/dev/null || true
umount -R /mnt 2>/dev/null || true

# Partition disk (EFI 512M, rest root)
wipefs -af "$DISK"
printf "label: gpt\n,512M,U\n,,L\n" | sfdisk --force "$DISK"
sync
udevadm settle
sleep 2

# Partition names
if [[ "$DISK" == *nvme* ]]; then
    EFI="${DISK}p1"
    ROOT="${DISK}p2"
else
    EFI="${DISK}1"
    ROOT="${DISK}2"
fi

# Format
mkfs.fat -F32 "$EFI"
mkfs.ext4 -F "$ROOT"

# Mount
mount "$ROOT" /mnt
mkdir -p /mnt/boot
mount "$EFI" /mnt/boot

# Base installation
basestrap /mnt \
base base-devel \
linux linux-firmware \
dinit elogind-dinit \
doas vi \
networkmanager networkmanager-dinit \
pipewire pipewire-alsa pipewire-pulse wireplumber \
zramen \
grub efibootmgr \
ntfs-3g dosfstools mtools \
whiptail git htop fastfetch

# Generate fstab
fstabgen -U /mnt >> /mnt/etc/fstab

# Locale selection
LOCALE=$(whiptail --title "$TITLE" --menu "Select locale" 20 70 10 \
$(grep "UTF-8" /mnt/usr/share/i18n/SUPPORTED | head -20 | awk '{print $1 " (UTF-8)"}') \
3>&1 1>&2 2>&3)
LOCALE=$(validate_input "$LOCALE")
echo "$LOCALE UTF-8" >> /mnt/etc/locale.gen
arch-chroot /mnt locale-gen
echo "LANG=$LOCALE" > /mnt/etc/locale.conf

# Timezone
TIMEZONE=$(whiptail --title "$TITLE" --menu "Select timezone" 20 70 10 \
$(timedatectl list-timezones | head -20 | awk '{print $1 " "}') \
3>&1 1>&2 2>&3)
TIMEZONE=$(validate_input "$TIMEZONE")
arch-chroot /mnt ln -sf /usr/share/zoneinfo/"$TIMEZONE" /etc/localtime
arch-chroot /mnt hwclock --systohc

# Hostname
HOSTNAME=$(whiptail --title "$TITLE" --inputbox "Enter hostname" 10 60 artix 3>&1 1>&2 2>&3)
HOSTNAME=$(validate_input "$HOSTNAME")
echo "$HOSTNAME" > /mnt/etc/hostname

# Root password
arch-chroot /mnt passwd

# Regular user
USERNAME=$(whiptail --title "$TITLE" --inputbox "Enter username" 10 60 user 3>&1 1>&2 2>&3)
USERNAME=$(validate_input "$USERNAME")
arch-chroot /mnt useradd -m -G wheel,audio,video,storage "$USERNAME"
arch-chroot /mnt passwd "$USERNAME"

# DOAS config
echo "permit persist :wheel" > /mnt/etc/doas.conf
arch-chroot /mnt chown root:root /etc/doas.conf
arch-chroot /mnt chmod 0400 /etc/doas.conf

# Enable essential services
arch-chroot /mnt ln -s /etc/dinit.d/networkmanager /etc/dinit.d/boot.d/
arch-chroot /mnt ln -s /etc/dinit.d/elogind /etc/dinit.d/boot.d/
arch-chroot /mnt ln -s /etc/dinit.d/zramen /etc/dinit.d/boot.d/

# Install GRUB
arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Artix
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

# Done
umount -R /mnt
sync

if whiptail --title "$TITLE" --yesno "Installation complete. Reboot now?" 10 60; then
    reboot
else
    echo "Reboot manually later."
fi
