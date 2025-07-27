#!/bin/bash

# ==============================================================================
# WireGuard VPN Management Script
# ==============================================================================
#
# This script provides a simple text-based user interface (TUI) for managing
# WireGuard VPN configurations and connections on a Linux system using 'dialog'.
# It requires root privileges (or sudo).
#
# This script is designed to be launched via a desktop icon (e.g., a .desktop file)
# and provides an entirely graphical (text-based) interaction experience,
# eliminating the need for command-line usage.
#
# Key Features:
# 1.  **Assisted 'dialog' Installation**: Guides the user to install 'dialog'
#     if it's not present, leveraging existing root privileges.
# 2.  **Interactive Menu (TUI)**: Presents a main menu to the user for:
#     - Connecting to a configured VPN.
#     - Disconnecting the currently active VPN (automatic detection).
#     - Managing (importing) new VPN configurations.
#     - Exiting the application.
# 3.  **VPN Connection Management**:
#     - Checks current WireGuard connection status.
#     - Presents a list of configured VPNs for activation.
#     - Activates/deactivates the selected WireGuard interface.
# 4.  **New VPN Configuration Management**:
#     - Supports importing configurations from QR code image files or plain text files.
#     - Automatic detection of input file type.
#     - Decodes QR codes using 'zbarimg'.
#     - Performs robust syntax validation on configuration content before saving.
# 5.  **Secure Storage**: Saves validated configurations to '/etc/wireguard/'.
#
# Prerequisites:
# -   'wireguard-tools' package (for 'wg', 'wg-quick' commands)
# -   'zbar-tools' package (for 'zbarimg' command, if using QR codes)
# -   'dialog' package (for the text-based user interface)
# -   'iproute2' package (for 'ip' command, usually pre-installed)
# -   'file' command (for mime-type detection, usually pre-installed)
#
# Usage:
#   sudo ./wireguard_vpn_manager.sh
#       (To launch the interactive TUI for managing WireGuard VPNs)
#
#   This script is intended to be launched via a .desktop file, providing
#   a seamless graphical experience without direct terminal interaction.
#
# Remember to make the script executable: chmod +x wireguard_vpn_manager.sh
# ==============================================================================

# --- Configuration Variables ---
# Directory for WireGuard configurations and destination for decoded QR files
WIREGUARD_CONFIG_DIR="/etc/wireguard"

# --- Functions ---

# Function to check if the dialog command is available
check_dialog_installed() {
    if ! command -v dialog &> /dev/null; then
        echo "================================================================"
        echo "ATTENZIONE: Il pacchetto 'dialog' non è installato."
        echo "Questo script richiede 'dialog' per la sua interfaccia grafica testuale."
        echo ""
        echo "Vuoi installare 'dialog' ora? (y/N)"
        echo "================================================================"
        read -p "Digita 'y' per sì, 'n' per no (premere Invio per continuare): " install_choice
        
        install_choice=${install_choice,,} # Convert to lowercase
        if [[ "$install_choice" == "y" || "$install_choice" == "s" ]]; then
            echo "Installazione di 'dialog' in corso..."
            if apt update && apt install -y dialog; then
                echo "'dialog' installato con successo!"
                echo "Ora puoi rieseguire lo script."
                return 0 # dialog is now installed
            else
                echo "ERRORE: Impossibile installare 'dialog'. Verifica la tua connessione internet o i permessi."
                return 1
            fi
        else
            echo "Installazione di 'dialog' annullata. Lo script non può continuare."
            return 1
        fi
    fi
    return 0 # dialog is already installed
}

# Function to check if the zbarimg command is available
check_zbarimg_installed() {
    if ! command -v zbarimg &> /dev/null; then
        dialog --title "ERRORE: ZBar Tools Non Trovati" --msgbox \
"Il comando 'zbarimg' non è stato trovato.
Per decodificare i codici QR, è necessario installare 'zbar-tools'.

Sui sistemi Debian/Ubuntu, puoi installarlo con:
sudo apt install zbar-tools" 15 60
        return 1
    fi
    return 0
}

