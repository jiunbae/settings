#!/bin/bash
# Create Linux VM using OrbStack
# This script creates an Ubuntu ARM64 VM for k3s worker node

set -e

# Default values
DEFAULT_VM_NAME="k3s-worker"
DEFAULT_UBUNTU_VERSION="22.04"

create_vm() {
    local vm_name="${VM_NAME:-$DEFAULT_VM_NAME}"
    local ubuntu_version="${UBUNTU_VERSION:-$DEFAULT_UBUNTU_VERSION}"

    echo "==> Creating Linux VM: $vm_name"

    # Check if OrbStack is available
    if ! command -v orb &> /dev/null; then
        echo "ERROR: OrbStack is not installed or not in PATH"
        exit 1
    fi

    # Check if VM already exists
    if orb list 2>/dev/null | grep -q "^$vm_name"; then
        echo "    VM '$vm_name' already exists"

        # Check if VM is running
        if orb list 2>/dev/null | grep "^$vm_name" | grep -q "running"; then
            echo "    VM is already running"
        else
            echo "==> Starting existing VM..."
            orb start "$vm_name"
        fi
        return 0
    fi

    echo "==> Creating Ubuntu $ubuntu_version VM..."
    orb create "ubuntu:$ubuntu_version" "$vm_name"

    echo "==> Waiting for VM to be ready..."
    sleep 5

    # Verify VM is running
    if ! orb list 2>/dev/null | grep "^$vm_name" | grep -q "running"; then
        echo "ERROR: VM failed to start"
        exit 1
    fi

    echo "==> Installing essential packages in VM..."
    orb -m "$vm_name" sudo apt-get update
    orb -m "$vm_name" sudo apt-get install -y \
        curl \
        wget \
        ca-certificates \
        apt-transport-https \
        gnupg \
        lsb-release

    echo "==> VM '$vm_name' created successfully"
    echo "    Access VM: orb shell $vm_name"
}

get_vm_ip() {
    local vm_name="${VM_NAME:-$DEFAULT_VM_NAME}"

    # Get VM IP address
    local ip
    ip=$(orb -m "$vm_name" hostname -I 2>/dev/null | awk '{print $1}')

    if [ -z "$ip" ]; then
        echo "ERROR: Could not determine VM IP address"
        exit 1
    fi

    echo "$ip"
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    create_vm
fi
