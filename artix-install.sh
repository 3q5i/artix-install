
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

# 1. Choose Desktop Environment / WM / Shell
UI_TYPE=$(whiptail --title "$TITLE" --menu "Choose interface type:" 20 60 3 \
"DE" "Desktop Environment" \
"WM" "Window Manager" \
"SHELL" "CLI Shell Only" 3>&1 1>&2 2>&3)
validate_input "$UI_TYPE"

if [[ "$UI_TYPE" == "DE" ]]; then
    DE_CHOICE=$(whiptail --title "$TITLE" --menu "Select Desktop Environment:" 20 70 5 \
    "Plasma" "KDE Plasma Full Suite" \
    "XFCE" "XFCE4 + Goodies" \
    "MATE" "MATE Desktop + Extras" \
    "LXQt" "LXQt Desktop" \
    "Moksha" "Moksha Desktop (Enlightenment fork)" 3>&1 1>&2 2>&3)
    validate_input "$DE_CHOICE"
elif [[ "$UI_TYPE" == "WM" ]]; then
    WM_CHOICE=$(whiptail --title "$TITLE" --menu "Select Window Manager:" 20 60 3 \
    "i3" "i3 Tiling WM" \
    "xmonad" "xmonad Tiling WM" \
    "WindowMaker" "Window Maker" 3>&1 1>&2 2>&3)
    validate_input "$WM_CHOICE"
fi

# 2. Disk Selection
DISK=$(lsblk -dpnoNAME,SIZE | grep -v loop | whiptail \
--title "$TITLE" \
--menu "Select installation disk (Use arrows/type first letter)" 20 70 10 \
$(lsblk -dpnoNAME,SIZE | grep -v loop | awk '{print $1 " " $2}') 3>&1 1>&2 2>&3)
validate_input "$DISK"

whiptail --title "$TITLE" --yesno "ALL DATA ON $DISK WILL BE DESTROYED" 10 60 || exit 1

# 3. Filesystem & Swap
FS_CHOICE=$(whiptail --title "$TITLE" --menu "Select Root File System:" 15 60 4 \
"ext4" "Ext4 Standard" \
"btrfs" "Btrfs" \
"xfs" "XFS" \
"f2fs" "F2FS" 3>&1 1>&2 2>&3)
validate_input "$FS_CHOICE"

SWAPSIZE=$(whiptail --title "$TITLE" --inputbox "Enter swap size (e.g., 8G):" 10 60 "8G" 3>&1 1>&2 2>&3)
validate_input "$SWAPSIZE"

# 4. User Info
HOSTNAME=$(whiptail --title "$TITLE" --inputbox "Enter hostname:" 10 60 artix 3>&1 1>&2 2>&3)
validate_input "$HOSTNAME"

ROOT_PW=$(get_password "Enter root password:")
USERNAME=$(whiptail --title "$TITLE" --inputbox "Enter username:" 10 60 user 3>&1 1>&2 2>&3)
validate_input "$USERNAME"
USER_PW=$(get_password "Enter password for $USERNAME:")

# --- Partitioning ---
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
[[ "$DISK" =~ [0-9]$ ]] && P="p" || P=""
EFI="${DISK}${P}1"
ROOT="${DISK}${P}2"

mkfs.fat -F32 "$EFI"
case $FS_CHOICE in
    ext4)  mkfs.ext4 -F "$ROOT" ;;
    btrfs) mkfs.btrfs -f "$ROOT" ;;
    xfs)   mkfs.xfs -f "$ROOT" ;;
    f2fs)  mkfs.f2fs -f "$ROOT" ;;
esac

mount "$ROOT" /mnt
mkdir -p /mnt/boot && mount "$EFI" /mnt/boot

# --- Swap ---
if [[ "$SWAPSIZE" != "0" ]]; then
    dd if=/dev/zero of=/mnt/swapfile bs=1M count=$(echo "$SWAPSIZE" | sed 's/G/*1024/' | bc) status=progress
    chmod 0600 /mnt/swapfile
    mkswap /mnt/swapfile
    swapon /mnt/swapfile
fi

