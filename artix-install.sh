#!/bin/bash

set -e
set -o pipefail

if [ "$EUID" -ne 0 ]; then
    echo "Run as root."
    exit 1
fi

clear
TITLE="Artix Linux Installer"

get_password() {
    local prompt="$1"
    local pw=""
    while [ -z "$pw" ]; do
        pw=$(whiptail --title "$TITLE" --passwordbox "$prompt" 10 60 3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && exit 1
    done
    echo "$pw"
}

validate_input() {
    local input="$1"
    if [ -z "$input" ]; then
        whiptail --title "$TITLE" --msgbox "Input cannot be empty. Installation cancelled." 10 60
        exit 1
    fi
    echo "$input"
}

# 1. Disk Selection
DISK=$(lsblk -dpno NAME,SIZE | grep -v loop | whiptail \
--title "$TITLE" \
--menu "Select installation disk (Use arrows/type first letter)" 20 70 10 \
$(lsblk -dpno NAME,SIZE | grep -v loop | awk '{print $1 " " $2}') \
3>&1 1>&2 2>&3)

[ -z "$DISK" ] && exit 1

whiptail --title "$TITLE" --yesno "ALL DATA ON $DISK WILL BE DESTROYED" 10 60 || exit 1

# 2. File System & Swap Choices
FS_CHOICE=$(whiptail --title "$TITLE" --menu "Select Root File System" 15 60 4 \
"ext4" "Standard Ext4" \
"btrfs" "B-Tree Filesystem" \
"xfs" "XFS Filesystem" \
"f2fs" "Flash-Friendly Filesystem" 3>&1 1>&2 2>&3)

SWAP_CHOICE=$(whiptail --title "$TITLE" --menu "Select Swap Configuration" 15 60 4 \
"Zram" "Use zramen (Compressed RAM)" \
"Swapfile" "Create a 4GB Swapfile" \
"Both" "Zram + 4GB Swapfile" \
"None" "No Swap" 3>&1 1>&2 2>&3)

# 3. Cleanup & Partitioning
umount -R /mnt 2>/dev/null || true
swapoff -a 2>/dev/null || true
wipefs -af "$DISK"

fdisk "$DISK" <<EOF
g
n
1

+1G
t
1
n
2


w
EOF

udevadm settle
sleep 2

if [[ "$DISK" =~ [0-9]$ ]]; then
    EFI="${DISK}p1"
    ROOT="${DISK}p2"
else
    EFI="${DISK}1"
    ROOT="${DISK}2"
fi

# Format EFI
mkfs.fat -F32 "$EFI"

# Format Root based on choice
case $FS_CHOICE in
    ext4)  mkfs.ext4 -F "$ROOT" ;;
    btrfs) mkfs.btrfs -f "$ROOT" ;;
    xfs)   mkfs.xfs -f "$ROOT" ;;
    f2fs)  mkfs.f2fs -f "$ROOT" ;;
esac

mount "$ROOT" /mnt
mkdir -p /mnt/boot
mount "$EFI" /mnt/boot

# 4. Swapfile Creation (if selected)
if [[ "$SWAP_CHOICE" == "Swapfile" || "$SWAP_CHOICE" == "Both" ]]; then
    echo "Creating 4GB swapfile..."
    dd if=/dev/zero of=/mnt/swapfile bs=1M count=4096 status=progress
    chmod 0600 /mnt/swapfile
    mkswap /mnt/swapfile
fi

# 5. Build Package List
BASE_PKGS="base base-devel linux linux-firmware intel-ucode amd-ucode dinit elogind-dinit dbus-dinit doas vi networkmanager networkmanager-dinit grub efibootmgr ntfs-3g dosfstools mtools libnewt"
AUDIO_PKGS="pipewire pipewire-alsa pipewire-pulse wireplumber alsa-utils pavucontrol"

FS_PKGS=""
[[ "$FS_CHOICE" == "btrfs" ]] && FS_PKGS="btrfs-progs"
[[ "$FS_CHOICE" == "xfs" ]]   && FS_PKGS="xfsprogs"
[[ "$FS_CHOICE" == "f2fs" ]]  && FS_PKGS="f2fs-tools"

SWAP_PKGS=""
[[ "$SWAP_CHOICE" == "Zram" || "$SWAP_CHOICE" == "Both" ]] && SWAP_PKGS="zramen zramen-dinit"

# 6. Basestrap
basestrap /mnt $BASE_PKGS $AUDIO_PKGS $FS_PKGS $SWAP_PKGS

fstabgen -U /mnt >> /mnt/etc/fstab

