#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# === CONFIG ===
$HomeDir = [Environment]::GetFolderPath('UserProfile')
$ConfigFile = Join-Path $HomeDir '.zen_sync_config.json'
$Files = @('places.sqlite','places.sqlite-shm','places.sqlite-wal','sessionstore.jsonlz4')
$SessionDir = 'sessionbackups'
$SessionStoreBackupsDir = 'sessionstore-backups'

# === CONFIGURATION MANAGEMENT ===
function Get-Config {
    if (Test-Path $ConfigFile) {
        return Get-Content -Path $ConfigFile -Raw | ConvertFrom-Json
    }
    return $null
}

function Save-Config {
    param([string]$RepoUrl, [string]$RepoDir)
    
    $config = @{
        repositoryUrl = $RepoUrl
        repositoryDir = $RepoDir
        lastBackup = $null
        lastRestore = $null
    } | ConvertTo-Json -Depth 2
    
    Set-Content -Path $ConfigFile -Value $config -Encoding UTF8
    Write-Host "Configuration saved" -ForegroundColor Green
}

function Initialize-Repository {
    param([string]$Action)
    
    Write-Host "Repository Setup for $Action" -ForegroundColor Yellow
    Write-Host "You need to provide a Git repository URL for your backups." -ForegroundColor Cyan
    Write-Host "Examples:" -ForegroundColor Gray
    Write-Host "  SSH: git@github.com:username/zen-browser-backup.git" -ForegroundColor Gray
    Write-Host "  HTTPS: https://github.com/username/zen-browser-backup.git" -ForegroundColor Gray
    
    do {
        $repoUrl = Read-Host "Enter your backup repository URL"
        if ([string]::IsNullOrWhiteSpace($repoUrl)) {
            Write-Host "Repository URL cannot be empty" -ForegroundColor Red
            continue
        }
        
        # Validate URL format
        if ($repoUrl -notmatch '^(https://|git@).*\.git$') {
            Write-Host "Invalid repository URL format" -ForegroundColor Red
            continue
        }
        
        break
    } while ($true)
    
    # Extract repo name for local directory
    $repoName = [System.IO.Path]::GetFileNameWithoutExtension(($repoUrl -split '/')[-1])
    $repoDir = Join-Path $env:TEMP "zen-backup-$repoName"
    
    Save-Config -RepoUrl $repoUrl -RepoDir $repoDir
    return @{ Url = $repoUrl; Dir = $repoDir }
}

# === ZEN BROWSER PROFILE DETECTION ===
function Get-ZenProfilePaths {
    $profiles = @()
    
    # Check for regular Zen Browser profiles
    $appData = $env:APPDATA
    $zenBase = Join-Path $appData 'Zen'
    $iniPath = Join-Path $zenBase 'profiles.ini'
    
    if (Test-Path $iniPath) {
        $ini = Get-Content -Raw -LiteralPath $iniPath -Encoding UTF8
        $isRelative = $false
        $pathLine = ($ini -split "`n") | Where-Object { $_ -match '^IsRelative=' } | Select-Object -First 1
        if ($pathLine) { $isRelative = ($pathLine -split '=',2)[1].Trim() -eq '1' }
        $profileLine = ($ini -split "`n") | Where-Object { $_ -match '^Path=' } | Select-Object -First 1
        if ($profileLine) {
            $profilePath = ($profileLine -split '=',2)[1].Trim()
            if ($isRelative) { 
                $profiles += @{ Name = "Regular"; Path = (Join-Path $zenBase $profilePath) }
            } else { 
                $profiles += @{ Name = "Regular"; Path = $profilePath }
            }
        }
    }
    
    # Check for Twilight Zen Browser profiles
    $twilightProfilesPath = Join-Path $appData 'zen\Profiles'
    if (Test-Path $twilightProfilesPath) {
        Get-ChildItem -Path $twilightProfilesPath -Directory | ForEach-Object {
            $profiles += @{ Name = "Twilight ($($_.Name))"; Path = $_.FullName }
        }
    }
    
    if ($profiles.Count -eq 0) {
        throw "No Zen Browser profiles found. Make sure Zen Browser is installed and has been run at least once."
    }
    
    return $profiles
}

