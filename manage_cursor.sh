#!/bin/bash

# --- Global Variables ---
# Change the install directory to a user home directory to avoid sudo in some steps
# Or keep /opt/Cursor if you want to install system-wide
CURSOR_INSTALL_DIR="/opt/Cursor"
APPIMAGE_FILENAME="cursor.AppImage" # Standardized filename
ICON_FILENAME_ON_DISK="cursor-icon.png" # Standardized local icon name

APPIMAGE_PATH="${CURSOR_INSTALL_DIR}/${APPIMAGE_FILENAME}"
ICON_PATH="${CURSOR_INSTALL_DIR}/${ICON_FILENAME_ON_DISK}"
DESKTOP_ENTRY_PATH="/usr/share/applications/cursor.desktop"

# --- Utility Functions ---
print_error() {
    echo "==============================="
    echo "❌ $1"
    echo "==============================="
}

print_success() {
    echo "==============================="
    echo "✅ $1"
    echo "==============================="
}

print_info() {
    echo "==============================="
    echo "ℹ️ $1"
    echo "==============================="
}

# --- Desktop Integration Utilities ---
ask_for_restart() {
    echo ""
    echo "🔄 For the best experience, we recommend refreshing your desktop:"
    echo "   1. Log out and log back in (recommended)"
    echo "   2. Restart your computer (best option): sudo reboot"
    echo "   3. Continue without restart (icons may not update immediately)"
    echo "⚠️ Make sure to save your work before restarting!"
}

# --- Dependency Management ---

# Detect the system package manager
detect_package_manager() {
    if command -v apt-get &> /dev/null; then
        echo "apt"
    elif command -v dnf &> /dev/null; then
        echo "dnf"
    elif command -v yum &> /dev/null; then
        echo "yum"
    elif command -v pacman &> /dev/null; then
        echo "pacman"
    elif command -v zypper &> /dev/null; then
        echo "zypper"
    else
        echo "unknown"
    fi
}

pkg_install() {
    local pkg_manager
    pkg_manager=$(detect_package_manager)
    case "$pkg_manager" in
        apt)    sudo apt-get update && sudo apt-get install -y "$@" ;;
        dnf)    sudo dnf install -y "$@" ;;
        yum)    sudo yum install -y "$@" ;;
        pacman) sudo pacman -S --noconfirm "$@" ;;
        zypper) sudo zypper install -y "$@" ;;
        *)
            print_error "Unsupported package manager. Please install the following manually: $*"
            return 1
            ;;
    esac
}

install_fuse_library() {
    local pkg_manager
    pkg_manager=$(detect_package_manager)

    # Already have libfuse2 loaded?
    if ldconfig -p 2>/dev/null | grep -q libfuse.so.2; then
        return 0
    fi
    # Fallback: search common library paths directly
    if find /lib /usr/lib /lib64 /usr/lib64 -name 'libfuse.so.2' 2>/dev/null | grep -q .; then
        return 0
    fi

    echo "📦 Installing FUSE library for AppImage support..."
    case "$pkg_manager" in
        apt)
            # Try libfuse2t64 first (Ubuntu 24.04+), then libfuse2
            if apt-cache show libfuse2t64 &>/dev/null; then
                sudo apt-get update && sudo apt-get install -y libfuse2t64
            elif apt-cache show libfuse2 &>/dev/null; then
                sudo apt-get update && sudo apt-get install -y libfuse2
            else
                echo "⚠️ Could not find libfuse2 package. AppImage may not work without it."
            fi
            ;;
        dnf|yum)
            sudo "$pkg_manager" install -y fuse-libs
            ;;
        pacman)
            sudo pacman -S --noconfirm fuse2
            ;;
        zypper)
            sudo zypper install -y libfuse2
            ;;
        *)
            echo "⚠️ Please install libfuse2 (FUSE 2) manually for AppImage support."
            ;;
    esac
}

install_dependencies() {
    local deps=("curl" "jq" "wget" "figlet")

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            echo "📦 $dep is not installed. Installing..."
            pkg_install "$dep"
        fi
    done

    install_fuse_library
}

