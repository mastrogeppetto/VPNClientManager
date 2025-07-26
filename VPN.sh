#!/bin/bash

# ==============================================================================
# WireGuard VPN Management Script
# ==============================================================================
#
# This script provides a simple command-line interface for managing WireGuard VPN
# configurations and connections on a Linux system. It requires root privileges
# (or sudo).
#
# Key Features:
# 1.  **Automatic VPN Status Check**: When run without arguments, it checks the
#     current WireGuard connection status. If connected, it attempts to
#     automatically disconnect the active interface. If disconnected, it
#     prompts the user to select an interface to connect.
# 2.  **Smart Disconnection**: Automatically identifies and disconnects the
#     currently active WireGuard interface if its name matches a configured
#     file in /etc/wireguard. If no single active interface is found, it
#     offers a list for manual selection.
# 3.  **New VPN Configuration Management**: Accepts either a QR code image file
#     or a plain text file containing a WireGuard configuration.
#     - **Automatic File Type Detection**: Automatically determines if the input
#       file is a QR code image (using 'file --mime-type') or a text file.
#     - **QR Code Decoding**: If an image is detected, it decodes the QR code
#       using 'zbarimg' to extract the configuration content.
#     - **Syntax Validation**: Before saving, it performs a robust syntax
#       validation on the WireGuard configuration content (checking for
#       [Interface]/[Peer] sections and key=value format).
#     - **Secure Storage**: Saves the validated configuration to
#       '/etc/wireguard/' with a '.conf' extension, ensuring sensitive
#       credentials are not displayed.
#
# Prerequisites:
# -   'wireguard-tools' package (for 'wg', 'wg-quick' commands)
# -   'zbar-tools' package (for 'zbarimg' command, if using QR codes)
# -   'iproute2' package (for 'ip' command, usually pre-installed)
# -   'file' command (for mime-type detection, usually pre-installed)
#
# Usage:
#   sudo ./VPN.sh
#       (To check/manage WireGuard connection status)
#
#   sudo ./VPN.sh <source_config_path> <config_base_name>
#       (To decode QR / read text file and save to '/etc/wireguard/<config_base_name>.conf')
#       <source_config_path> can be a QR image file or a text configuration file.
#
# Remember to make the script executable: chmod +x your_script_name.sh
# ==============================================================================

# --- Configuration Variables ---
# Directory for WireGuard configurations and destination for decoded QR files
WIREGUARD_CONFIG_DIR="/etc/wireguard"

# --- Functions ---

# Function to check if the zbarimg command is available
check_zbarimg_installed() {
    if ! command -v zbarimg &> /dev/null; then
        echo "Error: The command 'zbarimg' was not found."
        echo "To decode QR codes, you need to install 'zbar-tools'."
        echo "On Debian/Ubuntu systems, you can install it with: sudo apt install zbar-tools"
        return 1
    fi
    return 0
}

# Function to check if the wg command (part of wireguard-tools) is available
check_wg_installed() {
    if ! command -v wg &> /dev/null; then
        echo "Error: The command 'wg' was not found."
        echo "You need to install 'wireguard-tools' to manage WireGuard configurations."
        echo "On Debian/Ubuntu systems, you can install it with: sudo apt install wireguard-tools"
        return 1
    fi
    return 0
}

# Function to check the status of the WireGuard connection
check_wg_connection() {
    # Check for 'wg' command availability first
    if ! check_wg_installed; then
        return 1
    fi
    # Execute 'sudo wg' and capture the output
    # The 'grep -q' command searches for any non-empty line and sets the exit status to 0 if found, 1 otherwise.
    # The '-v ^$' option excludes completely empty lines.
    if sudo wg | grep -q -v '^$' ; then
        return 0 # Connected (non-empty output)
    else
        return 1 # Not connected (empty output or only empty lines)
    fi
}

# Function to get the list of configured WireGuard interfaces
get_wg_interfaces() {
    # Find all .conf files in the WireGuard directory and extract base names
    find "$WIREGUARD_CONFIG_DIR" -maxdepth 1 -type f -name "*.conf" -printf "%f\n" | sed 's/\.conf$//' | sort
}

# Function: Search for the active WireGuard interface among the configured ones
get_active_wg_interface() {
    local configured_interfaces=($(get_wg_interfaces))
    # Get all active and UP interfaces
    local active_system_interfaces=$(ip -o link show up | awk -F': ' '{print $2}' || true)
    
    for active_iface in $active_system_interfaces; do
        for configured_iface in "${configured_interfaces[@]}"; do
            # If an active system interface matches a configured WireGuard interface
            if [[ "$active_iface" == "$configured_iface" ]]; then
                echo "$active_iface"
                return 0 # Found an active and configured interface
            fi
        done
    done
    return 1 # No active and configured interface found
}

