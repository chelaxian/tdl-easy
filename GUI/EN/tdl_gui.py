import tkinter as tk
from tkinter import simpledialog, messagebox
import subprocess
import os
import sys
import shutil
import json
import re

# global reference to main root so dialogs can use it as parent
MAIN_ROOT = None

def resource_path(rel):
    if getattr(sys, "frozen", False):
        base = sys._MEIPASS
    else:
        base = os.path.abspath(os.path.dirname(__file__))
    return os.path.join(base, rel)

def get_launcher_dir():
    if getattr(sys, "frozen", False):
        exe_path = os.path.abspath(sys.argv[0])
        return os.path.dirname(exe_path)
    else:
        return os.path.abspath(os.path.dirname(__file__))

def run_powershell_script(script_path, extra_command=None):
    if not os.path.isfile(script_path):
        messagebox.showerror("Error", f"Script not found: {os.path.basename(script_path)}")
        return

    cmd = [
        "cmd", "/c", "start", "PowerShell.exe",
        "-NoExit",
        "-ExecutionPolicy", "Bypass",
    ]

    if extra_command:
        cmd += ["-Command", extra_command]
    else:
        cmd += ["-File", script_path]

    try:
        subprocess.Popen(cmd, cwd=os.path.dirname(script_path))
    except Exception as e:
        messagebox.showerror("Launch Error", str(e))

def ensure_and_copy(src_rel_name):
    launcher_dir = get_launcher_dir()
    src = resource_path(src_rel_name)
    dest = os.path.join(launcher_dir, src_rel_name)
    try:
        shutil.copy2(src, dest)
    except Exception as e:
        messagebox.showerror("Copy Error", f"Failed to copy {src_rel_name}: {e}")
        return None
    return dest

class StringInputDialog(simpledialog.Dialog):
    def __init__(self, parent, title, prompt, initialvalue="", width=80):
        self.prompt = prompt
        self.initialvalue = initialvalue
        self.entry_width = width
        self.result = None
        super().__init__(parent, title)

    def body(self, master):
        self.attributes("-topmost", True)
        tk.Label(master, text=self.prompt).grid(row=0, sticky="w", padx=5, pady=(5,0))
        self.entry = tk.Entry(master, width=self.entry_width)
        self.entry.grid(row=1, padx=5, pady=(0,5))
        self.entry.insert(0, self.initialvalue)
        self.entry.focus_set()
        return self.entry

    def apply(self):
        self.result = self.entry.get()

class IntegerInputDialog(simpledialog.Dialog):
    def __init__(self, parent, title, prompt, initialvalue=0, minvalue=None, maxvalue=None):
        self.prompt = prompt
        self.initialvalue = initialvalue
        self.minvalue = minvalue
        self.maxvalue = maxvalue
        self.result = None
        super().__init__(parent, title)

    def body(self, master):
        self.attributes("-topmost", True)
        tk.Label(master, text=self.prompt).grid(row=0, sticky="w", padx=5, pady=(5,0))
        if self.minvalue is not None and self.maxvalue is not None:
            self.spin = tk.Spinbox(master, from_=self.minvalue, to=self.maxvalue, width=10)
            self.spin.grid(row=1, padx=5, pady=(0,5))
            self.spin.delete(0, "end")
            self.spin.insert(0, str(self.initialvalue))
        else:
            self.spin = tk.Entry(master, width=10)
            self.spin.grid(row=1, padx=5, pady=(0,5))
            self.spin.insert(0, str(self.initialvalue))
        self.spin.focus_set()
        return self.spin

    def apply(self):
        try:
            val = int(self.spin.get())
            if self.minvalue is not None and val < self.minvalue:
                raise ValueError()
            if self.maxvalue is not None and val > self.maxvalue:
                raise ValueError()
            self.result = val
        except Exception:
            self.result = None

