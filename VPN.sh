#!/bin/bash

# --- Variabili di Configurazione ---
# Directory delle configurazioni WireGuard e destinazione per i file QR decodificati
WIREGUARD_CONFIG_DIR="/etc/wireguard"

# --- Funzioni ---

# Funzione per verificare la disponibilità del comando zbarimg
check_zbarimg_installed() {
    if ! command -v zbarimg &> /dev/null; then
        echo "Errore: Il comando 'zbarimg' non è stato trovato."
        echo "Per decodificare i QR code, è necessario installare 'zbar-tools'."
        echo "Su sistemi Debian/Ubuntu, puoi installarlo con: sudo apt install zbar-tools"
        return 1
    fi
    return 0
}

# Funzione per verificare lo stato della connessione WireGuard
check_wg_connection() {
    # Esegui 'sudo wg' e cattura l'output
    # Il comando 'grep -q' cerca qualsiasi riga non vuota e imposta l'exit status a 0 se trova qualcosa, 1 altrimenti.
    # L'opzione '-v ^$' esclude le righe completamente vuote.
    if sudo wg | grep -q -v '^$' ; then
        return 0 # Connesso (output non vuoto)
    else
        return 1 # Non connesso (output vuoto o solo righe vuote)
    fi
}

# Funzione per ottenere la lista delle interfacce WireGuard configurate
get_wg_interfaces() {
    # Trova tutti i file .conf nella directory WireGuard e estrai i nomi base
    find "$WIREGUARD_CONFIG_DIR" -maxdepth 1 -type f -name "*.conf" -printf "%f\n" | sed 's/\.conf$//' | sort
}

# Funzione: Cerca l'interfaccia WireGuard attiva tra quelle configurate
get_active_wg_interface() {
    local configured_interfaces=($(get_wg_interfaces))
    # Ottieni tutte le interfacce attive e in stato UP
    local active_system_interfaces=$(ip -o link show up | awk -F': ' '{print $2}' || true)
    
    for active_iface in $active_system_interfaces; do
        for configured_iface in "${configured_interfaces[@]}"; do
            # Se un'interfaccia di sistema attiva corrisponde a un'interfaccia WireGuard configurata
            if [[ "$active_iface" == "$configured_iface" ]]; then
                echo "$active_iface"
                return 0 # Trovata un'interfaccia attiva e configurata
            fi
        done
    done
    return 1 # Nessuna interfaccia attiva e configurata trovata
}


