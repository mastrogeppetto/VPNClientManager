#!/usr/bin/env python3

import tkinter as tk
from tkinter import messagebox, simpledialog, filedialog, ttk
import subprocess
import os
import threading # Per le operazioni in background

# --- Configuration ---
# Path to your WireGuard Bash script (relative to this Python script)
WIREGUARD_BASH_SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "VPN.sh")

# --- Helper Function to run Bash Script ---
def run_bash_command(command_args, wait_for_completion=True, show_success_popup=True):
    """
    Executes the main Bash script with given arguments using pkexec.
    Captures stdout/stderr and displays errors in a messagebox.
    Returns stdout on success, or None on error.
    """
    try:
        # pkexec is used to elevate privileges.
        # It needs to know the correct path to the script AND the policy action ID.
        # The .desktop file will handle the pkexec call.
        # Here we just prepare the command for pkexec which is run by the desktop environment.
        command = [WIREGUARD_BASH_SCRIPT] + command_args

        # Use subprocess.run to execute the bash script
        # Check=True will raise CalledProcessError for non-zero exit codes
        result = subprocess.run(command, capture_output=True, text=True, check=True)
        
        if show_success_popup and command_args[0] in ["connect", "disconnect", "import"]:
            messagebox.showinfo("Success", result.stdout.strip() or f"Operation '{command_args[0]}' completed successfully.")
        
        return result.stdout.strip()
    
    except FileNotFoundError:
        messagebox.showerror("Error", f"Script not found: {WIREGUARD_BASH_SCRIPT}\n"
                                     "Please ensure the Bash script is in the same directory and executable.")
        return None
    except subprocess.CalledProcessError as e:
        error_message = f"An error occurred during VPN operation:\n\n{e.stderr.strip() or e.stdout.strip() or e.output.strip()}"
        messagebox.showerror("Operation Failed", error_message)
        return None
    except Exception as e:
        messagebox.showerror("Unexpected Error", f"An unexpected error occurred: {e}")
        return None

# --- VPN Specific GUI Functions ---

def get_vpn_interface_names():
    """Calls Bash script to get the list of configured VPN interface names."""
    output = run_bash_command(["list_interfaces"], show_success_popup=False)
    if output:
        interfaces = [line.strip() for line in output.split('\n') if line.strip()]
        return sorted(interfaces)
    return []

def get_active_vpn_interface():
    """Calls Bash script to get the name of the currently active VPN interface."""
    return run_bash_command(["get_active"], show_success_popup=False)

def update_status():
    """Updates the status label and button states based on active VPN."""
    active_iface = get_active_vpn_interface()
    if active_iface:
        status_label.config(text=f"Status: Connected to {active_iface}")
        disconnect_button.config(state="normal")
    else:
        status_label.config(text="Status: Disconnected")
        disconnect_button.config(state="disabled")
    # Schedule next update
    root.after(5000, update_status) # Update every 5 seconds

def connect_vpn_gui():
    """Handles GUI flow for connecting to a VPN."""
    interfaces = get_vpn_interface_names()

    if not interfaces:
        messagebox.showinfo("Connect VPN", "No WireGuard VPN configurations found.\nPlease import a configuration first.")
        return

    connect_window = tk.Toplevel(root)
    connect_window.title("Select VPN to Connect")
    connect_window.transient(root)
    connect_window.grab_set()
    connect_window.geometry("400x150")
    connect_window.resizable(False, False)

    tk.Label(connect_window, text="Select a VPN interface:", font=("Helvetica", 12)).pack(pady=10)

    selected_vpn_name = tk.StringVar(connect_window)
    vpn_combobox = ttk.Combobox(connect_window, textvariable=selected_vpn_name, values=interfaces, state="readonly", font=("Helvetica", 10))
    vpn_combobox.pack(pady=5, padx=20, fill="x")
    if interfaces:
        vpn_combobox.set(interfaces[0])

    def do_connect():
        selected_name = selected_vpn_name.get()
        if not selected_name:
            messagebox.showwarning("Selection Required", "Please select a VPN interface.")
            return
        
        # Run connect in a separate thread to keep GUI responsive
        threading.Thread(target=lambda: run_bash_command(["connect", selected_name])).start()
        connect_window.destroy()
        root.after(1000, update_status) # Update status after connection attempt

    tk.Button(connect_window, text="Connect", command=do_connect,
              font=("Helvetica", 10), bg="#4CAF50", fg="white", padx=5, pady=3).pack(pady=10)
    
    connect_window.wait_window(connect_window)

