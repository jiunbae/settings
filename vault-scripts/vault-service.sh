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

PULL_PLIST="$HOME/Library/LaunchAgents/com.jiun.vault-pull.plist"
PUSH_PLIST="$HOME/Library/LaunchAgents/com.jiun.vault-push.plist"
CONTEXT_PLIST="$HOME/Library/LaunchAgents/com.jiun.claude-context-push.plist"
PULL_LABEL="com.jiun.vault-pull"
PUSH_LABEL="com.jiun.vault-push"
CONTEXT_LABEL="com.jiun.claude-context-push"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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

install_plists() {
    local python_bin="/opt/homebrew/bin/python3"
    if [ ! -f "$python_bin" ]; then
        python_bin="$(which python3)"
    fi

    echo "Installing launchd plists..."
    echo "  Python: $python_bin"
    echo "  Scripts: $SCRIPT_DIR"

    # Pull plist
    cat > "$PULL_PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$PULL_LABEL</string>
    <key>Comment</key>
    <string>Pull vault changes from CouchDB (every 10 minutes)</string>

    <key>ProgramArguments</key>
    <array>
        <string>$python_bin</string>
        <string>-u</string>
        <string>$SCRIPT_DIR/vault-pull.py</string>
        <string>--changed-only</string>
    </array>

    <key>StartInterval</key>
    <integer>600</integer>

    <key>RunAtLoad</key>
    <true/>

    <key>StandardOutPath</key>
    <string>/tmp/vault-pull.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/vault-pull.err</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
        <key>PYTHONUNBUFFERED</key>
        <string>1</string>
    </dict>
</dict>
</plist>
EOF
    echo "  Created: $PULL_PLIST"

    # Push plist (runs 5 min after pull)
    cat > "$PUSH_PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$PUSH_LABEL</string>
    <key>Comment</key>
    <string>Push vault changes to CouchDB (every 10 minutes)</string>

    <key>ProgramArguments</key>
    <array>
        <string>$python_bin</string>
        <string>-u</string>
        <string>$SCRIPT_DIR/vault-push.py</string>
    </array>

    <key>StartInterval</key>
    <integer>600</integer>

    <key>RunAtLoad</key>
    <true/>

    <key>StandardOutPath</key>
    <string>/tmp/vault-push.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/vault-push.err</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
        <key>PYTHONUNBUFFERED</key>
        <string>1</string>
    </dict>
</dict>
</plist>
EOF
    echo "  Created: $PUSH_PLIST"

    # Claude context push plist (runs every 30 min)
    cat > "$CONTEXT_PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$CONTEXT_LABEL</string>
    <key>Comment</key>
    <string>Push Claude session context to CouchDB (every 30 minutes)</string>

    <key>ProgramArguments</key>
    <array>
        <string>$python_bin</string>
        <string>-u</string>
        <string>$SCRIPT_DIR/claude-context-push.py</string>
    </array>

    <key>StartInterval</key>
    <integer>1800</integer>

    <key>RunAtLoad</key>
    <true/>

    <key>StandardOutPath</key>
    <string>/tmp/claude-context-push.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/claude-context-push.err</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
        <key>PYTHONUNBUFFERED</key>
        <string>1</string>
    </dict>
</dict>
</plist>
EOF
    echo "  Created: $CONTEXT_PLIST"

    # Load services
    launchctl unload "$PULL_PLIST" 2>/dev/null
    launchctl unload "$PUSH_PLIST" 2>/dev/null
    launchctl unload "$CONTEXT_PLIST" 2>/dev/null
    launchctl load "$PULL_PLIST"
    launchctl load "$PUSH_PLIST"
    launchctl load "$CONTEXT_PLIST"
    echo ""
    echo "Services loaded. Check: $0 status"
}