# Funzione per la connessione WireGuard
connect_wg() {
    echo ""
    echo "--- Interfacce WireGuard disponibili ---"
    local interfaces=($(get_wg_interfaces))
    
    if [[ ${#interfaces[@]} -eq 0 ]]; then
        echo "Nessuna interfaccia WireGuard configurata trovata in '$WIREGUARD_CONFIG_DIR'."
        return 1
    fi

    local i=1
    for iface in "${interfaces[@]}"; do
        echo "  $i) $iface"
        ((i++))
    done
    echo "-----------------------------------"
    echo -n "Seleziona l'interfaccia da attivare (numero): "
    read choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#interfaces[@]} ]]; then
        local selected_iface="${interfaces[$((choice-1))]}"
        echo "Attivando l'interfaccia '$selected_iface'..."
        sudo wg-quick up "$selected_iface"
        if [[ $? -eq 0 ]]; then
            echo "Interfaccia '$selected_iface' attivata con successo."
        else
            echo "Errore durante l'attivazione di '$selected_iface'."
            return 1
        fi
    else
        echo "Scelta non valida. Operazione annullata."
        return 1
    fi
    return 0
}

# Funzione per la disconnessione WireGuard
disconnect_wg() {
    local active_iface=$(get_active_wg_interface)

    if [[ -n "$active_iface" ]]; then
        echo "Disattivando l'interfaccia WireGuard attiva: '$active_iface'..."
        sudo wg-quick down "$active_iface"
        if [[ $? -eq 0 ]]; then
            echo "Interfaccia '$active_iface' disattivata con successo."
            return 0
        else
            echo "Errore durante la disattivazione di '$active_iface'."
            return 1
        fi
    else
        echo "Nessuna interfaccia WireGuard attiva e configurata rilevata."
        echo "--- Interfacce WireGuard disponibili per disconnessione manuale ---"
        local interfaces=($(get_wg_interfaces))

        if [[ ${#interfaces[@]} -eq 0 ]]; then
            echo "Nessuna interfaccia WireGuard configurata trovata in '$WIREGUARD_CONFIG_DIR'."
            return 1
        fi

        local i=1
        for iface in "${interfaces[@]}"; do
            echo "  $i) $iface"
            ((i++))
        done
        echo "-----------------------------------"
        echo -n "Seleziona l'interfaccia da disattivare (numero): "
        read choice

        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#interfaces[@]} ]]; then
            local selected_iface="${interfaces[$((choice-1))]}"
            echo "Disattivando l'interfaccia '$selected_iface'..."
            sudo wg-quick down "$selected_iface"
            if [[ $? -eq 0 ]]; then
                echo "Interfaccia '$selected_iface' disattivata con successo."
            else
                echo "Errore durante la disattivazione di '$selected_iface'."
                return 1
            fi
        else
            echo "Scelta non valida. Operazione annullata."
            return 1
        fi
    fi
    return 0
}

# Funzione per processare il file sorgente (immagine QR o testo) e salvare la configurazione
process_vpn_config_source() {
    local source_file="$1"
    local output_basename="$2" # È il nome base del file, senza estensione

    local file_mime_type=$(file --mime-type -b "$source_file")
    local config_content=""

    if [[ "$file_mime_type" == image/* ]]; then
        echo "Rilevata immagine QR code: '$source_file'."
        # Esegui il controllo di zbarimg qui, prima di tentare di usarlo
        if ! check_zbarimg_installed; then
            return 1 # Fallisce se zbarimg non è disponibile
        fi
        config_content=$(zbarimg --quiet --raw "$source_file")
        if [[ -z "$config_content" ]]; then
            echo "Errore: Nessun QR code valido trovato nell'immagine o contenuto vuoto."
            return 1
        fi
    else
        echo "Rilevato file di testo configurazione: '$source_file'."
        # Leggi il contenuto direttamente dal file di testo
        if [[ ! -f "$source_file" ]]; then
            echo "Errore: Il file di configurazione '$source_file' non esiste."
            return 1
        fi
        config_content=$(cat "$source_file")
        if [[ -z "$config_content" ]]; then
            echo "Avviso: Il file di configurazione '$source_file' è vuoto."
            # Non è un errore critico, ma un avviso
        fi
    fi

    # Costruisci il percorso completo del file di output con l'estensione .conf
    local full_output_path="${WIREGUARD_CONFIG_DIR}/${output_basename}.conf"

    # Crea la directory di destinazione se non esiste (sebbene /etc/wireguard dovrebbe esistere)
    mkdir -p "$WIREGUARD_CONFIG_DIR"

    echo "$config_content" > "$full_output_path"
    
    if [[ $? -eq 0 ]]; then
        echo "Configurazione VPN salvata con successo in '$full_output_path'."
        # Non visualizzare il contenuto per motivi di sicurezza
    else
        echo "Errore durante il salvataggio della configurazione VPN in '$full_output_path'."
        return 1
    fi
    return 0
}

# --- Controllo Permessi Root ---

if [[ $EUID -ne 0 ]]; then
   echo "Questo script deve essere eseguito come root o con sudo."
   echo "Esempio: sudo $0"
   exit 1
fi

# --- Logica Principale dello Script ---

NUM_PARAMS=$# 

if [[ "$NUM_PARAMS" -eq 0 ]]; then
    echo "Nessun parametro specificato. Verifico lo stato della connessione WireGuard..."
    
    if check_wg_connection; then
        echo "Stato WireGuard: CONNESSO (output di 'sudo wg' non vuoto)."
        disconnect_wg # Se connesso, tenta la disconnessione intelligente o chiede scelta
    else
        echo "Stato WireGuard: DISCONNESSO (output di 'sudo wg' vuoto)."
        connect_wg # Se disconnesso, chiede la scelta per connettersi
    fi

elif [[ "$NUM_PARAMS" -eq 2 ]]; then
    SOURCE_FILE_PATH="$1" # Può essere immagine QR o file di testo
    OUTPUT_FILE_NAME="$2" # Questo sarà il nome base, l'estensione .conf verrà aggiunta

    # Verifica che il file sorgente esista
    if [[ ! -f "$SOURCE_FILE_PATH" ]]; then 
        echo "Errore: Il file sorgente '$SOURCE_FILE_PATH' non esiste o non è un file."
        exit 1
    fi

    # Verifica che il nome del file di output sia valido (evita "/" o ".." che potrebbero creare path assoluti)
    if [[ "$OUTPUT_FILE_NAME" == *"/"* || "$OUTPUT_FILE_NAME" == *".."* ]]; then
        echo "Errore: Il nome del file '$OUTPUT_FILE_NAME' non può contenere '/' o '..'."
        exit 1
    fi

    process_vpn_config_source "$SOURCE_FILE_PATH" "$OUTPUT_FILE_NAME"
    
    if [[ $? -ne 0 ]]; then
        echo "Operazione di salvataggio configurazione fallita."
        exit 1
    fi

else
    echo "Errore: Numero di parametri non valido."
    echo "Utilizzo:"
    echo "  sudo $0                                 (per controllare/gestire la connessione WireGuard)"
    echo "  sudo $0 <percorso_sorgente_config> <nome_base_file_config> (per decodificare QR/leggere testo e salvare in '$WIREGUARD_CONFIG_DIR/nome_base_file_config.conf')"
    echo "    <percorso_sorgente_config> può essere un'immagine QR o un file di testo."
    exit 1
fi

exit 0