# --- Download Latest Cursor AppImage Function ---
download_latest_cursor_appimage() {
    USER_AGENT="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
    DOWNLOAD_PATH="/tmp/latest-cursor.AppImage"

    # Try the primary API first
    API_URL="https://www.cursor.com/api/download?platform=linux-x64&releaseTrack=stable"
    FINAL_URL=$(curl -sL -A "$USER_AGENT" "$API_URL" | jq -r '.url // .downloadUrl')

    # Fallback: resolve from the golden download endpoint
    if [ -z "$FINAL_URL" ] || [ "$FINAL_URL" = "null" ]; then
        FINAL_URL=$(curl -sIL -A "$USER_AGENT" \
            "https://api2.cursor.sh/updates/download/golden/linux-x64-appimage/cursor/stable" \
            2>/dev/null | grep -i '^location:' | tail -1 | tr -d '\r' | awk '{print $2}')
    fi

    if [ -z "$FINAL_URL" ] || [ "$FINAL_URL" = "null" ]; then
        print_error "Could not get the final AppImage URL from Cursor API."
        return 1
    fi

    echo "⬇️ Downloading latest Cursor AppImage from: $FINAL_URL"
    wget -q -O "$DOWNLOAD_PATH" "$FINAL_URL"

    if [ $? -eq 0 ] && [ -s "$DOWNLOAD_PATH" ]; then
        echo "✅ Downloaded latest Cursor AppImage successfully!"
        echo "$DOWNLOAD_PATH"
        return 0
    else
        print_error "Failed to download the AppImage."
        return 1
    fi
}

# --- Download Functions ---
get_appimage_path() {
    local operation="$1"  # "install" or "update"
    local action_text=""
    
    if [ "$operation" = "update" ]; then
        action_text="new Cursor AppImage"
    else
        action_text="Cursor AppImage"
    fi
    
    echo "⬇️ Automatically downloading the latest ${action_text}..." >&2
    local cursor_download_path=""
    
    # Try auto-download first
    cursor_download_path=$(download_latest_cursor_appimage 2>/dev/null | tail -n 1)
    
    if [ $? -eq 0 ] && [ -f "$cursor_download_path" ]; then
        echo "✅ Auto-download successful!" >&2
    else
        print_error "Auto-download failed!" >&2
        echo "" >&2
        echo "📋 Don't worry! Let's try manual download instead:" >&2
        echo "1. Visit: https://cursor.sh" >&2
        echo "2. Download the Cursor AppImage file for Linux" >&2
        echo "3. Provide the full path to the downloaded .AppImage file below" >&2
        echo "" >&2
        echo "⚠️ Important: Please provide a .AppImage file, NOT an icon file (.png)" >&2
        echo "" >&2
        
        # Get manual path with validation loop
        while true; do
            if [ "$operation" = "update" ]; then
                read -rp "📂 Enter the full path to your downloaded Cursor AppImage: " cursor_download_path >&2
            else
                read -rp "📂 Enter the full path to your downloaded Cursor AppImage: " cursor_download_path >&2
            fi
            
            # Validate the manual path
            if [ -f "$cursor_download_path" ] && [[ "$cursor_download_path" =~ \.AppImage$ ]]; then
                echo "✅ Valid AppImage file found!" >&2
                break
            elif [ ! -f "$cursor_download_path" ]; then
                echo "❌ File not found. Please check the path and try again." >&2
            elif [[ ! "$cursor_download_path" =~ \.AppImage$ ]]; then
                echo "❌ Invalid file type. Please provide a .AppImage file, not: $(basename "$cursor_download_path")" >&2
            else
                echo "❌ Unknown error. Please try again." >&2
            fi
            
            echo "Do you want to try another path? (y/n)" >&2
            read -r retry_choice >&2
            if [[ ! "$retry_choice" =~ ^[Yy]$ ]]; then
                print_error "Installation cancelled by user." >&2
                exit 1
            fi
        done
    fi
    
    # Return only the path
    echo "$cursor_download_path"
}

