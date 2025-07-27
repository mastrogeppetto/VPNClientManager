# ==============================================================================
# Makefile per l'installazione del WireGuard VPN Manager (Python GUI + Bash Backend)
# ==============================================================================

# Definizioni delle directory di installazione
# Queste sono le destinazioni finali dei tuoi file.
INSTALL_BIN_DIR = /usr/local/bin
INSTALL_POLKIT_DIR = /usr/share/polkit-1/actions
INSTALL_DESKTOP_DIR = /usr/local/share/applications
INSTALL_ICON_DIR = /usr/share/icons/hicolor/64x64/apps # Destinazione standard per icone 64x64

# Nomi dei file sorgente
BASH_SCRIPT_SRC = wireguard_vpn_manager.sh
PYTHON_SCRIPT_SRC = vpn_gui_launcher.py
POLKIT_POLICY_SRC = org.casamia.wireguardmanager.policy
DESKTOP_FILE_SRC = wireguard-vpn-manager-gui.desktop.in # Usiamo un template per il .desktop
ICON_FILE_SRC = WireguardIcon.png # Il nome del tuo file icona dovrebbe avere dimensione 64x64

# Nomi dei file di destinazione
BASH_SCRIPT_DST = $(INSTALL_BIN_DIR)/$(BASH_SCRIPT_SRC)
PYTHON_SCRIPT_DST = $(INSTALL_BIN_DIR)/$(PYTHON_SCRIPT_SRC)
POLKIT_POLICY_DST = $(INSTALL_POLKIT_DIR)/$(POLKIT_POLICY_SRC)
DESKTOP_FILE_DST = $(INSTALL_DESKTOP_DIR)/wireguard-vpn-manager-gui.desktop
ICON_FILE_DST = $(INSTALL_ICON_DIR)/$(ICON_FILE_SRC) # Percorso completo dell'icona installata

# ==============================================================================
# Variabili per la sostituzione dei percorsi nel file .desktop template
FULL_PYTHON_SCRIPT_PATH = $(PYTHON_SCRIPT_DST)
# ==============================================================================

.PHONY: all install uninstall clean

all:

# Regola per l'installazione di tutti i componenti
install: install_bin install_polkit install_desktop install_icon

# Installazione degli script eseguibili in /usr/local/bin
install_bin:
	@echo "Installazione degli script eseguibili in $(INSTALL_BIN_DIR)..."
	sudo install -m 755 $(BASH_SCRIPT_SRC) $(BASH_SCRIPT_DST)
	sudo install -m 755 $(PYTHON_SCRIPT_SRC) $(PYTHON_SCRIPT_DST)
	@echo "Script installati."

# Installazione del file PolicyKit
install_polkit:
	@echo "Installazione del file PolicyKit in $(INSTALL_POLKIT_DIR)..."
	sudo mkdir -p $(INSTALL_POLKIT_DIR)
	sudo install -m 644 $(POLKIT_POLICY_SRC) $(POLKIT_POLICY_DST)
	@echo "File PolicyKit installato. Potrebbe essere necessario riavviare la sessione per applicare le modifiche di PolicyKit."

# Installazione del file .desktop
install_desktop: $(DESKTOP_FILE_SRC)
	@echo "Generazione e installazione del file .desktop in $(INSTALL_DESKTOP_DIR)..."
	sudo mkdir -p $(INSTALL_DESKTOP_DIR)
	# Sostituisce il placeholder del percorso dello script Python e il nome dell'icona
	sed -e "s|@FULL_PYTHON_SCRIPT_PATH@|$(FULL_PYTHON_SCRIPT_PATH)|g" \
	    -e "s|@ICON_FILE_NAME@|$(ICON_FILE_SRC)|g" \
	    $(DESKTOP_FILE_SRC) | sudo tee $(DESKTOP_FILE_DST) > /dev/null
	sudo chmod 644 $(DESKTOP_FILE_DST)
	# Aggiorna il database delle applicazioni desktop
	sudo update-desktop-database $(INSTALL_DESKTOP_DIR)
	@echo "File .desktop installato."

# Installazione del file icona
install_icon:
	@echo "Installazione del file icona in $(INSTALL_ICON_DIR)..."
	sudo mkdir -p $(INSTALL_ICON_DIR)
	sudo install -m 644 $(ICON_FILE_SRC) $(ICON_FILE_DST)
	# Aggiorna la cache delle icone
	sudo gtk-update-icon-cache -f -t /usr/share/icons/hicolor || true
	@echo "Icona installata. Potrebbe essere necessario riavviare la sessione o ricaricare la cache delle icone."


# Regola per la disinstallazione
uninstall: uninstall_bin uninstall_polkit uninstall_desktop uninstall_icon

uninstall_bin:
	@echo "Disinstallazione degli script eseguibili da $(INSTALL_BIN_DIR)..."
	sudo rm -f $(BASH_SCRIPT_DST)
	sudo rm -f $(PYTHON_SCRIPT_DST)
	@echo "Script disinstallati."

uninstall_polkit:
	@echo "Disinstallazione del file PolicyKit da $(INSTALL_POLKIT_DIR)..."
	sudo rm -f $(POLKIT_POLICY_DST)
	@echo "File PolicyKit disinstallato."

uninstall_desktop:
	@echo "Disinstallazione del file .desktop da $(INSTALL_DESKTOP_DIR)..."
	sudo rm -f $(DESKTOP_FILE_DST)
	sudo update-desktop-database $(INSTALL_DESKTOP_DIR)
	@echo "File .desktop disinstallato."

uninstall_icon:
	@echo "Disinstallazione del file icona da $(INSTALL_ICON_DIR)..."
	sudo rm -f $(ICON_FILE_DST)
	sudo gtk-update-icon-cache -f -t /usr/share/icons/hicolor || true
	@echo "Icona disinstallata."

# Regola per pulire eventuali file temporanei
clean:
	@echo "Nessun file temporaneo da pulire."
