#!/bin/bash

# --- PRE-FLIGHT CHECKS ---
if [[ $EUID -ne 0 ]]; then
    whiptail --title "Error" --msgbox "This installer must be run as root." 10 60
    exit 1
fi

# Define a log file for background processes
LOG="/var/log/artix-install.log"
echo "Starting installation..." > "$LOG"

# Helper function to handle fatal errors
die() {
    clear
    echo -e "\n[FATAL ERROR] $1"
    echo "Check $LOG for more details."
    exit 1
}

# --- USER INPUT ---
DISK=$(lsblk -dpno NAME,SIZE | grep -E "/dev/sd|/dev/nvme" | \
whiptail --menu "Select disk for installation" 20 80 10 \
$(lsblk -dpno NAME,SIZE | grep -E "/dev/sd|/dev/nvme") \
3>&1 1>&2 2>&3)

[[ -z "$DISK" ]] && exit 1

SWAPSIZE=$(whiptail --inputbox "Enter swap size (e.g., 8G):" 10 60 "8G" 3>&1 1>&2 2>&3)
[[ -z "$SWAPSIZE" ]] && exit 1

USERNAME=$(whiptail --inputbox "Enter your new username:" 10 60 "user" 3>&1 1>&2 2>&3)
[[ -z "$USERNAME" ]] && exit 1

ROOT_PASS=$(whiptail --passwordbox "Enter a password for ROOT:" 10 60 3>&1 1>&2 2>&3)
USER_PASS=$(whiptail --passwordbox "Enter a password for $USERNAME:" 10 60 3>&1 1>&2 2>&3)

whiptail --title "WARNING" --yesno "This will completely erase ALL data on $DISK. Are you absolutely sure?" 10 60 || exit 1

# --- PREPARATION & PARTITIONING ---
clear
echo "Cleaning up existing mounts and wiping $DISK..."

swapoff -a
umount -R /mnt 2>/dev/null || true
rm -rf /mnt
mkdir -p /mnt

for p in $(lsblk -ln -o NAME "$DISK" | tail -n +2); do
    umount -l "/dev/$p" 2>/dev/null || true
done

fuser -km "$DISK" 2>/dev/null || true
dd if=/dev/zero of="$DISK" bs=1M count=10 status=none 2>> "$LOG"

echo "Partitioning disk..."
printf "label: gpt\n,1G,U\n,%s,S\n,,L\n" "$SWAPSIZE" | sfdisk "$DISK" >> "$LOG" 2>&1 || die "Failed to partition $DISK."

if [[ "$DISK" == *"nvme"* ]]; then
    EFI="${DISK}p1"
    SWAP="${DISK}p2"
    ROOT="${DISK}p3"
else
    EFI="${DISK}1"
    SWAP="${DISK}2"
    ROOT="${DISK}3"
fi

echo "Formatting partitions..."
mkfs.fat -F32 "$EFI" >> "$LOG" 2>&1 || die "Failed to format EFI partition."
mkswap "$SWAP" >> "$LOG" 2>&1 || die "Failed to format Swap partition."
swapon "$SWAP" >> "$LOG" 2>&1
mkfs.xfs -f "$ROOT" >> "$LOG" 2>&1 || die "Failed to format Root partition."

mount "$ROOT" /mnt
mkdir -p /mnt/boot
mount "$EFI" /mnt/boot

# --- BASE SYSTEM INSTALLATION ---
CPU_VENDOR=$(grep vendor_id /proc/cpuinfo | head -n 1 | awk '{print $3}')
if [[ "$CPU_VENDOR" == "AuthenticAMD" ]]; then
    UCODE="amd-ucode"
else
    UCODE="intel-ucode"
fi

clear
echo "======================================================="
echo " Installing base system... (This will take a few mins) "
echo "======================================================="
# We do NOT redirect basestrap to the log so you can visually confirm if it fails to download
basestrap /mnt base base-devel dinit elogind-dinit linux-zen linux-firmware $UCODE \
grub efibootmgr os-prober vim fastfetch \
networkmanager networkmanager-dinit dbus dbus-dinit opendoas git \
pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber rtkit-daemon || die "Basestrap failed! Check your internet connection or mirrorlist."

fstabgen -U /mnt >> /mnt/etc/fstab || die "Failed to generate fstab."

# --- CHROOT CONFIGURATION ---
echo "Configuring bootloader and services..."
artix-chroot /mnt /bin/bash -c "
set -e
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

mkdir -p /etc/dinit.d/boot.d
for svc in dbus elogind NetworkManager rtkit-daemon; do
    ln -sf /etc/dinit.d/\$svc /etc/dinit.d/boot.d/\$svc
done

grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=grub >> /var/log/artix-install.log 2>&1
grub-mkconfig -o /boot/grub/grub.cfg >> /var/log/artix-install.log 2>&1
" || die "Failed to configure GRUB and services."

# --- LOCALE SETUP ---
# Fix: Properly format the array so whiptail doesn't break
LOCALES=($(grep ' UTF-8' /mnt/etc/locale.gen | sed 's/^#//' | awk '{print $1}'))
MENU_ARGS=()
for loc in "${LOCALES[@]}"; do
    MENU_ARGS+=("$loc" "")
done

LOCALE=$(whiptail --title "Locale Selection" --menu "Select your locale" 20 60 12 "${MENU_ARGS[@]}" 3>&1 1>&2 2>&3)
[[ -z "$LOCALE" ]] && LOCALE="en_US.UTF-8" # Fallback if cancelled

artix-chroot /mnt /bin/bash -c "
sed -i \"s/^#\$LOCALE UTF-8/\$LOCALE UTF-8/\" /etc/locale.gen
locale-gen > /dev/null 2>&1
echo \"LANG=\$LOCALE\" > /etc/locale.conf
"

# --- USERS & PASSWORDS ---
echo "Setting up users and passwords..."
# We use chpasswd so it doesn't require an interactive TTY
echo "root:$ROOT_PASS" | artix-chroot /mnt chpasswd || die "Failed to set root password."

artix-chroot /mnt /bin/bash -c "
useradd -m -G wheel -s /bin/bash $USERNAME
usermod -aG audio,video,realtime $USERNAME
echo 'permit :wheel' > /etc/doas.conf
" || die "Failed to create user $USERNAME."

echo "$USERNAME:$USER_PASS" | artix-chroot /mnt chpasswd || die "Failed to set user password."

# --- WRAP UP ---
clear
echo "Unmounting partitions..."
umount -R /mnt 2>/dev/null || true
sync

if whiptail --title "Success!" --yesno "Installation complete. Reboot now?" 10 60; then
    reboot
else
    clear
    echo "Installation finished successfully. You may reboot manually."
fi
