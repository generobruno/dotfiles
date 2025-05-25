#!/bin/bash

# Don't exit on error
set +e

DOTFILES_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PACKAGES_DIR="$DOTFILES_DIR/packages"
FAILED_PACKAGES=()

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

    if ! command -v git &> /dev/null; then
        print_error "git is not installed. Please install git first."
        exit 1
    fi

    if ! command -v stow &> /dev/null; then
        print_error "GNU Stow is not installed. Installing it now..."
        install_package stow
        if ! command -v stow &> /dev/null; then
            print_error "Failed to install GNU Stow. Please install it manually."
            exit 1
        fi
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

# Handle package name mapping between different distributions
map_package_name() {
    local pkg_name=$1

    # Map common package name differences
    case $OS in
        "arch")
            case $pkg_name in
                "python3-pip") echo "python-pip" ;;
                *) echo "$pkg_name" ;;
            esac
            ;;
        "debian"|"ubuntu")
            case $pkg_name in
                "python-pip") echo "python3-pip" ;;
                *) echo "$pkg_name" ;;
            esac
            ;;
        *)
            echo "$pkg_name"
            ;;
    esac
}

# Setup AUR helper (yay) for Arch Linux
setup_aur_helper() {
    print_info "Setting up AUR helper (yay)..."

    if command -v yay &> /dev/null; then
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

    if command -v yay &> /dev/null; then
        print_success "yay has been installed successfully."
    else
        print_error "Failed to install yay."
        FAILED_PACKAGES+=("yay (AUR helper)")
    fi
}

