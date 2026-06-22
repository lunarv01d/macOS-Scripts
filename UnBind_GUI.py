#!/usr/bin/env python3

import tkinter as tk
from tkinter import messagebox, scrolledtext
import subprocess
import threading
import os
import sys

class UnbindGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("AD Unbind & Account Conversion")
        self.root.geometry("600x500")
        self.root.resizable(False, False)

        # Check root
        if os.geteuid() != 0:
            messagebox.showerror("Error", "This application must be run as root (via sudo).")
            sys.exit(1)

        # Get script directory
        self.script_dir = os.path.dirname(os.path.abspath(__file__))
        self.unbind_script = os.path.join(self.script_dir, "UnBind_macOS.sh")

        if not os.path.exists(self.unbind_script):
            messagebox.showerror("Error", f"UnBind_macOS.sh not found in {self.script_dir}")
            sys.exit(1)

        self.setup_ui()

    def setup_ui(self):
        # Header
        header = tk.Label(
            self.root,
            text="Unbind from Active Directory",
            font=("Helvetica", 18, "bold"),
            bg="#e8f4f8"
        )
        header.pack(fill=tk.X, padx=0, pady=10)

        # Info frame
        info_frame = tk.Frame(self.root)
        info_frame.pack(fill=tk.BOTH, expand=False, padx=20, pady=10)

        info_text = """This will:

• Convert mobile accounts to local accounts
• Unbind this Mac from Active Directory
• Preserve all user files

After completion, you can enroll with Jamf Connect
and Entra ID.

This process cannot be undone. Continue?"""

        info_label = tk.Label(
            info_frame,
            text=info_text,
            justify=tk.LEFT,
            font=("Helvetica", 11),
            wraplength=550
        )
        info_label.pack(side=tk.LEFT)

        # Log output
        log_label = tk.Label(
            self.root,
            text="Process Output:",
            font=("Helvetica", 10, "bold"),
            justify=tk.LEFT
        )
        log_label.pack(anchor=tk.W, padx=20, pady=(10, 5))

        self.log_text = scrolledtext.ScrolledText(
            self.root,
            height=10,
            width=70,
            font=("Courier", 9),
            state=tk.DISABLED,
            bg="#f5f5f5"
        )
        self.log_text.pack(fill=tk.BOTH, expand=True, padx=20, pady=(0, 10))

        # Button frame
        button_frame = tk.Frame(self.root)
        button_frame.pack(fill=tk.X, padx=20, pady=10)

        self.continue_btn = tk.Button(
            button_frame,
            text="Continue",
            command=self.start_process,
            bg="#4CAF50",
            fg="white",
            font=("Helvetica", 11),
            width=15,
            padx=10,
            pady=8
        )
        self.continue_btn.pack(side=tk.LEFT, padx=5)

        self.cancel_btn = tk.Button(
            button_frame,
            text="Cancel",
            command=self.root.quit,
            bg="#f44336",
            fg="white",
            font=("Helvetica", 11),
            width=15,
            padx=10,
            pady=8
        )
        self.cancel_btn.pack(side=tk.LEFT, padx=5)

    def log_output(self, message):
        self.log_text.config(state=tk.NORMAL)
        self.log_text.insert(tk.END, message + "\n")
        self.log_text.see(tk.END)
        self.log_text.config(state=tk.DISABLED)
        self.root.update()

    def start_process(self):
        self.continue_btn.config(state=tk.DISABLED)
        self.cancel_btn.config(state=tk.DISABLED)

        self.log_output("Starting AD unbind process...")
        self.log_output("")

        # Run in thread to keep UI responsive
        thread = threading.Thread(target=self.run_unbind, daemon=True)
        thread.start()

    def run_unbind(self):
        try:
            env = os.environ.copy()
            env["SILENT_MODE"] = "true"

            process = subprocess.Popen(
                ["bash", self.unbind_script],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                env=env,
                text=True
            )

            for line in process.stdout:
                self.log_output(line.rstrip())

            process.wait()
            exit_code = process.returncode

            self.log_output("")
            if exit_code == 0:
                self.log_output("✓ Process completed successfully!")
                self.root.after(500, lambda: messagebox.showinfo(
                    "Success",
                    "AD unbind completed successfully!\n\n"
                    "Your Mac has been unbound from Active Directory.\n"
                    "Local accounts have been converted.\n\n"
                    "You can now enroll with Jamf Connect."
                ))
            else:
                self.log_output(f"✗ Process failed with exit code {exit_code}")
                self.root.after(500, lambda: messagebox.showerror(
                    "Error",
                    "Errors occurred during processing.\n\n"
                    "See the output above for details.\n"
                    "Check /var/log/unbind_ad_conversion.log for full logs."
                ))

        except Exception as e:
            self.log_output(f"Error: {str(e)}")
            messagebox.showerror("Error", f"Failed to run script: {str(e)}")

        finally:
            self.continue_btn.config(state=tk.NORMAL)
            self.cancel_btn.config(state=tk.NORMAL)

if __name__ == "__main__":
    root = tk.Tk()
    app = UnbindGUI(root)
    root.mainloop()