function Select-Profile {
    $profiles = Get-ZenProfilePaths
    
    if ($profiles.Count -eq 1) {
        Write-Host "Found 1 profile: $($profiles[0].Name)" -ForegroundColor Green
        return $profiles[0].Path
    }
    
    Write-Host "Found $($profiles.Count) Zen Browser profiles:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $profiles.Count; $i++) {
        Write-Host "  [$($i + 1)] $($profiles[$i].Name)" -ForegroundColor Yellow
        Write-Host "      $($profiles[$i].Path)" -ForegroundColor Gray
    }
    
    do {
        $selection = Read-Host "Select profile (1-$($profiles.Count))"
        if ($selection -match '^\d+$' -and [int]$selection -ge 1 -and [int]$selection -le $profiles.Count) {
            return $profiles[[int]$selection - 1].Path
        }
        Write-Host "Invalid selection. Please enter a number between 1 and $($profiles.Count)." -ForegroundColor Red
    } while ($true)
}

# === UTILITY FUNCTIONS ===
function Test-Prerequisites {
    # Check Git
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Host "Git not found. Please install Git from: https://git-scm.com/" -ForegroundColor Red
        exit 1
    }
}

# === BACKUP FUNCTION ===
function Invoke-Backup {
    Write-Host "Starting Zen Browser Backup..." -ForegroundColor Cyan
    
    Test-Prerequisites
    
    $config = Get-Config
    if (-not $config) {
        Initialize-Repository "Backup" | Out-Null
        $config = Get-Config
    }
    
    $fullPath = Select-Profile
    Write-Host "Selected Zen Profile: $fullPath" -ForegroundColor Green
    
    # Clean up any existing repo directory
    if (Test-Path $config.repositoryDir) {
        Remove-Item -Recurse -Force $config.repositoryDir
    }
    
    try {
        # Clone or create repository
        Write-Host "Setting up repository..." -ForegroundColor Cyan
        
        # Try to clone first (repo exists)
        & git clone $config.repositoryUrl $config.repositoryDir 2>$null
        
        if ($LASTEXITCODE -ne 0) {
            # Repo doesn't exist or clone failed, initialize new
            New-Item -ItemType Directory -Path $config.repositoryDir -Force | Out-Null
            Push-Location $config.repositoryDir
            
            try {
                & git init
                & git remote add origin $config.repositoryUrl
                
                # Create initial commit
                "# Zen Browser Backups" | Out-File -FilePath "README.md" -Encoding UTF8
                & git add README.md
                & git commit -m "Initial commit"
                
                # Push to set up remote
                & git push -u origin master 2>$null
                if ($LASTEXITCODE -ne 0) {
                    & git push -u origin main 2>$null
                }
            } catch {
                throw "Failed to initialize repository: $_"
            } finally {
                Pop-Location
            }
        }
        
        Push-Location $config.repositoryDir
        
        $changed = $false
        
        # Backup individual files
        foreach ($file in $Files) {
            $src = Join-Path $fullPath $file
            $dst = Join-Path $config.repositoryDir $file
            
            if (Test-Path $src) {
                Write-Host "Copying $file..." -ForegroundColor Yellow
                Copy-Item -Path $src -Destination $dst -Force
                $changed = $true
            } else {
                Write-Host "File not found: $file" -ForegroundColor Yellow
            }
        }
        
        # Backup folders
        foreach ($folder in @($SessionDir, $SessionStoreBackupsDir)) {
            $srcFolder = Join-Path $fullPath $folder
            $tarFile = Join-Path $config.repositoryDir "$folder.tar.gz"
            
            if (Test-Path $srcFolder) {
                Write-Host "Archiving $folder..." -ForegroundColor Yellow
                & tar -czf $tarFile -C $fullPath $folder
                $changed = $true
            } else {
                Write-Host "Folder not found: $folder" -ForegroundColor Yellow
            }
        }
        
        if ($changed) {
            Write-Host "Pushing to repository..." -ForegroundColor Cyan
            & git add .
            & git commit -m "Zen Browser backup - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            & git push
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Backup completed successfully!" -ForegroundColor Green
                $config.lastBackup = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                $newConfig = $config | ConvertTo-Json -Depth 2
                Set-Content -Path $ConfigFile -Value $newConfig -Encoding UTF8
            } else {
                throw "Failed to push to repository"
            }
        } else {
            Write-Host "No files found to backup" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "Backup failed: $_" -ForegroundColor Red
        throw
    } finally {
        Pop-Location -ErrorAction SilentlyContinue
        if (Test-Path $config.repositoryDir) {
            Remove-Item -Recurse -Force $config.repositoryDir -ErrorAction SilentlyContinue
        }
    }
}

