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
LANG = 'RU'            # 'RU' or 'EN'
MIN_PS_VERSION = 7     # minimal required major version of PowerShell

# Interface texts
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
        'hint': 'PowerShell-окна остаются открытыми для просмотра/ввода.',
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
    try:
        out = subprocess.check_output(
            [exe_name, '-NoProfile', '-Command', '$PSVersionTable.PSVersion.Major'],
            stderr=subprocess.DEVNULL, text=True, timeout=5
        ).strip()
        return int(out)
    except:
        return 0

def ensure_pwsh():
    # 1) встроенный PowerShell
    if check_ps_version('powershell.exe') >= MIN_PS_VERSION:
        return 'powershell.exe'
    # 2) pwsh (PowerShell Core)
    pwsh_path = shutil.which('pwsh')
    if pwsh_path and check_ps_version(pwsh_path) >= MIN_PS_VERSION:
        return pwsh_path
    # 3) предложить установить через winget
    if shutil.which('winget'):
        t = TEXTS[LANG]
        if messagebox.askyesno(t['install_update'],
                               f"PowerShell ≥{MIN_PS_VERSION} не найден. Установить через winget?"):
            try:
                subprocess.check_call(['winget','install','--id','Microsoft.Powershell','--source','winget','-e'])
                pwsh_path = shutil.which('pwsh')
                if pwsh_path and check_ps_version(pwsh_path) >= MIN_PS_VERSION:
                    return pwsh_path
            except Exception as e:
                messagebox.showerror("Error", f"Winget install failed: {e}")
    # fallback
    return 'powershell.exe'

def ensure_unicode_encoding():
    """
    Перекодирует все .ps1 в папке лаунчера в UTF-16 LE (с BOM),
    чтобы PowerShell 5.1 на Server 2019 правильно их парсил.
    """
    ld = get_launcher_dir()
    for fname in os.listdir(ld):
        if fname.lower().endswith('.ps1'):
            path = os.path.join(ld, fname)
            try:
                with open(path, 'r', encoding='utf-8', errors='ignore') as rf:
                    content = rf.read()
                with open(path, 'w', encoding='utf-16') as wf:
                    wf.write(content)
            except Exception:
                pass

def run_powershell_script(script_path, extra_command=None):
    if not os.path.isfile(script_path):
        messagebox.showerror("Ошибка", f"Не найден скрипт: {os.path.basename(script_path)}")
        return
    shell = ensure_pwsh()
    # если используем встроенный powershell.exe (версия < 7), перекодируем
    if os.path.basename(shell).lower() == 'powershell.exe':
        ensure_unicode_encoding()
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
        messagebox.showerror("Ошибка копирования", f"{src_rel_name}: {e}")
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
            self.spin.delete(0,"end"); self.spin.insert(0, str(self.initialvalue))
        else:
            self.spin = tk.Entry(master, width=10)
            self.spin.grid(row=1, padx=5, pady=(0,5))
            self.spin.insert(0, str(self.initialvalue))
        self.spin.focus_set()
        return self.spin
    def apply(self):
        try:
            v = int(self.spin.get())
            if (self.minvalue is not None and v < self.minvalue) or (self.maxvalue is not None and v > self.maxvalue):
                raise ValueError()
            self.result = v
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
    t = TEXTS[LANG]
    messagebox.showinfo(t['telegram_login'],
        "Откроется консоль – выберите user ID, затем ответьте N на logout."
    )
    run_powershell_script(tdl_exe, "login")

def download_single_file():
    t = TEXTS[LANG]
    url = simpledialog.askstring(t['download_single'], "Вставьте ссылку на сообщение:", parent=MAIN_ROOT)
    if not url: return
    url = url.strip()
    if not re.match(r"^https?://", url):
        messagebox.showwarning("Неправильный URL", "Ожидается полный URL.")
        return
    d = get_launcher_dir()
    orig = ensure_and_copy("tdl-easy-single.ps1")
    if not orig: return
    wrap = os.path.join(d, "tdl-easy-single-wrapper.ps1")
    with open(orig, "r", encoding="utf-8", errors="ignore") as f:
        txt = f.read()
    esc = url.replace("'", "''")
    new = txt.replace("$telegramUrl = Read-Host", f"$telegramUrl = '{esc}'")
    with open(wrap, "w", encoding="utf-8") as f:
        f.write(new)
    run_powershell_script(wrap)

def write_state_json(path, obj):
    try:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(obj, f, ensure_ascii=False, indent=2)
    except Exception as e:
        messagebox.showerror("Ошибка записи", str(e))
        return False
    return True

def make_autoyes_wrapper(orig, wrap_name):
    d = get_launcher_dir()
    orig_path = ensure_and_copy(orig)
    if not orig_path: return None
    wrap = os.path.join(d, wrap_name)
    content = (
        "# Auto wrapper: answer Yes to saved parameters prompt\n"
        "function Read-Host { param($prompt) return \"Yes\" }\n"
        f"& \".\\{orig}\""
    )
    try:
        with open(wrap, "w", encoding="utf-8") as f:
            f.write(content)
    except Exception as e:
        messagebox.showerror("Ошибка wrapper", str(e))
        return None
    return wrap

