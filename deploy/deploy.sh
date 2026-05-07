#!/bin/bash
set -euo pipefail

REMOTE="${UNFAIRD_DEPLOY_REMOTE:-}"
REMOTE_DIR="${UNFAIRD_DEPLOY_DIR:-unfaird}"

die() {
	echo "FATAL: $*" >&2
	exit 1
}

[[ $# -eq 0 ]] || die "usage: UNFAIRD_DEPLOY_REMOTE=user@host $0"
[[ -n "$REMOTE" ]] || die "set UNFAIRD_DEPLOY_REMOTE=user@host"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ssh "$REMOTE" "mkdir -p '$REMOTE_DIR'"
rsync -az --delete \
	--exclude '.build' \
	--exclude 'References' \
	./ "$REMOTE:$REMOTE_DIR/"

echo "synced to ${REMOTE}:${REMOTE_DIR}"
echo "install on remote: cd '${REMOTE_DIR}' && make install"
