import tkinter as tk
from tkinter import simpledialog, messagebox
import subprocess
import os
import sys
import shutil
import json
import re

# Global state
MAIN_ROOT = None
LANG = 'RU'            # Default language
MIN_PS_VERSION = 7     # Минимальная требуемая версия PowerShell

# Тексты интерфейса
TEXTS = {
    'EN': {
        'menu': 'Menu:',
        'install_update': 'INSTALL/UPDATE TDL',
        'telegram_login': 'TELEGRAM LOGIN',
        'download_single': 'DOWNLOAD SINGLE FILE',
        'download_range': 'DOWNLOAD POSTS RANGE',
        'download_full': 'DOWNLOAD FULL CHAT',
        'exit': 'EXIT',
        'hint': 'PowerShell windows stay open for review/input.',
        'lang_en': 'EN',
        'lang_ru': 'RU',
    },
    'RU': {
        'menu': 'Меню:',
        'install_update': 'УСТАНОВИТЬ/ОБНОВИТЬ TDL',
        'telegram_login': 'ЛОГИН В TELEGRAM',
        'download_single': 'СКАЧАТЬ ОДИНОЧНЫЙ ФАЙЛ',
        'download_range': 'СКАЧАТЬ ДИАПАЗОН ПОСТОВ',
        'download_full': 'СКАЧАТЬ ВСЁ ИЗ ЧАТА',
        'exit': 'ВЫХОД',
        'hint': 'PowerShell-окна остаются открытыми для просмотра/ввода параметров.',
        'lang_en': 'EN',
        'lang_ru': 'RU',
    }
}

def resource_path(rel):
    if getattr(sys, "frozen", False):
        return os.path.join(sys._MEIPASS, rel)
    return os.path.join(os.path.dirname(__file__), rel)

def get_launcher_dir():
    if getattr(sys, "frozen", False):
        return os.path.dirname(sys.argv[0])
    return os.path.dirname(__file__)

def check_ps_version(exe_name):
    """Возвращает major-версию PowerShell или 0 при ошибке."""
    try:
        out = subprocess.check_output(
            [exe_name, '-NoProfile', '-Command', '$PSVersionTable.PSVersion.Major'],
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=5
        ).strip()
        return int(out)
    except:
        return 0

def ensure_pwsh():
    """Выбирает подходящий PowerShell: встроенный >= MIN_PS_VERSION,
       иначе pwsh >= MIN_PS_VERSION, иначе предлагает установить через winget."""
    # 1) встроенный
    if check_ps_version('powershell.exe') >= MIN_PS_VERSION:
        return 'powershell.exe'
    # 2) pwsh
    pwsh_path = shutil.which('pwsh')
    if pwsh_path and check_ps_version(pwsh_path) >= MIN_PS_VERSION:
        return pwsh_path
    # 3) предложить установить
    if shutil.which('winget'):
        txt = TEXTS[LANG]
        if messagebox.askyesno(txt['install_update'],
                               f"PowerShell ≥{MIN_PS_VERSION} not found. Install via winget?"):
            try:
                subprocess.check_call(['winget', 'install', '--id', 'Microsoft.Powershell', '--source', 'winget', '-e'])
                pwsh_path = shutil.which('pwsh')
                if pwsh_path and check_ps_version(pwsh_path) >= MIN_PS_VERSION:
                    return pwsh_path
            except Exception as e:
                messagebox.showerror("Error", f"Winget install failed: {e}")
    # fallback
    return 'powershell.exe'

def run_powershell_script(script_path, extra_command=None):
    if not os.path.isfile(script_path):
        messagebox.showerror("Ошибка", f"Не найден скрипт: {os.path.basename(script_path)}")
        return
    shell = ensure_pwsh()
    cmd = ["cmd", "/c", "start", "", shell, "-NoExit", "-ExecutionPolicy", "Bypass"]
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
        self.prompt, self.initialvalue, self.entry_width = prompt, initialvalue, width
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
        self.result = self.entry.get().strip()

class IntegerInputDialog(simpledialog.Dialog):
    def __init__(self, parent, title, prompt, initialvalue=0, minvalue=None, maxvalue=None):
        self.prompt, self.initialvalue, self.minvalue, self.maxvalue = prompt, initialvalue, minvalue, maxvalue
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
            if (self.minvalue is not None and val < self.minvalue) or (self.maxvalue is not None and val > self.maxvalue):
                raise ValueError()
            self.result = val
        except:
            self.result = None

