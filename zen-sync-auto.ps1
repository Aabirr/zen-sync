# Zen Browser Auto-Sync PowerShell Script
# Watches for changes and automatically syncs to Git

param(
    [Parameter(Position=0)]
    [ValidateSet('watch', 'schedule', 'push', 'pull')]
    [string]$Mode = 'watch',
    
    [Parameter(Position=1)]
    [int]$IntervalMinutes = 60
)

# Colors for output
$Colors = @{
    Green = "Green"
    Yellow = "Yellow"
    Red = "Red"
    Cyan = "Cyan"
}

function Write-Status {
    param([string]$Message, [string]$Color = "Green")
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" -ForegroundColor $Colors[$Color]
}

function Write-Error {
    param([string]$Message)
    Write-Status -Message $Message -Color "Red"
}

function Write-Warning {
    param([string]$Message)
    Write-Status -Message $Message -Color "Yellow"
}

# Function to get the main script path
function Get-MainScriptPath {
    $scriptPath = Join-Path $PSScriptRoot "zen-sync-no-gpg.ps1"
    if (-not (Test-Path $scriptPath)) {
        $scriptPath = Join-Path $PSScriptRoot "zen-sync-no-gpg.ps1"
    }
    return $scriptPath
}

# Function to get Zen profile path
function Get-ZenProfilePath {
    $mainScript = Get-MainScriptPath
    if (Test-Path $mainScript) {
        try {
            # Try to get profile from main script
            $detectedProfile = & $mainScript backup 2>&1 | Where-Object { $_ -match 'Selected Zen Profile:' } | ForEach-Object { ($_ -split 'Selected Zen Profile: ')[1] }
            if ($detectedProfile) {
                return $detectedProfile.Trim()
            }
        } catch {
            Write-Warning "Could not auto-detect profile: $_"
        }
    }
    
    # Manual selection fallback
    Write-Host "Please select your Zen Browser profile:"
    $profiles = @()
    
    # Check regular Zen
    $zenBase = Join-Path $env:APPDATA "Zen"
    $iniPath = Join-Path $zenBase "profiles.ini"
    if (Test-Path $iniPath) {
        $profiles += @{ Name = "Regular"; Path = $zenBase }
    }
    
    # Check Twilight Zen
    $twilightPath = Join-Path $env:APPDATA "zen\Profiles"
    if (Test-Path $twilightPath) {
        Get-ChildItem -Path $twilightPath -Directory | ForEach-Object {
            $profiles += @{ Name = "Twilight ($($_.Name))"; Path = $_.FullName }
        }
    }
    
    if ($profiles.Count -eq 0) {
        Write-Error "No Zen Browser profiles found. Make sure Zen Browser is installed and has been run at least once."
        exit 1
    }
    
    if ($profiles.Count -eq 1) {
        return $profiles[0].Path
    }
    
    Write-Host "Found $($profiles.Count) profiles:"
    for ($i = 0; $i -lt $profiles.Count; $i++) {
        Write-Host "  [$($i + 1)] $($profiles[$i].Name) - $($profiles[$i].Path)"
    }
    
    do {
        $selection = Read-Host "Select profile (1-$($profiles.Count))"
        if ($selection -match '^\d+$' -and [int]$selection -ge 1 -and [int]$selection -le $profiles.Count) {
            return $profiles[[int]$selection - 1].Path
        }
        Write-Host "Invalid selection. Please enter a number between 1 and $($profiles.Count)."
    } while ($true)
}

# Function to perform backup with automatic browser handling
function Invoke-Backup {
    Write-Status "Checking browser status..."
    
    # Check if Zen Browser is running
    $zenProcesses = Get-Process -Name "*zen*" -ErrorAction SilentlyContinue
    if ($zenProcesses) {
        Write-Status "Zen Browser is running - attempting backup anyway..."
        
        # Check file accessibility
        $lockedFiles = Test-FileAccess -ProfilePath $script:zenProfile
        if ($lockedFiles.Count -gt 0) {
            Write-Status "Files locked: $($lockedFiles -join ', ')"
            Write-Status "Will retry in 5 minutes..."
            return $false
        }
    }
    
    Write-Status "Performing automatic backup..."
    $mainScript = Get-MainScriptPath
    try {
        & $mainScript backup
        return $true
    } catch {
        Write-Status "Backup failed: $_"
        return $false
    }
}

# Function to perform restore with automatic handling
function Invoke-Restore {
    Write-Status "Performing automatic restore..."
    $mainScript = Get-MainScriptPath
    try {
        & $mainScript restore
        return $true
    } catch {
        Write-Status "Restore failed: $_"
        return $false
    }
}

# Function to check if files are accessible
function Test-FileAccess {
    param([string]$ProfilePath)
    
    $testFiles = @(
        Join-Path $ProfilePath "places.sqlite"
        Join-Path $ProfilePath "sessionstore.jsonlz4"
        Join-Path $ProfilePath "sessionstore-backups"
    )
    
    $lockedFiles = @()
    foreach ($file in $testFiles) {
        try {
            if (Test-Path $file) {
                $stream = [System.IO.File]::Open($file, 'Open', 'Read', 'Read')
                $stream.Close()
            }
        } catch {
            $lockedFiles += $file
        }
    }
    
    return $lockedFiles
}

# Function to perform restore
function Invoke-Restore {
    Write-Status "Performing automatic restore..."
    $mainScript = Get-MainScriptPath
    & $mainScript restore
}

