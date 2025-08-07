# tdl-easy (windows x64 only)

Portable GUI and PowerShell scripts to simplify downloading Telegram media from public/private groups/channels even without a public link. You only need the URL to any message in the private Telegram group/channel. Specify the message index range (for ex., from 1 to 1000), and script will download all media from this messages. Also you can copy-paste only 1 URL to any message in chat and script will download one or all media in that chat.

---

## Getting started

0. Just go to [Release page](https://github.com/chelaxian/tdl-easy/releases/latest) and downlod and run `tdl_gui.exe`
   
<img width="218" height="266" alt="image" src="https://github.com/user-attachments/assets/a08917ec-52c8-4842-b0d3-d8e3fce616fd" />



or if you want use powershell in console: 

1. download this project to your windows x64 PC/laptop
2. run Telegram client, open `cmd.exe` and run `powershell` (or directly open `powershell.exe`)
3. locate in powershell via `cd C:\PATH\TO\YOUR\FOLDER` command to scripts directory  and run `.\tdl-updater.ps1` to download/update `tdl.exe`
4. run `.\tdl.exe login` and choose your Telegram ID and say `No` when asking about logout.
5. run `.\tdl-easy-range.ps1` or `.\tdl-easy-full.ps1` or `.\tdl-easy-single.ps1` and follow interactive wizard to set up and start downloading.

---
## Source code usage:

<details>
   <summary>spoiler</summary>
   
## Compile GUI

If you want to compile GUI version from source copy file `GUI\tdl_gui.py` to other `ps1` scripts and use powershell command:
```python
pip install --upgrade pyinstaller
pyinstaller --onefile --noconsole `
  --hidden-import=tkinter `
  --hidden-import=tkinter.simpledialog `
  --hidden-import=tkinter.messagebox `
  --hidden-import=tkinter.filedialog `
  --add-data "tdl-updater.ps1;." `
  --add-data "tdl-easy-single.ps1;." `
  --add-data "tdl-easy-range.ps1;." `
  --add-data "tdl-easy-full.ps1;." `
  GUI/tdl_gui.py
```
---

## Interactive `tdl-easy-range.ps1` wizard view

```powershell
PS C:\Users\admin\Desktop\tdl> .\tdl-easy-range.ps1

╔════════════════════ TDL PATH CONFIGURATION ════════════════════════════════╗
║ Default: C:\Users\admin\Desktop\tdl
╠────────────────────────────────────────────────────────────────────────────╣
Enter the TDL path (e.g., D:\tdl, no trailing slash)
C:\Users\admin\Desktop\tdl
╚════════════════════════════════════════════════════════════════════════════╝

╔══════════════════ MEDIA DIRECTORY CONFIGURATION ═══════════════════════════╗
║ Default: C:\Users\admin\Desktop\tdl
╠────────────────────────────────────────────────────────────────────────────╣
Enter the directory for saving media files (e.g., D:\tdl\videos)
C:\Users\admin\Desktop\tdl\videos
╚════════════════════════════════════════════════════════════════════════════╝

╔════════════════════ TELEGRAM URL CONFIGURATION ════════════════════════════╗
║ Example: https://t.me/c/12345678/ (only this format is accepted)
╠────────────────────────────────────────────────────────────────────────────╣
Copy-Paste group/channel any message base URL without message index in the end
https://t.me/c/1234567890/
╚════════════════════════════════════════════════════════════════════════════╝

╔══════════════════ INDEX RANGE CONFIGURATION ═══════════════════════════════╗
║ Defaults: startId=1, endId=100 (endId forced >= startId)
╠────────────────────────────────────────────────────────────────────────────╣
Enter the starting message index (positive integer) [default: 1]
100
Enter the ending message index (must be >= 100) [default: 100]
500
╚════════════════════════════════════════════════════════════════════════════╝

╔════════════════ CONCURRENCY CONFIGURATION ═════════════════════════════════╗
║ Defaults: downloadLimit=2, threads=4
╠────────────────────────────────────────────────────────────────────────────╣
Enter max concurrent download tasks (-l, 1 to 10) [default: 2]
3
Enter max threads per task (-t, 1 to 8) [default: 4]
6
╚════════════════════════════════════════════════════════════════════════════╝
```
---
## Interactive `tdl-easy-full.ps1` wizard view

```powershell
PS C:\Users\admin\Desktop\tdl> .\tdl-easy-full.ps1

Type (Yes) to use saved parameters or type (No) to clean them and start new job: No

╔════════════════════ TDL PATH CONFIGURATION ════════════════════════════════╗
║ Default: C:\Users\admin\Desktop\tdl
╠────────────────────────────────────────────────────────────────────────────╣
Enter the TDL path (e.g., D:\tdl, no trailing slash)

╚════════════════════════════════════════════════════════════════════════════╝

╔══════════════════ MEDIA DIRECTORY CONFIGURATION ═══════════════════════════╗
║ Default: C:\Users\admin\Desktop\tdl
╠────────────────────────────────────────────────────────────────────────────╣
Enter the directory for saving media files (e.g., D:\tdl\videos)
C:\Users\admin\Desktop\tdl\Photos
╚════════════════════════════════════════════════════════════════════════════╝

╔════════════════════ TELEGRAM MESSAGE URL CONFIGURATION ════════════════════╗
║ Example: https://t.me/c/12345678/123 (any message from the chat)
╠────────────────────────────────────────────────────────────────────────────╣
Copy-Paste any message URL from the group/channel
https://t.me/c/1234567890/101
╚════════════════════════════════════════════════════════════════════════════╝

╔════════════════ CONCURRENCY CONFIGURATION ═════════════════════════════════╗
║ Defaults: downloadLimit=2, threads=4, maxRetries=1
╠────────────────────────────────────────────────────────────────────────────╣
Enter max concurrent download tasks (-l, 1 to 10) [default: 2]
4
Enter max threads per task (-t, 1 to 8) [default: 4]
8
Enter max retries for failed downloads (1 to 5) [default: 1]
1
╚════════════════════════════════════════════════════════════════════════════╝
```
---
## tdl-easy-range running status view
```powershell
ℹ️ Using PowerShell version: 5.1.27695.1000
📜 Loaded 1 processed indexes from C:\Users\admin\Desktop\tdl\processed.txt
📂 Found 2 fully downloaded indexes from files in C:\Users\admin\Desktop\tdl\videos
⏭️ Skipped index: 101 (processed or fully downloaded)
⏭️ Skipped index: 102 (processed or fully downloaded)
📋 Debug: Batch contains 3 URLs
🟡 Starting download for indexes: 103,104,105
📋 Command: .\tdl.exe download --desc --dir "C:\Users\admin\Desktop\tdl\videos" --url "https://t.me/c/1234567890/103" --url "https://t.me/c/1234567890/104" --url "https://t.me/c/1234567890/105" -l 3 -t 6
All files will be downloaded to 'C:\Users\admin\Desktop\tdl\videos' dir
Example Telegram Channel(1234567890):103 ~ ... done! [417.40 MB in 3m52.628s; 1.79 MB/s]
Example Telegram Channel(1234567890):104 ~ ... done! [586.61 MB in 5m9.747s; 1.89 MB/s]
Example Telegram Channel(1234567890):105 ~ ... done! [694.96 MB in 5m17.31s; 2.19 MB/s]
🟢 Successfully downloaded: 103,104,105
✅ Downloaded 1234567890_103_Example Telegram Channel 103.mp4
✅ Downloaded 1234567890_104_Example Telegram Channel 104.mp4
✅ Downloaded 1234567890_105_Example Telegram Channel 105.mp4
📋 Debug: Batch contains 3 URLs
🟡 Starting download for indexes: 106,107,108
📋 Command: .\tdl.exe download --desc --dir "C:\Users\admin\Desktop\tdl\videos" --url "https://t.me/c/1234567890/106" --url "https://t.me/c/1234567890/107" --url "https://t.me/c/1234567890/108" -l 3 -t 6
All files will be downloaded to 'C:\Users\admin\Desktop\tdl\videos' dir
Example Telegram Channel(1234567890):103 ~ ... done! [417.40 MB in 3m52.628s; 1.79 MB/s]
Example Telegram Channel(1234567890):104 ~ ... done! [586.61 MB in 5m9.747s; 1.89 MB/s]
Example Telegram Channel(1234567890):105 ~ ... done! [694.96 MB in 5m17.31s; 2.19 MB/s]
🟢 Successfully downloaded: 103,104,105
✅ Downloaded 1234567890_103_Example Telegram Channel 106.mp4
✅ Downloaded 1234567890_104_Example Telegram Channel 107.mp4
✅ Downloaded 1234567890_105_Example Telegram Channel 108.mp4
```
---
## tdl-easy-full running status view
```powershell
ℹ️ Using PowerShell version: 5.1.27695.1000
📂 Found 0 fully downloaded indexes from files in C:\Users\admin\Desktop\tdl\Photos
🟡 Starting export for chat ID: 1234567890
📋 Export Command: .\tdl.exe chat export -c 1234567890 --with-content -o "C:\Users\admin\Desktop\tdl\Photos\tdl-export.json"
WARN: Export only generates minimal JSON for tdl download, not for backup.
Occasional suspensions are due to Telegram rate limitations, please wait a moment.
Type: time | Input: [0 9223372036854775807]
TEST_Photos-1234567890     ... done! [79 in 934ms; 78/s]
🟢 Successfully exported messages to C:\Users\admin\Desktop\tdl\Photos\tdl-export.json
🟡 Starting download attempt 1 of 1
📋 Download Command: .\tdl.exe download --file "C:\Users\admin\Desktop\tdl\Photos\tdl-export.json" --dir "C:\Users\admin\Desktop\tdl\Photos" -l 4 -t 8 --skip-same
All files will be downloaded to 'C:\Users\admin\Desktop\tdl\Photos' dir
TEST_Photos(1234567890):4~ ... done! [130.12 KB in 619ms; 187.88 KB/s]
TEST_Photos(1234567890):2~ ... done! [3.53 MB in 1.035s; 3.25 MB/s]
TEST_Photos(1234567890):1~ ... done! [112.85 KB in 667ms; 150.47 KB/s]
TEST_Photos(1234567890):1~ ... done! [789.17 KB in 354ms; 1.76 MB/s]
TEST_Photos(1234567890):1~ ... done! [130.74 KB in 326ms; 375.40 KB/s]
TEST_Photos(1234567890):1~ ... done! [114.24 KB in 277ms; 349.82 KB/s]
TEST_Photos(1234567890):1~ ... done! [37.38 KB in 376ms; 80.88 KB/s]
TEST_Photos(1234567890):2~ ... done! [3.68 MB in 746ms; 4.92 MB/s]
TEST_Photos(1234567890):2~ ... done! [2.44 MB in 1.29s; 1.87 MB/s]
✅ Downloaded 1234567890_100_4.mp4 for index 100
✅ Downloaded 1234567890_101_2.mp4 for index 101
✅ Downloaded 1234567890_102_1.mp4 for index 102
✅ Downloaded 1234567890_15_1.jpg for index 15
✅ Downloaded 1234567890_16_1.mp4 for index 16
✅ Downloaded 1234567890_17_1.jpg for index 17
✅ Downloaded 1234567890_18_1.jpg for index 18
✅ Downloaded 1234567890_19_2.jpg for index 19
✅ Downloaded 1234567890_20_2.mp4 for index 20
🟢 Successfully downloaded indexes: 100,101,102,15,16,17,18,19,20
🗑️ File C:\Users\admin\Desktop\tdl\Photos\tdl-export.json deleted after completion.
🗑️ File C:\Users\admin\Desktop\tdl\Photos\processed.txt deleted after completion.
🎉 Completed! All indexes processed.
```
---
## tdl-easy-range updater view

```powershell
PS C:\Users\admin\Desktop\tdl> .\tdl_updater.ps1
Current version: v0.19.0
Latest version: v0.19.1
tdl.exe not found in C:\Users\admin\Desktop\tdl. Will download/install latest version.
A newer version (v0.19.1) is available. Updating now...
Downloading update for version v0.19.1...
Extracting update...
Replacing files in current directory...
Cleaning up temporary files...
Update to version v0.19.1 completed successfully!
Update check completed.

PS C:\Users\admin\Desktop\tdl> .\tdl_updater.ps1
Current version: v0.19.1
Latest version: v0.19.1
Version is up-to-date and tdl.exe exists.
Update check completed.
```

</details>
