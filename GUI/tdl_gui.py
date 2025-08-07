import tkinter as tk
from tkinter import simpledialog, messagebox
import subprocess
import os
import sys
import shutil
import json
import re

# ==============================================================================
# Globals and configuration
# ==============================================================================

# reference to main Tk window and main frame
MAIN_ROOT = None
MAIN_FRAME = None

# current UI language ('EN' or 'RU')
LANG = 'EN'

# whether to close terminals automatically after scripts finish
CLOSE_TERMINAL = True

# widget references for easy text updates
WIDGETS = {}

# menu texts for both languages
MENU_TEXT = {
    'EN': {
        'title': 'TDL Easy Launcher',
        'menu': 'Menu:',
        'install_update': 'INSTALL/UPDATE TDL',
        'telegram_login': 'TELEGRAM LOGIN',
        'download_single': 'DOWNLOAD SINGLE FILE',
        'download_range': 'DOWNLOAD POSTS RANGE',
        'download_full': 'DOWNLOAD FULL CHAT',
        'exit': 'EXIT',
        'button_en': 'EN',
        'button_ru': 'RU',
        'close_terminal': 'Close terminal',
        'hint_close': 'PowerShell windows will auto-close after execution.',
        'hint_no_close': 'PowerShell windows will stay open after execution.',
    },
    'RU': {
        'title': 'TDL Easy Launcher',
        'menu': 'Меню:',
        'install_update': 'УСТАНОВИТЬ/ОБНОВИТЬ TDL',
        'telegram_login': 'ЛОГИН В TELEGRAM',
        'download_single': 'СКАЧАТЬ ОДИНОЧНЫЙ ФАЙЛ',
        'download_range': 'СКАЧАТЬ ДИАПАЗОН ПОСТОВ',
        'download_full': 'СКАЧАТЬ ВСЁ ИЗ ЧАТА',
        'exit': 'ВЫХОД',
        'button_en': 'EN',
        'button_ru': 'RU',
        'close_terminal': 'Закрыть терминал',
        'hint_close': 'PowerShell-окна авто-закрываются по завершении.',
        'hint_no_close': 'PowerShell-окна остаются открытыми после выполнения.',
    }
}

# ==============================================================================
# Utility functions
# ==============================================================================

def resource_path(rel):
    """
    Return absolute path to resource, works for dev and PyInstaller.
    """
    if getattr(sys, 'frozen', False):
        base = sys._MEIPASS
    else:
        base = os.path.abspath(os.path.dirname(__file__))
    return os.path.join(base, rel)

def get_launcher_dir():
    """
    Return directory where this script/executable resides.
    """
    if getattr(sys, 'frozen', False):
        exe_path = os.path.abspath(sys.argv[0])
        return os.path.dirname(exe_path)
    else:
        return os.path.abspath(os.path.dirname(__file__))

def get_powershell_version():
    """
    Return major version of installed PowerShell, or 0 on error.
    """
    try:
        output = subprocess.check_output(
            ['powershell.exe', '-NoProfile', '-Command', '$PSVersionTable.PSVersion.Major'],
            stderr=subprocess.DEVNULL,
            text=True
        )
        return int(output.strip())
    except Exception:
        return 0