# === RESTORE FUNCTION ===
function Invoke-Restore {
    Write-Host "Starting Zen Browser Restore..." -ForegroundColor Cyan
    
    Test-Prerequisites
    
    $config = Get-Config
    if (-not $config) {
        Initialize-Repository "Restore" | Out-Null
        $config = Get-Config
    }
    
    $fullPath = Select-Profile
    Write-Host "Selected Zen Profile: $fullPath" -ForegroundColor Green
    
    # Clean up any existing repo directory
    if (Test-Path $config.repositoryDir) {
        Remove-Item -Recurse -Force $config.repositoryDir
    }
    
    try {
        # Clone repository
        Write-Host "Cloning backup repository..." -ForegroundColor Cyan
        & git clone $config.repositoryUrl $config.repositoryDir
        if ($LASTEXITCODE -ne 0) { 
            throw "Failed to clone repository. Make sure the URL is correct and you have access." 
        }
        
        Push-Location $config.repositoryDir
        
        # Restore individual files
        foreach ($file in $Files) {
            $src = Join-Path $config.repositoryDir $file
            $dst = Join-Path $fullPath $file
            
            if (Test-Path $src) {
                Write-Host "Restoring $file..." -ForegroundColor Yellow
                
                # Backup existing file
                if (Test-Path $dst) {
                    $bakFile = "$dst.bak"
                    Write-Host "Backing up existing $file to $(Split-Path $bakFile -Leaf)" -ForegroundColor Gray
                    Move-Item -Path $dst -Destination $bakFile -Force
                }
                
                Copy-Item -Path $src -Destination $dst -Force
            } else {
                Write-Host "Backup not found: $file" -ForegroundColor Yellow
            }
        }
        
        # Restore folders
        foreach ($folder in @($SessionDir, $SessionStoreBackupsDir)) {
            $src = Join-Path $config.repositoryDir "$folder.tar.gz"
            $dstFolder = Join-Path $fullPath $folder
            
            if (Test-Path $src) {
                Write-Host "Restoring $folder..." -ForegroundColor Yellow
                
                # Backup existing folder
                if (Test-Path $dstFolder) {
                    $bakFolder = "$dstFolder.bak"
                    Write-Host "Backing up existing $folder to $(Split-Path $bakFolder -Leaf)" -ForegroundColor Gray
                    if (Test-Path $bakFolder) { Remove-Item -Recurse -Force $bakFolder }
                    Move-Item -Path $dstFolder -Destination $bakFolder
                }
                
                & tar -xzf $src -C $fullPath
            } else {
                Write-Host "Backup not found: $folder.tar.gz" -ForegroundColor Yellow
            }
        }
        
        Write-Host "Restore completed successfully!" -ForegroundColor Green
        $config.lastRestore = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $newConfig = $config | ConvertTo-Json -Depth 2
        Set-Content -Path $ConfigFile -Value $newConfig -Encoding UTF8
    } catch {
        Write-Host "Restore failed: $_" -ForegroundColor Red
        throw
    } finally {
        Pop-Location -ErrorAction SilentlyContinue
        if (Test-Path $config.repositoryDir) {
            Remove-Item -Recurse -Force $config.repositoryDir -ErrorAction SilentlyContinue
        }
    }
}

# === MAIN ===
if ($args.Count -eq 0) {
    Write-Host "Zen Browser Profile Backup & Restore (No GPG)" -ForegroundColor Cyan
    Write-Host "Usage: zen-sync-no-gpg.ps1 {backup|restore}" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Prerequisites:" -ForegroundColor Gray
    Write-Host "  1. Have a Git repository ready for backups" -ForegroundColor Gray
    exit 1
}

switch ($args[0]) {
    'backup'  { Invoke-Backup }
    'restore' { Invoke-Restore }
    default {
        Write-Host "Usage: zen-sync-no-gpg.ps1 {backup|restore}" -ForegroundColor Yellow
        exit 1
    }
}