# Install a package based on the detected OS
install_package() {
    local original_package=$1
    local package_type=$2  # Optional: "aur" for AUR packages
    local mapped_package=$(map_package_name "$original_package")
    local exit_code=0

    case $OS in
        "arch")
            if [ "$package_type" = "aur" ]; then
                # Check if yay is installed
                if ! command -v yay &> /dev/null; then
                    setup_aur_helper
                fi
                if command -v yay &> /dev/null; then
                    yay -S --needed --noconfirm "$mapped_package"
                    exit_code=$?
                else
                    print_error "Cannot install AUR package $mapped_package: yay is not installed"
                    exit_code=1
                fi
            else
                # Try yay first if available (it handles regular packages too)
                if command -v yay &> /dev/null; then
                    yay -S --needed --noconfirm "$mapped_package"
                    exit_code=$?
                else
                    sudo pacman -S --needed --noconfirm "$mapped_package"
                    exit_code=$?
                fi
            fi
            ;;
        "debian"|"ubuntu")
            sudo apt-get update
            sudo apt-get install -y "$mapped_package"
            exit_code=$?
            ;;
        "fedora")
            sudo dnf install -y "$mapped_package"
            exit_code=$?
            ;;
        "macos")
            brew install "$mapped_package"
            exit_code=$?
            ;;
        *)
            print_error "Unsupported OS for package installation: $OS"
            exit_code=1
            ;;
    esac

    if [ $exit_code -ne 0 ]; then
        FAILED_PACKAGES+=("$original_package")
        print_error "Failed to install $original_package"
        return 1
    else
        print_success "Successfully installed $original_package"
        return 0
    fi
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
        done < "$PACKAGES_DIR/packages.conf"
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
        done < "$PACKAGES_DIR/$OS.conf"

        # Install AUR packages for Arch Linux
        if [ "$OS" = "arch" ] && [ -f "$PACKAGES_DIR/arch_aur.conf" ]; then
            print_info "Installing AUR packages..."
            while read -r package || [ -n "$package" ]; do
                # Skip comments and empty lines
                [[ $package =~ ^#.* ]] || [ -z "$package" ] && continue

                print_info "Installing AUR package: $package..."
                install_package "$package" "aur"
            done < "$PACKAGES_DIR/arch_aur.conf"
        fi
    else
        print_warning "No package configuration found for $OS"
    fi

    if [ ${#FAILED_PACKAGES[@]} -eq 0 ]; then
        print_success "All packages installed successfully."
    else
        print_warning "Package installation completed with some failures."
    fi
}

# Create symbolic links using GNU Stow
setup_dotfiles() {
    print_info "Setting up dotfiles..."

    # Change to dotfiles directory
    cd "$DOTFILES_DIR" || {
        print_error "Cannot access dotfiles directory: $DOTFILES_DIR"
        return 1
    }

    # Get list of stow packages (directories excluding hidden ones and packages dir)
    for dir in $(find . -mindepth 1 -maxdepth 1 -type d -not -path "*/\.*" -not -path "*/packages" | sed 's|^\./||'); do
        stow_pkg="$dir"
        print_info "Setting up $stow_pkg..."

        # Check for conflicts first
        if stow -n -v -t "$HOME" "$stow_pkg" 2>&1 | grep -q "would cause conflicts"; then
            print_warning "Conflicts detected for $stow_pkg. Backing up existing files..."

            # Create backup directory if it doesn't exist
            backup_dir="$HOME/.dotfiles-backup/$(date +%Y%m%d_%H%M%S)"
            mkdir -p "$backup_dir"

            # Get list of conflicting files and back them up
            stow -n -v -t "$HOME" "$stow_pkg" 2>&1 | grep "existing target" | while read -r line; do
                # Extract the target file path from stow output
                target_file=$(echo "$line" | sed -n 's/.*existing target \(.*\) since.*/\1/p')
                if [ -n "$target_file" ] && [ -f "$HOME/$target_file" ]; then
                    # Create directory structure in backup
                    target_dir=$(dirname "$target_file")
                    mkdir -p "$backup_dir/$target_dir"

                    # Move the conflicting file to backup
                    mv "$HOME/$target_file" "$backup_dir/$target_file"
                    print_info "Backed up $target_file to $backup_dir/$target_file"
                fi
            done
        fi

        # Now stow the package
        if stow -v -t "$HOME" "$stow_pkg"; then
            print_success "Successfully stowed $stow_pkg"
        else
            print_error "Failed to stow $stow_pkg"

            # If stow still fails, try the adopt method as fallback
            print_warning "Trying adopt method for $stow_pkg..."
            if stow --adopt -v -t "$HOME" "$stow_pkg"; then
                print_warning "Used adopt method for $stow_pkg - check git status for changes"
            else
                print_error "Complete failure to stow $stow_pkg"
            fi
        fi
    done

    print_success "Dotfiles setup completed."

    # Show any adopted files that might need review
    if git status --porcelain | grep -q .; then
        print_warning "Some files were adopted into your dotfiles repo."
        print_info "Run 'git status' in $DOTFILES_DIR to review changes."
    fi
}

# Setup Git submodules
setup_submodules() {
    print_info "Setting up Git submodules..."
    git submodule init
    git submodule update --recursive
    print_success "Submodules have been set up."
}

# Show summary of installation
show_summary() {
    echo
    print_info "Installation Summary:"
    print_success "Dotfiles installed to: $HOME"
    print_success "OS detected: $OS"

    if [ ${#FAILED_PACKAGES[@]} -eq 0 ]; then
        print_success "All packages were installed successfully."
    else
        print_warning "The following packages failed to install:"
        for pkg in "${FAILED_PACKAGES[@]}"; do
            echo -e "${YELLOW}  - $pkg${NC}"
        done
        echo
        print_info "You may want to install these packages manually."
    fi
}

# Main execution
main() {
    print_info "Starting dotfiles installation..."

    #check_requirements
    #detect_os

    # Set up submodules
    #setup_submodules

    # Ask user if they want to install packages
    #read -p "Do you want to install packages? (y/n) " -n 1 -r
    #echo
    #if [[ $REPLY =~ ^[Yy]$ ]]; then
    #    install_packages
    #fi

    setup_dotfiles

    # Show summary with any failed packages
    show_summary

    print_success "Dotfiles installation complete!"
}

main
