import tkinter as tk
from tkinter import simpledialog, messagebox
import subprocess
import os
import sys
import shutil
import json
import re

# ------------------------------------------------------------
# Глобальные переменные и интернационализация
# ------------------------------------------------------------
MAIN_ROOT = None
LANG = 'RU'            # 'RU' или 'EN'
MIN_PS_VERSION = 7     # минимальная мажорная версия PowerShell

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
        'login_info': "A console window will open: choose your user ID, then answer 'N' to the logout prompt."
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
        'login_info': "Откроется консоль: выберите user ID, затем ответьте 'N' на запрос отмены сессии."
    }
}

def switch_lang(new_lang):
    """Переключает язык интерфейса."""
    global LANG
    LANG = new_lang
    update_labels()

def update_labels():
    """Обновляет тексты всех виджетов при смене языка."""
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

# ------------------------------------------------------------
# Путь к ресурсам внутри скомпилированного .exe или скрипта
# ------------------------------------------------------------
def resource_path(rel):
    if getattr(sys, "frozen", False):
        # при работе из PyInstaller
        return os.path.join(sys._MEIPASS, rel)
    else:
        return os.path.join(os.path.abspath(os.path.dirname(__file__)), rel)

def get_launcher_dir():
    """Возвращает директорию, где находится исполняемый файл или скрипт."""
    if getattr(sys, "frozen", False):
        return os.path.dirname(os.path.abspath(sys.argv[0]))
    else:
        return os.path.abspath(os.path.dirname(__file__))

# ------------------------------------------------------------
# Проверка и установка PowerShell версии >= MIN_PS_VERSION
# ------------------------------------------------------------
def check_ps_version(exe_name):
    """Возвращает major-версию PS или 0 при ошибке."""
    try:
        out = subprocess.check_output(
            [exe_name, '-NoProfile', '-Command', '$PSVersionTable.PSVersion.Major'],
            stderr=subprocess.DEVNULL, text=True, timeout=5
        ).strip()
        return int(out)
    except:
        return 0

def ensure_pwsh():
    """Выбирает подходящий PowerShell или предлагает установить pwsh через winget."""
    # 1) проверить встроенный powershell.exe
    if check_ps_version('powershell.exe') >= MIN_PS_VERSION:
        return 'powershell.exe'
    # 2) проверить pwsh (PowerShell Core)
    pwsh_path = shutil.which('pwsh')
    if pwsh_path and check_ps_version(pwsh_path) >= MIN_PS_VERSION:
        return pwsh_path
    # 3) предложить установить через winget
    if shutil.which('winget'):
        t = TEXTS[LANG]
        if messagebox.askyesno(t['install_update'],
                               f"PowerShell ≥{MIN_PS_VERSION} не найден. Установить через winget?"):
            try:
                subprocess.check_call(['winget', 'install', '--id', 'Microsoft.Powershell', '--source', 'winget', '-e'])
                pwsh_path = shutil.which('pwsh')
                if pwsh_path and check_ps_version(pwsh_path) >= MIN_PS_VERSION:
                    return pwsh_path
            except Exception as e:
                messagebox.showerror("Error", f"Winget install failed: {e}")
    # fallback — вернём встроенный
    return 'powershell.exe'