def sanitize_script(script_path):
    """
    Remove unsupported characters (UTF-8 special symbols, emojis)
    for PowerShell versions below 7 by keeping only ASCII.
    Overwrites the original script file.
    """
    try:
        with open(script_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
        ascii_only = ''.join(c for c in content if ord(c) < 128)
        with open(script_path, 'w', encoding='utf-8') as f:
            f.write(ascii_only)
    except Exception as e:
        messagebox.showerror('Error', str(e))
    return script_path

def run_powershell_script(script_path=None, extra_command=None):
    """
    Launch a PowerShell script or command in its own window and
    optionally close the window automatically when done.
    """
    global CLOSE_TERMINAL
    if extra_command and not script_path:
        # running inline command
        if CLOSE_TERMINAL:
            cmd = [
                'cmd', '/c', 'start', '', 'PowerShell.exe',
                '-ExecutionPolicy', 'Bypass',
                '-Command', f"{extra_command}; exit"
            ]
        else:
            cmd = [
                'cmd', '/c', 'start', '', 'PowerShell.exe',
                '-NoExit',
                '-ExecutionPolicy', 'Bypass',
                '-Command', extra_command
            ]
        cwd = get_launcher_dir()
    else:
        # running a .ps1 file
        if not os.path.isfile(script_path):
            messagebox.showerror('Error', f'Script not found: {os.path.basename(script_path)}')
            return
        ps_ver = get_powershell_version()
        # if PS version < 7, sanitize unsupported characters in place
        if ps_ver < 7:
            sanitize_script(script_path)
        if CLOSE_TERMINAL:
            cmd = [
                'cmd', '/c', 'start', '', 'PowerShell.exe',
                '-ExecutionPolicy', 'Bypass',
                '-File', script_path
            ]
        else:
            cmd = [
                'cmd', '/c', 'start', '', 'PowerShell.exe',
                '-NoExit',
                '-ExecutionPolicy', 'Bypass',
                '-File', script_path
            ]
        cwd = os.path.dirname(script_path)
    try:
        subprocess.Popen(cmd, cwd=cwd)
    except Exception as e:
        messagebox.showerror('Launch Error', str(e))

def ensure_and_copy(src_rel_name):
    """
    Copy embedded resource script to launcher directory if not already present.
    """
    launcher_dir = get_launcher_dir()
    dest = os.path.join(launcher_dir, src_rel_name)
    if os.path.isfile(dest):
        return dest
    src = resource_path(src_rel_name)
    try:
        shutil.copy2(src, dest)
    except Exception as e:
        messagebox.showerror('Error', f'Failed to copy {src_rel_name}: {e}')
        return None
    return dest

def write_state_json(path, obj):
    """
    Write JSON state file for PS scripts.
    """
    try:
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(obj, f, ensure_ascii=False, indent=2)
    except Exception as e:
        messagebox.showerror('Error', str(e))
        return False
    return True

# ==============================================================================
# Dialog classes
# ==============================================================================

class StringInputDialog(simpledialog.Dialog):
    def __init__(self, parent, title, prompt, initialvalue='', width=80):
        self.prompt = prompt
        self.initialvalue = initialvalue
        self.entry_width = width
        self.result = None
        super().__init__(parent, title)

    def body(self, master):
        self.attributes('-topmost', True)
        tk.Label(master, text=self.prompt).grid(row=0, sticky='w', padx=5, pady=(5,0))
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
        self.attributes('-topmost', True)
        tk.Label(master, text=self.prompt).grid(row=0, sticky='w', padx=5, pady=(5,0))
        if self.minvalue is not None and self.maxvalue is not None:
            self.spin = tk.Spinbox(master, from_=self.minvalue, to=self.maxvalue, width=10)
            self.spin.grid(row=1, padx=5, pady=(0,5))
            self.spin.delete(0, 'end')
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

# ==============================================================================
# TDL actions
# ==============================================================================

def make_autoyes_wrapper(original_name, wrapper_name):
    launcher_dir = get_launcher_dir()
    original = ensure_and_copy(original_name)
    if not original:
        return None
    wrapper_path = os.path.join(launcher_dir, wrapper_name)
    content = f"""# Auto wrapper: answer Yes to saved parameters prompt and invoke original
function Read-Host {{
    param($prompt)
    return 'Yes'
}}
& '.\\{original_name}'
"""
    try:
        with open(wrapper_path, 'w', encoding='utf-8') as f:
            f.write(content)
    except Exception as e:
        messagebox.showerror('Error', str(e))
        return None
    return wrapper_path

def install_update_tdl():
    updater = ensure_and_copy('tdl-updater.ps1')
    if not updater:
        return
    run_powershell_script(updater)

def login_telegram():
    launcher_dir = get_launcher_dir()
    tdl_exe = os.path.join(launcher_dir, 'tdl.exe')
    if not os.path.isfile(tdl_exe):
        messagebox.showerror('Error', 'tdl.exe not found. Please install/update TDL first.')
        return
    messagebox.showinfo(
        MENU_TEXT[LANG]['telegram_login'],
        ("A console window will open. Manually choose user id,\n"
         "then at the prompt 'Do you want to logout existing desktop session?' answer N.")
    )
    run_powershell_script(
        None,
        extra_command=f"& '{tdl_exe}' login"
    )

def download_single_file():
    url = simpledialog.askstring(
        MENU_TEXT[LANG]['download_single'],
        'Paste the message link (https://t.me/...):',
        parent=MAIN_ROOT
    )
    if not url:
        return
    url = url.strip()
    if not (url.startswith('http://') or url.startswith('https://')):
        messagebox.showwarning('Invalid URL', 'URL must start with http:// or https://')
        return
    if not re.match(r"^https?://t\.me/(?:(?:c/\d+/(?:\d+))(?:/\d+)?|(?:[A-Za-z0-9_]{5,32}/\d+))$", url):
        messagebox.showwarning('Invalid URL', 'Expected https://t.me/username/123 or https://t.me/c/12345678/123')
        return
    launcher_dir = get_launcher_dir()
    original = ensure_and_copy('tdl-easy-single.ps1')
    if not original:
        return
    wrapper_name = 'tdl-easy-single-wrapper.ps1'
    wrapper_path = os.path.join(launcher_dir, wrapper_name)
    try:
        with open(original, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
        escaped_url = url.replace("'", "''")
        new_content = content.replace('$telegramUrl = Read-Host',
                                      f"$telegramUrl = '{escaped_url}'")
        with open(wrapper_path, 'w', encoding='utf-8') as f:
            f.write(new_content)
    except Exception as e:
        messagebox.showerror('Error', str(e))
        return
    run_powershell_script(wrapper_path)

def download_range():
    launcher_dir = get_launcher_dir()
    default_tdl = launcher_dir
    dlg = StringInputDialog(MAIN_ROOT, 'TDL path', 'Path to TDL:', initialvalue=default_tdl, width=80)
    tdl_path = dlg.result or default_tdl
    if not os.path.exists(tdl_path):
        messagebox.showerror('Error', f'TDL path not found: {tdl_path}')
        return

    dlg2 = StringInputDialog(MAIN_ROOT, 'Media directory', 'Directory to save into:',
                             initialvalue=launcher_dir, width=80)
    media_dir = dlg2.result or launcher_dir
    if not os.path.exists(media_dir):
        messagebox.showerror('Error', f'Media directory not found: {media_dir}')
        return

    while True:
        base_link = simpledialog.askstring(
            'Base Telegram URL',
            'Enter base link (https://t.me/c/12345678/ or https://t.me/username/):',
            parent=MAIN_ROOT
        )
        if not base_link:
            return
        base_link = base_link.strip()
        if not base_link.endswith('/'):
            base_link += '/'
        if (re.match(r"^https?://t\.me/c/\d+/$", base_link)
                or re.match(r"^https?://t\.me/c/\d+/\d+/$", base_link)
                or re.match(r"^https?://t\.me/[A-Za-z0-9_]{5,32}/$", base_link)):
            break
        messagebox.showwarning('Invalid Format',
                               'Expected https://t.me/c/12345678/ or https://t.me/username/')

    while True:
        start_id_dlg = IntegerInputDialog(MAIN_ROOT, 'Start Index',
                                          'Enter startId (positive integer, default 1):',
                                          initialvalue=1, minvalue=1)
        start_id = start_id_dlg.result
        if start_id is None:
            return
        end_id_dlg = IntegerInputDialog(MAIN_ROOT, 'End Index',
                                        f'Enter endId (>= {start_id}, default {start_id+99}):',
                                        initialvalue=start_id+99, minvalue=start_id)
        end_id = end_id_dlg.result
        if end_id is None:
            return
        if end_id < start_id:
            messagebox.showwarning('Error', 'endId must be >= startId.')
            continue
        break

    while True:
        dl_limit_dlg = IntegerInputDialog(MAIN_ROOT, 'Task Limit',
                                          'Max concurrent download tasks (1-10) [default 2]:',
                                          initialvalue=2, minvalue=1, maxvalue=10)
        dl_limit = dl_limit_dlg.result
        if dl_limit is None:
            return
        if 1 <= dl_limit <= 10:
            break
    while True:
        threads_dlg = IntegerInputDialog(MAIN_ROOT, 'Threads',
                                         'Max threads per task (1-8) [default 4]:',
                                         initialvalue=4, minvalue=1, maxvalue=8)
        threads = threads_dlg.result
        if threads is None:
            return
        if 1 <= threads <= 8:
            break

    state = {
        'tdl_path': tdl_path,
        'telegramUrl': base_link,
        'mediaDir': media_dir,
        'startId': start_id,
        'endId': end_id,
        'downloadLimit': dl_limit,
        'threads': threads,
        'maxRetries': 1
    }
    state_file = os.path.join(get_launcher_dir(), 'tdl_easy_runner.json')
    if not write_state_json(state_file, state):
        return

    wrapper = make_autoyes_wrapper('tdl-easy-range.ps1', 'tdl-easy-range-wrapper.ps1')
    if not wrapper:
        return
    run_powershell_script(wrapper)

def download_full_chat():
    launcher_dir = get_launcher_dir()
    default_tdl = launcher_dir
    dlg = StringInputDialog(MAIN_ROOT, 'TDL path', 'Path to TDL:', initialvalue=default_tdl, width=80)
    tdl_path = dlg.result or default_tdl
    if not os.path.exists(tdl_path):
        messagebox.showerror('Error', f'TDL path not found: {tdl_path}')
        return

    dlg2 = StringInputDialog(MAIN_ROOT, 'Media directory', 'Directory to save into:',
                             initialvalue=launcher_dir, width=80)
    media_dir = dlg2.result or launcher_dir
    if not os.path.exists(media_dir):
        messagebox.showerror('Error', f'Media directory not found: {media_dir}')
        return

    while True:
        msg_url = simpledialog.askstring(
            'Message URL',
            'Enter Telegram message URL (https://t.me/c/12345678/123 or https://t.me/username/123):',
            parent=MAIN_ROOT
        )
        if not msg_url:
            return
        msg_url = msg_url.strip()
        if (re.match(r"^https?://t\.me/c/\d+/\d+$", msg_url)
                or re.match(r"^https?://t\.me/c/\d+/\d+/\d+$", msg_url)
                or re.match(r"^https?://t\.me/[A-Za-z0-9_]{5,32}/\d+$", msg_url)):
            break
        messagebox.showwarning('Invalid Format',
                               'Expected https://t.me/username/123 or https://t.me/c/.../123')

    while True:
        dl_limit_dlg = IntegerInputDialog(MAIN_ROOT, 'Task Limit',
                                          'Max concurrent download tasks (1-10) [default 2]:',
                                          initialvalue=2, minvalue=1, maxvalue=10)
        dl_limit = dl_limit_dlg.result
        if dl_limit is None:
            return
        if 1 <= dl_limit <= 10:
            break
    while True:
        threads_dlg = IntegerInputDialog(MAIN_ROOT, 'Threads',
                                          'Max threads per task (1-8) [default 4]:',
                                          initialvalue=4, minvalue=1, maxvalue=8)
        threads = threads_dlg.result
        if threads is None:
            return
        if 1 <= threads <= 8:
            break

    state = {
        'tdl_path': tdl_path,
        'telegramMessageUrl': msg_url,
        'mediaDir': media_dir,
        'downloadLimit': dl_limit,
        'threads': threads,
        'maxRetries': 1
    }
    state_file = os.path.join(get_launcher_dir(), 'tdl_easy_runner.json')
    if not write_state_json(state_file, state):
        return

    wrapper = make_autoyes_wrapper('tdl-easy-full.ps1', 'tdl-easy-full-wrapper.ps1')
    if not wrapper:
        return
    run_powershell_script(wrapper)

# ==============================================================================
# UI construction and language switching
# ==============================================================================

def toggle_close_terminal():
    """
    Callback when checkbox toggled: update global and hint text.
    """
    global CLOSE_TERMINAL
    CLOSE_TERMINAL = WIDGETS['close_var'].get()
    hint_text = MENU_TEXT[LANG]['hint_close'] if CLOSE_TERMINAL else MENU_TEXT[LANG]['hint_no_close']
    WIDGETS['hint'].config(text=hint_text)

def build_widgets():
    """
    Create and grid all widgets inside MAIN_FRAME.
    """
    global WIDGETS

    for w in MAIN_FRAME.winfo_children():
        w.destroy()

    btn_en = tk.Button(MAIN_FRAME, text=MENU_TEXT[LANG]['button_en'], width=4,
                       command=lambda: switch_language('EN'))
    btn_ru = tk.Button(MAIN_FRAME, text=MENU_TEXT[LANG]['button_ru'], width=4,
                       command=lambda: switch_language('RU'))
    btn_en.grid(row=0, column=0, padx=(0,2), sticky='w')
    btn_ru.grid(row=0, column=1, padx=(2,10), sticky='w')

    close_var = tk.BooleanVar(value=CLOSE_TERMINAL)
    chk_close = tk.Checkbutton(MAIN_FRAME,
                               text=MENU_TEXT[LANG]['close_terminal'],
                               variable=close_var,
                               command=toggle_close_terminal)
    chk_close.grid(row=0, column=2, sticky='w')

    lbl_menu = tk.Label(MAIN_FRAME, text=MENU_TEXT[LANG]['menu'],
                        font=('Segoe UI', 14, 'bold'))
    lbl_menu.grid(row=1, column=0, columnspan=3, pady=(8,12), sticky='w')

    btn_update = tk.Button(MAIN_FRAME, text=MENU_TEXT[LANG]['install_update'], width=35,
                           command=install_update_tdl)
    btn_update.grid(row=2, column=0, columnspan=3, pady=4)

    btn_login = tk.Button(MAIN_FRAME, text=MENU_TEXT[LANG]['telegram_login'], width=35,
                          command=login_telegram)
    btn_login.grid(row=3, column=0, columnspan=3, pady=4)

    btn_single = tk.Button(MAIN_FRAME, text=MENU_TEXT[LANG]['download_single'], width=35,
                           command=download_single_file)
    btn_single.grid(row=4, column=0, columnspan=3, pady=4)

    btn_range = tk.Button(MAIN_FRAME, text=MENU_TEXT[LANG]['download_range'], width=35,
                          command=download_range)
    btn_range.grid(row=5, column=0, columnspan=3, pady=4)

    btn_full = tk.Button(MAIN_FRAME, text=MENU_TEXT[LANG]['download_full'], width=35,
                         command=download_full_chat)
    btn_full.grid(row=6, column=0, columnspan=3, pady=4)

    btn_exit = tk.Button(MAIN_FRAME, text=MENU_TEXT[LANG]['exit'], width=35,
                         command=MAIN_ROOT.destroy)
    btn_exit.grid(row=7, column=0, columnspan=3, pady=(12,4))

    hint_text = MENU_TEXT[LANG]['hint_close'] if CLOSE_TERMINAL else MENU_TEXT[LANG]['hint_no_close']
    hint = tk.Label(MAIN_FRAME, text=hint_text, font=('Segoe UI', 8), fg='gray')
    hint.grid(row=8, column=0, columnspan=3, pady=(8,0))

    WIDGETS.update({
        'btn_en': btn_en,
        'btn_ru': btn_ru,
        'chk_close': chk_close,
        'close_var': close_var,
        'lbl_menu': lbl_menu,
        'btn_update': btn_update,
        'btn_login': btn_login,
        'btn_single': btn_single,
        'btn_range': btn_range,
        'btn_full': btn_full,
        'btn_exit': btn_exit,
        'hint': hint,
    })

def switch_language(lang_code):
    """
    Change LANG and rebuild all widget texts.
    """
    global LANG
    if LANG == lang_code:
        return
    LANG = lang_code
    MAIN_ROOT.title(MENU_TEXT[LANG]['title'])
    build_widgets()

def build_ui():
    """
    Initialize the main window and widgets, then start mainloop.
    """
    global MAIN_ROOT, MAIN_FRAME
    MAIN_ROOT = tk.Tk()
    MAIN_ROOT.title(MENU_TEXT[LANG]['title'])
    MAIN_ROOT.resizable(False, False)

    MAIN_FRAME = tk.Frame(MAIN_ROOT, padx=12, pady=12)
    MAIN_FRAME.pack()

    build_widgets()

    MAIN_ROOT.mainloop()

if __name__ == '__main__':
    build_ui()