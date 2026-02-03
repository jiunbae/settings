#!/bin/bash
#
# vault-sync-machines.sh - Sync Obsidian vault between machines via rsync
#
# Usage:
#     ./vault-sync-machines.sh              # Sync to all machines
#     ./vault-sync-machines.sh june-mbp     # Sync to specific machine
#     ./vault-sync-machines.sh --dry-run    # Preview changes
#
# Syncs: articles/, workspace/, workspace-vibe/, workspace-ext/, Notes/, TaskManager/

set -euo pipefail

VAULT_ROOT="$HOME/s-lastorder"
SYNC_DIRS=(
    "articles"
    "workspace"
    "workspace-vibe"
    "workspace-ext"
    "Notes"
    "TaskManager"
)

# Target machines (SSH hosts from ~/.ssh/config)
MACHINES=(
    "june-mbp"
    "jiun-mbp"
)

# Rsync options
RSYNC_OPTS=(
    -avz
    --progress
    --delete
    --exclude='.DS_Store'
    --exclude='.git/'
    --exclude='node_modules/'
    --exclude='__pycache__/'
)

DRY_RUN=""
TARGET_MACHINE=""

# Parse arguments
for arg in "$@"; do
    case $arg in
        --dry-run)
            DRY_RUN="--dry-run"
            echo "[DRY RUN] No changes will be made"
            ;;
        *)
            TARGET_MACHINE="$arg"
            ;;
    esac
done

# Determine which machines to sync
if [[ -n "$TARGET_MACHINE" ]]; then
    MACHINES=("$TARGET_MACHINE")
fi

echo "============================================================"
echo "Vault Sync - Machine to Machine"
echo "============================================================"
echo "Source: $VAULT_ROOT"
echo "Targets: ${MACHINES[*]}"
echo ""

for machine in "${MACHINES[@]}"; do
    echo "------------------------------------------------------------"
    echo "Syncing to: $machine"
    echo "------------------------------------------------------------"

    # Check if machine is reachable
    if ! ssh -o ConnectTimeout=5 "$machine" "echo 'Connected'" &>/dev/null; then
        echo "  [SKIP] $machine is not reachable"
        continue
    fi

    for dir in "${SYNC_DIRS[@]}"; do
        src="$VAULT_ROOT/$dir/"

        # Skip if source doesn't exist
        if [[ ! -d "$src" ]]; then
            continue
        fi

        echo ""
        echo "  Syncing $dir/"

        # Create target directory if needed
        ssh "$machine" "mkdir -p ~/s-lastorder/$dir"

        # Rsync
        rsync "${RSYNC_OPTS[@]}" $DRY_RUN "$src" "$machine:~/s-lastorder/$dir/"
    done

    echo ""
    echo "  [DONE] $machine synced"
done

echo ""
echo "============================================================"
echo "Sync complete"
echo "============================================================"
