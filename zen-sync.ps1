#requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# === CONFIG ===
$HomeDir   = [Environment]::GetFolderPath('UserProfile')
$RepoDir   = Split-Path -Parent $MyInvocation.MyCommand.Path  # Use script's directory
$Files     = @('places.sqlite','places.sqlite-shm','places.sqlite-wal','sessionstore.jsonlz4')
$SessionDir = 'sessionbackups'
$SessionArchive = "$SessionDir.tar.gz.gpg"
$SessionStoreBackupsDir = 'sessionstore-backups'
$SessionStoreBackupsArchive = "$SessionStoreBackupsDir.tar.gz.gpg"
$HashFile  = Join-Path $RepoDir '.file_hashes'
$PassFile  = Join-Path $HomeDir '.zen_sync_pass'
$GitRemote = 'git@github.com:Aabirr/zen-sync.git'

# === DETECT PROFILE (Windows) ===
function Get-ZenProfilePath {
    $appData = $env:APPDATA  # e.g. C:\Users\<user>\AppData\Roaming
    $zenBase = Join-Path $appData 'Zen'
    $iniPath = Join-Path $zenBase 'profiles.ini'
    if (-not (Test-Path $iniPath)) { throw "profiles.ini not found at: $iniPath" }

    $ini = Get-Content -Raw -LiteralPath $iniPath -Encoding UTF8
    # Parse IsRelative and Path from the first profile section
    $isRelative = $false
    $pathLine = ($ini -split "`n") | Where-Object { $_ -match '^IsRelative=' } | Select-Object -First 1
    if ($pathLine) { $isRelative = ($pathLine -split '=',2)[1].Trim() -eq '1' }
    $profileLine = ($ini -split "`n") | Where-Object { $_ -match '^Path=' } | Select-Object -First 1
    if (-not $profileLine) { throw 'No Path= entry found in profiles.ini' }
    $profilePath = ($profileLine -split '=',2)[1].Trim()

    if ($isRelative) { return (Join-Path $zenBase $profilePath) }
    else { return $profilePath }
}

# === UTIL ===
function Ensure-Directory([string]$Path) { if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Path $Path | Out-Null } }

function Get-FileHashHex([string]$Path) {
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLower()
}

function Get-HashMap([string]$hashFilePath) {
    $map = @{}
    if (Test-Path $hashFilePath) {
        foreach ($line in Get-Content -LiteralPath $hashFilePath) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $parts = $line -split '\s+'
            if ($parts.Count -ge 2) { $map[$parts[0]] = $parts[1] }
        }
    }
    return $map
}

function Set-HashMap([string]$hashFilePath, $map) {
    $lines = @()
    foreach ($k in $map.Keys) { $lines += "$k $($map[$k])" }
    Set-Content -LiteralPath $hashFilePath -Value $lines -NoNewline:$false -Encoding UTF8
}

function Invoke-GpgEncrypt([string]$src, [string]$dst) {
    if (-not (Test-Path $PassFile)) { throw "Passphrase file not found: $PassFile" }
    $gpg = 'gpg'
    $args = @('--batch','--yes','--passphrase-file', $PassFile, '-o', $dst, '-c', $src)
    $p = Start-Process -FilePath $gpg -ArgumentList $args -NoNewWindow -Wait -PassThru
    if ($p.ExitCode -ne 0) { throw "gpg failed for $src" }
}

function Invoke-GpgDecrypt([string]$src, [string]$dst) {
    if (-not (Test-Path $PassFile)) { throw "Passphrase file not found: $PassFile" }
    $gpg = 'gpg'
    $args = @('--batch','--yes','--passphrase-file', $PassFile, '-o', $dst, '-d', $src)
    $p = Start-Process -FilePath $gpg -ArgumentList $args -NoNewWindow -Wait -PassThru
    if ($p.ExitCode -ne 0) { throw "gpg failed for $src" }
}

function Invoke-TarCreateGz([string]$workingDir, [string]$itemName, [string]$outTarGz) {
    Push-Location $workingDir
    try {
        # bsdtar on Windows supports -czf
        & tar -czf $outTarGz $itemName
        if ($LASTEXITCODE -ne 0) { throw "tar create failed for $itemName" }
    }
    finally { Pop-Location }
}

function Invoke-TarExtractGz([string]$tarGz, [string]$destDir) {
    Ensure-Directory $destDir
    Push-Location $destDir
    try {
        & tar -xzf $tarGz
        if ($LASTEXITCODE -ne 0) { throw "tar extract failed for $tarGz" }
    }
    finally { Pop-Location }
}

