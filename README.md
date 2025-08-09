# zen-sync
This script syncs zen browsers sidebar settings, tabs, and tab folders

## Table of Contents
- [Introduction](#introduction)
- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
- [Usage](#usage)
- [Configuration](#configuration)
- [Backup and Restore](#backup-and-restore)
- [Troubleshooting](#troubleshooting)

## Introduction
Zen Browser backup solution is a comprehensive tool designed to safeguard your browsing experience by backing up your Zen Browser settings, tabs, and tab folders. This solution ensures that your browsing data is secure and easily recoverable in case of data loss or browser reset.

## Features
- **Settings Backup**: Backup your Zen Browser settings, including bookmarks, extensions, and preferences.
- **Tab and Tab Folder Backup**: Backup your open tabs and tab folders, ensuring that you can quickly restore your browsing session.
- **Automatic Backup**: Schedule automatic backups to ensure that your data is regularly saved.
- **Manual Backup**: Perform manual backups at any time for added flexibility.

## Requirements
- **Zen Browser** installed on your system
- **Git** installed: `sudo apt install git` (Ubuntu/Debian) or `brew install git` (macOS)
- **tar** installed: Usually pre-installed on Linux/macOS
- **jq** installed: `sudo apt install jq` (Ubuntu/Debian) or `brew install jq` (macOS)

## Installation
1. **Install dependencies** (without sudo):
   ```bash
   # Ubuntu/Debian
   sudo apt update && sudo apt install git jq tar

   # Arch Linux
   sudo pacman -S git jq tar

   # Fedora
   sudo dnf install git jq tar
   ```

2. **Clone the repository**:
   ```bash
   git clone git@github.com:Aabirr/zen-sync.git
   cd zen-sync
   ```

3. **Make scripts executable**:
   ```bash
   chmod +x zen-sync-no-gpg.sh
   ```

## Usage on Linux

### First Time Setup
1. **Create GitHub repository** (if not exists):
   - Go to [GitHub](https://github.com/new)
   - Create private repository named `zen-sync`
   - Use SSH: `git@github.com:Aabirr/zen-sync.git`

2. **Run backup** (no sudo needed):
   ```bash
   ./zen-sync-no-gpg.sh backup
   ```

### Important Notes:
- **Never use sudo** with the backup script - it runs as your user
- **Install dependencies first** with sudo, then run script normally
- **Run from your home directory** or wherever you cloned the repo

### Fix Permission Denied:
```bash
# 1. Make sure you're in the correct directory
cd ~/zen-sync  # or wherever you cloned it

# 2. Fix file permissions
chmod +x zen-sync-no-gpg.sh
chmod +x zen-sync.sh

# 3. Verify permissions
ls -la zen-sync-no-gpg.sh
# Should show: -rwxr-xr-x

# 4. Run the script
./zen-sync-no-gpg.sh backup

# If still permission denied, check directory permissions:
ls -ld ~/zen-sync
# Should show: drwxr-xr-x

# If directory is wrong, fix it:
chmod 755 ~/zen-sync
```

3. **Select profile** when prompted:
   ```
   Found 2 Zen Browser profiles:
     [1] Regular
         /home/user/.var/app/app.zen_browser.zen/.zen/xxxxxxxx.default-release
     [2] Twilight (Default)
         /home/user/.zen/profiles/abc123.Default
   Select profile (1-2): 1
   ```

### Regular Usage
```bash
# Backup current profile
./zen-sync-no-gpg.sh backup

# Restore from backup
./zen-sync-no-gpg.sh restore

# Check last backup/restore
./zen-sync-no-gpg.sh backup  # Shows last backup time
./zen-sync-no-gpg.sh restore  # Shows last restore time
```

## Linux-Specific Paths
- **Regular Zen**: `~/.var/app/app.zen_browser.zen/.zen/`
- **Twilight Zen**: `~/.zen/profiles/`
- **Configuration**: `~/.zen_sync_config.json`

## Troubleshooting on Linux
- **"Permission denied"**: Run `chmod +x zen-sync-no-gpg.sh`
- **"jq not found"**: Install with `sudo apt install jq`
- **"Git not found"**: Install with `sudo apt install git`
- **"tar not found"**: Install with `sudo apt install tar`
- **"No profiles found"**: Ensure Zen Browser has been run at least once

## Troubleshooting
- **Common Issues**: Check the troubleshooting section for solutions to common problems
- **Support**: Contact the developer for further assistance
