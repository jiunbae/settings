#!/bin/bash
# Editable-install every package directory under a target directory.
set -uo pipefail

TARGET_DIR="${1-}"
EXCLUDE_DIRS=("_" "datasets" "iac")

if [[ -z "$TARGET_DIR" ]]; then
    echo "Usage: $(basename "$0") <directory>" >&2
    exit 2
fi

if [[ ! -d "$TARGET_DIR" ]]; then
    echo "Error: not a directory: $TARGET_DIR" >&2
    exit 2
fi

failed=0

for SUB_DIR in "$TARGET_DIR"/*; do
    [[ -d "$SUB_DIR" ]] || continue

    BASENAME=$(basename "$SUB_DIR")
    # Literal membership test; =~ against a quoted RHS matches as a regex, so a
    # directory name holding a metacharacter was excluded or kept wrongly.
    if [[ " ${EXCLUDE_DIRS[*]} " == *" $BASENAME "* ]]; then
        continue
    fi

    echo "Installing $BASENAME..."
    if pip install -e "$SUB_DIR"; then
        echo "> $BASENAME installed successfully."
    else
        echo "> Failed to install $BASENAME." >&2
        failed=$((failed + 1))
    fi
done

if (( failed > 0 )); then
    echo "$failed package(s) failed to install." >&2
    exit 1
fi
