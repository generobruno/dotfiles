#!/bin/bash

set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_DIR="$DOTFILES_DIR/packages"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

# Check for required commands
check_requirements() {
  print_info "Checking requirements..."

  if ! command -v git &>/dev/null; then
    print_error "git is not installed. Please install git first."
    exit 1
  fi

  if ! command -v stow &>/dev/null; then
    print_error "GNU Stow is not installed. Installing it now..."
    install_package stow
  else
    print_success "GNU Stow is installed."
  fi
}

# Detect the operating system
detect_os() {
  print_info "Detecting operating system..."

  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
  elif [ -f /etc/debian_version ]; then
    OS="debian"
  elif [ -f /etc/fedora-release ]; then
    OS="fedora"
  elif [ -f /etc/arch-release ]; then
    OS="arch"
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
  else
    OS="unknown"
  fi

  print_success "Detected OS: $OS"
  return 0
}

# Setup AUR helper (yay) for Arch Linux
setup_aur_helper() {
  print_info "Setting up AUR helper (yay)..."

  if command -v yay &>/dev/null; then
    print_success "yay is already installed."
    return 0
  fi

  # Install dependencies
  sudo pacman -S --needed --noconfirm git base-devel

  # Create temporary directory and clone yay
  TEMP_DIR=$(mktemp -d)
  git clone https://aur.archlinux.org/yay.git "$TEMP_DIR/yay"
  cd "$TEMP_DIR/yay"

  # Build and install yay
  makepkg -si --noconfirm

  # Clean up
  cd "$DOTFILES_DIR"
  rm -rf "$TEMP_DIR"

  if command -v yay &>/dev/null; then
    print_success "yay has been installed successfully."
  else
    print_error "Failed to install yay."
    exit 1
  fi
}

# Install a package based on the detected OS
install_package() {
  PACKAGE_NAME=$1
  PACKAGE_TYPE=$2 # Optional: "aur" for AUR packages

  case $OS in
  "arch")
    if [ "$PACKAGE_TYPE" = "aur" ]; then
      # Check if yay is installed
      if ! command -v yay &>/dev/null; then
        setup_aur_helper
      fi
      yay -S --noconfirm $PACKAGE_NAME
    else
      sudo pacman -S --needed --noconfirm $PACKAGE_NAME
    fi
    ;;
  "debian" | "ubuntu")
    sudo apt-get update
    sudo apt-get install -y $PACKAGE_NAME
    ;;
  "fedora")
    sudo dnf install -y $PACKAGE_NAME
    ;;
  "macos")
    brew install $PACKAGE_NAME
    ;;
  *)
    print_error "Unsupported OS for package installation: $OS"
    return 1
    ;;
  esac

  return 0
}

# Install packages from configuration files
install_packages() {
  print_info "Installing packages..."

  # Install common packages
  if [ -f "$PACKAGES_DIR/packages.conf" ]; then
    print_info "Installing common packages..."
    while read -r line || [ -n "$line" ]; do
      # Skip comments and empty lines
      [[ $line =~ ^#.* ]] || [ -z "$line" ] && continue

      # Parse package type (if specified)
      if [[ $line == *"#"* ]]; then
        package=$(echo $line | cut -d '#' -f 1 | xargs)
        package_type=$(echo $line | cut -d '#' -f 2 | xargs)
      else
        package=$line
        package_type=""
      fi

      print_info "Installing $package..."
      install_package "$package" "$package_type"
    done <"$PACKAGES_DIR/packages.conf"
  fi

  # Install OS-specific packages
  if [ -f "$PACKAGES_DIR/$OS.conf" ]; then
    print_info "Installing $OS-specific packages..."

    # For Arch Linux, install yay first if arch_aur.conf exists
    if [ "$OS" = "arch" ] && [ -f "$PACKAGES_DIR/arch_aur.conf" ]; then
      setup_aur_helper
    fi

    while read -r line || [ -n "$line" ]; do
      # Skip comments and empty lines
      [[ $line =~ ^#.* ]] || [ -z "$line" ] && continue

      # Parse package type (if specified)
      if [[ $line == *"#"* ]]; then
        package=$(echo $line | cut -d '#' -f 1 | xargs)
        package_type=$(echo $line | cut -d '#' -f 2 | xargs)
      else
        package=$line
        package_type=""
      fi

      print_info "Installing $package..."
      install_package "$package" "$package_type"
    done <"$PACKAGES_DIR/$OS.conf"

    # Install AUR packages for Arch Linux
    if [ "$OS" = "arch" ] && [ -f "$PACKAGES_DIR/arch_aur.conf" ]; then
      print_info "Installing AUR packages..."
      while read -r package || [ -n "$package" ]; do
        # Skip comments and empty lines
        [[ $package =~ ^#.* ]] || [ -z "$package" ] && continue

        print_info "Installing AUR package: $package..."
        install_package "$package" "aur"
      done <"$PACKAGES_DIR/arch_aur.conf"
    fi
  else
    print_warning "No package configuration found for $OS"
  fi

  print_success "Package installation completed."
}

# Create symbolic links using GNU Stow
setup_dotfiles() {
  print_info "Setting up dotfiles..."

  # First, backup existing dotfiles if they exist and aren't symlinks
  for dir in $(find "$DOTFILES_DIR" -mindepth 1 -maxdepth 1 -type d -not -path "*/\.*" -not -path "*/packages"); do
    stow_pkg=$(basename "$dir")
    print_info "Setting up $stow_pkg..."

    # Use stow to create symlinks
    cd "$DOTFILES_DIR"
    stow -v -t "$HOME" "$stow_pkg"
  done

  print_success "Dotfiles have been set up."
}

# Set up Git Submodules
setup_submodules() {
    print_info "Setting up Git submodules..."
    git submodule init
    git submodule update --recursive
    print_success "Submodules have been set up."
}


# Main execution
main() {
  print_info "Starting dotfiles installation..."

  check_requirements
  detect_os

  # Ask user if they want to install packages
  read -p "Do you want to install packages? (y/n) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    install_packages
  fi

  setup_dotfiles

  print_success "Dotfiles installation complete!"
}

main
