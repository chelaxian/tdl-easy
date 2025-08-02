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
        messagebox.showerror("Ошибка", f"Не найден скрипт: {os.path.basename(script_path)}")
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
        messagebox.showerror("Ошибка запуска", str(e))

def ensure_and_copy(src_rel_name):
    launcher_dir = get_launcher_dir()
    src = resource_path(src_rel_name)
    dest = os.path.join(launcher_dir, src_rel_name)
    try:
        shutil.copy2(src, dest)
    except Exception as e:
        messagebox.showerror("Ошибка копирования", f"Не удалось скопировать {src_rel_name}: {e}")
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
        # keep dialog always on top
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

def download_single_file():
    url = simpledialog.askstring("Одиночный файл", "Вставьте ссылку на сообщение (https://t.me/…/123):", parent=MAIN_ROOT)
    if not url:
        return
    url = url.strip()
    if not (url.startswith("http://") or url.startswith("https://")):
        messagebox.showwarning("Неправильный URL", "Ожидается полный URL начиная с http:// или https://")
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
        messagebox.showerror("Ошибка создания обёртки", str(e))
        return

    run_powershell_script(wrapper_path)

def write_state_json(path, obj):
    try:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(obj, f, ensure_ascii=False, indent=2)
    except Exception as e:
        messagebox.showerror("Ошибка записи состояния", str(e))
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
        messagebox.showerror("Ошибка создания wrapper", str(e))
        return None
    return wrapper_path

