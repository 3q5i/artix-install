#!/bin/bash
set -e
set -o pipefail

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root."
    exit 1
fi

clear
TITLE="Artix Linux Hardware-Ready Installer"

# --- HELPERS ---
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
    if [ -z "$input" ]; then exit 1; fi
    echo "$input"
}

# --- STAGE 1: INPUTS ---
DISK=$(lsblk -dpnoNAME,SIZE | grep -v loop | whiptail --title "$TITLE" --menu "Select Disk" 20 70 10 $(lsblk -dpnoNAME,SIZE | grep -v loop | awk '{print $1 " " $2}') 3>&1 1>&2 2>&3)
[ -z "$DISK" ] && exit 1

FS_CHOICE=$(whiptail --title "$TITLE" --menu "Select Filesystem" 15 60 4 "ext4" "Ext4" "btrfs" "Btrfs" "xfs" "XFS" "f2fs" "F2FS" 3>&1 1>&2 2>&3)
SWAPSIZE=$(whiptail --title "$TITLE" --inputbox "Swap size (e.g. 8G)" 10 60 "8G" 3>&1 1>&2 2>&3)

LOCALE=$(whiptail --title "$TITLE" --menu "Locale" 20 70 10 $(grep "UTF-8" /usr/share/i18n/SUPPORTED | awk '{print $1 " " $1}') 3>&1 1>&2 2>&3)
TIMEZONE=$(whiptail --title "$TITLE" --menu "Timezone" 20 70 10 $(awk '/^[^#]/ {print $3 " " $3}' /usr/share/zoneinfo/zone.tab | sort) 3>&1 1>&2 2>&3)

HOSTNAME=$(whiptail --title "$TITLE" --inputbox "Hostname" 10 60 "artix" 3>&1 1>&2 2>&3)
ROOT_PW=$(get_password "Root Password")
USERNAME=$(whiptail --title "$TITLE" --inputbox "Username" 10 60 "user" 3>&1 1>&2 2>&3)
USER_PW=$(get_password "User Password")

DE_CHOICE=$(whiptail --title "$TITLE" --menu "Desktop" 20 70 6 "Plasma" "KDE" "XFCE" "XFCE" "i3" "i3-WM" 3>&1 1>&2 2>&3)

# --- STAGE 2: DISK OPS ---
wipefs -af "$DISK"
fdisk "$DISK" <<EOF
g
n
1

+1G
t
1
1
n
2


w
EOF
udevadm settle
[[ "$DISK" =~ [0-9]$ ]] && P="p" || P=""
EFI="${DISK}${P}1"
ROOT="${DISK}${P}2"

mkfs.fat -F32 "$EFI"
case $FS_CHOICE in
    ext4) mkfs.ext4 -F "$ROOT" ;;
    btrfs) mkfs.btrfs -f "$ROOT" ;;
    xfs) mkfs.xfs -f "$ROOT" ;;
    f2fs) mkfs.f2fs -f "$ROOT" ;;
esac

mount "$ROOT" /mnt
mkdir -p /mnt/boot
mount "$EFI" /mnt/boot

# --- STAGE 3: SWAP & BASE ---
# Added wpa_supplicant and wireless-regdb for WiFi support
BASE_PKGS="base base-devel linux linux-firmware intel-ucode amd-ucode dinit elogind-dinit dbus-dinit doas vi networkmanager networkmanager-dinit wpa_supplicant wireless-regdb grub efibootmgr mesa xorg-server"
AUDIO_PKGS="pipewire pipewire-alsa pipewire-pulse wireplumber alsa-utils pavucontrol"

basestrap /mnt $BASE_PKGS $AUDIO_PKGS
fstabgen -U /mnt >> /mnt/etc/fstab

# --- STAGE 4: CONFIG ---
echo "$LOCALE UTF-8" >> /mnt/etc/locale.gen
artix-chroot /mnt locale-gen
echo "LANG=$LOCALE" > /mnt/etc/locale.conf
artix-chroot /mnt ln -sf /usr/share/zoneinfo/"$TIMEZONE" /etc/localtime
echo "$HOSTNAME" > /mnt/etc/hostname

# User & Security
echo "root:$ROOT_PW" | artix-chroot /mnt chpasswd
artix-chroot /mnt useradd -m -G wheel,audio,video,storage "$USERNAME"
echo "$USERNAME:$USER_PW" | artix-chroot /mnt chpasswd
echo "permit persist :wheel" > /mnt/etc/doas.conf
artix-chroot /mnt ln -sf /usr/bin/doas /usr/bin/sudo

# --- HARDWARE AUTO-CONFIG ---
# 1. Enable Services
artix-chroot /mnt mkdir -p /etc/dinit.d/boot.d
for svc in dbus networkmanager elogind; do
    artix-chroot /mnt ln -sf /etc/dinit.d/$svc /etc/dinit.d/boot.d/
done

# 2. Audio Autostart (Global Profile)
artix-chroot /mnt bash -c "cat > /etc/profile.d/pipewire-start.sh <<EOF
if [ -n \"\\\$DISPLAY\" ] || [ -n \"\\\$WAYLAND_DISPLAY\" ]; then
    pgrep -x pipewire > /dev/null || pipewire &
    pgrep -x pipewire-pulse > /dev/null || pipewire-pulse &
    pgrep -x wireplumber > /dev/null || wireplumber &
fi
EOF"

# 3. DE Install
case $DE_CHOICE in
    Plasma) artix-chroot /mnt pacman -S --noconfirm plasma kde-applications sddm-dinit ;;
    XFCE)   artix-chroot /mnt pacman -S --noconfirm xfce4 xfce4-goodies lightdm-dinit ;;
    i3)     artix-chroot /mnt pacman -S --noconfirm i3-wm dmenu lightdm-dinit xterm ;;
esac

# 4. DM Service
DM="lightdm"
[[ "$DE_CHOICE" == "Plasma" ]] && DM="sddm"
artix-chroot /mnt ln -sf /etc/dinit.d/$DM /etc/dinit.d/boot.d/

# --- STAGE 5: BOOT ---
artix-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Artix
artix-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

umount -R /mnt
whiptail --title "$TITLE" --msgbox "Done! Reboot and your WiFi/Audio should work." 10 60
reboot
