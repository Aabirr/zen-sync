#!/bin/bash

# === CONFIG ===
REPO_DIR="$HOME/zen-browser-profile-backup"
FILES=("places.sqlite" "places.sqlite-shm" "places.sqlite-wal" "sessionstore.jsonlz4")
FOLDERS=("sessionstore-backups")
SESSION_DIR="sessionbackups"
SESSIONSTORE_BACKUPS_DIR="sessionstore-backups"
SESSIONSTORE_BACKUPS_ARCHIVE="${SESSIONSTORE_BACKUPS_DIR}.tar.gz.gpg"
SESSION_ARCHIVE="${SESSION_DIR}.tar.gz.gpg"
HASH_FILE="$REPO_DIR/.file_hashes"
PASS_FILE="$HOME/.zen_sync_pass"
GIT_REMOTE="git@github.com:Aabirr/zen-sync.git"

# === DETECT OS & PROFILE ===
detect_profile() {
    OS="$(uname -s)"
    case "$OS" in
        Linux*)     PLATFORM="Linux";;
        Darwin*)    PLATFORM="macOS";;
        MINGW*|MSYS*|CYGWIN*) PLATFORM="Windows";;
        *)          echo "Unsupported OS: $OS"; exit 1;;
    esac

    if [[ "$PLATFORM" == "Linux" ]]; then
        # Check for Flatpak installation first
        if [[ -d "$HOME/.var/app/app.zen_browser.zen/.zen" ]]; then
            INI_PATH="$HOME/.var/app/app.zen_browser.zen/.zen/profiles.ini"
            PROFILE_DIR=$(grep -m 1 '^Path=' "$INI_PATH" | cut -d= -f2)
            FULL_PATH="$HOME/.var/app/app.zen_browser.zen/.zen/$PROFILE_DIR"
        else
            # Standard installation
            INI_PATH="$HOME/.zen/profiles.ini"
            PROFILE_DIR=$(grep -m 1 '^Path=' "$INI_PATH" | cut -d= -f2)
            FULL_PATH="$HOME/.zen/$PROFILE_DIR"
        fi
    elif [[ "$PLATFORM" == "macOS" ]]; then
        INI_PATH="$HOME/Library/Application Support/Zen/profiles.ini"
        PROFILE_DIR=$(grep -m 1 '^Path=' "$INI_PATH" | cut -d= -f2)
        FULL_PATH="$HOME/Library/Application Support/Zen/$PROFILE_DIR"
    elif [[ "$PLATFORM" == "Windows" ]]; then
        WIN_HOME="$(cmd.exe /c echo %USERPROFILE% 2>/dev/null | tr -d '\r')"
        INI_PATH="$(wslpath "$WIN_HOME\\AppData\\Roaming\\Zen\\profiles.ini")"
        PROFILE_DIR=$(grep -m 1 '^Path=' "$INI_PATH" | cut -d= -f2)
        FULL_PATH="$(wslpath "$WIN_HOME\\AppData\\Roaming\\Zen\\$PROFILE_DIR")"
    fi
}