def download_range():
    launcher_dir = get_launcher_dir()

    # TDL path with prefill using custom dialog
    default_tdl = launcher_dir
    dlg = StringInputDialog(MAIN_ROOT, "TDL path", "Путь до TDL:", initialvalue=default_tdl, width=80)
    tdl_path = dlg.result if dlg.result and dlg.result.strip() != "" else default_tdl
    if not os.path.exists(tdl_path):
        messagebox.showerror("Ошибка", f"TDL path не найден: {tdl_path}")
        return

    # Media directory with prefill
    default_media = launcher_dir
    dlg2 = StringInputDialog(MAIN_ROOT, "Media directory", "Директория для сохранения:", initialvalue=default_media, width=80)
    media_dir = dlg2.result if dlg2.result and dlg2.result.strip() != "" else default_media
    if not os.path.exists(media_dir):
        messagebox.showerror("Ошибка", f"Media directory не найден: {media_dir}")
        return

    # Telegram base link
    while True:
        base_link = simpledialog.askstring("Базовая ссылка Telegram", "Введите базовую ссылку (https://t.me/c/12345678/ или https://t.me/username/):", parent=MAIN_ROOT)
        if not base_link:
            return
        base_link = base_link.strip()
        if not base_link.endswith("/"):
            base_link += "/"
        if re.match(r"^https?://t\.me/c/\d+/$", base_link) or re.match(r"^https?://t\.me/[A-Za-z0-9_]{5,32}/$", base_link):
            break
        messagebox.showwarning("Неправильный формат", "Ожидается https://t.me/c/12345678/ или https://t.me/username/ с завершающим слешем.")

    # startId / endId
    while True:
        start_id_dlg = IntegerInputDialog(MAIN_ROOT, "Начальный индекс", "Введите startId (положительное целое, по умолчанию 1):", initialvalue=1, minvalue=1)
        start_id = start_id_dlg.result
        if start_id is None:
            return
        end_id_dlg = IntegerInputDialog(MAIN_ROOT, "Конечный индекс", f"Введите endId (>= {start_id}, по умолчанию {start_id + 99}):", initialvalue=start_id + 99, minvalue=start_id)
        end_id = end_id_dlg.result
        if end_id is None:
            return
        if end_id < start_id:
            messagebox.showwarning("Ошибка", "endId должен быть >= startId.")
            continue
        break

    # downloadLimit
    while True:
        dl_limit_dlg = IntegerInputDialog(MAIN_ROOT, "Лимит задач", "Макс concurrent download tasks (1-10) [default 2]:", initialvalue=2, minvalue=1, maxvalue=10)
        dl_limit = dl_limit_dlg.result
        if dl_limit is None:
            return
        if 1 <= dl_limit <= 10:
            break

    # threads
    while True:
        threads_dlg = IntegerInputDialog(MAIN_ROOT, "Потоки", "Max threads per task (1-8) [default 4]:", initialvalue=4, minvalue=1, maxvalue=8)
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

    # TDL path with prefill
    default_tdl = launcher_dir
    dlg = StringInputDialog(MAIN_ROOT, "TDL path", "Путь до TDL:", initialvalue=default_tdl, width=80)
    tdl_path = dlg.result if dlg.result and dlg.result.strip() != "" else default_tdl
    if not os.path.exists(tdl_path):
        messagebox.showerror("Ошибка", f"TDL path не найден: {tdl_path}")
        return

    # Media directory with prefill
    default_media = launcher_dir
    dlg2 = StringInputDialog(MAIN_ROOT, "Media directory", "Директория для сохранения:", initialvalue=default_media, width=80)
    media_dir = dlg2.result if dlg2.result and dlg2.result.strip() != "" else default_media
    if not os.path.exists(media_dir):
        messagebox.showerror("Ошибка", f"Media directory не найден: {media_dir}")
        return

    # Telegram message URL
    while True:
        msg_url = simpledialog.askstring("Ссылка на сообщение", "Введите Telegram message URL (https://t.me/c/12345678/123 или https://t.me/username/123):", parent=MAIN_ROOT)
        if not msg_url:
            return
        msg_url = msg_url.strip()
        if re.match(r"^https?://t\.me/c/\d+/\d+$", msg_url) or re.match(r"^https?://t\.me/[A-Za-z0-9_]{5,32}/\d+$", msg_url):
            break
        messagebox.showwarning("Неправильный формат", "Ожидается https://t.me/c/12345678/123 или https://t.me/username/123.")

    # downloadLimit
    while True:
        dl_limit_dlg = IntegerInputDialog(MAIN_ROOT, "Лимит задач", "Макс concurrent download tasks (1-10) [default 2]:", initialvalue=2, minvalue=1, maxvalue=10)
        dl_limit = dl_limit_dlg.result
        if dl_limit is None:
            return
        if 1 <= dl_limit <= 10:
            break

    # threads
    while True:
        threads_dlg = IntegerInputDialog(MAIN_ROOT, "Потоки", "Max threads per task (1-8) [default 4]:", initialvalue=4, minvalue=1, maxvalue=8)
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

    lbl = tk.Label(frm, text="Меню:", font=("Segoe UI", 14, "bold"))
    lbl.grid(row=0, column=0, columnspan=2, pady=(0,8), sticky="w")

    btn_update = tk.Button(frm, text="УСТАНОВИТЬ/ОБНОВИТЬ TDL", width=35, command=install_update_tdl)
    btn_update.grid(row=1, column=0, pady=4, padx=4)

    btn_single = tk.Button(frm, text="СКАЧАТЬ ОДИНОЧНЫЙ ФАЙЛ", width=35, command=download_single_file)
    btn_single.grid(row=2, column=0, pady=4, padx=4)

    btn_range = tk.Button(frm, text="СКАЧАТЬ ДИАПАЗОН ПОСТОВ", width=35, command=download_range)
    btn_range.grid(row=3, column=0, pady=4, padx=4)

    btn_full = tk.Button(frm, text="СКАЧАТЬ ВСЁ ИЗ ЧАТА", width=35, command=download_full_chat)
    btn_full.grid(row=4, column=0, pady=4, padx=4)

    btn_exit = tk.Button(frm, text="ВЫХОД", width=35, command=root.destroy)
    btn_exit.grid(row=5, column=0, pady=(12,4), padx=4)

    hint = tk.Label(frm, text="PowerShell-окна остаются открытыми для просмотра/ввода параметров.", font=("Segoe UI", 8), fg="gray")
    hint.grid(row=6, column=0, columnspan=2, pady=(8,0))

    root.mainloop()

if __name__ == "__main__":
    build_ui()