def download_range():
    d = get_launcher_dir()
    default = d
    dlg = StringInputDialog(MAIN_ROOT, "TDL path", "Путь до TDL:", initialvalue=default, width=80)
    tdl_path = dlg.result or default
    if not os.path.exists(tdl_path):
        messagebox.showerror("Ошибка", f"TDL path не найден: {tdl_path}"); return
    dlg2 = StringInputDialog(MAIN_ROOT, "Media directory", "Директория для сохранения:", initialvalue=default, width=80)
    media_dir = dlg2.result or default
    if not os.path.exists(media_dir):
        messagebox.showerror("Ошибка", f"Media directory не найден: {media_dir}"); return
    while True:
        base = simpledialog.askstring("Базовая ссылка Telegram",
            "Введите базовую ссылку (https://t.me/c/12345678/ или https://t.me/username/):",
            parent=MAIN_ROOT)
        if not base: return
        base = base.strip()
        if not base.endswith("/"): base += "/"
        if re.match(r"^https?://t\.me/c/\d+/$", base) or re.match(r"^https?://t\.me/[A-Za-z0-9_]{5,32}/$", base):
            break
        messagebox.showwarning("Неправильный формат", "Ожидается ссылка с '/' на конце.")
    start = IntegerInputDialog(MAIN_ROOT, "Начальный индекс", "Введите startId:", initialvalue=1, minvalue=1).result
    if start is None: return
    end = IntegerInputDialog(MAIN_ROOT, "Конечный индекс", f"Введите endId (>= {start}):", initialvalue=start+99, minvalue=start).result
    if end is None: return
    dl_lim = IntegerInputDialog(MAIN_ROOT, "Лимит задач", "Max concurrent tasks (1-10):", initialvalue=2, minvalue=1, maxvalue=10).result
    if dl_lim is None: return
    thr = IntegerInputDialog(MAIN_ROOT, "Потоки", "Max threads (1-8):", initialvalue=4, minvalue=1, maxvalue=8).result
    if thr is None: return
    state = {
        "tdl_path": tdl_path,
        "telegramUrl": base,
        "mediaDir": media_dir,
        "startId": start,
        "endId": end,
        "downloadLimit": dl_lim,
        "threads": thr,
        "maxRetries": 1
    }
    path = os.path.join(d, "tdl_easy_runner.json")
    if not write_state_json(path, state): return
    wrap = make_autoyes_wrapper("tdl-easy-range.ps1", "tdl-easy-range-wrapper.ps1")
    if wrap:
        run_powershell_script(wrap)

def download_full_chat():
    d = get_launcher_dir()
    default = d
    dlg = StringInputDialog(MAIN_ROOT, "TDL path", "Путь до TDL:", initialvalue=default, width=80)
    tdl_path = dlg.result or default
    if not os.path.exists(tdl_path):
        messagebox.showerror("Ошибка", f"TDL path не найден: {tdl_path}"); return
    dlg2 = StringInputDialog(MAIN_ROOT, "Media directory", "Директория для сохранения:", initialvalue=default, width=80)
    media_dir = dlg2.result or default
    if not os.path.exists(media_dir):
        messagebox.showerror("Ошибка", f"Media directory не найден: {media_dir}"); return
    while True:
        msg = simpledialog.askstring("Ссылка на сообщение",
            "Введите URL (https://t.me/c/12345678/123 или https://t.me/username/123):",
            parent=MAIN_ROOT)
        if not msg: return
        msg = msg.strip()
        if re.match(r"^https?://t\.me/c/\d+/\d+$", msg) or re.match(r"^https?://t\.me/[A-Za-z0-9_]{5,32}/\d+$", msg):
            break
        messagebox.showwarning("Неправильный формат", "Ожидается корректный URL.")
    dl_lim = IntegerInputDialog(MAIN_ROOT, "Лимит задач", "Max concurrent tasks (1-10):", initialvalue=2, minvalue=1, maxvalue=10).result
    if dl_lim is None: return
    thr = IntegerInputDialog(MAIN_ROOT, "Потоки", "Max threads (1-8):", initialvalue=4, minvalue=1, maxvalue=8).result
    if thr is None: return
    state = {
        "tdl_path": tdl_path,
        "telegramMessageUrl": msg,
        "mediaDir": media_dir,
        "downloadLimit": dl_lim,
        "threads": thr,
        "maxRetries": 1
    }
    path = os.path.join(d, "tdl_easy_runner.json")
    if not write_state_json(path, state): return
    wrap = make_autoyes_wrapper("tdl-easy-full.ps1", "tdl-easy-full-wrapper.ps1")
    if wrap:
        run_powershell_script(wrap)

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
    # language switcher
    lang_frm = tk.Frame(frm)
    btn_en = tk.Button(lang_frm, width=3, command=lambda: switch_lang('EN'))
    btn_ru = tk.Button(lang_frm, width=3, command=lambda: switch_lang('RU'))
    btn_en.pack(side='left'); btn_ru.pack(side='left')
    lang_frm.grid(row=0, column=0, sticky='w', pady=(0,8))
    # menu
    lbl_menu = tk.Label(frm, font=("Segoe UI",14,"bold")); lbl_menu.grid(row=1, column=0, sticky="w")
    btn_update = tk.Button(frm, width=35, command=install_update_tdl);      btn_update.grid(row=2, column=0, pady=4)
    btn_login  = tk.Button(frm, width=35, command=login_telegram);         btn_login.grid(row=3, column=0, pady=4)
    btn_single = tk.Button(frm, width=35, command=download_single_file);    btn_single.grid(row=4, column=0, pady=4)
    btn_range  = tk.Button(frm, width=35, command=download_range);          btn_range.grid(row=5, column=0, pady=4)
    btn_full   = tk.Button(frm, width=35, command=download_full_chat);      btn_full.grid(row=6, column=0, pady=4)
    btn_exit   = tk.Button(frm, width=35, command=root.destroy);            btn_exit.grid(row=7, column=0, pady=(12,4))
    hint_label = tk.Label(frm, font=("Segoe UI",8), fg="gray");            hint_label.grid(row=8, column=0, pady=(8,0))
    update_labels()
    root.mainloop()

if __name__ == "__main__":
    build_ui()