# --- AppImage Processing ---
process_appimage() {
    local source_path="$1"
    local operation="$2"  # "install" or "update"
    
    # Final validation before processing
    if [ ! -f "$source_path" ]; then
        print_error "AppImage file not found: $source_path"
        exit 1
    fi
    
    if [[ ! "$source_path" =~ \.AppImage$ ]]; then
        print_error "Invalid file type. Expected .AppImage file, got: $(basename "$source_path")"
        exit 1
    fi
    
    # Check if file is executable/valid
    if ! file "$source_path" | grep -q "executable"; then
        print_error "The provided file does not appear to be a valid executable AppImage."
        print_info "File info: $(file "$source_path")"
        exit 1
    fi
    
    echo "✅ AppImage validation passed: $(basename "$source_path")"
    
    if [ "$operation" = "update" ]; then
        echo "🗑️ Removing old Cursor AppImage at $APPIMAGE_PATH..."
        sudo rm -f "$APPIMAGE_PATH"
        if [ $? -ne 0 ]; then
            print_error "Failed to remove old AppImage. Please check permissions."
            exit 1
        fi
        echo "✅ Old AppImage removed successfully."
    fi

    echo "📦 Move Cursor AppImage to $APPIMAGE_PATH..."
    sudo mv "$source_path" "$APPIMAGE_PATH"
    if [ $? -ne 0 ]; then
        print_error "Failed to move AppImage. Please check the URL and permissions."
        exit 1
    fi
    echo "✅ Cursor AppImage moved successfully."

    echo "🔧 Setting proper permissions..."
    # Set directory permissions (755 = rwxr-xr-x)
    sudo chmod -R 755 "$CURSOR_INSTALL_DIR"
    # Ensure AppImage is executable
    sudo chmod +x "$APPIMAGE_PATH"
    if [ $? -ne 0 ]; then
        print_error "Failed to set permissions. Please check system configuration."
        exit 1
    fi
    echo "✅ Permissions set successfully."
}

# --- Installation Function ---
installCursor() {
    if ! [ -f "$APPIMAGE_PATH" ]; then
        figlet -f slant "Install Cursor"
        echo "💿 Installing Cursor AI IDE on Linux..."
        
        install_dependencies
        
        local cursor_download_path=$(get_appimage_path "install")
        
        read -rp "🎨 Enter icon filename from GitHub (e.g: cursor-icon.png or cursor-black-icon.png): " icon_name_from_github
        local icon_download_url="https://raw.githubusercontent.com/hieutt192/Cursor-ubuntu/main/images/$icon_name_from_github"

        echo "📁 Creating installation directory ${CURSOR_INSTALL_DIR}..."
        sudo mkdir -p "$CURSOR_INSTALL_DIR"
        if [ $? -ne 0 ]; then
            print_error "Failed to create installation directory. Please check permissions."
            exit 1
        fi
        echo "✅ Installation directory ${CURSOR_INSTALL_DIR} created successfully."

        process_appimage "$cursor_download_path" "install"

        echo "🎨 Downloading Cursor icon to $ICON_PATH..."
        sudo curl -L "$icon_download_url" -o "$ICON_PATH"

        echo "🖥️ Creating .desktop entry for Cursor..."
        sudo tee "$DESKTOP_ENTRY_PATH" >/dev/null <<EOL
[Desktop Entry]
Name=Cursor AI IDE
Exec=$APPIMAGE_PATH
Icon=$ICON_PATH
Type=Application
Categories=Development;
MimeType=x-scheme-handler/cursor;
EOL

        # Set standard permissions for .desktop file (644 = rw-r--r--)
        echo "🔧 Setting desktop entry permissions..."
        sudo chmod 644 "$DESKTOP_ENTRY_PATH"
        if [ $? -ne 0 ]; then
            print_error "Failed to set desktop entry permissions."
            exit 1
        fi
        echo "✅ Desktop entry created with proper permissions."

        print_success "Cursor AI IDE installation complete. You can find it in your application menu."
        echo ""
        echo "📝 Important Notes:"
        echo "   • Cursor is now available in your Applications menu"
        echo "   • Launch Cursor from terminal: $APPIMAGE_PATH --no-sandbox"
        
        # Ask if user wants restart guidance
        ask_for_restart
    else
        print_info "Cursor AI IDE seems to be already installed at $APPIMAGE_PATH. If you want to update, please choose the update option."
    fi
}

