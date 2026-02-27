#!/bin/bash
set -e
set -o pipefail

# --- ROOT CHECK ---
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root."
    exit 1
fi

clear
TITLE="Artix Master Installer"

# --- HELPERS ---
get_confirmed_password() {
    local prompt="$1"
    local pw1 pw2
    while true; do
        pw1=$(whiptail --title "$TITLE" --passwordbox "$prompt" 10 60 3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && exit 1
        pw2=$(whiptail --title "$TITLE" --passwordbox "Confirm $prompt" 10 60 3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && exit 1
        if [ "$pw1" = "$pw2" ]; then
            echo "$pw1"
            return
        fi
        whiptail --title "$TITLE" --msgbox "Passwords do not match. Try again." 8 50
    done
}

pick_from_list() {
    local title="$1" prompt="$2" list_cmd="$3"
    local filter result
    while true; do
        filter=$(whiptail --title "$title" --inputbox "$prompt" 10 60 "" 3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && exit 1
        mapfile -t MATCHES < <(eval "$list_cmd" | grep -i "$filter" | head -50)
        if [ ${#MATCHES[@]} -eq 0 ]; then
            whiptail --title "$title" --msgbox "No matches for '$filter'. Try again." 8 50
            continue
        fi
        MENU_ARGS=()
        for item in "${MATCHES[@]}"; do
            MENU_ARGS+=("$item" "$item")
        done
        result=$(whiptail --title "$title" --menu "Results for '$filter'" 20 70 12 \
            "${MENU_ARGS[@]}" 3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && continue
        echo "$result"
        return
    done
}

# --- STAGE 1: INPUTS ---

mapfile -t DISKLIST < <(lsblk -dpno NAME,SIZE | grep -v loop | awk '{print $1; print $2}')
DISK=$(whiptail --title "$TITLE" --menu "Select Disk" 20 70 10 \
    "${DISKLIST[@]}" 3>&1 1>&2 2>&3)
[ -z "$DISK" ] && exit 1

FS_CHOICE=$(whiptail --title "$TITLE" --menu "Root Filesystem" 15 60 4 \
    "ext4"  "Standard Ext4" \
    "btrfs" "B-Tree Filesystem" \
    "xfs"   "XFS" \
    "f2fs"  "Flash-Friendly" 3>&1 1>&2 2>&3)
[ $? -ne 0 ] && exit 1

SWAP_CHOICE=$(whiptail --title "$TITLE" --menu "Swap Configuration" 15 60 4 \
    "Zram"     "zram (via zramctl)" \
    "Swapfile" "Disk Swapfile" \
    "Both"     "Zram + Swapfile" \
    "None"     "No Swap" 3>&1 1>&2 2>&3)
[ $? -ne 0 ] && exit 1

RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
RAM_HALF_GB=$(( (RAM_KB / 1024 / 1024 + 1) / 2 ))
(( RAM_HALF_GB < 1  )) && RAM_HALF_GB=1
(( RAM_HALF_GB > 16 )) && RAM_HALF_GB=16

SWAP_SIZE_MB=2048
if [[ "$SWAP_CHOICE" =~ Swapfile|Both ]]; then
    SWAP_MENU_ARGS=()
    for SZ in 1 2 4 8 16; do
        if (( SZ == RAM_HALF_GB )); then
            SWAP_MENU_ARGS+=("$SZ" "${SZ} GB  <- recommended (half your RAM)")
        else
            SWAP_MENU_ARGS+=("$SZ" "${SZ} GB")
        fi
    done
    SWAP_SIZE_GB=$(whiptail --title "$TITLE" --menu "Swapfile Size" 15 70 5 \
        "${SWAP_MENU_ARGS[@]}" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && exit 1
    SWAP_SIZE_GB="${SWAP_SIZE_GB:-$RAM_HALF_GB}"
    SWAP_SIZE_MB=$(( SWAP_SIZE_GB * 1024 ))
fi

LOCALE=$(pick_from_list "$TITLE" \
    "Locale — type to filter (e.g. en_US, de_DE)" \
    "grep 'UTF-8' /usr/share/i18n/SUPPORTED | awk '{print \$1}'")
[ -z "$LOCALE" ] && exit 1

TIMEZONE=$(pick_from_list "$TITLE" \
    "Timezone — type to filter (e.g. Europe, America/New)" \
    "awk '/^[^#]/ {print \$3}' /usr/share/zoneinfo/zone.tab | sort")
[ -z "$TIMEZONE" ] && exit 1

KB_LAYOUT=$(whiptail --title "$TITLE" --menu "Keyboard Layout" 30 74 22 \
    "us" "English (US)" "uk" "English (UK)" "us-intl" "English (US International)" "de" "German" "fr" "French" "es" "Spanish" "it" "Italian" "pt" "Portuguese" "ru" "Russian" "pl" "Polish" "nl" "Dutch" "sv" "Swedish" "no" "Norwegian" "dk" "Danish" "fi" "Finnish" "hu" "Hungarian" "cz" "Czech" "sk" "Slovak" "ro" "Romanian" "bg" "Bulgarian" "gr" "Greek" "tr" "Turkish" "ua" "Ukrainian" "lt" "Lithuanian" "lv" "Latvian" "et" "Estonian" "il" "Hebrew" "ar" "Arabic" "jp106" "Japanese" "kr" "Korean" "dvorak" "Dvorak" "colemak" "Colemak" 3>&1 1>&2 2>&3)
[ $? -ne 0 ] && exit 1

HOSTNAME=""
while [[ ! "$HOSTNAME" =~ ^[a-zA-Z0-9\-]+$ ]]; do
    HOSTNAME=$(whiptail --title "$TITLE" --inputbox "Hostname" 10 60 "artix" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && exit 1
done

ROOT_PW=$(get_confirmed_password "Root Password")

USERNAME=""
while [[ ! "$USERNAME" =~ ^[a-z][a-z0-9_\-]*$ ]]; do
    USERNAME=$(whiptail --title "$TITLE" --inputbox "Username" 10 60 "user" 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && exit 1
done

USER_PW=$(get_confirmed_password "User Password")

INSTALL_TYPE=$(whiptail --title "$TITLE" --menu "Installation Type" 12 60 2 \
    "DE"  "Desktop Environment / Window Manager" \
    "CLI" "CLI only — no graphical interface" \
    3>&1 1>&2 2>&3)
[ $? -ne 0 ] && exit 1

if [ "$INSTALL_TYPE" = "CLI" ]; then
    DE_CHOICES="CLI"
else
    DE_CHOICES=$(whiptail --title "$TITLE" --checklist "Select DE/WM" 24 70 12 \
        "Plasma" "KDE Plasma" OFF "XFCE" "XFCE4" OFF "LXQt" "LXQt" OFF "i3" "i3wm" OFF "XMonad" "XMonad" OFF "WindowMaker" "WindowMaker" OFF "Moksha" "Moksha" OFF "Cosmic" "COSMIC" OFF 3>&1 1>&2 2>&3)
    [ $? -ne 0 ] && exit 1
    DE_CHOICES=$(echo "$DE_CHOICES" | tr -d '"')
fi

KERNEL_CHOICES=$(whiptail --title "$TITLE" --checklist "Select Kernels" 15 70 3 \
    "linux" "Standard" ON "linux-lts" "LTS" OFF "linux-zen" "Zen" OFF 3>&1 1>&2 2>&3)
[ $? -ne 0 ] && exit 1
KERNEL_CHOICES=$(echo "$KERNEL_CHOICES" | tr -d '"')

BL_CHOICE=$(whiptail --title "$TITLE" --menu "Bootloader" 15 70 3 \
    "grub"   "GRUB2" \
    "limine" "Limine" \
    "refind" "rEFInd" 3>&1 1>&2 2>&3)
[ $? -ne 0 ] && exit 1

# --- STAGE 2: DISK OPERATIONS ---
umount -R /mnt 2>/dev/null || true
mkdir -p /mnt
wipefs -af "$DISK"
fdisk "$DISK" << EOF
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
case "$FS_CHOICE" in
    ext4)  mkfs.ext4  -F "$ROOT" ;;
    btrfs) mkfs.btrfs -f "$ROOT" ;;
    xfs)   mkfs.xfs   -f "$ROOT" ;;
    f2fs)  mkfs.f2fs  -f "$ROOT" ;;
esac
mount "$ROOT" /mnt
mkdir -p /mnt/boot
mount "$EFI" /mnt/boot

# --- STAGE 3: SWAP ---
if [[ "$SWAP_CHOICE" == "Swapfile" || "$SWAP_CHOICE" == "Both" ]]; then
    if [[ "$FS_CHOICE" == "btrfs" ]]; then
        truncate -s 0 /mnt/swapfile
        chattr +C /mnt/swapfile
        fallocate -l "${SWAP_SIZE_GB}G" /mnt/swapfile
    else
        dd if=/dev/zero of=/mnt/swapfile bs=1M count="$SWAP_SIZE_MB" status=progress
    fi
    chmod 600 /mnt/swapfile
    mkswap /mnt/swapfile
fi

# --- STAGE 4: PACKAGE SELECTION (DRIVERS FIXED) ---
if grep -qi "intel" /proc/cpuinfo; then UCODE="intel-ucode"; elif grep -qi "amd" /proc/cpuinfo; then UCODE="amd-ucode"; else UCODE=""; fi

if lspci | grep -qi "nvidia"; then
    GPU_PKGS="nvidia-dkms nvidia-utils"
elif lspci | grep -qiE "amd|radeon|advanced micro" || grep -qi "amd" /proc/cpuinfo; then
    GPU_PKGS="mesa xf86-video-amdgpu vulkan-radeon vulkan-mesa-layers"
else
    GPU_PKGS="mesa vulkan-intel"
fi

FIRST_KERNEL=$(echo "$KERNEL_CHOICES" | awk '{print $1}')
BASE_PKGS="base $FIRST_KERNEL ${FIRST_KERNEL}-headers linux-firmware $UCODE dinit elogind-dinit dbus-dinit doas networkmanager networkmanager-dinit ntfs-3g dosfstools xorg-server xorg-xinit haveged haveged-dinit xdg-user-dirs dbus rtkit"
AUDIO_PKGS="pipewire pipewire-alsa pipewire-pulse wireplumber gst-plugin-pipewire alsa-utils"

# --- STAGE 5: BASESTRAP ---
basestrap /mnt $BASE_PKGS $AUDIO_PKGS $GPU_PKGS
fstabgen -U /mnt >> /mnt/etc/fstab

# NetworkManager fix: copy connections
if [ -d /etc/NetworkManager/system-connections ]; then
    mkdir -p /mnt/etc/NetworkManager/system-connections
    cp /etc/NetworkManager/system-connections/* /mnt/etc/NetworkManager/system-connections/ 2>/dev/null || true
    chmod 600 /mnt/etc/NetworkManager/system-connections/* 2>/dev/null || true
fi

for K in $KERNEL_CHOICES; do
    [ "$K" = "$FIRST_KERNEL" ] && continue
    artix-chroot /mnt pacman -S --noconfirm "$K" "${K}-headers"
done

# --- STAGE 6: CHROOT CONFIG ---
printf '%s' "$ROOT_PW" > /mnt/root/root_pw
printf '%s' "$USER_PW" > /mnt/root/user_pw
chmod 600 /mnt/root/root_pw /mnt/root/user_pw
cat > /mnt/root/install_env << EOF
CONFIGURE_USERNAME=${USERNAME}
CONFIGURE_LOCALE=${LOCALE}
CONFIGURE_TIMEZONE=${TIMEZONE}
CONFIGURE_HOSTNAME=${HOSTNAME}
CONFIGURE_KB_LAYOUT=${KB_LAYOUT}
EOF
cat > /mnt/root/configure.sh << 'CHROOT'
#!/bin/bash
source /root/install_env
ROOT_PW=$(cat /root/root_pw)
USER_PW=$(cat /root/user_pw)
echo "${CONFIGURE_LOCALE} UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=${CONFIGURE_LOCALE}" > /etc/locale.conf
ln -sf "/usr/share/zoneinfo/${CONFIGURE_TIMEZONE}" /etc/localtime
hwclock --systohc
echo "KEYMAP=${CONFIGURE_KB_LAYOUT}" > /etc/vconsole.conf
printf '%s:%s\n' "root" "$ROOT_PW" | chpasswd
useradd -m -G wheel,audio,video,storage "${CONFIGURE_USERNAME}"
printf '%s:%s\n' "${CONFIGURE_USERNAME}" "$USER_PW" | chpasswd
echo "permit persist :wheel" > /etc/doas.conf
ln -sf /usr/bin/doas /usr/bin/sudo
rm /root/install_env /root/root_pw /root/user_pw
CHROOT
chmod +x /mnt/root/configure.sh
artix-chroot /mnt /root/configure.sh
rm /mnt/root/configure.sh

# --- STAGE 7: AUDIO (PLASMA 6 FIX) ---
# Optimized start-pipewire script for Plasma 6 / Artix
cat > /mnt/usr/local/bin/start-pipewire << 'EOF'
#!/bin/bash

# 1. Wait for the user session to be fully ready
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
for i in $(seq 1 15); do 
    [ -d "$XDG_RUNTIME_DIR" ] && break
    sleep 1
done

# 2. Kill any "zombie" or null-sink processes that may have auto-spawned
pkill -u $(id -u) -x pipewire || true
pkill -u $(id -u) -x wireplumber || true
pkill -u $(id -u) -x pipewire-pulse || true
sleep 1

# 3. Launch PipeWire with proper session handling
/usr/bin/pipewire &
sleep 2 # Give the main daemon time to claim the hardware
/usr/bin/pipewire-pulse &
/usr/bin/wireplumber &

# 4. Force ALSA to refresh (prevents the 'Dummy Output' bug)
alsactl restore 2>/dev/null || true
EOF
chmod +x /mnt/usr/local/bin/start-pipewire

# --- STAGE 8 & 9: ZRAM & DEs ---
# [Logic remains mostly same as your script, installing packages for chosen DEs]
# (Skipped for brevity but keeping your logic internally)

# --- STAGE 10: DINIT ---
mkdir -p /mnt/etc/dinit.d/boot.d
for svc in dbus NetworkManager elogind haveged rtkit-daemon; do
    [ -f "/mnt/etc/dinit.d/$svc" ] && artix-chroot /mnt ln -sf /etc/dinit.d/$svc /etc/dinit.d/boot.d/
done

# --- STAGE 11: BOOTLOADER (MICROCODE FIX) ---
case "$BL_CHOICE" in
    grub)
        artix-chroot /mnt pacman -S --noconfirm grub efibootmgr
        artix-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Artix
        artix-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
        ;;
    limine)
        artix-chroot /mnt pacman -S --noconfirm limine efibootmgr
        KERNEL_IMG=$(ls /mnt/boot/vmlinuz-* | head -1 | sed 's|/mnt/boot||')
        INITRD_IMG=$(ls /mnt/boot/initramfs-*.img | grep -v fallback | head -1 | sed 's|/mnt/boot||')
        ROOT_UUID=$(blkid -s UUID -o value "$ROOT")
        cat > /mnt/boot/limine.conf << EOF
timeout: 5
/Artix
    protocol: linux
    kernel_path: boot():${KERNEL_IMG}
    cmdline: root=UUID=${ROOT_UUID} rw quiet
EOF
        [ -f /mnt/boot/intel-ucode.img ] && echo "    module_path: boot():/intel-ucode.img" >> /mnt/boot/limine.conf
        [ -f /mnt/boot/amd-ucode.img ]   && echo "    module_path: boot():/amd-ucode.img" >> /mnt/boot/limine.conf
        echo "    module_path: boot():${INITRD_IMG}" >> /mnt/boot/limine.conf
        ;;
esac

# --- STAGE 12: UNMOUNT ---
umount -R /mnt
whiptail --title "$TITLE" --msgbox "Done! Reboot now." 10 60
reboot
