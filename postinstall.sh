#!/bin/bash

# Función para verificar si un paquete está instalado
is_installed() {
  pacman -Qi $1 &>/dev/null || yay -Qi $1 &>/dev/null
}

# Instalar el paquete solo si no está instalado o si la versión no está actualizada
install_if_needed() {
  if ! is_installed $1; then
    echo "Instalando $1..."
    yay -S --needed $1
  else
    echo "$1 ya está instalado y actualizado."
  fi
}

# Verificar si yay ya está instalado
is_yay_installed() {
  if is_installed yay; then
    echo "yay ya está instalado, saltando instalación."
    return 0 # yay ya está instalado, no lo instalamos
  else
    return 1 # yay no está instalado, lo instalaremos
  fi
}

# Actualiza el sistema
echo "Actualizando el sistema..."
sudo pacman -Syu

# Instalar paquetes esenciales si no están ya instalados
echo "Instalando paquetes básicos..."
sudo pacman -S --needed git base-devel

# Verificar si yay ya está instalado, si no, lo instalamos
echo "Verificando si yay está instalado..."
if ! is_yay_installed; then
  # Clonar y compilar yay (AUR helper)
  echo "Instalando yay..."
  git clone https://aur.archlinux.org/yay.git
  cd yay
  makepkg -si
  cd ..
fi

# Instalar los paquetes mencionados desde repositorios oficiales
echo "Instalando paquetes desde repositorios oficiales..."
for pkg in kitty hyprland dunst wl-clipboard swww sddm blueman bluez bluez-utils waybar rofi-wayland neovim nwg-look pipewire firefox udisks2 udiskie yazi unzip unrar; do
  install_if_needed $pkg
done

# Usar yay para instalar paquetes AUR
echo "Instalando paquetes AUR..."
for pkg in zen-browser-bin; do
  install_if_needed $pkg
done

# Fin del script
echo "Instalación completada."
