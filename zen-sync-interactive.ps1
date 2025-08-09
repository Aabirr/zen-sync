#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# === CONFIG ===
$HomeDir = [Environment]::GetFolderPath('UserProfile')
$ConfigFile = Join-Path $HomeDir '.zen_sync_config.json'
$PassFile = Join-Path $HomeDir '.zen_sync_pass'
$Files = @('places.sqlite','places.sqlite-shm','places.sqlite-wal','sessionstore.jsonlz4')
$SessionDir = 'sessionbackups'
$SessionArchive = "$SessionDir.tar.gz.gpg"
$SessionStoreBackupsDir = 'sessionstore-backups'
$SessionStoreBackupsArchive = "$SessionStoreBackupsDir.tar.gz.gpg"

# === GITHUB AUTH & REPO MANAGEMENT ===
function Test-GitHubCLI {
    try {
        $null = Get-Command gh -ErrorAction Stop
        $status = & gh auth status 2>&1
        return $status -match "Logged in"
    }
    catch { return $false }
}

function Initialize-GitHubAuth {
    Write-Host "🔐 GitHub Authentication Required" -ForegroundColor Yellow
    
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-Host "❌ GitHub CLI (gh) not found. Please install it from: https://cli.github.com/" -ForegroundColor Red
        Write-Host "After installation, restart PowerShell and run this script again." -ForegroundColor Red
        exit 1
    }
    
    if (-not (Test-GitHubCLI)) {
        Write-Host "Please log in to GitHub..." -ForegroundColor Cyan
        & gh auth login
        if ($LASTEXITCODE -ne 0) {
            Write-Host "❌ GitHub authentication failed" -ForegroundColor Red
            exit 1
        }
    }
    
    Write-Host "✅ GitHub authentication successful" -ForegroundColor Green
}

function Get-BackupRepo {
    param([string]$Action)
    
    Write-Host "`n📁 Select Backup Repository for $Action" -ForegroundColor Yellow
    
    # List user's repos
    $repos = & gh repo list --json name,isPrivate,url | ConvertFrom-Json
    if ($repos.Count -eq 0) {
        Write-Host "No repositories found. Let's create one..." -ForegroundColor Cyan
        return New-BackupRepo
    }
    
    Write-Host "Available repositories:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $repos.Count; $i++) {
        $privacy = if ($repos[$i].isPrivate) { "🔒 Private" } else { "🌐 Public" }
        Write-Host "  [$($i+1)] $($repos[$i].name) - $privacy"
    }
    Write-Host "  [0] Create new repository"
    
    do {
        $choice = Read-Host "`nEnter choice (0-$($repos.Count))"
        $choiceNum = [int]$choice
    } while ($choiceNum -lt 0 -or $choiceNum -gt $repos.Count)
    
    if ($choiceNum -eq 0) {
        return New-BackupRepo
    } else {
        return $repos[$choiceNum - 1].name
    }
}

function New-BackupRepo {
    $repoName = Read-Host "Enter name for new backup repository (e.g., 'zen-browser-backup')"
    $isPrivate = (Read-Host "Make repository private? (y/N)").ToLower() -eq 'y'
    
    $visibility = if ($isPrivate) { "--private" } else { "--public" }
    
    Write-Host "Creating repository '$repoName'..." -ForegroundColor Cyan
    & gh repo create $repoName $visibility --description "Zen Browser Profile Backup"
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Failed to create repository" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "✅ Repository '$repoName' created successfully" -ForegroundColor Green
    return $repoName
}

function Save-Config {
    param([string]$RepoName)
    
    $config = @{
        repository = $repoName
        lastBackup = $null
        lastRestore = $null
    } | ConvertTo-Json -Depth 2
    
    Set-Content -Path $ConfigFile -Value $config -Encoding UTF8
    Write-Host "✅ Configuration saved" -ForegroundColor Green
}

function Get-Config {
    if (Test-Path $ConfigFile) {
        return Get-Content -Path $ConfigFile -Raw | ConvertFrom-Json
    }
    return $null
}

