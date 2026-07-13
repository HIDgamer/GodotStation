#!/usr/bin/env bash
# =============================================================================
# deploy.sh — GodotStation Dedicated Server Deployment
#
# Shipped from the repo and executed remotely by GitHub Actions.
# Because Actions SCPs this file fresh on every run, it is always
# the version from the current commit — no manual server updates needed.
#
# Usage (called by GitHub Actions):
#   bash /tmp/gs_deploy.sh <TAG> <REPO> <PANEL_PASSWORD>
#
#   TAG            e.g. v1.2.0
#   REPO           e.g. owner/GodotStation
#   PANEL_PASSWORD panel.js password from ${{ secrets.PANEL_PASSWORD }}
# =============================================================================
set -euo pipefail

TAG="$1"
REPO="$2"
PANEL_PASSWORD="$3"

# ── Config ────────────────────────────────────────────────────────────────────
DEPLOY_DIR="/home/ubuntu/godotstation"
BACKUP_DIR="$DEPLOY_DIR/backups"
PANEL_URL="http://localhost:8087"
COOKIE="/tmp/gs_cookie_$$.txt"
EXTRACT="/tmp/gs_extract_$$"
ZIPFILE="/tmp/gs_update_$$.zip"

BINARY_IN_ZIP="GodotStationServer.x86_64"
PCK_IN_ZIP="GodotStationServer.pck"
DATA_DIR_IN_ZIP="data_GodotStation_linuxbsd_x86_64"
ADDONS_DIR_IN_ZIP="Addons"

BINARY_NAME="GodotStationServer.x86_64"
PCK_NAME="GodotStationServer.pck"

ASSET_URL="https://github.com/${REPO}/releases/download/${TAG}/GodotStation-Server-Linux.zip"

# ── Cleanup trap (always runs) ────────────────────────────────────────────────
cleanup() {
  rm -rf "$EXTRACT" "$ZIPFILE" "$COOKIE"
}
trap cleanup EXIT

mkdir -p "$BACKUP_DIR"

# ── Helpers ───────────────────────────────────────────────────────────────────
panel_login() {
  curl -sf -X POST \
    -H "Content-Type: application/json" \
    -d "{\"password\":\"${PANEL_PASSWORD}\"}" \
    "$PANEL_URL/api/login" \
    -c "$COOKIE" > /dev/null || true
}

panel() {
  curl -sf -X POST "$PANEL_URL/api/$1" -b "$COOKIE" > /dev/null || true
}

restore_and_exit() {
  echo "ERROR: $1"
  echo "=== Restoring backup and restarting previous version ==="
  [ -f "$BACKUP_DIR/$BINARY_NAME.bak" ] && cp "$BACKUP_DIR/$BINARY_NAME.bak" "$DEPLOY_DIR/$BINARY_NAME"
  [ -f "$BACKUP_DIR/$PCK_NAME.bak"    ] && cp "$BACKUP_DIR/$PCK_NAME.bak"    "$DEPLOY_DIR/$PCK_NAME"
  panel start
  exit 1
}

# ── Stop ──────────────────────────────────────────────────────────────────────
echo "=== Stopping server (tag: $TAG) ==="
panel_login
panel stop
sleep 3

# ── Backup ────────────────────────────────────────────────────────────────────
if [ -f "$DEPLOY_DIR/$BINARY_NAME" ]; then
  echo "=== Backing up current build ==="
  cp "$DEPLOY_DIR/$BINARY_NAME" "$BACKUP_DIR/$BINARY_NAME.bak"
  cp "$DEPLOY_DIR/$PCK_NAME"    "$BACKUP_DIR/$PCK_NAME.bak" 2>/dev/null || true
fi

# ── Wipe old files ────────────────────────────────────────────────────────────
echo "=== Removing old binaries ==="
rm -fv "$DEPLOY_DIR/$BINARY_NAME" \
       "$DEPLOY_DIR/$PCK_NAME" \
       "$DEPLOY_DIR/GodotStation.x86_64" \
       "$DEPLOY_DIR/GodotStation.pck" \
       "$DEPLOY_DIR/GodotStation.server"

# ── Download ──────────────────────────────────────────────────────────────────
echo "=== Downloading: $ASSET_URL ==="
wget -q "$ASSET_URL" -O "$ZIPFILE"
unzip -q -o "$ZIPFILE" -d "$EXTRACT"

echo "=== Zip contents ==="
ls -la "$EXTRACT/"

# ── Validate ──────────────────────────────────────────────────────────────────
[ ! -f "$EXTRACT/$BINARY_IN_ZIP" ] && restore_and_exit "'$BINARY_IN_ZIP' not found in zip."
[ ! -f "$EXTRACT/$PCK_IN_ZIP"    ] && restore_and_exit "'$PCK_IN_ZIP' not found in zip."

# ── Install ───────────────────────────────────────────────────────────────────
echo "=== Installing new build ==="
cp "$EXTRACT/$BINARY_IN_ZIP" "$DEPLOY_DIR/$BINARY_NAME"
cp "$EXTRACT/$PCK_IN_ZIP"    "$DEPLOY_DIR/$PCK_NAME"
chmod +x "$DEPLOY_DIR/$BINARY_NAME"

if [ -d "$EXTRACT/$DATA_DIR_IN_ZIP" ]; then
  echo "=== Installing Mono data folder ==="
  rm -rf "$DEPLOY_DIR/$DATA_DIR_IN_ZIP"
  cp -r  "$EXTRACT/$DATA_DIR_IN_ZIP" "$DEPLOY_DIR/"
fi

if [ -d "$EXTRACT/$ADDONS_DIR_IN_ZIP" ]; then
  echo "=== Installing addons folder ==="
  rm -rf "$DEPLOY_DIR/$ADDONS_DIR_IN_ZIP"
  cp -r "$EXTRACT/$ADDONS_DIR_IN_ZIP" "$DEPLOY_DIR/"
fi

# Dedicated server must never ship the Rapier addon.
rm -rf "$DEPLOY_DIR/Addons/godot-rapier2d"

echo "=== Installed ==="
ls -lh "$DEPLOY_DIR/$BINARY_NAME" "$DEPLOY_DIR/$PCK_NAME"

# ── Start ─────────────────────────────────────────────────────────────────────
echo "=== Starting server ==="
panel start
echo "$TAG" > "$DEPLOY_DIR/version.txt"

echo "=== Deployment complete: $TAG ==="
