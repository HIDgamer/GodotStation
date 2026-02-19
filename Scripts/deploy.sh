#!/usr/bin/env bash
# =============================================================================
# deploy.sh
# GodotStation Dedicated Server — Deployment Script
#
# Invoked remotely by GitHub Actions on every tagged release.
# Handles: stop → backup → wipe → download → validate → install → start
#
# Arguments:
#   $1  TAG            — Git release tag (e.g. v1.0.1)
#   $2  REPO           — GitHub repository slug (e.g. owner/repo)
#   $3  PANEL_PASSWORD — Password for the local management panel API
# =============================================================================
set -e

TAG="$1"
REPO="$2"
PANEL_PASSWORD="$3"

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
DEPLOY_DIR="/home/ubuntu/godotstation"
BACKUP_DIR="$DEPLOY_DIR/backups"
PANEL_URL="http://localhost:8087"

# Names as they appear inside the release zip
BINARY_IN_ZIP="GodotStationServer.x86_64"
PCK_IN_ZIP="GodotStationServer.pck"
DATA_DIR_IN_ZIP="data_GodotStation_linuxbsd_x86_64"

# Names as they are stored on disk
BINARY_NAME="GodotStationServer.x86_64"
PCK_NAME="GodotStationServer.pck"

ASSET_URL="https://github.com/${REPO}/releases/download/${TAG}/GodotStation-Server-Linux.zip"

mkdir -p "$BACKUP_DIR"

# -----------------------------------------------------------------------------
# Stop the running server via the management panel
# -----------------------------------------------------------------------------
echo "=== Stopping server (deploying tag: $TAG) ==="
curl -sf -X POST \
  -H "Content-Type: application/json" \
  -d "{\"password\":\"${PANEL_PASSWORD}\"}" \
  "$PANEL_URL/api/login" \
  -c /tmp/gs_deploy.txt || true
curl -sf -X POST "$PANEL_URL/api/stop" -b /tmp/gs_deploy.txt || true
sleep 3

# -----------------------------------------------------------------------------
# Back up the current build so we can restore it if deployment fails
# -----------------------------------------------------------------------------
if [ -f "$DEPLOY_DIR/$BINARY_NAME" ]; then
  echo "=== Backing up current build ==="
  cp "$DEPLOY_DIR/$BINARY_NAME" "$BACKUP_DIR/$BINARY_NAME.bak"
  cp "$DEPLOY_DIR/$PCK_NAME"    "$BACKUP_DIR/$PCK_NAME.bak" 2>/dev/null || true
fi

# -----------------------------------------------------------------------------
# Wipe old binaries to ensure no stale files remain after install
# -----------------------------------------------------------------------------
echo "=== Removing old binaries ==="
rm -fv "$DEPLOY_DIR/$BINARY_NAME"
rm -fv "$DEPLOY_DIR/$PCK_NAME"
rm -fv "$DEPLOY_DIR/GodotStation.x86_64"
rm -fv "$DEPLOY_DIR/GodotStation.pck"
rm -fv "$DEPLOY_DIR/GodotStation.server"

# -----------------------------------------------------------------------------
# Download and extract the release artifact
# -----------------------------------------------------------------------------
echo "=== Downloading release artifact: $ASSET_URL ==="
rm -rf /tmp/gs_extract /tmp/server_update.zip
wget -q "$ASSET_URL" -O /tmp/server_update.zip
unzip -q -o /tmp/server_update.zip -d /tmp/gs_extract

echo "=== Zip contents ==="
ls -la /tmp/gs_extract/

# -----------------------------------------------------------------------------
# Validate — abort and restore backup if expected files are missing.
# A binary/pck mismatch will crash the server on startup, so both are required.
# -----------------------------------------------------------------------------
_restore_and_exit() {
  echo "ERROR: $1"
  echo "Restoring backup and restarting previous version."
  [ -f "$BACKUP_DIR/$BINARY_NAME.bak" ] && cp "$BACKUP_DIR/$BINARY_NAME.bak" "$DEPLOY_DIR/$BINARY_NAME"
  [ -f "$BACKUP_DIR/$PCK_NAME.bak"    ] && cp "$BACKUP_DIR/$PCK_NAME.bak"    "$DEPLOY_DIR/$PCK_NAME"
  curl -sf -X POST "$PANEL_URL/api/start" -b /tmp/gs_deploy.txt || true
  rm -rf /tmp/gs_extract /tmp/server_update.zip /tmp/gs_deploy.txt
  exit 1
}

[ ! -f "/tmp/gs_extract/$BINARY_IN_ZIP" ] && _restore_and_exit "'$BINARY_IN_ZIP' not found in zip."
[ ! -f "/tmp/gs_extract/$PCK_IN_ZIP"    ] && _restore_and_exit "'$PCK_IN_ZIP' not found in zip."

# -----------------------------------------------------------------------------
# Install the new build
# -----------------------------------------------------------------------------
echo "=== Installing new build ==="
cp "/tmp/gs_extract/$BINARY_IN_ZIP" "$DEPLOY_DIR/$BINARY_NAME"
cp "/tmp/gs_extract/$PCK_IN_ZIP"    "$DEPLOY_DIR/$PCK_NAME"
chmod +x "$DEPLOY_DIR/$BINARY_NAME"

# Copy the Mono runtime data folder — required for C# scripting to function
if [ -d "/tmp/gs_extract/$DATA_DIR_IN_ZIP" ]; then
  echo "=== Installing Mono runtime data folder ==="
  rm -rf "$DEPLOY_DIR/$DATA_DIR_IN_ZIP"
  cp -r "/tmp/gs_extract/$DATA_DIR_IN_ZIP" "$DEPLOY_DIR/"
fi

echo "=== Installed files ==="
ls -lh "$DEPLOY_DIR/$BINARY_NAME" "$DEPLOY_DIR/$PCK_NAME"

# -----------------------------------------------------------------------------
# Start the server and record the deployed version
# -----------------------------------------------------------------------------
echo "=== Starting server ==="
curl -sf -X POST "$PANEL_URL/api/start" -b /tmp/gs_deploy.txt || true

echo "$TAG" > "$DEPLOY_DIR/version.txt"
rm -rf /tmp/gs_extract /tmp/server_update.zip /tmp/gs_deploy.txt

echo "=== Deployment complete: $TAG ==="
