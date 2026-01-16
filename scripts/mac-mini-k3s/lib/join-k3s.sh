#!/bin/bash
# Join K3s cluster as worker node
# This script installs k3s agent and joins the existing cluster

set -e

join_k3s_cluster() {
    local vm_name="${VM_NAME:-k3s-worker}"
    local k3s_url="${K3S_URL}"
    local k3s_token="${K3S_TOKEN}"
    local node_name="${NODE_NAME:-$vm_name}"
    local node_env="${NODE_ENV:-dev}"
    local node_purpose="${NODE_PURPOSE:-general}"
    local extra_args="${K3S_EXTRA_ARGS:-}"

    # Validate required parameters
    if [ -z "$k3s_url" ]; then
        echo "ERROR: K3S_URL is not set"
        exit 1
    fi

    if [ -z "$k3s_token" ]; then
        echo "ERROR: K3S_TOKEN is not set"
        echo "Get token from master: sudo cat /var/lib/rancher/k3s/server/node-token"
        exit 1
    fi

    echo "==> Joining K3s cluster as worker node"
    echo "    K3s URL: $k3s_url"
    echo "    Node name: $node_name"
    echo "    Environment: $node_env"
    echo "    Purpose: $node_purpose"

    # Check if k3s is already installed
    if orb -m "$vm_name" command -v k3s &>/dev/null; then
        echo "==> K3s is already installed in VM"

        if orb -m "$vm_name" sudo systemctl is-active k3s-agent &>/dev/null; then
            echo "    K3s agent is already running"
            return 0
        else
            echo "==> Starting existing K3s agent..."
            orb -m "$vm_name" sudo systemctl start k3s-agent
            return 0
        fi
    fi

    # Build k3s install command
    local install_cmd="curl -sfL https://get.k3s.io | "
    install_cmd+="K3S_URL='${k3s_url}' "
    install_cmd+="K3S_TOKEN='${k3s_token}' "
    install_cmd+="INSTALL_K3S_EXEC='agent "
    install_cmd+="--node-name=${node_name} "
    install_cmd+="--node-label=env=${node_env} "
    install_cmd+="--node-label=purpose=${node_purpose} "
    install_cmd+="--node-label=kubernetes.io/arch=arm64 "

    # Add extra args if provided
    if [ -n "$extra_args" ]; then
        install_cmd+="${extra_args} "
    fi

    install_cmd+="' sh -"

    echo "==> Installing K3s agent in VM..."
    orb -m "$vm_name" bash -c "$install_cmd"

    # Wait for k3s agent to start
    echo "==> Waiting for K3s agent to start..."
    local max_attempts=30
    local attempt=0

    while ! orb -m "$vm_name" sudo systemctl is-active k3s-agent &>/dev/null; do
        attempt=$((attempt + 1))
        if [ $attempt -ge $max_attempts ]; then
            echo "ERROR: K3s agent did not start"
            echo "Check logs: orb -m $vm_name sudo journalctl -u k3s-agent -f"
            exit 1
        fi
        echo "    Waiting... ($attempt/$max_attempts)"
        sleep 2
    done

    echo "==> K3s agent started successfully"
    echo "    Check node status: kubectl get nodes"
}

verify_join() {
    local vm_name="${VM_NAME:-k3s-worker}"
    local node_name="${NODE_NAME:-$vm_name}"

    echo "==> Verifying K3s agent status..."

    # Check k3s-agent service
    if orb -m "$vm_name" sudo systemctl is-active k3s-agent &>/dev/null; then
        echo "    K3s agent service: running"
    else
        echo "    K3s agent service: not running"
        echo "    Check logs: orb -m $vm_name sudo journalctl -u k3s-agent"
        return 1
    fi

    # Show recent logs
    echo "==> Recent K3s agent logs:"
    orb -m "$vm_name" sudo journalctl -u k3s-agent --no-pager -n 10

    echo ""
    echo "==> To verify from K3s master, run:"
    echo "    kubectl get nodes"
    echo "    kubectl get nodes -l env=${NODE_ENV:-dev}"
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    join_k3s_cluster
    verify_join
fi
