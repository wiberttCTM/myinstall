#!/bin/bash
set -euo pipefail

# --------------------------------------------------------------
#  Arch Linux Automated Installation (UEFI + NVMe + GRUB + user)
#  Configuración:
#   - Disco: /dev/nvme0n1
#   - Particiones: EFI (800 MB) + ROOT (resto)
#   - Idioma del sistema: inglés (en_US.UTF-8)
#   - Usuario normal con sudo: wibertt
#   - Hora: America/Lima
# --------------------------------------------------------------

DISK="/dev/nvme0n1"
EFI="${DISK}p1"
ROOT="${DISK}p2"
HOSTNAME="archlinux"
USERNAME="wibertt"

echo ">>> Verificando arranque UEFI..."
if [[ ! -d /sys/firmware/efi/efivars ]]; then
  echo "ERROR: No estás en modo UEFI."
  exit 1
fi

echo ">>> Limpiando disco $DISK..."
wipefs -a "$DISK"
sgdisk --zap-all "$DISK"

echo ">>> Creando particiones GPT..."
parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart ESP fat32 1MiB 801MiB
parted -s "$DISK" set 1 esp on
parted -s "$DISK" mkpart primary ext4 801MiB 100%

echo ">>> Formateando particiones..."
mkfs.fat -F32 "$EFI"
mkfs.ext4 -F "$ROOT"

echo ">>> Montando particiones..."
mount "$ROOT" /mnt
mount --mkdir "$EFI" /mnt/boot

echo ">>> Instalando sistema base..."
pacstrap -K /mnt base linux linux-firmware grub efibootmgr vim nano sudo networkmanager

echo ">>> Generando fstab..."
genfstab -U /mnt >>/mnt/etc/fstab

echo ">>> Entrando al sistema..."
arch-chroot /mnt /bin/bash <<EOF
set -euo pipefail

echo ">>> Configuración básica..."
ln -sf /usr/share/zoneinfo/America/Lima /etc/localtime
hwclock --systohc

# Locale solo en_US
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Hostname y hosts
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<HOSTS
127.0.0.1    localhost
::1          localhost
127.0.1.1    $HOSTNAME.localdomain $HOSTNAME
HOSTS

echo ">>> Instalando y configurando GRUB..."
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

echo ">>> Configurando root y usuario..."
echo "root:root" | chpasswd
useradd -m -G wheel -s /bin/bash $USERNAME
echo "$USERNAME:1234" | chpasswd

# Habilitar sudo
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

echo ">>> Habilitando servicios..."
systemctl enable NetworkManager
systemctl enable systemd-timesyncd

EOF

echo ">>> Instalación completada. Puedes reiniciar con: reboot"
