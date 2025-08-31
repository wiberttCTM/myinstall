#!/bin/bash
set -uo pipefail

# ---------------------------------------------------------------------------------------
# Arch Linux Automated Installation (UEFI + NVMe + GRUB + User)
# Adaptado para Lenovo V15 G2 ALC Ryzen 5 5500U
# ---------------------------------------------------------------------------------------

# Function to display error messages and exit
function error_exit {
    echo "ERROR: $1" >&2
    exit 1
}

# === Update mirrors before installing ===
echo ">>> Actualizando mirrors..."
pacman -Sy --noconfirm reflector pacman-contrib || error_exit "No se pudo instalar reflector y pacman-contrib."
reflector --country Peru,Brazil,Chile \
    --protocol https \
    --sort rate \
    --save /etc/pacman.d/mirrorlist
pacman -Syy

# === Ask for destination disk ===
lsblk -d -o NAME,SIZE,MODEL
read -rp ">>> Ingresa el disco destino (ej: /dev/nvme0n1): " DISK

# Validate disk input
if [[ ! -b "$DISK" ]]; then
    error_exit "El disco ingresado no es válido."
fi

# Confirmation before wiping the disk
read -rp "⚠️ Se borrará TODO en $DISK. ¿Estás seguro? (yes/NO): " CONFIRM
[[ "$CONFIRM" == "yes" ]] || exit 1

# === Ask for user data ===
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

# === Ask for passwords ===
while true; do
    read -rsp ">>> Ingresa la contraseña de ROOT: " ROOTPASS
    echo
    read -rsp ">>> Confirma la contraseña de ROOT: " ROOTPASS2
    echo
    [[ "$ROOTPASS" == "$ROOTPASS2" ]] && break
    echo "ERROR: Las contraseñas no coinciden."
done

while true; do
    read -rsp ">>> Ingresa la contraseña de $USERNAME: " USERPASS
    echo
    read -rsp ">>> Confirma la contraseña de $USERNAME: " USERPASS2
    echo
    [[ "$USERPASS" == "$USERPASS2" ]] && break
    echo "ERROR: Las contraseñas no coinciden."
done

# === Verify UEFI ===
echo ">>> Verificando arranque UEFI..."
if [[ ! -d /sys/firmware/efi/efivars ]]; then
    error_exit "No estás en modo UEFI."
fi

# === Clean disk and create partitions ===
echo ">>> Limpiando disco $DISK..."
wipefs -a "$DISK"
sgdisk --zap-all "$DISK"

echo ">>> Creando particiones GPT..."
parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart primary fat32 1MiB 801MiB
parted -s "$DISK" set 1 esp on
parted -s "$DISK" mkpart primary ext4 801MiB 100%

EFI="${DISK}p1"
ROOT="${DISK}p2"

# === Format and mount ===
echo ">>> Formateando particiones..."
mkfs.fat -F32 "$EFI"
mkfs.ext4 -F "$ROOT"

echo ">>> Montando particiones..."
mount "$ROOT" /mnt
mkdir -p /mnt/boot/efi
mount "$EFI" /mnt/boot/efi

# === Install base system ===
echo ">>> Instalando sistema base..."
pacstrap -K /mnt base linux linux-firmware amd-ucode grub efibootmgr sudo networkmanager

# === Generate fstab ===
echo ">>> Generando fstab..."
genfstab -U /mnt >>/mnt/etc/fstab

# === Enter chroot and configure ===
arch-chroot /mnt /bin/bash <<EOF
set -uo pipefail

# Configuration
echo ">>> Configuración de zona horaria..."
ln -sf /usr/share/zoneinfo/America/Lima /etc/localtime
hwclock --systohc

# Locale en_US
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Hostname and hosts
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<HOSTS
127.0.0.1    localhost
::1          localhost
127.0.1.1    $HOSTNAME.localdomain $HOSTNAME
HOSTS

# Install and configure GRUB
echo ">>> Instalando GRUB..."
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ArchLinux
grub-mkconfig -o /boot/grub/grub.cfg

# Create user with ZSH as default shell
useradd -m -G wheel -s /bin/bash "$USERNAME"

# Enable sudo for wheel group
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Basic services
echo ">>> Habilitando servicios..."
systemctl enable NetworkManager
systemctl enable systemd-timesyncd

# Passwords (applied from variables)
echo "root:$ROOTPASS" | chpasswd
echo "$USERNAME:$USERPASS" | chpasswd

# Copy postinstall.sh if it exists
if [[ -f /root/postinstall.sh ]]; then
    cp /root/postinstall.sh "/home/$USERNAME/"
    chown "$USERNAME:$USERNAME" "/home/$USERNAME/postinstall.sh"
    chmod +x "/home/$USERNAME/postinstall.sh"
fi
EOF

# === Finalize installation with menu ===
echo
echo ">>> Instalación completada."
echo ">>> ¿Qué deseas hacer ahora?"
while true; do
    echo "1) Reiniciar"
    echo "2) Salir sin reiniciar"
    read -rp "Selecciona una opción (1-2): " choice
    case $choice in
        1)
            echo ">>> Reiniciando..."
            umount -R /mnt
            reboot
            break
            ;;
        2)
            echo ">>> Has salido del script. Recuerda reiniciar manualmente antes de usar Arch."
            umount -R /mnt
            break
            ;;
        *)
            echo "Opción inválida. Por favor, ingresa 1 o 2."
            ;;
    esac
done