def install_update_tdl():
    updater = ensure_and_copy("tdl-updater.ps1")
    if not updater:
        return
    run_powershell_script(updater)

def login_telegram():
    launcher_dir = get_launcher_dir()
    tdl_exe = os.path.join(launcher_dir, "tdl.exe")
    if not os.path.isfile(tdl_exe):
        messagebox.showerror("Error", "tdl.exe not found in the launch directory. Please install/update TDL first.")
        return

    messagebox.showinfo(
        "Telegram Login",
        "A console window will open. Manually choose user id, then when asked\n"
        "'Do you want to logout existing desktop session?' answer N."
    )
    cmd = [
        "cmd", "/c", "start", "PowerShell.exe",
        "-NoExit",
        "-ExecutionPolicy", "Bypass",
        "-Command", f"& '{tdl_exe}' login"
    ]
    try:
        subprocess.Popen(cmd, cwd=launcher_dir)
    except Exception as e:
        messagebox.showerror("Launch Error", str(e))

def download_single_file():
    url = simpledialog.askstring("Single File", "Paste the message link (https://t.me/...):", parent=MAIN_ROOT)
    if not url:
        return
    url = url.strip()
    if not (url.startswith("http://") or url.startswith("https://")):
        messagebox.showwarning("Invalid URL", "Expecting full URL starting with http:// or https://")
        return
    # validate single message or topic message URL
    if not re.match(r"^https?://t\.me/(?:(?:c/\d+/(?:\d+))(?:/\d+)?|(?:[A-Za-z0-9_]{5,32}/\d+))$", url):
        messagebox.showwarning("Invalid URL", "Expected link like https://t.me/username/123 or https://t.me/c/12345678/123 or https://t.me/c/12345678/456/123")
        return

    launcher_dir = get_launcher_dir()
    original = ensure_and_copy("tdl-easy-single.ps1")
    if not original:
        return

    wrapper_name = "tdl-easy-single-wrapper.ps1"
    wrapper_path = os.path.join(launcher_dir, wrapper_name)

    try:
        with open(original, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()
        escaped_url = url.replace("'", "''")
        replacement = f"$telegramUrl = '{escaped_url}'"
        new_content = content.replace("$telegramUrl = Read-Host", replacement)
        with open(wrapper_path, "w", encoding="utf-8") as f:
            f.write(new_content)
    except Exception as e:
        messagebox.showerror("Wrapper Creation Error", str(e))
        return

    run_powershell_script(wrapper_path)

def write_state_json(path, obj):
    try:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(obj, f, ensure_ascii=False, indent=2)
    except Exception as e:
        messagebox.showerror("State Write Error", str(e))
        return False
    return True

def make_autoyes_wrapper(original_name, wrapper_name):
    launcher_dir = get_launcher_dir()
    original = ensure_and_copy(original_name)
    if not original:
        return None
    wrapper_path = os.path.join(launcher_dir, wrapper_name)
    content = f"""# Auto wrapper: answer Yes to saved parameters prompt and invoke original
function Read-Host {{
    param($prompt)
    return "Yes"
}}
& ".\\{original_name}"
"""
    try:
        with open(wrapper_path, "w", encoding="utf-8") as f:
            f.write(content)
    except Exception as e:
        messagebox.showerror("Wrapper Creation Error", str(e))
        return None
    return wrapper_path

def download_range():
    launcher_dir = get_launcher_dir()

    default_tdl = launcher_dir
    dlg = StringInputDialog(MAIN_ROOT, "TDL path", "Path to TDL:", initialvalue=default_tdl, width=80)
    tdl_path = dlg.result if dlg.result and dlg.result.strip() != "" else default_tdl
    if not os.path.exists(tdl_path):
        messagebox.showerror("Error", f"TDL path not found: {tdl_path}")
        return

    default_media = launcher_dir
    dlg2 = StringInputDialog(MAIN_ROOT, "Media directory", "Directory to save into:", initialvalue=default_media, width=80)
    media_dir = dlg2.result if dlg2.result and dlg2.result.strip() != "" else default_media
    if not os.path.exists(media_dir):
        messagebox.showerror("Error", f"Media directory not found: {media_dir}")
        return

    while True:
        base_link = simpledialog.askstring("Base Telegram URL", "Enter base link (https://t.me/c/12345678/ or https://t.me/username/ or https://t.me/c/2267448302/166/):", parent=MAIN_ROOT)
        if not base_link:
            return
        base_link = base_link.strip()
        if not base_link.endswith("/"):
            base_link += "/"
        # support topic base
        if (re.match(r"^https?://t\.me/c/\d+/$", base_link)
                or re.match(r"^https?://t\.me/c/\d+/\d+/$", base_link)
                or re.match(r"^https?://t\.me/[A-Za-z0-9_]{5,32}/$", base_link)):
            break
        messagebox.showwarning("Invalid Format", "Expected https://t.me/c/12345678/ or https://t.me/c/12345678/123/ or https://t.me/username/ with trailing slash.")

    while True:
        start_id_dlg = IntegerInputDialog(MAIN_ROOT, "Start Index", "Enter startId (positive integer, default 1):", initialvalue=1, minvalue=1)
        start_id = start_id_dlg.result
        if start_id is None:
            return
        end_id_dlg = IntegerInputDialog(MAIN_ROOT, "End Index", f"Enter endId (>= {start_id}, default {start_id + 99}):", initialvalue=start_id + 99, minvalue=start_id)
        end_id = end_id_dlg.result
        if end_id is None:
            return
        if end_id < start_id:
            messagebox.showwarning("Error", "endId must be >= startId.")
            continue
        break

    while True:
        dl_limit_dlg = IntegerInputDialog(MAIN_ROOT, "Task Limit", "Max concurrent download tasks (1-10) [default 2]:", initialvalue=2, minvalue=1, maxvalue=10)
        dl_limit = dl_limit_dlg.result
        if dl_limit is None:
            return
        if 1 <= dl_limit <= 10:
            break

    while True:
        threads_dlg = IntegerInputDialog(MAIN_ROOT, "Threads", "Max threads per task (1-8) [default 4]:", initialvalue=4, minvalue=1, maxvalue=8)
        threads = threads_dlg.result
        if threads is None:
            return
        if 1 <= threads <= 8:
            break

    state = {
        "tdl_path": tdl_path,
        "telegramUrl": base_link,
        "mediaDir": media_dir,
        "startId": start_id,
        "endId": end_id,
        "downloadLimit": dl_limit,
        "threads": threads,
        "maxRetries": 1
    }
    state_file = os.path.join(get_launcher_dir(), "tdl_easy_runner.json")
    if not write_state_json(state_file, state):
        return

    wrapper = make_autoyes_wrapper("tdl-easy-range.ps1", "tdl-easy-range-wrapper.ps1")
    if not wrapper:
        return
    run_powershell_script(wrapper)

def download_full_chat():
    launcher_dir = get_launcher_dir()

    default_tdl = launcher_dir
    dlg = StringInputDialog(MAIN_ROOT, "TDL path", "Path to TDL:", initialvalue=default_tdl, width=80)
    tdl_path = dlg.result if dlg.result and dlg.result.strip() != "" else default_tdl
    if not os.path.exists(tdl_path):
        messagebox.showerror("Error", f"TDL path not found: {tdl_path}")
        return

    default_media = launcher_dir
    dlg2 = StringInputDialog(MAIN_ROOT, "Media directory", "Directory to save into:", initialvalue=default_media, width=80)
    media_dir = dlg2.result if dlg2.result and dlg2.result.strip() != "" else default_media
    if not os.path.exists(media_dir):
        messagebox.showerror("Error", f"Media directory not found: {media_dir}")
        return

    while True:
        msg_url = simpledialog.askstring("Message URL", "Enter Telegram message URL (https://t.me/c/12345678/123 or https://t.me/username/123 or https://t.me/c/2267448302/166/4771):", parent=MAIN_ROOT)
        if not msg_url:
            return
        msg_url = msg_url.strip()
        # allow topic message URL
        if re.match(r"^https?://t\.me/c/\d+/\d+$", msg_url) or re.match(r"^https?://t\.me/c/\d+/\d+/\d+$", msg_url) or re.match(r"^https?://t\.me/[A-Za-z0-9_]{5,32}/\d+$", msg_url):
            break
        messagebox.showwarning("Invalid Format", "Expected link like https://t.me/c/12345678/123 or https://t.me/c/12345678/123/456 or https://t.me/username/123.")

    while True:
        dl_limit_dlg = IntegerInputDialog(MAIN_ROOT, "Task Limit", "Max concurrent download tasks (1-10) [default 2]:", initialvalue=2, minvalue=1, maxvalue=10)
        dl_limit = dl_limit_dlg.result
        if dl_limit is None:
            return
        if 1 <= dl_limit <= 10:
            break

    while True:
        threads_dlg = IntegerInputDialog(MAIN_ROOT, "Threads", "Max threads per task (1-8) [default 4]:", initialvalue=4, minvalue=1, maxvalue=8)
        threads = threads_dlg.result
        if threads is None:
            return
        if 1 <= threads <= 8:
            break

    state = {
        "tdl_path": tdl_path,
        "telegramMessageUrl": msg_url,
        "mediaDir": media_dir,
        "downloadLimit": dl_limit,
        "threads": threads,
        "maxRetries": 1
    }
    state_file = os.path.join(get_launcher_dir(), "tdl_easy_runner.json")
    if not write_state_json(state_file, state):
        return

    wrapper = make_autoyes_wrapper("tdl-easy-full.ps1", "tdl-easy-full-wrapper.ps1")
    if not wrapper:
        return
    run_powershell_script(wrapper)

def build_ui():
    global MAIN_ROOT
    root = tk.Tk()
    MAIN_ROOT = root  # keep reference for dialogs
    root.title("TDL Easy Launcher")
    root.resizable(False, False)

    frm = tk.Frame(root, padx=12, pady=12)
    frm.pack()

    lbl = tk.Label(frm, text="Menu:", font=("Segoe UI", 14, "bold"))
    lbl.grid(row=0, column=0, columnspan=2, pady=(0,8), sticky="w")

    btn_update = tk.Button(frm, text="INSTALL/UPDATE TDL", width=35, command=install_update_tdl)
    btn_update.grid(row=1, column=0, pady=4, padx=4)

    btn_login = tk.Button(frm, text="TELEGRAM LOGIN", width=35, command=login_telegram)
    btn_login.grid(row=2, column=0, pady=4, padx=4)

    btn_single = tk.Button(frm, text="DOWNLOAD SINGLE FILE", width=35, command=download_single_file)
    btn_single.grid(row=3, column=0, pady=4, padx=4)

    btn_range = tk.Button(frm, text="DOWNLOAD POSTS RANGE", width=35, command=download_range)
    btn_range.grid(row=4, column=0, pady=4, padx=4)

    btn_full = tk.Button(frm, text="DOWNLOAD FULL CHAT", width=35, command=download_full_chat)
    btn_full.grid(row=5, column=0, pady=4, padx=4)

    btn_exit = tk.Button(frm, text="EXIT", width=35, command=root.destroy)
    btn_exit.grid(row=6, column=0, pady=(12,4), padx=4)

    hint = tk.Label(frm, text="PowerShell windows stay open for review/input.", font=("Segoe UI", 8), fg="gray")
    hint.grid(row=7, column=0, columnspan=2, pady=(8,0))

    root.mainloop()

if __name__ == "__main__":
    build_ui()