def disconnect_vpn_gui():
    """Handles GUI flow for disconnecting the active VPN."""
    active_iface = get_active_vpn_interface()
    if not active_iface:
        messagebox.showinfo("Disconnect VPN", "No active WireGuard VPN detected.")
        return

    if messagebox.askyesno("Disconnect VPN", f"Are you sure you want to disconnect from {active_iface}?"):
        # Run disconnect in a separate thread
        threading.Thread(target=lambda: run_bash_command(["disconnect", active_iface])).start()
        root.after(1000, update_status) # Update status after disconnection attempt

def import_config_gui():
    """Handles GUI flow for importing a new VPN configuration."""
    source_file = filedialog.askopenfilename(
        title="Select Configuration File (QR image or text)",
        filetypes=[("All Files", "*.*"), ("Image Files", "*.png *.jpg *.jpeg *.gif"), ("Text Files", "*.txt *.conf")]
    )
    if not source_file:
        return

    config_name = simpledialog.askstring(
        "Configuration Name",
        "Enter a name for this VPN configuration (e.g., my_work_vpn).\n"
        "This will be used as the filename (e.g., my_work_vpn.conf):"
    )
    if not config_name:
        messagebox.showerror("Error", "Configuration name cannot be empty. Operation cancelled.")
        return
    
    # Basic filename validation
    if "/" in config_name or ".." in config_name:
        messagebox.showerror("Invalid Name", "VPN name cannot contain '/' or '..'")
        return

    # Run import in a separate thread
    threading.Thread(target=lambda: run_bash_command(["import", source_file, config_name])).start()
    root.after(1000, update_status) # Update status after import attempt

# --- Main GUI Window Setup ---
def create_main_window():
    global root, status_label, disconnect_button # Make them accessible globally
    root = tk.Tk()
    root.title("WireGuard VPN Client Manager")
    root.geometry("450x280")
    root.resizable(False, False)

    main_frame = tk.Frame(root, padx=20, pady=20)
    main_frame.pack(expand=True, fill="both")

    title_label = tk.Label(main_frame, text="WireGuard VPN Manager", font=("Helvetica", 16, "bold"))
    title_label.pack(pady=10)

    status_label = tk.Label(main_frame, text="Status: Checking...", font=("Helvetica", 12))
    status_label.pack(pady=5)

    btn_connect = tk.Button(main_frame, text="  Connect VPN  ", command=connect_vpn_gui,
                           font=("Helvetica", 12), bg="#4CAF50", fg="white", padx=10, pady=5)
    btn_connect.pack(pady=5)

    disconnect_button = tk.Button(main_frame, text="  Disconnect VPN  ", command=disconnect_vpn_gui,
                           font=("Helvetica", 12), bg="#f44336", fg="white", padx=10, pady=5, state="disabled")
    disconnect_button.pack(pady=5)

    btn_import = tk.Button(main_frame, text="  Import New VPN Config  ", command=import_config_gui,
                           font=("Helvetica", 12), bg="#2196F3", fg="white", padx=10, pady=5)
    btn_import.pack(pady=5)

    btn_exit = tk.Button(main_frame, text="Exit", command=root.destroy,
                         font=("Helvetica", 12), bg="#607D8B", fg="white", padx=10, pady=5)
    btn_exit.pack(pady=5)

    # Initial status update and start periodic updates
    update_status()

    root.mainloop()

if __name__ == "__main__":
    create_main_window()
    
