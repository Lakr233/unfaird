#!/bin/bash
set -euo pipefail

LABEL="wiki.qaq.unfaird"
PLIST_SOURCE="$(cd "$(dirname "$0")" && pwd)/launchd/${LABEL}.plist"
PLIST_DEST="/Library/LaunchDaemons/${LABEL}.plist"
INSTALL_DIR="/usr/local/lib/unfaird"

die() {
	echo "FATAL: $*" >&2
	exit 1
}

[[ "$(uname)" == "Darwin" ]] || die "macOS required"
[[ -x ".build/release/UnfairDaemon" ]] || die ".build/release/UnfairDaemon missing"
[[ -f "$PLIST_SOURCE" ]] || die "plist missing: $PLIST_SOURCE"

sudo install -d -m 755 "$INSTALL_DIR"
sudo rm -f "${INSTALL_DIR}/unfaird" "${INSTALL_DIR}/unfair-runner"
sudo install -m 755 ".build/release/UnfairDaemon" "${INSTALL_DIR}/UnfairDaemon"
sudo install -d -m 700 -o root -g wheel "/var/tmp/unfaird/jobs"
sudo install -d -m 700 -o root -g wheel "/var/tmp/unfaird/logs"
sudo install -m 644 "$PLIST_SOURCE" "$PLIST_DEST"
sudo chown root:wheel "$PLIST_DEST"

sudo launchctl bootout "system/${LABEL}" 2>/dev/null || true
sudo launchctl enable "system/${LABEL}" 2>/dev/null || true
sudo launchctl bootstrap system "$PLIST_DEST"
sudo launchctl enable "system/${LABEL}"
sudo launchctl kickstart -k "system/${LABEL}"
sudo launchctl print "system/${LABEL}" >/dev/null

echo "${LABEL} installed and running"