# ------------------------------------------------------------
# Преобразование .ps1 в UTF-16 LE для старых PowerShell 5.1
# ------------------------------------------------------------
def ensure_unicode_encoding():
    """
    Если используется старый powershell.exe без поддержки UTF-8,
    рекодируем все .ps1 из папки запуска в UTF-16 LE (с BOM).
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
            except:
                pass

# ------------------------------------------------------------
# Запуск PowerShell-скриптов через выбранный shell
# ------------------------------------------------------------
def run_powershell_script(script_path, extra_command=None):
    if not os.path.isfile(script_path):
        messagebox.showerror("Error", f"Script not found: {os.path.basename(script_path)}")
        return
    shell = ensure_pwsh()
    # если это встроенный powershell.exe — перекодируем скрипты
    if os.path.basename(shell).lower() == 'powershell.exe':
        ensure_unicode_encoding()
    # формируем команду
    cmd = [
        "cmd", "/c", "start", "", shell,
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

# ------------------------------------------------------------
# Копирование .ps1 из ресурсов в папку запуска
# ------------------------------------------------------------
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

# ------------------------------------------------------------
# Диалоги ввода строк и чисел
# ------------------------------------------------------------
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
        self.result = self.entry.get().strip()

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

# ------------------------------------------------------------
# Установка или обновление TDL
# ------------------------------------------------------------
def install_update_tdl():
    updater = ensure_and_copy("tdl-updater.ps1")
    if not updater:
        return
    run_powershell_script(updater)

# ------------------------------------------------------------
# Логин в Telegram через tdl.exe login
# ------------------------------------------------------------
def login_telegram():
    launcher_dir = get_launcher_dir()
    tdl_exe = os.path.join(launcher_dir, "tdl.exe")
    if not os.path.isfile(tdl_exe):
        messagebox.showerror("Error", "tdl.exe not found. Install/update TDL first.")
        return
    t = TEXTS[LANG]
    messagebox.showinfo(t['telegram_login'], t['login_info'])
    # Запуск: & 'tdl.exe' login
    run_powershell_script(tdl_exe, f"& '{tdl_exe}' login")

# ------------------------------------------------------------
# Скачивание одиночного файла
# ------------------------------------------------------------
def download_single_file():
    t = TEXTS[LANG]
    url = simpledialog.askstring(t['download_single'], "Paste the message link (https://t.me/...):", parent=MAIN_ROOT)
    if not url:
        return
    url = url.strip()
    if not re.match(r"^https?://", url):
        messagebox.showwarning("Invalid URL", "Expecting full URL starting with http:// or https://")
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

# ------------------------------------------------------------
# Вспомогательная запись состояния
# ------------------------------------------------------------
def write_state_json(path, obj):
    try:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(obj, f, ensure_ascii=False, indent=2)
    except Exception as e:
        messagebox.showerror("State Write Error", str(e))
        return False
    return True

# ------------------------------------------------------------
# Создание wrapper для авто-ответа "Yes"
# ------------------------------------------------------------
def make_autoyes_wrapper(original_name, wrapper_name):
    launcher_dir = get_launcher_dir()
    original = ensure_and_copy(original_name)
    if not original:
        return None
    wrapper_path = os.path.join(launcher_dir, wrapper_name)
    content = f"""# Auto wrapper: answer Yes to saved parameters prompt
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

# ------------------------------------------------------------
# Скачивание диапазона постов
# ------------------------------------------------------------
def download_range():
    launcher_dir = get_launcher_dir()
    default = launcher_dir

    # Path to TDL
    dlg = StringInputDialog(MAIN_ROOT, "TDL path", "Path to TDL:", initialvalue=default, width=80)
    tdl_path = dlg.result if dlg.result else default
    if not os.path.exists(tdl_path):
        messagebox.showerror("Error", f"TDL path not found: {tdl_path}")
        return

    # Media directory
    dlg2 = StringInputDialog(MAIN_ROOT, "Media directory", "Directory to save into:", initialvalue=default, width=80)
    media_dir = dlg2.result if dlg2.result else default
    if not os.path.exists(media_dir):
        messagebox.showerror("Error", f"Media directory not found: {media_dir}")
        return

    # Base Telegram link
    while True:
        base_link = simpledialog.askstring(
            "Base Telegram URL",
            "Enter base link (https://t.me/c/12345678/ or https://t.me/username/):",
            parent=MAIN_ROOT
        )
        if not base_link:
            return
        base_link = base_link.strip()
        if not base_link.endswith("/"):
            base_link += "/"
        if re.match(r"^https?://t\.me/c/\d+/$", base_link) or re.match(r"^https?://t\.me/[A-Za-z0-9_]{5,32}/$", base_link):
            break
        messagebox.showwarning("Invalid Format", "URL must end with '/' and be a channel or username link.")

    # startId / endId
    while True:
        start_id = IntegerInputDialog(
            MAIN_ROOT,
            "Start Index",
            "Enter startId (positive integer, default 1):",
            initialvalue=1,
            minvalue=1
        ).result
        if start_id is None:
            return
        end_id = IntegerInputDialog(
            MAIN_ROOT,
            "End Index",
            f"Enter endId (>= {start_id}, default {start_id+99}):",
            initialvalue=start_id+99,
            minvalue=start_id
        ).result
        if end_id is None:
            return
        if end_id < start_id:
            messagebox.showwarning("Error", "endId must be >= startId.")
            continue
        break

    # downloadLimit
    while True:
        dl_limit = IntegerInputDialog(
            MAIN_ROOT,
            "Task Limit",
            "Max concurrent download tasks (1-10):",
            initialvalue=2,
            minvalue=1,
            maxvalue=10
        ).result
        if dl_limit is None:
            return
        if 1 <= dl_limit <= 10:
            break

    # threads
    while True:
        threads = IntegerInputDialog(
            MAIN_ROOT,
            "Threads",
            "Max threads per task (1-8):",
            initialvalue=4,
            minvalue=1,
            maxvalue=8
        ).result
        if threads is None:
            return
        if 1 <= threads <= 8:
            break

    # Save state
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

    # Create wrapper and run
    wrapper = make_autoyes_wrapper("tdl-easy-range.ps1", "tdl-easy-range-wrapper.ps1")
    if wrapper:
        run_powershell_script(wrapper)

