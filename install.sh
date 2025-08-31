#!/bin/bash
set -uo pipefail # evitar errores por variables no definidas

# --------------------------------------------------------------
#  Arch Linux Automated Installation (UEFI + NVMe + GRUB + user)
# --------------------------------------------------------------

DISK="/dev/nvme0n1"
EFI="${DISK}p1"
ROOT="${DISK}p2"

# Pedir datos al usuario
while true; do
  read -rp ">>> Ingresa el nombre del HOSTNAME: " HOSTNAME
  [[ -n "$HOSTNAME" ]] && break
  echo "ERROR: El hostname no puede estar vacío."
done

while true; do
  read -rp ">>> Ingresa el nombre del USUARIO: " USERNAME
  [[ -n "$USERNAME" ]] && break
  echo "ERROR: El usuario no puede estar vacío."
done

while true; do
  read -rsp ">>> Contraseña para ROOT: " ROOT_PASS
  echo
  read -rsp ">>> Contraseña para USUARIO $USERNAME: " USER_PASS
  echo
  [[ -n "$ROOT_PASS" && -n "$USER_PASS" ]] && break
  echo "ERROR: Las contraseñas no pueden estar vacías."
done

# Verificar UEFI
echo ">>> Verificando arranque UEFI..."
if [[ ! -d /sys/firmware/efi/efivars ]]; then
  echo "ERROR: No estás en modo UEFI."
  exit 1
fi

# Limpiar disco y crear particiones
echo ">>> Limpiando disco $DISK..."
wipefs -a "$DISK"
sgdisk --zap-all "$DISK"

echo ">>> Creando particiones GPT..."
parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart ESP fat32 1MiB 801MiB
parted -s "$DISK" set 1 esp on
parted -s "$DISK" mkpart primary ext4 801MiB 100%

# Formatear y montar
echo ">>> Formateando particiones..."
mkfs.fat -F32 "$EFI"
mkfs.ext4 -F "$ROOT"

echo ">>> Montando particiones..."
mount "$ROOT" /mnt
mount --mkdir "$EFI" /mnt/boot

# Instalar sistema base
echo ">>> Instalando sistema base..."
pacstrap -K /mnt base linux linux-firmware grub efibootmgr vim nano sudo networkmanager

# Generar fstab
echo ">>> Generando fstab..."
genfstab -U /mnt >>/mnt/etc/fstab

# Entrar al chroot y configurar
arch-chroot /mnt /bin/bash <<EOF
set -uo pipefail

# Variables pasadas desde fuera
HOSTNAME="$HOSTNAME"
USERNAME="$USERNAME"
ROOT_PASS="$ROOT_PASS"
USER_PASS="$USER_PASS"

# Configuración básica
echo ">>> Configuración de zona horaria..."
ln -sf /usr/share/zoneinfo/America/Lima /etc/localtime
hwclock --systohc

# Locale en_US
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Hostname y hosts
echo "\$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<HOSTS
127.0.0.1    localhost
::1          localhost
127.0.1.1    \$HOSTNAME.localdomain \$HOSTNAME
HOSTS

# Instalar y configurar GRUB
echo ">>> Instalando GRUB..."
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Archlinux
grub-mkconfig -o /boot/grub/grub.cfg

# Configurar root y usuario
echo ">>> Configurando contraseñas..."
echo "root:\$ROOT_PASS" | chpasswd
useradd -m -G wheel -s /bin/bash "\$USERNAME"
echo "\$USERNAME:\$USER_PASS" | chpasswd

# Habilitar sudo
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Servicios
echo ">>> Habilitando servicios..."
systemctl enable NetworkManager
systemctl enable systemd-timesyncd

# Copiar postinstall.sh al sistema
if [[ -f /root/postinstall.sh ]]; then
    cp /root/postinstall.sh /root/
    chmod +x /root/postinstall.sh
fi

EOF

# Pausa y reinicio
echo ">>> Instalación completada. Presiona Enter para reiniciar..."
read -r _
reboot
