#!/bin/bash

set -euo pipefail

# ----------------------------
# CONFIGURATION
# ----------------------------

DISK="/dev/sda"
EFI_PART="${DISK}1"
SWAP_PART="${DISK}2"
ROOT_PART="${DISK}3"
MOUNTPOINT="/mnt"
LOCALE="en_US.UTF-8 UTF-8"
LOCALE_CONF="en_US.UTF-8"
TIMEZONE="Asia/Kolkata"
HOSTNAME="localhost"

# ----------------------------
# WARN USER
# ----------------------------

echo "WARNING: This will ERASE ALL DATA on $DISK!"
read -p "Type 'YES' to continue: " CONFIRM
if [[ "$CONFIRM" != "YES" ]]; then
    echo "Aborted."
    exit 1
fi

# ----------------------------
# UNMOUNT AND WIPE
# ----------------------------

echo "Unmounting partitions on $DISK..."
for part in $(ls ${DISK}?* 2>/dev/null); do
    umount -R "$part" || true
done
swapoff -a || true

echo "Wiping $DISK..."
wipefs -a "$DISK"

# ----------------------------
# PARTITIONING
# ----------------------------

echo "Creating GPT partition table on $DISK..."
parted -s "$DISK" mklabel gpt

echo "Creating EFI, Swap, and Root partitions..."
parted -s "$DISK" \
    mkpart "EFI system partition" fat32 1MiB 1025MiB \
    set 1 esp on \
    mkpart mkpart "swap partition" linux-swap 1025MiB 5121MiB \
    mkpart mkpart "root partition" ext4 5121MiB 100%

# ----------------------------
# FORMATTING
# ----------------------------

echo "Formatting partitions..."
mkfs.fat -F32 "$EFI_PART"
mkswap "$SWAP_PART"
mkfs.ext4 "$ROOT_PART"

# ----------------------------
# MOUNTING
# ----------------------------

echo "Mounting partitions..."
mount "$ROOT_PART" "$MOUNTPOINT"
mkdir -p "$MOUNTPOINT/boot"
mount "$EFI_PART" "$MOUNTPOINT/boot"
swapon "$SWAP_PART"

# ----------------------------
# BASE SYSTEM INSTALL
# ----------------------------

echo "Installing base system with pacstrap..."
pacstrap -K "$MOUNTPOINT" base linux linux-firmware nano base-devel iwd cfdisk grub efibootmgr parted os-prober man

# ----------------------------
# CONFIGURE SYSTEM
# ----------------------------

echo "Generating fstab..."
genfstab -U "$MOUNTPOINT" >> "$MOUNTPOINT/etc/fstab"

echo "Configuring chroot environment..."

arch-chroot "$MOUNTPOINT" /bin/bash <<EOF
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

sed -i "s|^#${LOCALE}|${LOCALE}|" /etc/locale.gen
locale-gen

echo "LANG=$LOCALE_CONF" > /etc/locale.conf
echo "$HOSTNAME" > /etc/hostname

# Set root password
echo "Set root password:"
while true; do
    read -s -p "Password: " p1; echo
    read -s -p "Confirm: " p2; echo
    [[ "$p1" == "$p2" ]] && break
    echo "Passwords do not match. Try again."
done
echo "root:$p1" | chpasswd

# Install and configure GRUB
echo "Installing GRUB bootloader..."
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

EOF

echo "Installation complete. You may now reboot."
