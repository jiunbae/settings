#!/bin/bash
# macos.sh - macOS system preferences: keyboard, shortcuts, Finder, menu bar, power
# Can be run standalone or sourced by install.sh

# ==============================================================================
# Standalone execution support
# ==============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/../lib/core.sh"
    source "$SCRIPT_DIR/../lib/platform.sh"
    detect_platform
fi

# ==============================================================================
# Configuration
#
# Every value here was captured from a working machine (june-mbp); what each
# one does and why is documented in docs/macos.md. Writes go through
# _macos_default, which reads first and only writes on a difference, so a
# re-run reports "already set" instead of touching the preference store.
#
# Deliberately NOT managed: screenshot location, language/region, Siri,
# privacy (TCC) grants — see docs/macos.md.
# ==============================================================================
readonly MACOS_KEYBINDINGS_DIR="$HOME/Library/KeyBindings"
readonly MACOS_LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
readonly MACOS_CAPSLOCK_LABEL="dev.jiun.capslock-to-control"
readonly MACOS_ACTIVATE_SETTINGS="/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings"

# Caps Lock (HID usage 0x39) -> Control. 0xE4 is what System Settings writes
# for "Control" in its per-keyboard modifier mapping.
readonly MACOS_CAPSLOCK_MAPPING='{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x7000000E4}]}'

# "domain|key|type|value" — domain "-g" is NSGlobalDomain; a "host:" prefix
# writes to -currentHost.
readonly MACOS_KEYBOARD_DEFAULTS=(
    "-g|KeyRepeat|int|1"
    "-g|InitialKeyRepeat|int|11"
    "-g|ApplePressAndHoldEnabled|bool|false"
    "-g|com.apple.keyboard.fnState|bool|true"
    "-g|AppleKeyboardUIMode|int|1"
    "-g|NSAutomaticCapitalizationEnabled|bool|true"
    "-g|NSAutomaticDashSubstitutionEnabled|bool|false"
    "-g|NSAutomaticPeriodSubstitutionEnabled|bool|false"
    "-g|NSAutomaticQuoteSubstitutionEnabled|bool|false"
    "-g|NSAutomaticSpellingCorrectionEnabled|bool|false"
    "-g|WebAutomaticSpellingCorrectionEnabled|bool|false"
    "-g|TISRomanSwitchState|int|0"
)

readonly MACOS_UI_DEFAULTS=(
    "-g|AppleShowAllExtensions|bool|true"
    "-g|AppleShowScrollBars|string|WhenScrolling"
    "-g|NSQuitAlwaysKeepsWindows|bool|true"
    "host:-g|NSStatusItemSpacing|int|6"
    "host:-g|NSStatusItemSelectionPadding|int|12"
)

# Set by _macos_default when anything changed, so services are only restarted
# when there is something for them to pick up.
_MACOS_UI_CHANGED=false
_MACOS_KEYS_CHANGED=false

# ==============================================================================
# Helpers
# ==============================================================================

