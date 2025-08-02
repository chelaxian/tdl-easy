# tdl-easy (windows x64 only)

PowerShell script to simplify downloading Telegram media from private groups/channels without a public link. You only need the URL to any message in the private Telegram group/channel. Specify the message index range (например, с 1 до 1000), и скрипт скачает все медиа из этих сообщений.

---

## Getting started

1. download `tdl-updater.ps1` and `tdl-easy.ps1` to your windows x64 PC/laptop
2. run Telegram client, open `cmd.exe` and run `powershell` (or directly open `powershell.exe`)
3. locate in powershell via `cd C:\PATH\TO\YOUR\FOLDER` command to scripts directory  and run `.\tdl-updater.ps1` to download/update `tdl.exe`
4. run `.\tdl-easy.ps1` and follow interactive wizard to set up and start downloading.

---

## Interactive wizard view

```powershell
PS C:\Telegram\tdl> .\tdl-updater.ps1

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

## tdl-easy running status view
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
## tdl-easy updater view

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
