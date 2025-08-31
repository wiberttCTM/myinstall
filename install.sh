#!/bin/bash
set -uo pipefail  # evitar errores por variables no definidas

# --------------------------------------------------------------
#  Arch Linux Automated Installation (UEFI + NVMe + GRUB + user)
#  Adaptado para Lenovo V15 G2 ALC Ryzen 5 5500U
# --------------------------------------------------------------

# === Actualizar mirrors antes de instalar ===
echo ">>> Actualizando mirrors (los más rápidos en tu zona)..."
pacman -Sy --noconfirm pacman-contrib curl
curl -s "https://archlinux.org/mirrorlist/?country=PE&country=BR&country=CL&protocol=https&ip_version=4" \
  | sed 's/^#Server/Server/' > /etc/pacman.d/mirrorlist
rankmirrors -n 5 /etc/pacman.d/mirrorlist > /etc/pacman.d/mirrorlist.new
mv /etc/pacman.d/mirrorlist.new /etc/pacman.d/mirrorlist
pacman -Syy

# === Pedir disco destino ===
lsblk -d -o NAME,SIZE,MODEL
read -rp ">>> Ingresa el disco destino (ej: /dev/nvme0n1): " DISK
EFI="${DISK}p1"
ROOT="${DISK}p2"

# Confirmación antes de borrar todo
read -rp "⚠️ Se borrará TODO en $DISK. ¿Seguro? (yes/NO): " CONFIRM
[[ "$CONFIRM" == "yes" ]] || exit 1

# === Pedir datos de usuario ===
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

# === Verificar UEFI ===
echo ">>> Verificando arranque UEFI..."
if [[ ! -d /sys/firmware/efi/efivars ]]; then
  echo "ERROR: No estás en modo UEFI."
  exit 1
fi

# === Limpiar disco y crear particiones ===
echo ">>> Limpiando disco $DISK..."
wipefs -a "$DISK"
sgdisk --zap-all "$DISK"

echo ">>> Creando particiones GPT..."
parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart ESP fat32 1MiB 801MiB
parted -s "$DISK" set 1 esp on
parted -s "$DISK" mkpart primary ext4 801MiB 100%

# === Formatear y montar ===
echo ">>> Formateando particiones..."
mkfs.fat -F32 "$EFI"
mkfs.ext4 -F "$ROOT"

echo ">>> Montando particiones..."
mount "$ROOT" /mnt
mount --mkdir "$EFI" /mnt/boot

# === Instalar sistema base ===
echo ">>> Instalando sistema base..."
pacstrap -K /mnt base linux linux-firmware amd-ucode grub efibootmgr sudo networkmanager

# === Generar fstab ===
echo ">>> Generando fstab..."
genfstab -U /mnt >>/mnt/etc/fstab

# === Entrar al chroot y configurar ===
arch-chroot /mnt /bin/bash <<EOF
set -uo pipefail

# Configuración básica
echo ">>> Configuración de zona horaria..."
ln -sf /usr/share/zoneinfo/America/Lima /etc/localtime
hwclock --systohc

# Locale en_US
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Hostname y hosts
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<HOSTS
127.0.0.1    localhost localhost.localdomain
::1          localhost localhost.localdomain
127.0.1.1    $HOSTNAME.localdomain $HOSTNAME
HOSTS

# Instalar y configurar GRUB
echo ">>> Instalando GRUB..."
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=ArchLinux
grub-mkconfig -o /boot/grub/grub.cfg

# Crear usuario con ZSH por defecto
useradd -m -G wheel -s /bin/zsh "$USERNAME"

# Habilitar sudo para grupo wheel
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Servicios
echo ">>> Habilitando servicios..."
systemctl enable NetworkManager
systemctl enable systemd-timesyncd
systemctl enable bluetooth
systemctl enable sddm

# Contraseñas (se piden aquí dentro para seguridad)
echo ">>> Configura la contraseña de ROOT:"
passwd root
echo ">>> Configura la contraseña de $USERNAME:"
passwd $USERNAME

# Copiar postinstall.sh si existe
if [[ -f /root/postinstall.sh ]]; then
    cp /root/postinstall.sh /home/$USERNAME/
    chown $USERNAME:$USERNAME /home/$USERNAME/postinstall.sh
    chmod +x /home/$USERNAME/postinstall.sh
fi

EOF

# === Finalizar instalación con menú ===
echo
echo ">>> ✅ Instalación completada."
echo ">>> ¿Qué deseas hacer ahora?"
select opt in "Reiniciar" "Salir sin reiniciar"; do
    case $opt in
        "Reiniciar")
            echo ">>> Reiniciando..."
            reboot
            break
            ;;
        "Salir sin reiniciar")
            echo ">>> Has salido del script. Recuerda reiniciar manualmente antes de usar Arch."
            break
            ;;
        *)
            echo "Opción inválida."
            ;;
    esac
done
