#!/bin/bash

TARGET_DIR="$1"
EXCLUDE_DIRS=("_" "datasets" "iac")

for SUB_DIR in "$TARGET_DIR"/*; do
    if [ -d "$SUB_DIR" ]; then
        BASENAME=$(basename "$SUB_DIR")
        if [[ ! " ${EXCLUDE_DIRS[@]} " =~ " $BASENAME " ]]; then
            echo "Installing $BASENAME..."
            if pip install -e "$SUB_DIR" > /dev/null 2>&1; then
                echo "> $BASENAME installed successfully."
            else
                echo "> Failed to install $BASENAME."
            fi
        fi
    fi
done