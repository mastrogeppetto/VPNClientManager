#!/bin/bash

# ==============================================================================
# WireGuard VPN Management Script (Backend for GUI)
# ==============================================================================
#
# This script provides core functionalities for managing WireGuard VPN
# configurations and connections on a Linux system. It requires root privileges
# (or sudo).
#
# This script is designed to be called programmatically by a graphical
# user interface (GUI) wrapper (e.g., Python Tkinter), which handles user
# interaction and argument preparation.
#
# Key Features:
# 1.  **VPN Connection Management**: Activates or deactivates a specified
#     WireGuard interface by its name.
# 2.  **Configuration Import**: Decodes QR code images or reads text files
#     containing WireGuard configurations and saves them to /etc/wireguard/.
# 3.  **Syntax Validation**: Performs robust syntax validation on configuration
#     content before saving.
# 4.  **Interface Listing**: Provides a clean list of available WireGuard
#     configurations for the GUI wrapper.
#
# Prerequisites:
# -   'wireguard-tools' package (for 'wg', 'wg-quick' commands)
# -   'zbar-tools' package (for 'zbarimg' command, if using QR codes)
# -   'iproute2' package (for 'ip' command, usually pre-installed)
# -   'file' command (for mime-type detection, usually pre-installed)
#
# Usage (intended for programmatic calls, typically from a GUI wrapper):
#   sudo ./wireguard_vpn_manager.sh list_interfaces
#       (Outputs a list of configured VPN interface names, one per line)
#
#   sudo ./wireguard_vpn_manager.sh connect <interface_name>
#       (Activates the specified WireGuard interface)
#
#   sudo ./wireguard_vpn_manager.sh disconnect <interface_name>
#       (Deactivates the specified WireGuard interface)
#
#   sudo ./wireguard_vpn_manager.sh import <source_config_path> <config_base_name>
#       (Decodes QR / reads text file and saves to '/etc/wireguard/<config_base_name>.conf')
#       <source_config_path> can be a QR image file or a text configuration file.
#
# Remember to make the script executable: chmod +x wireguard_vpn_manager.sh
# ==============================================================================

# --- Configuration Variables ---
WIREGUARD_CONFIG_DIR="/etc/wireguard"

# --- Functions ---

# Function to check if the zbarimg command is available
check_zbarimg_installed() {
    if ! command -v zbarimg &> /dev/null; then
        echo "Error: The command 'zbarimg' was not found. Install 'zbar-tools'."
        return 1
    fi
    return 0
}

# Function to check if the wg command (part of wireguard-tools) is available
check_wg_installed() {
    if ! command -v wg &> /dev/null; then
        echo "Error: The command 'wg' was not found. Install 'wireguard-tools'."
        return 1
    fi
    return 0
}

# Function to get the list of configured WireGuard interfaces
get_wg_interfaces() {
    find "$WIREGUARD_CONFIG_DIR" -maxdepth 1 -type f -name "*.conf" -printf "%f\n" | sed 's/\.conf$//' | sort
}

# Function: Search for the active WireGuard interface among the configured ones
get_active_wg_interface() {
    local configured_interfaces=($(get_wg_interfaces))
    local active_system_interfaces=$(ip -o link show up | awk -F': ' '{print $2}' || true)
    
    for active_iface in $active_system_interfaces; do
        for configured_iface in "${configured_interfaces[@]}"; do
            if [[ "$active_iface" == "$configured_iface" ]]; then
                echo "$active_iface"
                return 0
            fi
        done
    done
    return 1
}

# Function to connect a WireGuard interface
connect_wg() {
    local iface_name="$1"
    if [[ -z "$iface_name" ]]; then
        echo "Error: Interface name not provided for connection."
        return 1
    fi
    echo "Activating interface '$iface_name'..."
    wg-quick up "$iface_name"
    if [[ $? -ne 0 ]]; then
        echo "Error activating '$iface_name'. Check configuration and logs."
        return 1
    fi
    return 0
}

# Function for WireGuard disconnection
disconnect_wg() {
    local iface_name="$1"
    if [[ -z "$iface_name" ]]; then
        echo "Error: Interface name not provided for disconnection."
        return 1
    fi
    echo "Deactivating interface '$iface_name'..."
    wg-quick down "$iface_name"
    if [[ $? -ne 0 ]]; then
        echo "Error deactivating '$iface_name'. Check configuration and logs."
        return 1
    fi
    return 0
}

