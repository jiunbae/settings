#!/bin/bash
# Configure network for K3s worker VM
# Handles NAT and bridge network modes

set -e

configure_network() {
    local vm_name="${VM_NAME:-k3s-worker}"
    local network_mode="${NETWORK_MODE:-nat}"

    echo "==> Configuring network (mode: $network_mode)..."

    case "$network_mode" in
        nat)
            configure_nat_network "$vm_name"
            ;;
        bridge)
            configure_bridge_network "$vm_name"
            ;;
        *)
            echo "ERROR: Unknown network mode: $network_mode"
            echo "Supported modes: nat, bridge"
            exit 1
            ;;
    esac
}

configure_nat_network() {
    local vm_name="$1"

    echo "==> Using NAT network mode"
    echo "    VM will communicate with K3s master through OrbStack's NAT"

    # Get VM's internal IP
    local vm_ip
    vm_ip=$(orb -m "$vm_name" hostname -I 2>/dev/null | awk '{print $1}')

    echo "    VM IP (internal): $vm_ip"

    # Test connectivity to K3s master
    echo "==> Testing connectivity to K3s master..."
    if orb -m "$vm_name" curl -sk --connect-timeout 5 "${K3S_URL}/healthz" &>/dev/null; then
        echo "    K3s master is reachable"
    else
        echo "WARNING: Cannot reach K3s master at ${K3S_URL}"
        echo "    This might be expected if K3s master is on a different network"
        echo "    You may need to configure routing or use bridge mode"
    fi
}

configure_bridge_network() {
    local vm_name="$1"

    echo "==> Configuring bridge network mode"
    echo "WARNING: Bridge mode requires additional macOS configuration"

    # Bridge mode in OrbStack requires manual network configuration
    # This is a placeholder for future implementation

    cat << 'EOF'

Bridge mode setup instructions:

1. OrbStack uses macOS Virtualization.framework which has limited
   bridge networking support compared to traditional VMs.

2. For full bridge networking, consider these alternatives:

   Option A: Use host network routing
   - Add a route on your router to forward traffic to OrbStack's subnet
   - OrbStack subnet is typically 198.19.x.x or similar

   Option B: Use SSH port forwarding
   - Forward required K3s ports through SSH tunnel

   Option C: Use Tailscale/ZeroTier
   - Install Tailscale in the VM for overlay networking
   - This provides seamless connectivity across networks

3. For now, NAT mode with proper routing is recommended.

EOF

    if [ -n "$VM_STATIC_IP" ]; then
        echo "Static IP configuration requested: $VM_STATIC_IP"
        echo "Note: Static IP in OrbStack requires manual netplan configuration"
    fi
}

setup_tailscale() {
    local vm_name="${VM_NAME:-k3s-worker}"

    echo "==> Installing Tailscale in VM for overlay networking..."

    orb -m "$vm_name" bash -c 'curl -fsSL https://tailscale.com/install.sh | sh'

    echo "==> Tailscale installed. Run 'sudo tailscale up' in VM to authenticate"
    echo "    Then use Tailscale IP for K3s communication"
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    configure_network
fi
