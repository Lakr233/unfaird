#!/bin/bash
set -euo pipefail

LABEL="wiki.qaq.unfaird"
PLIST_DEST="/Library/LaunchDaemons/${LABEL}.plist"
INSTALL_DIR="/usr/local/lib/unfaird"
DATA_DIR="/var/tmp/unfaird"

sudo launchctl bootout "system/${LABEL}" 2>/dev/null || true
sudo launchctl enable "system/${LABEL}" 2>/dev/null || true
sudo rm -f "$PLIST_DEST"

sudo rm -rf "$INSTALL_DIR"
sudo rm -rf "$DATA_DIR"

echo "${LABEL} uninstalled"