# === ZEN BROWSER PROFILE DETECTION ===
function Get-ZenProfilePath {
    $appData = $env:APPDATA
    $zenBase = Join-Path $appData 'Zen'
    $iniPath = Join-Path $zenBase 'profiles.ini'
    
    if (-not (Test-Path $iniPath)) { 
        throw "❌ Zen Browser profiles.ini not found at: $iniPath`nMake sure Zen Browser is installed and has been run at least once." 
    }

    $ini = Get-Content -Raw -LiteralPath $iniPath -Encoding UTF8
    $isRelative = $false
    $pathLine = ($ini -split "`n") | Where-Object { $_ -match '^IsRelative=' } | Select-Object -First 1
    if ($pathLine) { $isRelative = ($pathLine -split '=',2)[1].Trim() -eq '1' }
    $profileLine = ($ini -split "`n") | Where-Object { $_ -match '^Path=' } | Select-Object -First 1
    if (-not $profileLine) { throw '❌ No Path= entry found in profiles.ini' }
    $profilePath = ($profileLine -split '=',2)[1].Trim()

    if ($isRelative) { return (Join-Path $zenBase $profilePath) }
    else { return $profilePath }
}

# === UTILITY FUNCTIONS ===
function Ensure-Directory([string]$Path) { 
    if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path | Out-Null } 
}

function Test-Prerequisites {
    # Check GPG
    if (-not (Get-Command gpg -ErrorAction SilentlyContinue)) {
        Write-Host "❌ GPG not found. Please install Gpg4win from: https://www.gpg4win.org/" -ForegroundColor Red
        exit 1
    }
    
    # Check Git
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Host "❌ Git not found. Please install Git from: https://git-scm.com/" -ForegroundColor Red
        exit 1
    }
    
    # Check passphrase file
    if (-not (Test-Path $PassFile)) {
        Write-Host "❌ Passphrase file not found: $PassFile" -ForegroundColor Red
        Write-Host "Please create this file with your encryption passphrase (one line, plain text)" -ForegroundColor Yellow
        exit 1
    }
}

function Invoke-GpgEncrypt([string]$src, [string]$dst) {
    $args = @('--batch','--yes','--passphrase-file', $PassFile, '-o', $dst, '-c', $src)
    $p = Start-Process -FilePath 'gpg' -ArgumentList $args -NoNewWindow -Wait -PassThru
    if ($p.ExitCode -ne 0) { throw "❌ GPG encryption failed for $src" }
}

function Invoke-GpgDecrypt([string]$src, [string]$dst) {
    $args = @('--batch','--yes','--passphrase-file', $PassFile, '-o', $dst, '-d', $src)
    $p = Start-Process -FilePath 'gpg' -ArgumentList $args -NoNewWindow -Wait -PassThru
    if ($p.ExitCode -ne 0) { throw "❌ GPG decryption failed for $src" }
}

# === BACKUP FUNCTION ===
function Invoke-Backup {
    Write-Host "🔄 Starting Zen Browser Backup..." -ForegroundColor Cyan
    
    Test-Prerequisites
    Initialize-GitHubAuth
    
    $config = Get-Config
    if (-not $config) {
        $repoName = Get-BackupRepo "Backup"
        Save-Config -RepoName $repoName
        $config = Get-Config
    }
    
    $fullPath = Get-ZenProfilePath
    Write-Host "📂 Zen Profile: $fullPath" -ForegroundColor Gray
    
    # Create temporary directory for backup
    $tempDir = Join-Path $env:TEMP "zen-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    New-Item -ItemType Directory -Path $tempDir | Out-Null
    
    try {
        # Clone or update repo
        $repoDir = Join-Path $tempDir $config.repository
        Write-Host "📥 Cloning backup repository..." -ForegroundColor Cyan
        & gh repo clone $config.repository $repoDir
        if ($LASTEXITCODE -ne 0) { throw "Failed to clone repository" }
        
        Push-Location $repoDir
        
        $changed = $false
        
        # Backup individual files
        foreach ($file in $Files) {
            $src = Join-Path $fullPath $file
            $dst = Join-Path $repoDir "$file.gpg"
            
            if (Test-Path $src) {
                Write-Host "🔐 Encrypting $file..." -ForegroundColor Yellow
                Invoke-GpgEncrypt -src $src -dst $dst
                $changed = $true
            } else {
                Write-Host "⚠️  File not found: $file" -ForegroundColor Yellow
            }
        }
        
        # Backup folders
        foreach ($folder in @($SessionDir, $SessionStoreBackupsDir)) {
            $srcFolder = Join-Path $fullPath $folder
            if (Test-Path $srcFolder) {
                Write-Host "📦 Archiving $folder..." -ForegroundColor Yellow
                $tarFile = "$folder.tar.gz"
                $encFile = "$folder.tar.gz.gpg"
                
                & tar -czf $tarFile -C $fullPath $folder
                if ($LASTEXITCODE -eq 0) {
                    Invoke-GpgEncrypt -src $tarFile -dst $encFile
                    Remove-Item $tarFile -Force
                    $changed = $true
                }
            }
        }
        
        if ($changed) {
            Write-Host "📤 Pushing to GitHub..." -ForegroundColor Cyan
            & git add .
            & git commit -m "Zen Browser backup - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            & git push
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "✅ Backup completed successfully!" -ForegroundColor Green
                $config.lastBackup = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                Save-Config -RepoName $config.repository
            } else {
                throw "Failed to push to GitHub"
            }
        } else {
            Write-Host "ℹ️  No files found to backup" -ForegroundColor Yellow
        }
        
    } finally {
        Pop-Location
        Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
    }
}