case "${1:-status}" in
    status)
        show_service_status "$PULL_LABEL" "Vault Pull" /tmp/vault-pull.log /tmp/vault-pull.err
        show_service_status "$PUSH_LABEL" "Vault Push" /tmp/vault-push.log /tmp/vault-push.err
        show_service_status "$CONTEXT_LABEL" "Claude Context Push" /tmp/claude-context-push.log /tmp/claude-context-push.err

        # .env check
        if [ -f "$SCRIPT_DIR/.env" ]; then
            echo "Credentials: .env found"
        else
            echo "Credentials: .env MISSING (create $SCRIPT_DIR/.env)"
        fi
        ;;

    restart)
        case "${2:-all}" in
            pull)
                echo "Restarting vault-pull..."
                launchctl unload "$PULL_PLIST" 2>/dev/null
                launchctl load "$PULL_PLIST"
                ;;
            push)
                echo "Restarting vault-push..."
                launchctl unload "$PUSH_PLIST" 2>/dev/null
                launchctl load "$PUSH_PLIST"
                ;;
            context)
                echo "Restarting claude-context-push..."
                launchctl unload "$CONTEXT_PLIST" 2>/dev/null
                launchctl load "$CONTEXT_PLIST"
                ;;
            all|*)
                echo "Restarting all services..."
                launchctl unload "$PULL_PLIST" 2>/dev/null
                launchctl unload "$PUSH_PLIST" 2>/dev/null
                launchctl unload "$CONTEXT_PLIST" 2>/dev/null
                launchctl load "$PULL_PLIST"
                launchctl load "$PUSH_PLIST"
                launchctl load "$CONTEXT_PLIST"
                ;;
        esac
        echo "Done. Check: $0 status"
        ;;

    stop)
        case "${2:-all}" in
            pull)
                echo "Stopping vault-pull..."
                launchctl unload "$PULL_PLIST" 2>/dev/null
                ;;
            push)
                echo "Stopping vault-push..."
                launchctl unload "$PUSH_PLIST" 2>/dev/null
                ;;
            context)
                echo "Stopping claude-context-push..."
                launchctl unload "$CONTEXT_PLIST" 2>/dev/null
                ;;
            all|*)
                echo "Stopping all services..."
                launchctl unload "$PULL_PLIST" 2>/dev/null
                launchctl unload "$PUSH_PLIST" 2>/dev/null
                launchctl unload "$CONTEXT_PLIST" 2>/dev/null
                ;;
        esac
        echo "Stopped."
        ;;

    logs)
        case "${2:-all}" in
            pull)
                echo "=== Pull stdout ==="
                tail -30 /tmp/vault-pull.log 2>/dev/null || echo "No logs"
                echo ""
                echo "=== Pull stderr ==="
                tail -10 /tmp/vault-pull.err 2>/dev/null || echo "No errors"
                ;;
            push)
                echo "=== Push stdout ==="
                tail -30 /tmp/vault-push.log 2>/dev/null || echo "No logs"
                echo ""
                echo "=== Push stderr ==="
                tail -10 /tmp/vault-push.err 2>/dev/null || echo "No errors"
                ;;
            context)
                echo "=== Claude Context Push stdout ==="
                tail -30 /tmp/claude-context-push.log 2>/dev/null || echo "No logs"
                echo ""
                echo "=== Claude Context Push stderr ==="
                tail -10 /tmp/claude-context-push.err 2>/dev/null || echo "No errors"
                ;;
            all|*)
                echo "=== Pull stdout ==="
                tail -15 /tmp/vault-pull.log 2>/dev/null || echo "No logs"
                echo ""
                echo "=== Push stdout ==="
                tail -15 /tmp/vault-push.log 2>/dev/null || echo "No logs"
                echo ""
                echo "=== Claude Context Push stdout ==="
                tail -15 /tmp/claude-context-push.log 2>/dev/null || echo "No logs"
                echo ""
                echo "=== Errors (pull) ==="
                tail -5 /tmp/vault-pull.err 2>/dev/null || echo "No errors"
                echo "=== Errors (push) ==="
                tail -5 /tmp/vault-push.err 2>/dev/null || echo "No errors"
                echo "=== Errors (context) ==="
                tail -5 /tmp/claude-context-push.err 2>/dev/null || echo "No errors"
                ;;
        esac
        ;;

    install)
        install_plists
        ;;

    *)
        echo "Usage: $0 {status|restart|stop|logs|install} [pull|push|context]"
        echo ""
        echo "  status                       Check all services"
        echo "  restart [pull|push|context]  Restart service(s)"
        echo "  stop [pull|push|context]     Stop service(s)"
        echo "  logs [pull|push|context]     View recent logs"
        echo "  install                      Install/reinstall launchd plists"
        exit 1
        ;;
esac