# Function to check if the wg command (part of wireguard-tools) is available
check_wg_installed() {
    if ! command -v wg &> /dev/null; then
        dialog --title "ERRORE: WireGuard Tools Non Trovati" --msgbox \
"Il comando 'wg' non è stato trovato.
Devi installare 'wireguard-tools' per gestire le configurazioni WireGuard.

Sui sistemi Debian/Ubuntu, puoi installarlo con:
sudo apt install wireguard-tools" 15 60
        return 1
    fi
    return 0
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

# Function to connect a WireGuard interface
connect_wg() {
    local iface_name="$1"
    if [[ -z "$iface_name" ]]; then
        dialog --title "Errore" --msgbox "Nome interfaccia non fornito per la connessione." 8 40
        return 1
    fi

    dialog --infobox "Attivazione interfaccia '$iface_name'..." 5 50
    sleep 1 # Give time for infobox to be seen
    sudo wg-quick up "$iface_name" &> /tmp/wg_output.log # Redirect output to a temp file
    if [[ $? -eq 0 ]]; then
        dialog --title "Successo" --msgbox "Interfaccia '$iface_name' attivata con successo." 8 50
    else
        dialog --title "Errore" --msgbox "Errore durante l'attivazione di '$iface_name'.\n\nControllare /tmp/wg_output.log per i dettagli." 10 60
        return 1
    fi
    return 0
}

# Function for WireGuard disconnection (automatica)
disconnect_wg() {
    local active_iface=$(get_active_wg_interface)
    if [[ -z "$active_iface" ]]; then
        dialog --title "Info" --msgbox "Nessuna interfaccia WireGuard attiva rilevata da disconnettere." 8 60
        return 0
    fi

    dialog --infobox "Disattivazione interfaccia attiva '$active_iface'..." 5 50
    sleep 1
    sudo wg-quick down "$active_iface" &> /tmp/wg_output.log
    if [[ $? -eq 0 ]]; then
        dialog --title "Successo" --msgbox "Interfaccia '$active_iface' disattivata con successo." 8 50
    else
        dialog --title "Errore" --msgbox "Errore durante la disattivazione di '$active_iface'.\n\nControllare /tmp/wg_output.log per i dettagli." 10 60
        return 1
    fi
    return 0
}

# Function: Valida la sintassi della configurazione WireGuard
# Basata su controlli grep/awk, compatibile con versioni wg meno recenti
validate_wg_syntax() {
    local config_content="$1"
    local errors=()

    # Rimuovi commenti e righe vuote per semplificare l'analisi della sintassi
    local cleaned_content=$(echo "$config_content" | grep -vE '^\s*#|^\s*$' | sed 's/^\s*//; s/\s*$//')

    # 1. Controlla la presenza delle sezioni [Interface]
    if ! echo "$cleaned_content" | grep -q '\[Interface\]'; then
        errors+=("Manca la sezione '[Interface]'.")
    fi

    # 2. Controlla che le sezioni siano ben formate (iniziano con '[' e finiscono con ']')
    if echo "$cleaned_content" | grep -vE '^\s*\[[a-zA-Z0-9_]+\]$' | grep -q '\['; then
        errors+=("Sezioni malformate trovate (es. '[[Sezione]' o '[Sezione').")
    fi

    # 3. Controlla il formato chiave = valore all'interno delle sezioni
    local invalid_key_value_lines=$(echo "$cleaned_content" | grep -vE '^\s*\[[a-zA-Z0-9_]+\]$' | grep -vE '^\s*[a-zA-Z0-9_]+\s*=\s*.*$')

    if [[ -n "$invalid_key_value_lines" ]]; then
        errors+=("Righe con formato 'chiave = valore' non valido o chiavi non riconosciute.")
    fi

    if [[ ${#errors[@]} -eq 0 ]]; then
        dialog --title "Controllo Sintassi" --msgbox "Sintassi della configurazione WireGuard validata: OK." 8 50
        return 0
    else
        local error_message="Sintassi della configurazione WireGuard NON valida:\n"
        for err in "${errors[@]}"; do
            error_message+="  - $err\n"
        done
        dialog --title "Errore Sintassi" --msgbox "$error_message" 15 70
        return 1
    fi
}


# Function to process the source file (QR image or text) and save the configuration
import_vpn_config() {
    local source_file="$1"
    local output_basename="$2"

    if [[ -z "$source_file" || -z "$output_basename" ]]; then
        dialog --title "Errore" --msgbox "Percorso del file sorgente o nome base di output mancante per l'operazione di importazione." 10 60
        return 1
    fi

    local file_mime_type=$(file --mime-type -b "$source_file")
    local config_content=""

    if [[ "$file_mime_type" == image/* ]]; then
        dialog --infobox "Rilevata immagine QR code: '$source_file'. Decodifica in corso..." 5 70
        sleep 1
        if ! check_zbarimg_installed; then
            return 1 # Fails if zbarimg is not available (message already shown by check_zbarimg_installed)
        fi
        config_content=$(zbarimg --quiet --raw "$source_file")
        if [[ -z "$config_content" ]]; then
            dialog --title "Errore" --msgbox "Nessun codice QR valido trovato nell'immagine o contenuto vuoto." 10 60
            return 1
        fi
    else
        dialog --infobox "Rilevato file di configurazione testuale: '$source_file'. Lettura in corso..." 5 70
        sleep 1
        if [[ ! -f "$source_file" ]]; then
            dialog --title "Errore" --msgbox "Il file di configurazione '$source_file' non esiste." 10 60
            return 1
        fi
        config_content=$(cat "$source_file")
        if [[ -z "$config_content" ]]; then
            dialog --title "Avviso" --msgbox "Il file di configurazione '$source_file' è vuoto. Procedo comunque." 10 60
        fi
    fi

    # --- Syntax Validation ---
    if ! validate_wg_syntax "$config_content"; then
        dialog --title "Importazione Fallita" --msgbox "La configurazione non è stata salvata a causa di errori di sintassi." 8 60
        return 1
    fi
    # --- End Syntax Validation ---

    local full_output_path="${WIREGUARD_CONFIG_DIR}/${output_basename}.conf"

    mkdir -p "$WIREGUARD_CONFIG_DIR" # Ensure directory exists

    echo "$config_content" | sudo tee "$full_output_path" > /dev/null
    
    if [[ $? -eq 0 ]]; then
        dialog --title "Successo" --msgbox "Configurazione VPN salvata con successo in '$full_output_path'." 8 60
    else
        dialog --title "Errore" --msgbox "Errore durante il salvataggio della configurazione VPN in '$full_output_path'." 8 60
        return 1
    fi
    return 0
}

# --- Root Permissions Check ---
if [[ $EUID -ne 0 ]]; then
   # Use echo for this initial check since dialog might not be installed yet
   echo "Questo script deve essere eseguito come root o con sudo." >&2
   echo "Esempio: sudo $0" >&2
   exit 1
fi

# --- Main Script Logic ---

# Check essential prerequisites
# The check for dialog must be first, as subsequent messages rely on it.
if ! check_dialog_installed; then
    exit 1
fi
if ! check_wg_installed; then
    exit 1
fi

# The script now always enters the interactive dialog mode
while true; do
    # Get active interface for status display
    local current_active_iface=$(get_active_wg_interface)
    local status_text="Stato: DISCONNESSO"
    if [[ -n "$current_active_iface" ]]; then
        status_text="Stato: CONNESSO a $current_active_iface"
    fi

    main_menu_choice=$(dialog --clear \
        --backtitle "WireGuard VPN Client Manager" \
        --title "Menu Principale" \
        --menu "$status_text\n\nScegli un'opzione:" 15 60 4 \
        "1" "Connetti VPN" \
        "2" "Disconnetti VPN" \
        "3" "Gestisci Configurazioni" \
        "4" "Esci" \
        2>&1 >/dev/tty) # Redirect stderr to stdout, then stdout to /dev/tty

    case $main_menu_choice in
        1) # Connetti VPN
            local interfaces=($(get_wg_interfaces))
            if [[ ${#interfaces[@]} -eq 0 ]]; then
                dialog --title "Info" --msgbox "Nessuna configurazione WireGuard trovata in '$WIREGUARD_CONFIG_DIR'.\nImporta prima una configurazione." 10 60
                continue # Back to main menu
            fi

            local menu_items=()
            for iface in "${interfaces[@]}"; do
                menu_items+=( "$iface" "$iface" ) # Format: TAG ITEM
            done

            vpn_selection=$(dialog --clear \
                --backtitle "WireGuard VPN Client Manager" \
                --title "Seleziona VPN da Connettere" \
                --menu "Scegli un'interfaccia da attivare:" 15 60 ${#interfaces[@]} \
                "${menu_items[@]}" \
                2>&1 >/dev/tty)
            
            if [[ $? -eq 0 ]]; then # OK button pressed
                connect_wg "$vpn_selection"
            else # Cancel pressed
                dialog --title "Annullato" --msgbox "Connessione annullata." 8 40
            fi
            ;;
        2) # Disconnetti VPN
            disconnect_wg # Automatically detects and disconnects active VPN
            ;;
        3) # Gestisci Configurazioni (Importa nuova)
            local source_file_path=$(dialog --clear \
                --backtitle "WireGuard VPN Client Manager" \
                --title "Seleziona File Sorgente" \
                --fselect "$HOME/" 14 60 \
                2>&1 >/dev/tty)

            if [[ $? -eq 0 && -n "$source_file_path" ]]; then # OK selected and path is not empty
                local output_file_name=$(dialog --clear \
                    --backtitle "WireGuard VPN Client Manager" \
                    --title "Nome Configurazione" \
                    --inputbox "Inserisci un nome per questa VPN (es. my_home_vpn):\n(Questo sarà il nome del file .conf)" 10 60 \
                    "" \
                    2>&1 >/dev/tty)
                
                if [[ $? -eq 0 && -n "$output_file_name" ]]; then # OK selected and name is not empty
                    # Basic filename validation (no slashes or '..')
                    if [[ "$output_file_name" == *"/"* || "$output_file_name" == *".."* ]]; then
                        dialog --title "Errore" --msgbox "Nome non valido: '/' o '..' non sono consentiti." 8 60
                    else
                        import_vpn_config "$source_file_path" "$output_file_name"
                    fi
                else # Cancel or empty name
                    dialog --title "Annullato" --msgbox "Nome configurazione non fornito o annullato." 8 60
                fi
            else # Cancelled file selection
                dialog --title "Annullato" --msgbox "Selezione file annullata." 8 60
            fi
            ;;
        4) # Esci
            dialog --title "Esci" --msgbox "Uscita da WireGuard VPN Manager. Arrivederci!" 8 40
            break
            ;;
        *) # User pressed Cancel or closed dialog
            dialog --title "Annullato" --msgbox "Operazione annullata. Uscita." 8 40
            exit 0
            ;;
    esac
done

exit 0
