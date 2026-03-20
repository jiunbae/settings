#!/bin/bash
# vault-service.sh - Manage vault pull/push launchd services
#
# Usage:
#   ./vault-service.sh status          # Check both services
#   ./vault-service.sh restart         # Restart both services
#   ./vault-service.sh restart pull    # Restart pull only
#   ./vault-service.sh restart push    # Restart push only
#   ./vault-service.sh stop            # Stop both services
#   ./vault-service.sh logs            # View recent logs
#   ./vault-service.sh logs pull       # View pull logs only
#   ./vault-service.sh logs push       # View push logs only
#   ./vault-service.sh install         # Install/reinstall launchd plists

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Service registry: name:label:script:interval:logprefix
SERVICES=(
    "pull:com.jiun.vault-pull:vault-pull.py --changed-only:600:vault-pull"
    "push:com.jiun.vault-push:vault-push.py:600:vault-push"
    "context:com.jiun.claude-context-push:claude-context-push.py:1800:claude-context-push"
    "codex:com.jiun.codex-context-push:codex-context-push.py:1800:codex-context-push"
    "opencode:com.jiun.opencode-context-push:opencode-context-push.py:1800:opencode-context-push"
    "docs:com.jiun.vault-docs-sync:vault-docs-sync.py:600:vault-docs-sync"
)

_get_field() { echo "$1" | cut -d: -f"$2"; }
_plist_path() { echo "$HOME/Library/LaunchAgents/$(_get_field "$1" 2).plist"; }

show_service_status() {
    local label="$1" name="$2" logfile="$3" errfile="$4"
    echo "=== $name ==="
    if launchctl list 2>/dev/null | grep -q "$label"; then
        exit_code=$(launchctl list 2>/dev/null | grep "$label" | awk '{print $2}')
        echo "  Status: loaded (last exit: $exit_code)"
    else
        echo "  Status: not loaded"
    fi
    echo "  Recent log:"
    tail -3 "$logfile" 2>/dev/null || echo "    No logs"
    echo "  Recent errors:"
    tail -3 "$errfile" 2>/dev/null || echo "    No errors"
    echo ""
}

_find_service() {
    local target="$1"
    for svc in "${SERVICES[@]}"; do
        name=$(_get_field "$svc" 1)
        if [ "$name" = "$target" ]; then
            echo "$svc"
            return 0
        fi
    done
    return 1
}

install_plists() {
    local python_bin="/opt/homebrew/bin/python3"
    if [ ! -f "$python_bin" ]; then
        python_bin="$(which python3)"
    fi

    echo "Installing launchd plists..."
    echo "  Python: $python_bin"
    echo "  Scripts: $SCRIPT_DIR"

    for svc in "${SERVICES[@]}"; do
        name=$(_get_field "$svc" 1)
        label=$(_get_field "$svc" 2)
        script=$(_get_field "$svc" 3)
        interval=$(_get_field "$svc" 4)
        logprefix=$(_get_field "$svc" 5)
        plist=$(_plist_path "$svc")

        # Build ProgramArguments: split script field by spaces for args
        script_name="${script%% *}"
        script_args="${script#* }"
        [ "$script_args" = "$script" ] && script_args=""

        args_xml="        <string>$python_bin</string>
        <string>-u</string>
        <string>$SCRIPT_DIR/$script_name</string>"
        if [ -n "$script_args" ]; then
            args_xml="$args_xml
        <string>$script_args</string>"
        fi

        cat > "$plist" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$label</string>

    <key>ProgramArguments</key>
    <array>
$args_xml
    </array>

    <key>StartInterval</key>
    <integer>$interval</integer>

    <key>RunAtLoad</key>
    <true/>

    <key>StandardOutPath</key>
    <string>/tmp/${logprefix}.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/${logprefix}.err</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
        <key>PYTHONUNBUFFERED</key>
        <string>1</string>
    </dict>
</dict>
</plist>
PLISTEOF
        echo "  Created: $plist ($name, every ${interval}s)"
    done

    # Reload all services
    for svc in "${SERVICES[@]}"; do
        plist=$(_plist_path "$svc")
        launchctl unload "$plist" 2>/dev/null
        launchctl load "$plist"
    done
    echo ""
    echo "Services loaded. Check: $0 status"
}

