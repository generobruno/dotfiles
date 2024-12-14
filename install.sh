#!/bin/bash

# Global Variables
PACKAGES_CONF="packages.conf"
UNAVAILABLE_PACKAGES=()

# Detect Distribution
detect_distro() {
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        DISTRO=$ID
    else
        echo "Unsupported distribution."
        exit 1
    fi
    echo "Detected distribution: $DISTRO"
}

# Install Packages
install_packages() {
    if [ ! -f "$PACKAGES_CONF" ]; then
        echo "Error: $PACKAGES_CONF not found. Exiting."
        exit 1
    fi

    echo "Installing packages..."
    while IFS=':' read -r package arch_pkg deb_pkg rpm_pkg; do
        package_to_install=""
        case "$DISTRO" in
            arch|manjaro)
                package_to_install=$arch_pkg
                package_manager="sudo pacman -S --noconfirm"
                ;;
            ubuntu|debian)
                package_to_install=$deb_pkg
                package_manager="sudo apt install -y"
                ;;
            fedora|rhel|centos)
                package_to_install=$rpm_pkg
                package_manager="sudo dnf install -y"
                ;;
            *)
                echo "Unsupported distribution: $DISTRO"
                exit 1
                ;;
        esac

        # Skip if no package specified for this distro
        if [ -z "$package_to_install" ]; then
            echo "Skipping $package: Not available for $DISTRO."
            UNAVAILABLE_PACKAGES+=("$package")
            continue
        fi

        # Check if package is already installed
        if command -v "$package_to_install" &>/dev/null; then
            echo "$package is already installed."
            continue
        fi

        # Install the package
        echo "Installing $package_to_install..."
        if ! $package_manager "$package_to_install"; then
            echo "Failed to install $package_to_install."
            UNAVAILABLE_PACKAGES+=("$package")
        fi
    done < "$PACKAGES_CONF"
}

# Backup and Link Dotfiles
backup_and_link_dotfiles() {
    CONFIG_DIR="$HOME/dotfiles/configs"
    echo "Linking dotfiles from $CONFIG_DIR..."

    if [ ! -d "$CONFIG_DIR" ]; then
        echo "Error: Dotfiles directory not found: $CONFIG_DIR"
        exit 1
    fi

    for file in "$CONFIG_DIR"/* "$CONFIG_DIR"/.config/*; do
        # Determine destination
        dest="$HOME/${file#$CONFIG_DIR/}"

        # Backup if file already exists
        if [ -e "$dest" ] || [ -L "$dest" ]; then
            echo "Backing up existing file: $dest -> $dest.bak"
            mv "$dest" "$dest.bak"
        fi

        # Create parent directories if needed
        mkdir -p "$(dirname "$dest")"

        # Link the file
        echo "Linking $file -> $dest"
        ln -s "$file" "$dest"
    done
}

# Reload Configurations
reload_shell_configs() {
    if [ -f "$HOME/.zshrc" ]; then
        echo "Reloading .zshrc..."
        source "$HOME/.zshrc"
    elif [ -f "$HOME/.bashrc" ]; then
        echo "Reloading .bashrc..."
        source "$HOME/.bashrc"
    fi
}

# Main Function
main() {
    detect_distro
    install_packages
    backup_and_link_dotfiles
    reload_shell_configs

    # Warn about unavailable packages
    if [ "${#UNAVAILABLE_PACKAGES[@]}" -ne 0 ]; then
        echo -e "\nWarning: The following packages could not be installed for $DISTRO:"
        printf "  - %s\n" "${UNAVAILABLE_PACKAGES[@]}"
    fi
    echo -e "\nDotfiles installation complete!"
}

# Execute Script
main