# === BACKUP FUNCTION ===
backup() {
    detect_profile
    mkdir -p "$REPO_DIR"
    cd "$REPO_DIR" || exit

    # Git setup
    if [ ! -d ".git" ]; then
        git init
        git remote add origin "$GIT_REMOTE"
        git checkout -b main
    fi

    touch "$HASH_FILE"
    CHANGED=false

    # Sync and encrypt individual files
    for FILE in "${FILES[@]}"; do
        SRC="$FULL_PATH/$FILE"
        ENC="$REPO_DIR/$FILE.gpg"
        if [[ -f "$SRC" ]]; then
            NEW_HASH=$(sha256sum "$SRC" | awk '{print $1}')
            OLD_HASH=$(grep "$FILE" "$HASH_FILE" | awk '{print $2}')
            if [[ "$NEW_HASH" != "$OLD_HASH" ]]; then
                echo "Encrypting $FILE..."
                gpg --batch --yes --passphrase-file "$PASS_FILE" -c "$SRC"
                mv "$FILE.gpg" "$ENC"
                sed -i.bak "/$FILE/d" "$HASH_FILE" && rm -f "$HASH_FILE.bak"
                echo "$FILE $NEW_HASH" >> "$HASH_FILE"
                CHANGED=true
            fi
        fi
    done

    # Archive and encrypt sessionbackups
    SRC_SESSION="$FULL_PATH/$SESSION_DIR"
    if [[ -d "$SRC_SESSION" ]]; then
        echo "Archiving and encrypting sessionbackups..."
        tar -czf "${SESSION_DIR}.tar.gz" -C "$FULL_PATH" "$SESSION_DIR"
        gpg --batch --yes --passphrase-file "$PASS_FILE" -c "${SESSION_DIR}.tar.gz"
        mv "${SESSION_DIR}.tar.gz.gpg" "$REPO_DIR/$SESSION_ARCHIVE"
        rm -f "${SESSION_DIR}.tar.gz"
        CHANGED=true
    fi

    # Archive and encrypt sessionstore-backups
    SRC_SESSIONSTORE_BACKUPS="$FULL_PATH/$SESSIONSTORE_BACKUPS_DIR"
    if [[ -d "$SRC_SESSIONSTORE_BACKUPS" ]]; then
        echo "Archiving and encrypting sessionstore-backups..."
        tar -czf "${SESSIONSTORE_BACKUPS_DIR}.tar.gz" -C "$FULL_PATH" "$SESSIONSTORE_BACKUPS_DIR"
        gpg --batch --yes --passphrase-file "$PASS_FILE" -c "${SESSIONSTORE_BACKUPS_DIR}.tar.gz"
        mv "${SESSIONSTORE_BACKUPS_DIR}.tar.gz.gpg" "$REPO_DIR/$SESSIONSTORE_BACKUPS_ARCHIVE"
        rm -f "${SESSIONSTORE_BACKUPS_DIR}.tar.gz"
        CHANGED=true
    fi

    # Commit and push
    if $CHANGED; then
        git add .
        git commit -m "Encrypted sync: $(date)"
        git push origin main
    else
        echo "No changes detected."
    fi
}

# === RESTORE FUNCTION ===
restore() {
    detect_profile

    for FILE in "${FILES[@]}"; do
        ENC="$REPO_DIR/$FILE.gpg"
        DEST="$FULL_PATH/$FILE"
        if [[ -f "$ENC" ]]; then
            echo "Decrypting $FILE..."
            gpg --batch --yes --passphrase-file "$PASS_FILE" -o "$DEST" -d "$ENC"
        else
            echo "Missing: $ENC"
        fi
    done

    ARCHIVE="$REPO_DIR/$SESSION_ARCHIVE"
    if [[ -f "$ARCHIVE" ]]; then
        echo "Decrypting sessionbackups archive..."
        gpg --batch --yes --passphrase-file "$PASS_FILE" -o "$REPO_DIR/sessionbackups.tar.gz" -d "$ARCHIVE"
        tar -xzf "$REPO_DIR/sessionbackups.tar.gz" -C "$FULL_PATH"
        rm "$REPO_DIR/sessionbackups.tar.gz"
    else
        echo "Missing: $ARCHIVE"
    fi

    SESSIONSTORE_ARCHIVE="$REPO_DIR/$SESSIONSTORE_BACKUPS_ARCHIVE"
    if [[ -f "$SESSIONSTORE_ARCHIVE" ]]; then
        echo "Decrypting sessionstore-backups archive..."
        gpg --batch --yes --passphrase-file "$PASS_FILE" -o "$REPO_DIR/sessionstore-backups.tar.gz" -d "$SESSIONSTORE_ARCHIVE"
        tar -xzf "$REPO_DIR/sessionstore-backups.tar.gz" -C "$FULL_PATH"
        rm "$REPO_DIR/sessionstore-backups.tar.gz"
    else
        echo "Missing: $SESSIONSTORE_ARCHIVE"
    fi

    echo "✅ Restore complete."
}

# === MAIN ENTRY ===
case "$1" in
    backup)  backup ;;
    restore) restore ;;
    *)
        echo "Usage: $0 {backup|restore}"
        exit 1
        ;;
esac