# _macos_default <domain> <key> <type> <value>  — returns 0 if it wrote
_macos_default() {
    local domain=$1 key=$2 type=$3 value=$4
    local host_flag=()
    if [[ "$domain" == host:* ]]; then
        host_flag=(-currentHost)
        domain=${domain#host:}
    fi

    local want=$value current
    [[ "$type" == "bool" ]] && { [[ "$value" == "true" ]] && want=1 || want=0; }
    current=$(defaults ${host_flag[@]+"${host_flag[@]}"} read "$domain" "$key" 2>/dev/null) || current="<unset>"

    if [[ "$current" == "$want" ]]; then
        log_debug "already set: $domain $key = $value"
        return 1
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would set $domain $key: $current -> $value"
        return 0
    fi

    # ${arr[@]+...} keeps bash 3.2 (macOS /bin/bash) happy under set -u
    defaults ${host_flag[@]+"${host_flag[@]}"} write "$domain" "$key" "-$type" "$value"
    log_info "Set $domain $key: $current -> $value"
    return 0
}

_macos_apply_list() {
    local changed=1 entry domain key type value
    for entry in "$@"; do
        IFS='|' read -r domain key type value <<< "$entry"
        _macos_default "$domain" "$key" "$type" "$value" && changed=0
    done
    return $changed
}

# ==============================================================================
# Installation Functions
# ==============================================================================

install_macos_keyboard() {
    print_section "Keyboard preferences"

    if _macos_apply_list "${MACOS_KEYBOARD_DEFAULTS[@]}"; then
        _MACOS_KEYS_CHANGED=true
        track_installed "Keyboard preferences"
    else
        log_info "Keyboard preferences already set"
        track_skipped "Keyboard preferences"
    fi
}

install_macos_shortcuts() {
    print_section "System keyboard shortcuts"

    local root_dir
    root_dir=$(get_root_dir)
    local table="$root_dir/configs/macos/symbolichotkeys.tsv"

    # plistlib compares the live dictionary entry by entry; only entries that
    # differ are written, each as a single -dict-add so every other shortcut
    # on the machine is left alone.
    local changes
    changes=$(python3 - "$table" <<'PY'
import plistlib, subprocess, sys

raw = subprocess.run(["defaults", "export", "com.apple.symbolichotkeys", "-"],
                     capture_output=True).stdout
current = plistlib.loads(raw).get("AppleSymbolicHotKeys", {}) if raw else {}

for line in open(sys.argv[1], encoding="utf-8"):
    if not line.strip() or line.startswith("#"):
        continue
    hid, enabled, params = line.rstrip("\n").split("\t")[:3]
    want = {"enabled": enabled == "1"}
    xml = "<dict><key>enabled</key><%s/>" % ("true" if want["enabled"] else "false")
    if params:
        nums = [int(p) for p in params.split(",")]
        want["value"] = {"parameters": nums, "type": "standard"}
        xml += ("<key>value</key><dict><key>parameters</key><array>"
                + "".join("<integer>%d</integer>" % n for n in nums)
                + "</array><key>type</key><string>standard</string></dict>")
    xml += "</dict>"
    if current.get(hid) != want:
        print("%s\t%s" % (hid, xml))
PY
    ) || { log_error "Could not read com.apple.symbolichotkeys"; return 1; }

    if [[ -z "$changes" ]]; then
        log_info "System shortcuts already match $table"
        track_skipped "System keyboard shortcuts"
        return 0
    fi

    local count
    count=$(printf '%s\n' "$changes" | wc -l | tr -d ' ')
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would update $count system shortcut(s)"
        return 0
    fi

    local hid xml
    while IFS=$'\t' read -r hid xml; do
        defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add "$hid" "$xml"
    done <<< "$changes"

    _MACOS_KEYS_CHANGED=true
    track_installed "System keyboard shortcuts ($count updated)"
    log_success "Updated $count system shortcut(s)"
}

install_macos_keybindings() {
    print_section "Cocoa text key bindings"

    local root_dir
    root_dir=$(get_root_dir)
    local source="$root_dir/configs/macos/DefaultKeyBinding.dict"
    local target="$MACOS_KEYBINDINGS_DIR/DefaultKeyBinding.dict"

    # Copy mode compares contents; otherwise every re-run would back up and
    # recopy an identical file.
    if [[ "$LINK_MODE" == "copy" ]]; then
        if [[ -f "$target" && ! -L "$target" ]] && cmp -s "$source" "$target"; then
            log_info "DefaultKeyBinding.dict already up to date"
            track_skipped "DefaultKeyBinding.dict"
            return 0
        fi
    elif [[ -L "$target" && "$(readlink "$target")" == "$source" ]]; then
        log_info "DefaultKeyBinding.dict already linked"
        track_skipped "DefaultKeyBinding.dict"
        return 0
    fi

    FORCE=true backup_and_link "$source" "$target"
    track_installed "DefaultKeyBinding.dict"
    log_info "Apps pick up DefaultKeyBinding.dict when they are relaunched"
}

install_macos_capslock() {
    print_section "Caps Lock -> Control"

    local plist="$MACOS_LAUNCH_AGENTS_DIR/$MACOS_CAPSLOCK_LABEL.plist"
    local tmp
    tmp=$(mktemp)

    # hidutil mappings do not survive a reboot, so a LaunchAgent re-applies it
    # at login. Unlike System Settings' per-keyboard mapping this covers every
    # keyboard, including ones that have never been connected before.
    # launchd will not load a symlinked plist, so it is written, not linked.
    cat > "$tmp" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$MACOS_CAPSLOCK_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/hidutil</string>
        <string>property</string>
        <string>--set</string>
        <string>$MACOS_CAPSLOCK_MAPPING</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOF

    if [[ -f "$plist" ]] && cmp -s "$tmp" "$plist"; then
        rm -f "$tmp"
        log_info "Caps Lock LaunchAgent already installed"
        track_skipped "Caps Lock -> Control"
    elif [[ "$DRY_RUN" == "true" ]]; then
        rm -f "$tmp"
        log_info "[DRY-RUN] Would install $plist and remap Caps Lock"
        return 0
    else
        mkdir -p "$MACOS_LAUNCH_AGENTS_DIR"
        mv "$tmp" "$plist"
        launchctl bootout "gui/$(id -u)/$MACOS_CAPSLOCK_LABEL" 2>/dev/null || true
        launchctl bootstrap "gui/$(id -u)" "$plist" 2>/dev/null || true
        track_installed "Caps Lock -> Control"
        log_success "Installed $plist"
    fi

    # Apply now as well; bootstrap alone may race the first keypress.
    [[ "$DRY_RUN" == "true" ]] || /usr/bin/hidutil property --set "$MACOS_CAPSLOCK_MAPPING" >/dev/null
}

install_macos_ui() {
    print_section "Finder, windows and menu bar"

    if _macos_apply_list "${MACOS_UI_DEFAULTS[@]}"; then
        _MACOS_UI_CHANGED=true
        track_installed "Finder / window / menu bar preferences"
    else
        log_info "Finder / window / menu bar preferences already set"
        track_skipped "Finder / window / menu bar preferences"
    fi
}

install_macos_power() {
    print_section "Power: never sleep on AC"

    # Only the AC profile (-c). On battery the system keeps its normal sleep.
    local current
    current=$(pmset -g custom 2>/dev/null | awk '/^AC Power:/{ac=1} ac && $1=="sleep"{print $2; exit}')
    if [[ "$current" == "0" ]]; then
        log_info "System sleep on AC already disabled"
        track_skipped "pmset -c sleep 0"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would run: sudo pmset -c sleep 0 (currently ${current:-unknown})"
        return 0
    fi

    if [[ "$NO_SUDO" == "true" ]] || ! sudo -n true 2>/dev/null; then
        log_warn "pmset needs sudo — run manually: sudo pmset -c sleep 0"
        track_skipped "pmset -c sleep 0 (needs sudo)"
        return 0
    fi

    sudo pmset -c sleep 0
    track_installed "pmset -c sleep 0"
    log_success "System sleep disabled on AC power"
}

_macos_refresh() {
    [[ "$DRY_RUN" == "true" ]] && return 0

    if [[ "$_MACOS_KEYS_CHANGED" == "true" && -x "$MACOS_ACTIVATE_SETTINGS" ]]; then
        "$MACOS_ACTIVATE_SETTINGS" -u 2>/dev/null || true
    fi
    if [[ "$_MACOS_UI_CHANGED" == "true" ]]; then
        killall Finder SystemUIServer ControlCenter 2>/dev/null || true
        log_info "Menu bar spacing applies to apps as they relaunch (or after logout)"
    fi
    if [[ "$_MACOS_KEYS_CHANGED" == "true" ]]; then
        log_info "Key repeat changes apply to apps as they relaunch (or after logout)"
    fi
}

# ==============================================================================
# Main Installation
# ==============================================================================

install_macos() {
    log_info "Starting macOS preferences..."

    if [[ "$PLATFORM" != "macos" ]]; then
        log_info "macOS preferences are macOS-only, skipping on platform: $PLATFORM"
        track_skipped "macOS preferences (not macOS)"
        return 0
    fi

    install_macos_keyboard
    install_macos_shortcuts || return 1
    install_macos_keybindings
    install_macos_capslock
    install_macos_ui
    install_macos_power
    _macos_refresh

    log_success "macOS preferences complete!"
}

# ==============================================================================
# Standalone Execution
# ==============================================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    setup_error_handling
    install_macos
fi