# ------------------------------------------------------------
# Скачивание всего чата
# ------------------------------------------------------------
def download_full_chat():
    launcher_dir = get_launcher_dir()
    default = launcher_dir

    # Path to TDL
    dlg = StringInputDialog(MAIN_ROOT, "TDL path", "Path to TDL:", initialvalue=default, width=80)
    tdl_path = dlg.result if dlg.result else default
    if not os.path.exists(tdl_path):
        messagebox.showerror("Error", f"TDL path not found: {tdl_path}")
        return

    # Media directory
    dlg2 = StringInputDialog(MAIN_ROOT, "Media directory", "Directory to save into:", initialvalue=default, width=80)
    media_dir = dlg2.result if dlg2.result else default
    if not os.path.exists(media_dir):
        messagebox.showerror("Error", f"Media directory not found: {media_dir}")
        return

    # Telegram message URL
    while True:
        msg_url = simpledialog.askstring(
            "Message URL",
            "Enter message URL (https://t.me/c/12345678/123 or https://t.me/username/123):",
            parent=MAIN_ROOT
        )
        if not msg_url:
            return
        msg_url = msg_url.strip()
        if re.match(r"^https?://t\.me/c/\d+/\d+$", msg_url) or re.match(r"^https?://t\.me/[A-Za-z0-9_]{5,32}/\d+$", msg_url):
            break
        messagebox.showwarning("Invalid Format", "Expected a valid Telegram message URL.")

    # downloadLimit
    while True:
        dl_limit = IntegerInputDialog(
            MAIN_ROOT,
            "Task Limit",
            "Max concurrent download tasks (1-10):",
            initialvalue=2,
            minvalue=1,
            maxvalue=10
        ).result
        if dl_limit is None:
            return
        if 1 <= dl_limit <= 10:
            break

    # threads
    while True:
        threads = IntegerInputDialog(
            MAIN_ROOT,
            "Threads",
            "Max threads per task (1-8):",
            initialvalue=4,
            minvalue=1,
            maxvalue=8
        ).result
        if threads is None:
            return
        if 1 <= threads <= 8:
            break

    # Save state
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

    # Create wrapper and run
    wrapper = make_autoyes_wrapper("tdl-easy-full.ps1", "tdl-easy-full-wrapper.ps1")
    if wrapper:
        run_powershell_script(wrapper)

# ------------------------------------------------------------
# Построение UI
# ------------------------------------------------------------
def build_ui():
    global MAIN_ROOT
    global lbl_menu, btn_update, btn_login, btn_single, btn_range, btn_full, btn_exit, hint_label, btn_en, btn_ru

    root = tk.Tk()
    MAIN_ROOT = root
    root.title("TDL Easy Launcher")
    root.resizable(False, False)

    frm = tk.Frame(root, padx=12, pady=12)
    frm.pack()

    # language selector
    lang_frm = tk.Frame(frm)
    btn_en = tk.Button(lang_frm, width=3, command=lambda: switch_lang('EN'))
    btn_ru = tk.Button(lang_frm, width=3, command=lambda: switch_lang('RU'))
    btn_en.pack(side='left')
    btn_ru.pack(side='left')
    lang_frm.grid(row=0, column=0, sticky='w', pady=(0,8))

    # menu label
    lbl_menu = tk.Label(frm, font=("Segoe UI", 14, "bold"))
    lbl_menu.grid(row=1, column=0, sticky="w")

    # buttons
    btn_update = tk.Button(frm, width=35, command=install_update_tdl)
    btn_update.grid(row=2, column=0, pady=4)

    btn_login = tk.Button(frm, width=35, command=login_telegram)
    btn_login.grid(row=3, column=0, pady=4)

    btn_single = tk.Button(frm, width=35, command=download_single_file)
    btn_single.grid(row=4, column=0, pady=4)

    btn_range = tk.Button(frm, width=35, command=download_range)
    btn_range.grid(row=5, column=0, pady=4)

    btn_full = tk.Button(frm, width=35, command=download_full_chat)
    btn_full.grid(row=6, column=0, pady=4)

    btn_exit = tk.Button(frm, width=35, command=root.destroy)
    btn_exit.grid(row=7, column=0, pady=(12,4))

    hint_label = tk.Label(frm, font=("Segoe UI", 8), fg="gray")
    hint_label.grid(row=8, column=0, pady=(8,0))

    update_labels()
    root.mainloop()

if __name__ == "__main__":
    build_ui()