def install_update_tdl():
    updater = ensure_and_copy("tdl-updater.ps1")
    if updater:
        run_powershell_script(updater)

def login_telegram():
    launcher_dir = get_launcher_dir()
    tdl_exe = os.path.join(launcher_dir, "tdl.exe")
    if not os.path.isfile(tdl_exe):
        messagebox.showerror("Ошибка", "tdl.exe не найден. Сначала установите/обновите TDL.")
        return
    messagebox.showinfo(TEXTS[LANG]['telegram_login'],
        "Откроется консоль – выберите user id, затем ответьте N на logout."
    )
    run_powershell_script(tdl_exe, "login")

def download_single_file():
    url = simpledialog.askstring(TEXTS[LANG]['download_single'], "Вставьте ссылку на сообщение:", parent=MAIN_ROOT)
    if not url:
        return
    url = url.strip()
    if not re.match(r"^https?://", url):
        messagebox.showwarning("Неправильный URL", "Ожидается полный URL.")
        return
    launcher_dir = get_launcher_dir()
    original = ensure_and_copy("tdl-easy-single.ps1")
    if not original:
        return
    wrapper = os.path.join(launcher_dir, "tdl-easy-single-wrapper.ps1")
    with open(original, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()
    escaped = url.replace("'", "''")
    new = content.replace("$telegramUrl = Read-Host", f"$telegramUrl = '{escaped}'")
    with open(wrapper, "w", encoding="utf-8") as f:
        f.write(new)
    run_powershell_script(wrapper)

def download_range():
    # вставьте здесь вашу реализацию из GitHub, аналогично download_single_file
    ...

def download_full_chat():
    # вставьте здесь вашу реализацию из GitHub, аналогично download_single_file
    ...

def switch_lang(new_lang):
    global LANG
    LANG = new_lang
    update_labels()

def update_labels():
    t = TEXTS[LANG]
    lbl_menu.config(text=t['menu'])
    btn_update.config(text=t['install_update'])
    btn_login.config(text=t['telegram_login'])
    btn_single.config(text=t['download_single'])
    btn_range.config(text=t['download_range'])
    btn_full.config(text=t['download_full'])
    btn_exit.config(text=t['exit'])
    hint_label.config(text=t['hint'])
    btn_en.config(text=t['lang_en'])
    btn_ru.config(text=t['lang_ru'])

def build_ui():
    global MAIN_ROOT, lbl_menu, btn_update, btn_login, btn_single, btn_range, btn_full, btn_exit, hint_label, btn_en, btn_ru
    root = tk.Tk(); MAIN_ROOT = root
    root.title("TDL Easy Launcher"); root.resizable(False, False)

    frm = tk.Frame(root, padx=12, pady=12); frm.pack()

    # переключатель языка
    lang_frm = tk.Frame(frm)
    btn_en = tk.Button(lang_frm, width=3, command=lambda: switch_lang('EN'))
    btn_ru = tk.Button(lang_frm, width=3, command=lambda: switch_lang('RU'))
    btn_en.pack(side='left'); btn_ru.pack(side='left')
    lang_frm.grid(row=0, column=0, sticky='w', pady=(0,8))

    # меню
    lbl_menu = tk.Label(frm, font=("Segoe UI", 14, "bold")); lbl_menu.grid(row=1, column=0, sticky="w")
    btn_update = tk.Button(frm, width=35, command=install_update_tdl); btn_update.grid(row=2, column=0, pady=4)
    btn_login  = tk.Button(frm, width=35, command=login_telegram);    btn_login.grid(row=3, column=0, pady=4)
    btn_single = tk.Button(frm, width=35, command=download_single_file); btn_single.grid(row=4, column=0, pady=4)
    btn_range  = tk.Button(frm, width=35, command=download_range);    btn_range.grid(row=5, column=0, pady=4)
    btn_full   = tk.Button(frm, width=35, command=download_full_chat); btn_full.grid(row=6, column=0, pady=4)
    btn_exit   = tk.Button(frm, width=35, command=root.destroy);      btn_exit.grid(row=7, column=0, pady=(12,4))

    hint_label = tk.Label(frm, font=("Segoe UI", 8), fg="gray"); hint_label.grid(row=8, column=0, pady=(8,0))

    update_labels()
    root.mainloop()

if __name__ == "__main__":
    build_ui()