# --- Package Installation ---
BASE_PKGS="base base-devel linux linux-firmware intel-ucode amd-ucode dinit elogind-dinit dbus-dinit doas vi networkmanager networkmanager-dinit grub efibootmgr ntfs-3g dosfstools mtools whiptail"
AUDIO_PKGS="pipewire pipewire-alsa pipewire-pulse wireplumber alsa-utils pavucontrol"
FS_PKGS=""
[[ "$FS_CHOICE" == "btrfs" ]] && FS_PKGS="btrfs-progs"
[[ "$FS_CHOICE" == "xfs" ]] && FS_PKGS="xfsprogs"
[[ "$FS_CHOICE" == "f2fs" ]] && FS_PKGS="f2fs-tools"

basestrap /mnt $BASE_PKGS $AUDIO_PKGS $FS_PKGS

fstabgen -U /mnt >> /mnt/etc/fstab
[[ "$SWAPSIZE" != "0" ]] && echo "/swapfile none swap defaults 0 0" >> /mnt/etc/fstab

# --- Localization & Timezone ---
LOCALE=$(whiptail --title "$TITLE" --menu "Select locale:" 20 70 10 \
$(grep "UTF-8" /mnt/usr/share/i18n/SUPPORTED | awk '{print $1 " " $1}') 3>&1 1>&2 2>&3)
validate_input "$LOCALE"
echo "$LOCALE UTF-8" >> /mnt/etc/locale.gen
artix-chroot /mnt locale-gen
echo "LANG=$LOCALE" > /mnt/etc/locale.conf

TIMEZONE=$(whiptail --title "$TITLE" --menu "Select timezone:" 20 70 10 \
$(awk '/^[^#]/ {print $3 " " $3}' /mnt/usr/share/zoneinfo/zone.tab | sort) 3>&1 1>&2 2>&3)
validate_input "$TIMEZONE"
artix-chroot /mnt ln -sf /usr/share/zoneinfo/"$TIMEZONE" /etc/localtime
artix-chroot /mnt hwclock --systohc

# --- Hostname & Users ---
echo "$HOSTNAME" > /mnt/etc/hostname
echo "root:$ROOT_PW" | artix-chroot /mnt chpasswd
artix-chroot /mnt useradd -m -G wheel,audio,video,storage "$USERNAME"
echo "$USERNAME:$USER_PW" | artix-chroot /mnt chpasswd
echo "permit persist :wheel" > /mnt/etc/doas.conf
artix-chroot /mnt chown root:root /etc/doas.conf
artix-chroot /mnt chmod 0400 /etc/doas.conf

# --- DE/WM Installation ---
if [[ "$UI_TYPE" == "DE" ]]; then
    case $DE_CHOICE in
        Plasma) artix-chroot /mnt pacman -S --noconfirm plasma kde-applications sddm-dinit ;;
        XFCE)   artix-chroot /mnt pacman -S --noconfirm xfce4 xfce4-goodies lightdm-dinit ;;
        MATE)   artix-chroot /mnt pacman -S --noconfirm mate mate-extra system-config-printer blueman connman-gtk lightdm-dinit ;;
        LXQt)   artix-chroot /mnt pacman -S --noconfirm lxqt sddm-dinit ;;
        Moksha) artix-chroot /mnt pacman -S --noconfirm moksha-artix lightdm-dinit ;;
    esac
elif [[ "$UI_TYPE" == "WM" ]]; then
    case $WM_CHOICE in
        i3) artix-chroot /mnt pacman -S --noconfirm i3-gaps i3status dmenu ;;
        xmonad) artix-chroot /mnt pacman -S --noconfirm xmonad xmonad-contrib xmobar ;;
        WindowMaker) artix-chroot /mnt pacman -S --noconfirm windowmaker wmaker-tools ;;
    esac
fi

# --- Enable Services & Bootloader ---
artix-chroot /mnt mkdir -p /etc/dinit.d/boot.d
for svc in dbus NetworkManager elogind zramen sddm lightdm; do
    [ -f "/mnt/etc/dinit.d/$svc" ] && artix-chroot /mnt ln -sf /etc/dinit.d/$svc /etc/dinit.d/boot.d/
done

artix-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Artix
artix-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

# --- Finish ---
umount -R /mnt
sync

if whiptail --title "$TITLE" --yesno "Installation complete! Reboot now?" 10 60; then
    reboot
else
    clear
    echo "Installation finished. Still in live environment."
    echo "Chroot into new system with: artix-chroot /mnt"
    echo "Reboot manually when ready."
fi
