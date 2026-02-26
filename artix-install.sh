#!/bin/bash

set -e
set -o pipefail

TITLE="Artix Linux Installer"

if [ "$EUID" -ne 0 ]; then
    echo "Run as root."
    exit 1
fi

validate_input() {
    local input="$1"
    if [ -z "$input" ]; then
        whiptail --title "$TITLE" --msgbox "Input cannot be empty. Installation cancelled." 10 60
        exit 1
    fi
    echo "$input"
}

DISK=$(lsblk -dpno NAME,SIZE | grep -v loop | whiptail \
--title "$TITLE" \
--menu "Select installation disk" 20 70 10 \
$(lsblk -dpno NAME,SIZE | grep -v loop | awk '{print $1 " " $2}') \
3>&1 1>&2 2>&3)

[ -z "$DISK" ] && exit 1

whiptail --title "$TITLE" --yesno "ALL DATA ON $DISK WILL BE DESTROYED" 10 60 || exit 1

umount -R /mnt 2>/dev/null || true
swapoff -a 2>/dev/null || true

wipefs -af "$DISK"

printf "label: gpt\n,512M,U\n,,L\n" | sfdisk "$DISK"

partprobe "$DISK"
udevadm settle
sleep 2

if [[ "$DISK" == *"nvme"* ]]; then
    EFI="${DISK}p1"
    ROOT="${DISK}p2"
else
    EFI="${DISK}1"
    ROOT="${DISK}2"
fi

mkfs.fat -F32 "$EFI"
mkfs.ext4 -F "$ROOT"

mount "$ROOT" /mnt
mkdir -p /mnt/boot
mount "$EFI" /mnt/boot

basestrap /mnt \
base base-devel \
linux linux-firmware \
dinit elogind-dinit \
bash doas vi \
networkmanager networkmanager-dinit \
pipewire pipewire-alsa pipewire-pulse wireplumber \
zramen \
grub efibootmgr \
ntfs-3g dosfstools mtools \
whiptail

fstabgen -U /mnt >> /mnt/etc/fstab

LOCALE=$(whiptail \
--title "$TITLE" \
--menu "Select locale" 25 70 15 \
$(grep "UTF-8" /mnt/etc/locale.gen | sed 's/^#//' | awk '{print $1 " locale"}') \
3>&1 1>&2 2>&3)

LOCALE=$(validate_input "$LOCALE")

sed -i "s/^#$LOCALE UTF-8/$LOCALE UTF-8/" /mnt/etc/locale.gen

artix-chroot /mnt locale-gen

echo "LANG=$LOCALE" > /mnt/etc/locale.conf

TIMEZONE=$(whiptail \
--title "$TITLE" \
--menu "Select timezone" 25 70 15 \
$(timedatectl list-timezones | awk '{print $1 " tz"}') \
3>&1 1>&2 2>&3)

TIMEZONE=$(validate_input "$TIMEZONE")

artix-chroot /mnt ln -sf /usr/share/zoneinfo/"$TIMEZONE" /etc/localtime
artix-chroot /mnt hwclock --systohc

HOSTNAME=$(whiptail \
--title "$TITLE" \
--inputbox "Enter hostname" 10 60 artix \
3>&1 1>&2 2>&3)

HOSTNAME=$(validate_input "$HOSTNAME")

echo "$HOSTNAME" > /mnt/etc/hostname

whiptail --title "$TITLE" --msgbox "Set ROOT password" 8 40
artix-chroot /mnt passwd

USERNAME=$(whiptail \
--title "$TITLE" \
--inputbox "Enter username" 10 60 user \
3>&1 1>&2 2>&3)

USERNAME=$(validate_input "$USERNAME")

artix-chroot /mnt useradd -m -G wheel,audio,video,storage "$USERNAME"

whiptail --title "$TITLE" --msgbox "Set password for $USERNAME" 8 40
artix-chroot /mnt passwd "$USERNAME"

echo "permit persist :wheel" > /mnt/etc/doas.conf
chmod 0400 /mnt/etc/doas.conf

mkdir -p /mnt/etc/dinit.d/boot.d

ln -sf /etc/dinit.d/NetworkManager /mnt/etc/dinit.d/boot.d/
ln -sf /etc/dinit.d/elogind /mnt/etc/dinit.d/boot.d/
ln -sf /etc/dinit.d/zramen /mnt/etc/dinit.d/boot.d/

artix-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Artix
artix-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

umount -R /mnt
sync

if whiptail --title "$TITLE" --yesno "Installation complete. Reboot now?" 10 60; then
    reboot
fi