# Add swapfile to fstab if it was created
if [[ "$SWAP_CHOICE" == "Swapfile" || "$SWAP_CHOICE" == "Both" ]]; then
    echo "/swapfile none swap defaults 0 0" >> /mnt/etc/fstab
fi

# 7. Desktop Environment Selection
DE_CHOICE=$(whiptail --title "$TITLE" --menu "Select Desktop Environment" 20 70 6 \
"Plasma" "KDE Plasma Full Suite" \
"XFCE" "XFCE4 + Goodies (Lightweight)" \
"MATE" "MATE Desktop + Extra" \
"LXQt" "LXQt Desktop" \
"Moksha" "Moksha Desktop (Enlightenment fork)" \
"None" "Standard CLI only" 3>&1 1>&2 2>&3)

# 8. Localization
LOCALE=$(whiptail --title "$TITLE" --menu "Select locale (Type letter to jump)" 20 70 10 \
$(grep "UTF-8" /mnt/usr/share/i18n/SUPPORTED | awk '{print $1 " " $1}') 3>&1 1>&2 2>&3)
LOCALE=$(validate_input "$LOCALE")

echo "$LOCALE UTF-8" >> /mnt/etc/locale.gen
artix-chroot /mnt locale-gen
echo "LANG=$LOCALE" > /mnt/etc/locale.conf

TIMEZONE=$(whiptail --title "$TITLE" --menu "Select timezone (Type letter to jump)" 20 70 10 \
$(awk '/^[^#]/ {print $3 " " $3}' /mnt/usr/share/zoneinfo/zone.tab | sort) 3>&1 1>&2 2>&3)
TIMEZONE=$(validate_input "$TIMEZONE")

artix-chroot /mnt ln -sf /usr/share/zoneinfo/"$TIMEZONE" /etc/localtime
artix-chroot /mnt hwclock --systohc

# 9. Hostname & User Configuration
HOSTNAME=$(whiptail --title "$TITLE" --inputbox "Enter hostname" 10 60 artix 3>&1 1>&2 2>&3)
HOSTNAME=$(validate_input "$HOSTNAME")
echo "$HOSTNAME" > /mnt/etc/hostname

ROOT_PW=$(get_password "Enter Root Password")
echo "root:$ROOT_PW" | artix-chroot /mnt chpasswd

USERNAME=$(whiptail --title "$TITLE" --inputbox "Enter username" 10 60 user 3>&1 1>&2 2>&3)
USERNAME=$(validate_input "$USERNAME")
USER_PW=$(get_password "Enter password for $USERNAME")

artix-chroot /mnt useradd -m -G wheel,audio,video,storage "$USERNAME"
echo "$USERNAME:$USER_PW" | artix-chroot /mnt chpasswd

echo "permit persist :wheel" > /mnt/etc/doas.conf
artix-chroot /mnt chown root:root /etc/doas.conf
artix-chroot /mnt chmod 0400 /etc/doas.conf

# 10. Install Desktop Environment
case $DE_CHOICE in
    Plasma) artix-chroot /mnt pacman -S --noconfirm plasma kde-applications sddm-dinit ;;
    XFCE)   artix-chroot /mnt pacman -S --noconfirm xfce4 xfce4-goodies lightdm-dinit ;;
    MATE)   artix-chroot /mnt pacman -S --noconfirm mate mate-extra system-config-printer blueman connman-gtk lightdm-dinit ;;
    LXQt)   artix-chroot /mnt pacman -S --noconfirm lxqt sddm-dinit ;;
    Moksha) artix-chroot /mnt pacman -S --noconfirm moksha-artix lightdm-dinit ;;
    None)   echo "No DE selected." ;;
esac

# 11. Services & Bootloader
artix-chroot /mnt mkdir -p /etc/dinit.d/boot.d
[[ "$DE_CHOICE" == "Plasma" || "$DE_CHOICE" == "LXQt" ]] && DM="sddm"
[[ "$DE_CHOICE" == "XFCE" || "$DE_CHOICE" == "MATE" || "$DE_CHOICE" == "Moksha" ]] && DM="lightdm"

for svc in dbus NetworkManager elogind zramen $DM; do
    [ -f "/mnt/etc/dinit.d/$svc" ] && artix-chroot /mnt ln -sf /etc/dinit.d/$svc /etc/dinit.d/boot.d/
done

artix-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Artix
artix-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

# 12. Finish
umount -R /mnt
sync

if whiptail --title "$TITLE" --yesno "Installation complete! Would you like to reboot now?" 10 60; then
    reboot
else
    clear
    echo "================================================================"
    echo "Installation finished. You are still in the live environment."
    echo "You can chroot into your new system to make additional changes:"
    echo "  artix-chroot /mnt"
    echo "When you are done, simply type 'reboot'."
    echo "================================================================"
fi
