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
- **Profile Detection**: Automatically detects all Zen Browser profiles including regular and twilight builds
- **Profile Selection**: Interactive prompt to select which profile to backup/restore when multiple profiles exist
- **Complete Backup**: Backs up places.sqlite (bookmarks/history), sessionstore.jsonlz4 (tabs), and sessionstore-backups
- **Git Integration**: Uses GitHub repository for secure cloud storage of backups
- **Cross-Platform**: Works on Linux, macOS, and Windows
- **No GPG**: Simplified version without encryption for easier setup

## Requirements
- **Zen Browser** installed on your system
- **Git** installed and configured
- **jq** for JSON processing (install with your package manager)
- **GitHub repository** for storing backups
- **GitHub token** (optional, for automated pushes)

## Quick Start

### 1. Configure Your Repository
```bash
./zen-sync-no-gpg.sh setup
```

### 2. Backup Your Profile
```bash
./zen-sync-no-gpg.sh backup
```

### 3. Restore Your Profile
```bash
./zen-sync-no-gpg.sh restore
```

## Usage Examples

### Backup Process
When running backup, the script will:
1. Detect all Zen Browser profiles
2. Prompt you to select which profile to backup
3. Create a backup of your browsing data
4. Push to your GitHub repository

### Restore Process
When running restore, the script will:
1. Detect all Zen Browser profiles
2. Prompt you to select which profile to restore to
3. Download the latest backup from GitHub
4. Restore your browsing data to the selected profile

## Files Backed Up
- `places.sqlite` - Bookmarks and browsing history
- `places.sqlite-wal` - Write-ahead log for places.sqlite
- `sessionstore.jsonlz4` - Current session state (tabs, windows)
- `sessionstore-backups` - Automatic session backups

## Configuration
The script uses a JSON configuration file (`config.json`) to store:
- GitHub repository URL
- Local repository directory
- Backup preferences

## Troubleshooting
- **No profiles found**: Ensure Zen Browser has been run at least once
- **Permission errors**: Check file permissions on your Zen profile directory
- **Git errors**: Verify your GitHub credentials and repository access
- **Missing jq**: Install jq using your system's package manager
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

## Windows PowerShell Usage
For Windows users, use the PowerShell script provided:

### Basic Usage
```powershell
# Run setup
.\zen-sync-no-gpg.ps1 setup

# Backup your profile
.\zen-sync-no-gpg.ps1 backup

# Restore your profile
.\zen-sync-no-gpg.ps1 restore
```

### Windows-Specific Paths
- **Regular Zen**: `%APPDATA%/zen/`
- **Twilight Zen**: `%APPDATA%/zen/profiles/`
- **Configuration**: `%USERPROFILE%/zen_sync_config.json`

### Windows Troubleshooting
- **Execution Policy**: Run `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`
- **PowerShell not found**: Use Windows PowerShell or PowerShell Core
- **Git not found**: Install Git for Windows from git-scm.com
- **jq not found**: Install using `winget install jqlang.jq` or download from stedolan.github.io/jq/
- **No profiles found**: Ensure Zen Browser has been run at least once

## Linux-Specific Paths
- **Regular Zen**: `~/.var/app/app.zen_browser.zen/.zen/`
- **Twilight Zen**: `~/.zen/profiles/`
- **Configuration**: `~/.zen_sync_config.json`

- **"Permission denied"**: Run `chmod +x zen-sync-no-gpg.sh`
- **"jq not found"**: Install with `sudo apt install jq`
- **"Git not found"**: Install with `sudo apt install git`
- **"tar not found"**: Install with `sudo apt install tar`
- **"No profiles found"**: Ensure Zen Browser has been run at least once

## Troubleshooting
- **Common Issues**: Check the troubleshooting section for solutions to common problems
- **Support**: Contact the developer for further assistance
