# WireGuard VPN Manager Script

A versatile Bash script for managing WireGuard VPN connections and importing configurations from various sources.

---

## Table of Contents

* [Features](#features)
* [Prerequisites](#prerequisites)
* [Installation](#installation)
* [Usage](#usage)
    * [Managing VPN Connections](#managing-vpn-connections)
    * [Importing New VPN Configurations](#importing-new-vpn-configurations)
* [Configuration](#configuration)
* [Contributing](#contributing)
* [License](#license)

---

## Features

* **Intelligent Connection Management**:
    * Automatically detects WireGuard VPN connection status (`CONNECTED`/`DISCONNECTED`).
    * If connected, it attempts to intelligently identify and disconnect the active WireGuard interface.
    * If disconnected or multiple interfaces are active/inactive, it provides a menu to connect/disconnect a specific VPN configuration.
* **Flexible Configuration Import**:
    * Supports importing WireGuard configurations from both **QR code image files** (e.g., `.png`, `.jpg`) and plain **text files**.
    * Automatic detection of input file type.
    * Decodes QR codes using `zbarimg`.
* **Robust Syntax Validation**:
    * Performs thorough syntax checks on imported WireGuard configurations to ensure they adhere to the expected `[Section]` and `Key = Value` format before saving. This helps prevent invalid configurations from being deployed.
* **Secure Configuration Storage**:
    * All imported and validated configurations are saved securely to the `/etc/wireguard/` directory with a `.conf` extension.
    * Sensitive content (like private keys) is never displayed in the console.

---

## Prerequisites

Before using this script, ensure you have the following packages installed on your Debian/Ubuntu-based system:

* **`wireguard-tools`**: Provides `wg` and `wg-quick` commands for WireGuard management.
    ```bash
    sudo apt install wireguard-tools
    ```
* **`zbar-tools`**: Required for decoding QR code images.
    ```bash
    sudo apt install zbar-tools
    ```
* **`iproute2`**: Provides the `ip` command (usually pre-installed).
* **`file`**: Used for determining file types (usually pre-installed).

---

## Installation

1.  **Download the script**:
    ```bash
    git clone [https://github.com/mastrogeppetto/VPNClientManager](https://github.com/mastrogeppetto/VPNClientManager)
    cd VPNClientManager
    # Or simply download the script file directly
    ```
2.  **Make it executable**:
    ```bash
    chmod +x VPN.sh
    ```
3.  **(Optional) Move to a PATH directory**: For easier execution from anywhere:
    ```bash
    sudo mv VPN.sh /usr/local/bin/

---

## Usage

The script requires `sudo` privileges for all operations as it interacts with network interfaces and system configuration files in `/etc/wireguard/`.

### Managing VPN Connections

To check your current WireGuard VPN status and interactively manage connections:

```bash
sudo ./VPN.sh
# Or if moved to /usr/local/bin:
# sudo VPN.sh