# Function to watch for file changes
function Start-WatchMode {
    param([string]$ProfilePath)
    
    Write-Status "Starting watch mode for: $ProfilePath"
    
    # Files to watch
    # Check file access before watching
    $lockedFiles = Test-FileAccess -ProfilePath $ProfilePath
    if ($lockedFiles.Count -gt 0) {
        Write-Status "Files locked: $($lockedFiles -join ', ')"
        Write-Status "Will use polling mode instead"
    }
    
    # Use polling mode for reliability
    Start-PollingMode -ProfilePath $ProfilePath
}

# Function to poll for changes with remote sync
function Start-PollingMode {
    param([string]$ProfilePath)
    
    Write-Status "Starting polling mode for: $ProfilePath"
    $lastLocalHash = $null
    $lastRemoteHash = $null
    $retryCount = 0
    $maxRetries = 3
    
    # Function to check remote changes
    function Test-RemoteChanges {
        try {
            # Check if repo exists
            if (-not (Test-Path ".git")) {
                return $false
            }
            
            # Fetch latest changes
            git fetch origin 2>&1 | Out-Null
            
            # Check if local is behind remote
            $localCommit = git rev-parse HEAD 2>&1
            $remoteCommit = git rev-parse origin/main 2>&1
            
            if ($localCommit -ne $remoteCommit) {
                Write-Status "Remote changes detected"
                return $true
            }
            return $false
        } catch {
            Write-Status "Error checking remote changes: $_"
            return $false
        }
    }
    
    # Function to create hash of local files
    function Get-LocalFileHash {
        $files = @(
            Join-Path $ProfilePath "places.sqlite"
            Join-Path $ProfilePath "sessionstore.jsonlz4"
            Join-Path $ProfilePath "sessionstore-backups\sessionstore.jsonlz4"
        )
        
        $hashString = ""
        foreach ($file in $files) {
            if (Test-Path $file) {
                try {
                    $hash = Get-FileHash $file -Algorithm MD5 -ErrorAction SilentlyContinue
                    $hashString += $hash.Hash
                } catch {
                    $hashString += "locked"
                }
            } else {
                $hashString += "missing"
            }
        }
        return $hashString
    }
    
    while ($true) {
        try {
            # Check for remote changes first
            if (Test-RemoteChanges) {
                Write-Status "Remote changes detected, pulling..."
                $success = Invoke-Restore
                if ($success) {
                    Write-Status "Remote sync completed"
                    $lastRemoteHash = Get-LocalFileHash
                    $lastLocalHash = $lastRemoteHash
                }
            }
            
            # Check for local changes
            $currentHash = Get-LocalFileHash
            if ($currentHash -ne $lastLocalHash) {
                Write-Status "Local changes detected, attempting backup..."
                $success = Invoke-Backup
                if ($success) {
                    $lastLocalHash = $currentHash
                    $retryCount = 0
                    Write-Status "Backup completed successfully"
                } else {
                    $retryCount++
                    if ($retryCount -lt $maxRetries) {
                        Write-Status "Backup failed, retrying in 5 minutes... ($retryCount/$maxRetries)"
                        Start-Sleep -Seconds 300
                    } else {
                        Write-Status "Max retries reached, waiting 30 minutes..."
                        Start-Sleep -Seconds 1800
                        $retryCount = 0
                    }
                }
            }
        } catch {
            Write-Status "Error during polling: $_"
        }
        
        Start-Sleep -Seconds 60
    }
}

# Function to pull changes from Git
function Invoke-PullChanges {
    Write-Status "Pulling changes from GitHub..."
    Invoke-Restore
}

# Function to schedule periodic sync
function Start-ScheduleMode {
    param([int]$IntervalMinutes, [string]$ProfilePath)
    
    Write-Status "Starting scheduled sync every $IntervalMinutes minutes"
    
    while ($true) {
        Write-Status "Scheduled backup at $(Get-Date)"
        Invoke-Backup
        Start-Sleep -Seconds ($IntervalMinutes * 60)
    }
}

# Function to push changes to Git
function Invoke-PushChanges {
    Write-Status "Pushing changes to GitHub..."
    Invoke-Backup
}

# Main function
function Start-Main {
    param([string]$Mode, [int]$IntervalMinutes)
    
    $mainScript = Get-MainScriptPath
    if (-not (Test-Path $mainScript)) {
        Write-Error "Main script not found: $mainScript"
        exit 1
    }
    
    $zenProfile = Get-ZenProfilePath
    Write-Status "Using Zen profile: $zenProfile"
    
    switch ($Mode) {
        'watch' {
            Start-WatchMode -ProfilePath $zenProfile
        }
        'schedule' {
            Start-ScheduleMode -IntervalMinutes $IntervalMinutes -ProfilePath $zenProfile
        }
        'push' {
            Invoke-PushChanges
        }
        'pull' {
            Invoke-PullChanges
        }
        default {
            Write-Host "Usage: .\zen-sync-auto.ps1 {watch|schedule [interval]|push|pull}"
            Write-Host "  watch     - Monitor files for changes and auto-backup"
            Write-Host "  schedule  - Backup every N minutes (default: 60)"
            Write-Host "  push      - Manually push changes to GitHub"
            Write-Host "  pull      - Manually pull changes from GitHub"
            Write-Host ""
            Write-Host "Examples:"
            Write-Host "  .\zen-sync-auto.ps1 watch"
            Write-Host "  .\zen-sync-auto.ps1 schedule 30"
            Write-Host "  .\zen-sync-auto.ps1 push"
            exit 1
        }
    }
}

# Run main
Start-Main -Mode $Mode -IntervalMinutes $IntervalMinutes
