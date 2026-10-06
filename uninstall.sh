#!/bin/bash
# Removes Stash.app. Pass --purge to delete the clipboard history as well.
set -euo pipefail

SUPPORT="$HOME/Library/Application Support/Stash"

pkill -x Stash 2>/dev/null || true
sleep 1
rm -rf /Applications/Stash.app
echo "removed  /Applications/Stash.app"
echo "note     if you had Open at Login on, remove Stash from"
echo "         System Settings > General > Login Items"

if [[ "${1:-}" == "--purge" ]]; then
    rm -rf "$SUPPORT"
    echo "removed  $SUPPORT"
else
    echo "kept     $SUPPORT  (pass --purge to delete your clip history too)"
fi
