#!/bin/bash
# Install OrbStack on macOS
# This script installs OrbStack using Homebrew

set -e

install_orbstack() {
    echo "==> Checking for OrbStack installation..."

    if command -v orb &> /dev/null; then
        echo "    OrbStack is already installed"
        orb version
        return 0
    fi

    echo "==> Installing OrbStack..."

    # Check for Homebrew
    if ! command -v brew &> /dev/null; then
        echo "ERROR: Homebrew is not installed"
        echo "Please install Homebrew first: https://brew.sh"
        exit 1
    fi

    # Install OrbStack via Homebrew
    brew install --cask orbstack

    echo "==> Starting OrbStack..."
    open -a OrbStack

    # Wait for OrbStack to be ready
    echo "==> Waiting for OrbStack to initialize..."
    local max_attempts=30
    local attempt=0

    while ! command -v orb &> /dev/null; do
        attempt=$((attempt + 1))
        if [ $attempt -ge $max_attempts ]; then
            echo "ERROR: OrbStack did not start within expected time"
            echo "Please start OrbStack manually and run this script again"
            exit 1
        fi
        echo "    Waiting... ($attempt/$max_attempts)"
        sleep 2
    done

    echo "==> OrbStack installed successfully"
    orb version
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_orbstack
fi