# === BACKUP ===
function Invoke-Backup {
    $fullPath = Get-ZenProfilePath
    Ensure-Directory $RepoDir
    Push-Location $RepoDir
    try {
        # Git setup
        if (-not (Test-Path (Join-Path $RepoDir '.git'))) {
            git init | Out-Null
            git remote add origin $GitRemote | Out-Null
            git checkout -b main | Out-Null
        }

        $hashMap = Get-HashMap $HashFile
        $changed = $false

        # Files
        foreach ($f in $Files) {
            $src = Join-Path $fullPath $f
            $enc = Join-Path $RepoDir ("$f.gpg")
            if (Test-Path $src) {
                $newHash = Get-FileHashHex $src
                $oldHash = $hashMap[$f]
                if ($newHash -ne $oldHash) {
                    Write-Host "Encrypting $f..."
                    Invoke-GpgEncrypt -src $src -dst $enc
                    $hashMap[$f] = $newHash
                    $changed = $true
                }
            }
        }

        # sessionbackups folder
        $srcSession = Join-Path $fullPath $SessionDir
        if (Test-Path $srcSession) {
            Write-Host 'Archiving and encrypting sessionbackups...'
            $tmpTar = "$SessionDir.tar.gz"
            Invoke-TarCreateGz -workingDir $fullPath -itemName $SessionDir -outTarGz $tmpTar
            Invoke-GpgEncrypt -src (Join-Path $fullPath $tmpTar) -dst (Join-Path $RepoDir $SessionArchive)
            Remove-Item -Force (Join-Path $fullPath $tmpTar)
            $changed = $true
        }

        # sessionstore-backups folder
        $srcSessionStore = Join-Path $fullPath $SessionStoreBackupsDir
        if (Test-Path $srcSessionStore) {
            Write-Host 'Archiving and encrypting sessionstore-backups...'
            $tmpTar2 = "$SessionStoreBackupsDir.tar.gz"
            Invoke-TarCreateGz -workingDir $fullPath -itemName $SessionStoreBackupsDir -outTarGz $tmpTar2
            Invoke-GpgEncrypt -src (Join-Path $fullPath $tmpTar2) -dst (Join-Path $RepoDir $SessionStoreBackupsArchive)
            Remove-Item -Force (Join-Path $fullPath $tmpTar2)
            $changed = $true
        }

        # Save hashes
        Set-HashMap -hashFilePath $HashFile -map $hashMap

        if ($changed) {
            git add . | Out-Null
            git commit -m ("Encrypted sync: $(Get-Date -Format 'u')") | Out-Null
            git push origin main | Out-Null
        }
        else {
            Write-Host 'No changes detected.'
        }
    }
    finally { Pop-Location }
}

# === RESTORE ===
function Invoke-Restore {
    $fullPath = Get-ZenProfilePath
    Ensure-Directory $RepoDir

    foreach ($f in $Files) {
        $enc = Join-Path $RepoDir ("$f.gpg")
        $dest = Join-Path $fullPath $f
        if (Test-Path $enc) {
            Write-Host "Decrypting $f..."
            Ensure-Directory (Split-Path $dest -Parent)
            
            # Backup existing file if it exists
            if (Test-Path $dest) {
                $bakFile = "$dest.bak"
                Write-Host "Backing up existing $f to $([System.IO.Path]::GetFileName($bakFile))"
                Move-Item -Path $dest -Destination $bakFile -Force
            }
            
            Invoke-GpgDecrypt -src $enc -dst $dest
        } else { Write-Host "Missing: $enc" }
    }

    $arch = Join-Path $RepoDir $SessionArchive
    if (Test-Path $arch) {
        Write-Host 'Decrypting sessionbackups archive...'
        $tmp = Join-Path $RepoDir 'sessionbackups.tar.gz'
        $sessionDest = Join-Path $fullPath $SessionDir
        
        # Backup existing sessionbackups folder
        if (Test-Path $sessionDest) {
            $bakDir = "$sessionDest.bak"
            Write-Host "Backing up existing sessionbackups to $([System.IO.Path]::GetFileName($bakDir))"
            if (Test-Path $bakDir) { Remove-Item -Recurse -Force $bakDir }
            Move-Item -Path $sessionDest -Destination $bakDir
        }
        
        Invoke-GpgDecrypt -src $arch -dst $tmp
        Invoke-TarExtractGz -tarGz $tmp -destDir $fullPath
        Remove-Item -Force $tmp
    } else { Write-Host "Missing: $arch" }

    $arch2 = Join-Path $RepoDir $SessionStoreBackupsArchive
    if (Test-Path $arch2) {
        Write-Host 'Decrypting sessionstore-backups archive...'
        $tmp2 = Join-Path $RepoDir 'sessionstore-backups.tar.gz'
        $sessionStoreDest = Join-Path $fullPath $SessionStoreBackupsDir
        
        # Backup existing sessionstore-backups folder
        if (Test-Path $sessionStoreDest) {
            $bakDir2 = "$sessionStoreDest.bak"
            Write-Host "Backing up existing sessionstore-backups to $([System.IO.Path]::GetFileName($bakDir2))"
            if (Test-Path $bakDir2) { Remove-Item -Recurse -Force $bakDir2 }
            Move-Item -Path $sessionStoreDest -Destination $bakDir2
        }
        
        Invoke-GpgDecrypt -src $arch2 -dst $tmp2
        Invoke-TarExtractGz -tarGz $tmp2 -destDir $fullPath
        Remove-Item -Force $tmp2
    } else { Write-Host "Missing: $arch2" }

    Write-Host "Restore complete."
}

# === MAIN ===
if ($args.Count -eq 0) {
    Write-Host "Usage: zen-sync.ps1 {backup|restore}"
    exit 1
}

switch ($args[0]) {
    'backup'  { Invoke-Backup }
    'restore' { Invoke-Restore }
    default {
        Write-Host "Usage: zen-sync.ps1 {backup|restore}"
        exit 1
    }
}
