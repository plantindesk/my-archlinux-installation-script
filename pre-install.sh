#!/bin/bash

set -euo pipefail
cat << EOF
# ----------------------------
# CONFIGURATION
# ----------------------------
EOF

DISK="/dev/sda"
EFI_PART="${DISK}1"
SWAP_PART="${DISK}2"
ROOT_PART="${DISK}3"
MOUNTPOINT="/mnt"
LOCALE="en_US.UTF-8 UTF-8"
LOCALE_CONF="en_US.UTF-8"
TIMEZONE="Asia/Kolkata"
HOSTNAME="localhost"
MIRRORLIST_BACKUP="/etc/pacman.d/mirrorlist.backup"
MIRRORLIST="/etc/pacman.d/mirrorlist"

cat << EOF
# ----------------------------
# WARN USER
# ----------------------------
EOF

echo "WARNING: This will ERASE ALL DATA on $DISK!"
read -p "Type 'YES' to continue: " CONFIRM
if [[ "$CONFIRM" != "YES" ]]; then
    echo "Aborted."
    exit 1
fi

cat << EOF
# ----------------------------
# UPDATING MIRRORS
# ----------------------------
EOF

pacman -Sy pacman-contrib
curl -o "$MIRRORLIST_BACKUP" "https://archlinux.org/mirrorlist/?country=IN&protocol=http&protocol=https&ip_version=4&use_mirror_status=on"
sed -i -E 's|^#(Server = https://.*)|\1|' "$MIRRORLIST_BACKUP"
rankmirrors -n 6 "$MIRRORLIST_BACKUP" > "$MIRRORLIST"

cat << EOF
# ----------------------------
# UNMOUNT AND WIPE
# ----------------------------
EOF
echo "Unmounting partitions on $DISK..."
for part in $(ls ${DISK}?* 2>/dev/null); do
    umount -R "$part" || true
done
swapoff -a || true

echo "Wiping $DISK..."
wipefs -a "$DISK"

parted -s "$DISK" mklabel gpt

cat << EOF
# ----------------------------
# PARTITIONING
# ----------------------------
EOF
echo "Creating GPT partition table on $DISK..."
parted -s "$DISK" mklabel gpt

echo "Creating EFI, Swap, and Root partitions..."
parted -s "$DISK" \
    mkpart ESP fat32 1MiB 1025MiB \
    set 1 esp on \
    mkpart mkpart linux-swap 1025MiB 5121MiB \
    mkpart mkpart ext4 5121MiB 100%

cat << EOF
# ----------------------------
# FORMATTING
# ----------------------------
EOF
echo "Formatting partitions..."
mkfs.fat -F32 "$EFI_PART"
mkswap "$SWAP_PART"
mkfs.ext4 "$ROOT_PART"

cat << EOF
# ----------------------------
# MOUNTING
# ----------------------------
EOF

echo "Mounting partitions..."
mount "$ROOT_PART" "$MOUNTPOINT"
mkdir -p "$MOUNTPOINT/boot"
mount "$EFI_PART" "$MOUNTPOINT/boot"
swapon "$SWAP_PART"

# ----------------------------
# SET ROOT PASSWORD
# ----------------------------
echo "Set root password for the new system:"
while true; do
    read -s -p "Enter password: " ROOT_PASSWORD; echo
    read -s -p "Confirm password: " ROOT_PASSWORD_CONFIRM; echo
    if [[ "$ROOT_PASSWORD" == "$ROOT_PASSWORD_CONFIRM" ]]; then
        break
    else
        echo "Passwords do not match. Please try again."
    fi
done



cat << EOF
# ----------------------------
# BASE SYSTEM INSTALL
# ----------------------------
EOF
echo "Installing base system with pacstrap..."
pacstrap -K "$MOUNTPOINT" base linux linux-firmware nano base-devel iwd grub efibootmgr parted os-prober man-db pacman-contrib dhcpcd wpa_supplicant

cat << EOF
# ----------------------------
# CONFIGURE SYSTEM
# ----------------------------
EOF

echo "Generating fstab..."
genfstab -U "$MOUNTPOINT" >> "$MOUNTPOINT/etc/fstab"

echo "Configuring chroot environment..."

# Pass necessary variables into the chroot environment
arch-chroot "$MOUNTPOINT" /bin/bash -s -- "$TIMEZONE" "$LOCALE" "$LOCALE_CONF" "$HOSTNAME" "$ROOT_PASSWORD" <<'EOF'
# Assign the passed arguments to variables inside the chroot
TIMEZONE="$1"
LOCALE="$2"
LOCALE_CONF="$3"
HOSTNAME="$4"
ROOT_PASSWORD="$5"

set -euo pipefail

ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
hwclock --systohc

sed -i "s|^#${LOCALE}|${LOCALE}|" /etc/locale.gen
locale-gen

echo "LANG=${LOCALE_CONF}" > /etc/locale.conf
echo "${HOSTNAME}" > /etc/hostname

echo "Setting root password..."
echo "root:${ROOT_PASSWORD}" | chpasswd

# Install and configure GRUB
echo "Installing GRUB bootloader..."
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

EOF

echo "Installation complete. You may now reboot."
