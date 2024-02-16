#!/bin/bash

export ACMEDNS_UPDATE_URL="https://auth.acme-dns.io/update"
export ACMEDNS_USERNAME="REDACTED_USERNAME"
export ACMEDNS_PASSWORD="REDACTED_PASSWORD"
export ACMEDNS_SUBDOMAIN="REDACTED_SUBDOMAIN"

certs_src_dir="/usr/syno/etc/certificate/system/default"

/usr/local/share/acme.sh/acme.sh --renew --force --dns dns_acmedns \
	-d "*.example.com" \
	--cert-file $certs_src_dir/cert.pem \
	--key-file $certs_src_dir/privkey.pem \
	--ca-file $certs_src_dir/chain.pem \
	--fullchain-file $certs_src_dir/fullchain.pem \
	--reloadcmd "synosystemctl reload nginx" \
	--server letsencrypt

DEBUG=  # Set to any non-empty value to turn on debug mode
error_exit() { echo "[ERROR] $1"; exit 1; }
warn() { echo "[WARN ] $1"; }
info() { echo "[INFO ] $1"; }
debug() { [[ "${DEBUG}" ]] && echo "[DEBUG ] $1"; }

# 1. Initialization
# =================
[[ "$EUID" -ne 0 ]] && error_exit "Please run as root"  # Script only works as root


services_to_restart=("avahi" "nginx")
packages_to_restart=("ScsiTarget" "SynologyDrive" "WebDAVServer" "ActiveBackup")
target_cert_dirs=(
    "/usr/syno/etc/certificate/system/FQDN"
    "/usr/local/etc/certificate/ScsiTarget/pkg-scsi-plugin-server/"
    "/usr/local/etc/certificate/SynologyDrive/SynologyDrive/"
    "/usr/local/etc/certificate/WebDAVServer/webdav/"
    "/usr/local/etc/certificate/ActiveBackup/ActiveBackup/"
    "/usr/syno/etc/certificate/smbftpd/ftpd/"
    "/volume1/Workspace/.cert"
    "/volume1/docker/shared/.cert"
    )

# Add the default directory
default_dir_name=$(</usr/syno/etc/certificate/_archive/DEFAULT)
if [[ -n "$default_dir_name" ]]; then
    target_cert_dirs+=("/usr/syno/etc/certificate/_archive/${default_dir_name}")
    debug "Default cert directory found: '/usr/syno/etc/certificate/_archive/${default_dir_name}'"
else
    warn "No default directory found. Probably unusual? Check: 'cat /usr/syno/etc/certificate/_archive/DEFAULT'"
fi

# Add reverse proxy app directories
for proxy in /usr/syno/etc/certificate/ReverseProxy/*/; do
    debug "Found proxy dir: ${proxy}"
    target_cert_dirs+=("${proxy}")
done

[[ "${DEBUG}" ]] && set -x

# 2. Move and chown certificates from /tmp to default directory
# =============================================================
chown root:root "${certs_src_dir}/"{privkey,chain,fullchain,cert}.pem || error_exit "Halting because of error chowning files"
info "Certs moved from /tmp & chowned."

# 3. Copy certificates to target directories if they exist
# ========================================================
for target_dir in "${target_cert_dirs[@]}"; do
    if [[ ! -d "$target_dir" ]]; then
      debug "Target cert directory '$target_dir' not found, skipping..."
      continue
    fi

    info "Copying certificates to '$target_dir'"
    if ! (cp "${certs_src_dir}/"{privkey,chain,fullchain,cert}.pem "$target_dir/" && \
        chown root:root "$target_dir/"{privkey,chain,fullchain,cert}.pem); then
          warn "Error copying or chowning certs to ${target_dir}"
    fi
done

# 4. Restart services & packages
# ==============================
info "Rebooting all the things..."
for service in "${services_to_restart[@]}"; do
    /usr/syno/bin/synosystemctl restart "$service"
done
for package in "${packages_to_restart[@]}"; do  # Restart packages that are installed & turned on
    /usr/syno/bin/synopkg is_onoff "$package" 1>/dev/null && /usr/syno/bin/synopkg restart "$package"
done

# Faster ngnix restart (if certs don't appear to be refreshing, change to synosystemctl
if ! (/usr/syno/bin/synow3tool --gen-all && sudo systemctl reload nginx); then
    warn "nginx failed to restart"
fi
/usr/syno/bin/synosystemctl restart nginx

info "Completed"