# --- Update Function ---
updateCursor() {
    if [ -f "$APPIMAGE_PATH" ]; then
        figlet -f slant "Update Cursor"
        echo "🆙 Updating Cursor AI IDE..."
        
        install_dependencies
        
        local cursor_download_path=$(get_appimage_path "update")
        
        process_appimage "$cursor_download_path" "update"

        print_success "Cursor AI IDE update complete. Please restart Cursor if it was running."
        echo ""
        echo "📝 Update Notes:"
        echo "   • Close and reopen Cursor to use the new version"
        echo "   • Your settings and projects are automatically preserved"
    else
        print_error "Cursor AI IDE is not installed. Please run the installer first."
    fi
}

# --- Uninstall Function ---
uninstallCursor() {
    figlet -f slant "Uninstall Cursor"
    echo "🗑️ Uninstalling Cursor AI IDE..."
    
    # Check if Cursor is installed
    if [ ! -f "$APPIMAGE_PATH" ] && [ ! -f "$DESKTOP_ENTRY_PATH" ]; then
        print_info "Cursor AI IDE does not appear to be installed on this system."
        echo "No files found at:"
        echo "  - $APPIMAGE_PATH"
        echo "  - $DESKTOP_ENTRY_PATH"
        return 0
    fi
    
    # Confirm uninstallation
    echo "⚠️ This will completely remove Cursor AI IDE from your system."
    echo "Files to be removed:"
    
    if [ -d "$CURSOR_INSTALL_DIR" ]; then
        echo "  📁 Installation directory: $CURSOR_INSTALL_DIR"
    fi
    
    if [ -f "$DESKTOP_ENTRY_PATH" ]; then
        echo "  🖥️ Desktop entry: $DESKTOP_ENTRY_PATH"
    fi
    
    echo ""
    echo "⚠️ Note: Your Cursor settings and projects will NOT be affected."
    echo ""
    read -rp "Are you sure you want to uninstall Cursor? (y/N): " confirm_uninstall
    
    if [[ ! "$confirm_uninstall" =~ ^[Yy]$ ]]; then
        print_info "Uninstallation cancelled."
        return 0
    fi
    
    echo "🗑️ Removing Cursor AI IDE..."
    
    # Remove installation directory
    if [ -d "$CURSOR_INSTALL_DIR" ]; then
        echo "📁 Removing installation directory..."
        sudo rm -rf "$CURSOR_INSTALL_DIR"
        if [ $? -eq 0 ]; then
            echo "✅ Installation directory removed successfully."
        else
            print_error "Failed to remove installation directory. Please check permissions."
            return 1
        fi
    fi
    
    # Remove desktop entry
    if [ -f "$DESKTOP_ENTRY_PATH" ]; then
        echo "🖥️ Removing desktop entry..."
        sudo rm -f "$DESKTOP_ENTRY_PATH"
        if [ $? -eq 0 ]; then
            echo "✅ Desktop entry removed successfully."
        else
            print_error "Failed to remove desktop entry. Please check permissions."
            return 1
        fi
    fi
    
    echo "🗑️ Updating desktop entries..."
    echo "💡 To refresh your application menu, you may need to:"
    echo "   • Log out and log back in"
    echo "   • Restart your computer"
    echo "   • Or wait a few minutes for automatic refresh"
    
    print_success "Cursor AI IDE has been successfully uninstalled from your system."
    echo ""
    echo "📝 Important Notes:"
    echo "   • Your Cursor settings and projects are preserved"
    echo "   • To reinstall: run this script again and choose option 1"
    echo "   • If old icons persist after reinstall:"
    echo "     - Log out and log back in"
    echo "     - Restart your computer for complete refresh"
}

# --- Main Program ---
install_dependencies

# Welcome message
figlet -f slant "Cursor AI IDE"
echo "For Linux"
echo "-------------------------------------------------"
echo "  /\\_/\\"
echo " ( o.o )"
echo "  > ^ <"
echo "------------------------"
echo "1. 💿 Install Cursor"
echo "2. 🆙 Update Cursor"
echo "3. 🗑️  Uninstall Cursor"
echo "Note: If the menu reappears after choosing an option, check any error message above."
echo "------------------------"

read -rp "Please choose an option (1, 2, or 3): " choice

case $choice in
    1)
        installCursor
        ;;
    2)
        updateCursor
        ;;
    3)
        uninstallCursor
        ;;
    *)
        print_error "Invalid option. Please choose 1, 2, or 3."
        exit 1
        ;;
esac

exit 0