# === RESTORE FUNCTION ===
function Invoke-Restore {
    Write-Host "🔄 Starting Zen Browser Restore..." -ForegroundColor Cyan
    
    Test-Prerequisites
    Initialize-GitHubAuth
    
    $config = Get-Config
    if (-not $config) {
        $repoName = Get-BackupRepo "Restore"
        Save-Config -RepoName $repoName
        $config = Get-Config
    }
    
    $fullPath = Get-ZenProfilePath
    Write-Host "📂 Zen Profile: $fullPath" -ForegroundColor Gray
    
    # Create temporary directory for restore
    $tempDir = Join-Path $env:TEMP "zen-restore-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    New-Item -ItemType Directory -Path $tempDir | Out-Null
    
    try {
        # Clone repo
        $repoDir = Join-Path $tempDir $config.repository
        Write-Host "📥 Cloning backup repository..." -ForegroundColor Cyan
        & gh repo clone $config.repository $repoDir
        if ($LASTEXITCODE -ne 0) { throw "Failed to clone repository" }
        
        # Restore individual files
        foreach ($file in $Files) {
            $src = Join-Path $repoDir "$file.gpg"
            $dst = Join-Path $fullPath $file
            
            if (Test-Path $src) {
                Write-Host "🔓 Restoring $file..." -ForegroundColor Yellow
                
                # Backup existing file
                if (Test-Path $dst) {
                    $bakFile = "$dst.bak"
                    Write-Host "💾 Backing up existing $file to $(Split-Path $bakFile -Leaf)" -ForegroundColor Gray
                    Move-Item -Path $dst -Destination $bakFile -Force
                }
                
                Invoke-GpgDecrypt -src $src -dst $dst
            } else {
                Write-Host "⚠️  Backup not found: $file.gpg" -ForegroundColor Yellow
            }
        }
        
        # Restore folders
        foreach ($folder in @($SessionDir, $SessionStoreBackupsDir)) {
            $src = Join-Path $repoDir "$folder.tar.gz.gpg"
            $dstFolder = Join-Path $fullPath $folder
            
            if (Test-Path $src) {
                Write-Host "📦 Restoring $folder..." -ForegroundColor Yellow
                
                # Backup existing folder
                if (Test-Path $dstFolder) {
                    $bakFolder = "$dstFolder.bak"
                    Write-Host "💾 Backing up existing $folder to $(Split-Path $bakFolder -Leaf)" -ForegroundColor Gray
                    if (Test-Path $bakFolder) { Remove-Item -Recurse -Force $bakFolder }
                    Move-Item -Path $dstFolder -Destination $bakFolder
                }
                
                $tarFile = Join-Path $tempDir "$folder.tar.gz"
                Invoke-GpgDecrypt -src $src -dst $tarFile
                & tar -xzf $tarFile -C $fullPath
                Remove-Item $tarFile -Force
            } else {
                Write-Host "⚠️  Backup not found: $folder.tar.gz.gpg" -ForegroundColor Yellow
            }
        }
        
        Write-Host "✅ Restore completed successfully!" -ForegroundColor Green
        $config.lastRestore = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Save-Config -RepoName $config.repository
        
    } finally {
        Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
    }
}

# === MAIN ===
if ($args.Count -eq 0) {
    Write-Host "Zen Browser Profile Backup & Restore" -ForegroundColor Cyan
    Write-Host "Usage: zen-sync-interactive.ps1 {backup|restore}" -ForegroundColor Yellow
    exit 1
}

switch ($args[0]) {
    'backup'  { Invoke-Backup }
    'restore' { Invoke-Restore }
    default {
        Write-Host "Usage: zen-sync-interactive.ps1 {backup|restore}" -ForegroundColor Yellow
        exit 1
    }
}