# Function: Validates WireGuard configuration syntax
validate_wg_syntax() {
    local config_content="$1"
    local errors=()
    local cleaned_content=$(echo "$config_content" | grep -vE '^\s*#|^\s*$' | sed 's/^\s*//; s/\s*$//')

    if ! echo "$cleaned_content" | grep -q '\[Interface\]'; then
        errors+=("Missing '[Interface]' section.")
    fi
    if echo "$cleaned_content" | grep -vE '^\s*\[[a-zA-Z0-9_]+\]$' | grep -q '\['; then
        errors+=("Malformed sections found (e.g., '[[Section]' or '[Section').")
    fi
    local invalid_key_value_lines=$(echo "$cleaned_content" | grep -vE '^\s*\[[a-zA-Z0-9_]+\]$' | grep -vE '^\s*[a-zA-Z0-9_]+\s*=\s*.*$')
    if [[ -n "$invalid_key_value_lines" ]]; then
        errors+=("Lines with invalid 'key = value' format or unrecognized keys.")
    fi

    if [[ ${#errors[@]} -eq 0 ]]; then
        echo "Syntax OK."
        return 0
    else
        echo "Syntax NOT valid:"
        for err in "${errors[@]}"; do
            echo "  - $err"
        done
        return 1
    fi
}

# Function to process the source file (QR image or text) and save the configuration
import_vpn_config() {
    local source_file="$1"
    local output_basename="$2"

    if [[ -z "$source_file" || -z "$output_basename" ]]; then
        echo "Error: Missing source file path or output base name for import operation."
        return 1
    fi

    local file_mime_type=$(file --mime-type -b "$source_file")
    local config_content=""

    if [[ "$file_mime_type" == image/* ]]; then
        if ! check_zbarimg_installed; then
            return 1
        fi
        config_content=$(zbarimg --quiet --raw "$source_file")
        if [[ -z "$config_content" ]]; then
            echo "Error: No valid QR code found in the image or empty content."
            return 1
        fi
    else
        if [[ ! -f "$source_file" ]]; then
            echo "Error: Configuration file '$source_file' does not exist."
            return 1
        fi
        config_content=$(cat "$source_file")
    fi

    if ! validate_wg_syntax "$config_content"; then
        echo "Configuration was not saved due to syntax errors."
        return 1
    fi

    local full_output_path="${WIREGUARD_CONFIG_DIR}/${output_basename}.conf"
    mkdir -p "$WIREGUARD_CONFIG_DIR"
    echo "$config_content" > "$full_output_path"
    
    if [[ $? -eq 0 ]]; then
        echo "VPN configuration saved successfully to '$full_output_path'."
    else
        echo "Error saving VPN configuration to '$full_output_path'."
        return 1
    fi
    return 0
}

# --- Root Permissions Check ---
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root. Use 'sudo' or 'pkexec'."
   exit 1
fi

# --- Main Script Logic ---
# Initial check: Ensure 'wg' is installed
if ! check_wg_installed; then
    exit 1
fi

case "$1" in
    list_interfaces)
        get_wg_interfaces
        ;;
    connect)
        connect_wg "$2"
        ;;
    disconnect)
        # Disconnect from the currently active interface (detected by Python)
        # or from a specified one if passed.
        if [[ -n "$2" ]]; then
            disconnect_wg "$2"
        else
            # If no interface is explicitly provided, try to find an active one
            local active_iface=$(get_active_wg_interface)
            if [[ -n "$active_iface" ]]; then
                disconnect_wg "$active_iface"
            else
                echo "Info: No active WireGuard interface found to disconnect."
                exit 0
            fi
        fi
        ;;
    import)
        import_vpn_config "$2" "$3"
        ;;
    get_active) # New command for Python to query active interface
        get_active_wg_interface
        ;;
    *)
        echo "Error: Invalid command or missing parameters for backend script."
        echo "Usage: (intended for programmatic calls)"
        echo "  $0 list_interfaces"
        echo "  $0 connect <interface_name>"
        echo "  $0 disconnect [interface_name]"
        echo "  $0 import <source_config_path> <config_base_name>"
        echo "  $0 get_active"
        exit 1
        ;;
esac

exit 0