_svc_names() {
    for svc in "${SERVICES[@]}"; do
        echo -n "$(_get_field "$svc" 1) "
    done
}

case "${1:-status}" in
    status)
        for svc in "${SERVICES[@]}"; do
            _name=$(_get_field "$svc" 1)
            _label=$(_get_field "$svc" 2)
            _logprefix=$(_get_field "$svc" 5)
            show_service_status "$_label" "$_name" "/tmp/${_logprefix}.log" "/tmp/${_logprefix}.err"
        done
        if [ -f "$SCRIPT_DIR/.env" ]; then
            echo "Credentials: .env found"
        else
            echo "Credentials: .env MISSING (create $SCRIPT_DIR/.env)"
        fi
        ;;

    restart)
        target="${2:-all}"
        if [ "$target" = "all" ]; then
            echo "Restarting all services..."
            for svc in "${SERVICES[@]}"; do
                plist=$(_plist_path "$svc")
                launchctl unload "$plist" 2>/dev/null
                launchctl load "$plist"
            done
        else
            svc=$(_find_service "$target") || { echo "Unknown service: $target"; echo "Available: $(_svc_names)"; exit 1; }
            plist=$(_plist_path "$svc")
            echo "Restarting $target..."
            launchctl unload "$plist" 2>/dev/null
            launchctl load "$plist"
        fi
        echo "Done. Check: $0 status"
        ;;

    stop)
        target="${2:-all}"
        if [ "$target" = "all" ]; then
            echo "Stopping all services..."
            for svc in "${SERVICES[@]}"; do
                launchctl unload "$(_plist_path "$svc")" 2>/dev/null
            done
        else
            svc=$(_find_service "$target") || { echo "Unknown service: $target"; exit 1; }
            echo "Stopping $target..."
            launchctl unload "$(_plist_path "$svc")" 2>/dev/null
        fi
        echo "Stopped."
        ;;

    logs)
        target="${2:-all}"
        if [ "$target" = "all" ]; then
            for svc in "${SERVICES[@]}"; do
                name=$(_get_field "$svc" 1)
                logprefix=$(_get_field "$svc" 5)
                echo "=== $name stdout ==="
                tail -10 "/tmp/${logprefix}.log" 2>/dev/null || echo "No logs"
                echo ""
            done
            for svc in "${SERVICES[@]}"; do
                name=$(_get_field "$svc" 1)
                logprefix=$(_get_field "$svc" 5)
                echo "=== $name stderr ==="
                tail -5 "/tmp/${logprefix}.err" 2>/dev/null || echo "No errors"
            done
        else
            svc=$(_find_service "$target") || { echo "Unknown service: $target"; exit 1; }
            logprefix=$(_get_field "$svc" 5)
            echo "=== $target stdout ==="
            tail -30 "/tmp/${logprefix}.log" 2>/dev/null || echo "No logs"
            echo ""
            echo "=== $target stderr ==="
            tail -10 "/tmp/${logprefix}.err" 2>/dev/null || echo "No errors"
        fi
        ;;

    install)
        install_plists
        ;;

    *)
        echo "Usage: $0 {status|restart|stop|logs|install} [SERVICE]"
        echo ""
        echo "  status                Check all services"
        echo "  restart [SERVICE]     Restart service(s)"
        echo "  stop [SERVICE]        Stop service(s)"
        echo "  logs [SERVICE]        View recent logs"
        echo "  install               Install/reinstall launchd plists"
        echo ""
        echo "Services: $(_svc_names)"
        exit 1
        ;;
esac