# Function for WireGuard connection
connect_wg() {
    echo ""
    echo "--- Available WireGuard Interfaces ---"
    local interfaces=($(get_wg_interfaces))
    
    if [[ ${#interfaces[@]} -eq 0 ]]; then
        echo "No WireGuard interface configurations found in '$WIREGUARD_CONFIG_DIR'."
        return 1
    fi

    local i=1
    for iface in "${interfaces[@]}"; do
        echo "  $i) $iface"
        ((i++))
    done
    echo "-----------------------------------"
    echo -n "Select the interface to activate (number): "
    read choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#interfaces[@]} ]]; then
        local selected_iface="${interfaces[$((choice-1))]}"
        echo "Activating interface '$selected_iface'..."
        sudo wg-quick up "$selected_iface"
        if [[ $? -eq 0 ]]; then
            echo "Interface '$selected_iface' activated successfully."
        else
            echo "Error activating '$selected_iface'."
            return 1
        fi
    else
        echo "Invalid choice. Operation cancelled."
        return 1
    fi
    return 0
}

# Function for WireGuard disconnection
disconnect_wg() {
    local active_iface=$(get_active_wg_interface)

    if [[ -n "$active_iface" ]]; then
        echo "Deactivating active WireGuard interface: '$active_iface'..."
        sudo wg-quick down "$active_iface"
        if [[ $? -eq 0 ]]; then
            echo "Interface '$active_iface' deactivated successfully."
            return 0
        else
            echo "Error deactivating '$active_iface'."
            return 1
        fi
    else
        echo "No active and configured WireGuard interface detected."
        echo "--- Available WireGuard Interfaces for manual disconnection ---"
        local interfaces=($(get_wg_interfaces))

        if [[ ${#interfaces[@]} -eq 0 ]]; then
            echo "No WireGuard interface configurations found in '$WIREGUARD_CONFIG_DIR'."
            return 1
        fi

        local i=1
        for iface in "${interfaces[@]}"; do
            echo "  $i) $iface"
            ((i++))
        done
        echo "-----------------------------------"
        echo -n "Select the interface to deactivate (number): "
        read choice

        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#interfaces[@]} ]]; then
            local selected_iface="${interfaces[$((choice-1))]}"
            echo "Deactivating interface '$selected_iface'..."
            sudo wg-quick down "$selected_iface"
            if [[ $? -eq 0 ]]; then
                echo "Interface '$selected_iface' deactivated successfully."
            else
                echo "Error deactivating '$selected_iface'."
                return 1
            fi
        else
            echo "Invalid choice. Operation cancelled."
            return 1
        fi
    fi
    return 0
}

# Function: Validates WireGuard configuration syntax
# This validation is based on grep/awk checks for compatibility with older wg versions
validate_wg_syntax() {
    local config_content="$1"
    local errors=()

    # Remove comments and empty lines to simplify syntax analysis
    local cleaned_content=$(echo "$config_content" | grep -vE '^\s*#|^\s*$' | sed 's/^\s*//; s/\s*$//')

    # 1. Check for the presence of [Interface] section
    if ! echo "$cleaned_content" | grep -q '\[Interface\]'; then
        errors+=("Missing '[Interface]' section.")
    fi
    # [Peer] is common, but not strictly mandatory for a simple client interface.
    # If ! echo "$cleaned_content" | grep -q '\[Peer\]'; then
    #     errors+=("Warning: Missing '[Peer]' section. The configuration might be incomplete for some VPNs.")
    # fi

    # 2. Check that sections are well-formed (start with '[' and end with ']')
    # This checks for lines that are not valid sections but contain '['
    if echo "$cleaned_content" | grep -vE '^\s*\[[a-zA-Z0-9_]+\]$' | grep -q '\['; then
        errors+=("Error: Malformed sections found (e.g., '[[Section]' or '[Section').")
    fi

    # 3. Check for key = value format within sections
    # This regex is robust: ^\s*[a-zA-Z0-9_]+(\s*=\s*.*)?\s*$
    # It ensures lines are either valid sections or correctly formatted key-value pairs
    local invalid_key_value_lines=$(echo "$cleaned_content" | grep -vE '^\s*\[[a-zA-Z0-9_]+\]$' | grep -vE '^\s*[a-zA-Z0-9_]+\s*=\s*.*$')

    if [[ -n "$invalid_key_value_lines" ]]; then
        errors+=("Error: Lines with invalid 'key = value' format or unrecognized keys.")
        # If you want to show which lines are problematic:
        # errors+=("Problematic lines:\n$invalid_key_value_lines")
    fi

    if [[ ${#errors[@]} -eq 0 ]]; then
        echo "WireGuard configuration syntax validated: OK."
        return 0
    else
        echo "WireGuard configuration syntax NOT valid:"
        for err in "${errors[@]}"; do
            echo "  - $err"
        done
        return 1
    fi
}


# Function to process the source file (QR image or text) and save the configuration
process_vpn_config_source() {
    local source_file="$1"
    local output_basename="$2" # This is the base name of the file, without extension

    local file_mime_type=$(file --mime-type -b "$source_file")
    local config_content=""

    if [[ "$file_mime_type" == image/* ]]; then
        echo "Detected QR code image: '$source_file'."
        # Execute zbarimg check here, before attempting to use it
        if ! check_zbarimg_installed; then
            return 1 # Fails if zbarimg is not available
        fi
        config_content=$(zbarimg --quiet --raw "$source_file")
        if [[ -z "$config_content" ]]; then
            echo "Error: No valid QR code found in the image or empty content."
            return 1
        fi
    else
        echo "Detected text configuration file: '$source_file'."
        # Read content directly from the text file
        if [[ ! -f "$source_file" ]]; then
            echo "Error: Configuration file '$source_file' does not exist."
            return 1
        fi
        config_content=$(cat "$source_file")
        if [[ -z "$config_content" ]]; then
            echo "Warning: Configuration file '$source_file' is empty."
            # Not a critical error, but a warning
        fi
    fi

    # --- Syntax Validation ---
    if ! validate_wg_syntax "$config_content"; then
        echo "Configuration was not saved due to syntax errors."
        return 1
    fi
    # --- End Syntax Validation ---

    # Construct the full output file path with the .conf extension
    local full_output_path="${WIREGUARD_CONFIG_DIR}/${output_basename}.conf"

    # Create the destination directory if it doesn't exist (though /etc/wireguard should exist)
    mkdir -p "$WIREGUARD_CONFIG_DIR"

    echo "$config_content" > "$full_output_path"
    
    if [[ $? -eq 0 ]]; then
        echo "VPN configuration saved successfully to '$full_output_path'."
        # Do not display content for security reasons
    else
        echo "Error saving VPN configuration to '$full_output_path'."
        return 1
    fi
    return 0
}

# --- Root Permissions Check ---

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root or with sudo."
   echo "Example: sudo $0"
   exit 1
fi

# --- Main Script Logic ---

# Initial check: Ensure 'wg' is installed, as it's required for connection management and syntax validation.
if ! check_wg_installed; then
    exit 1
fi

NUM_PARAMS=$# 

if [[ "$NUM_PARAMS" -eq 0 ]]; then
    echo "No parameters specified. Checking WireGuard connection status..."
    
    if check_wg_connection; then
        echo "WireGuard Status: CONNECTED (non-empty 'sudo wg' output)."
        disconnect_wg # If connected, attempt intelligent disconnection or ask for choice
    else
        echo "WireGuard Status: DISCONNECTED (empty 'sudo wg' output)."
        connect_wg # If disconnected, ask for choice to connect
    fi

elif [[ "$NUM_PARAMS" -eq 2 ]]; then
    SOURCE_FILE_PATH="$1" # Can be QR image or text file
    OUTPUT_FILE_NAME="$2" # This will be the base name, .conf extension will be added

    # Check that the source file exists
    if [[ ! -f "$SOURCE_FILE_PATH" ]]; then 
        echo "Error: Source file '$SOURCE_FILE_PATH' does not exist or is not a file."
        exit 1
    fi

    # Check that the output file name is valid (prevents "/" or ".." which could create absolute paths)
    if [[ "$OUTPUT_FILE_NAME" == *"/"* || "$OUTPUT_FILE_NAME" == *".."* ]]; then
        echo "Error: The output file name '$OUTPUT_FILE_NAME' cannot contain '/' or '..'."
        exit 1
    fi

    process_vpn_config_source "$SOURCE_FILE_PATH" "$OUTPUT_FILE_NAME"
    
    if [[ $? -ne 0 ]]; then
        echo "Configuration saving operation failed."
        exit 1
    fi

else
    echo "Error: Invalid number of parameters."
    echo "Usage:"
    echo "  sudo $0                                 (to check/manage WireGuard connection)"
    echo "  sudo $0 <source_config_path> <config_base_name> (to decode QR/read text and save to '$WIREGUARD_CONFIG_DIR/<config_base_name>.conf')"
    echo "    <source_config_path> can be a QR image file or a text configuration file."
    exit 1
fi

exit 0
