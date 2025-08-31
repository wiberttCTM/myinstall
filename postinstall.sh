#!/bin/bash

# --------------------------------------------------------------
#  Arch Linux Post-install Script (yay + paquetes + configuración)
# --------------------------------------------------------------

# Función para verificar si un paquete está instalado
is_installed() {
  pacman -Qi "$1" &>/dev/null || yay -Qi "$1" &>/dev/null
}

# Instalar yay si no está
is_yay_installed() {
  is_installed yay
}

if ! is_yay_installed; then
  echo ">>> Instalando yay..."
  tmpdir=$(mktemp -d)
  git clone https://aur.archlinux.org/yay.git "$tmpdir"
  cd "$tmpdir" || exit 1
  makepkg -si --noconfirm
  cd -
  rm -rf "$tmpdir"
fi

# Actualizar sistema
echo ">>> Actualizando el sistema..."
sudo pacman -Syu --noconfirm

# Instalar paquetes base
echo ">>> Instalando paquetes básicos..."
sudo pacman -S --needed --noconfirm git base-devel

# Instalar paquetes esenciales automáticamente
echo ">>> Instalando paquetes esenciales..."
yay -S --needed --noconfirm \
  kitty hyprland dunst wl-clipboard swww sddm blueman bluez bluez-utils \
  waybar rofi-wayland neovim nwg-look pipewire pipewire-pulse pipewire-alsa \
  firefox udisks2 udiskie yazi unzip unrar

# Instalar paquetes AUR (manual para que elijas opciones si hay)
echo ">>> Instalando paquetes AUR manualmente..."
yay -S zen-browser-bin visual-studio-code-bin

# Habilitar servicios extra
echo ">>> Habilitando servicios..."
sudo systemctl enable bluetooth
sudo systemctl enable sddm

echo ">>> Post-instalación completada ✅"
