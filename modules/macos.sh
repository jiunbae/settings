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
# Label of the hidutil LaunchAgent earlier versions installed; removed on sight.
readonly MACOS_CAPSLOCK_LABEL="dev.jiun.capslock-to-control"
readonly MACOS_ACTIVATE_SETTINGS="/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings"

# Caps Lock (HID usage 0x39) -> Control. 0xE4 is what System Settings writes
# for "Control" in its per-keyboard modifier mapping.
readonly MACOS_CAPSLOCK_SRC=30064771129
readonly MACOS_CAPSLOCK_DST=30064771300
readonly MACOS_CAPSLOCK_MAPPING='{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x7000000E4}]}'

# "domain|key|type|value" — domain "-g" is NSGlobalDomain; a "host:" prefix
# writes to -currentHost. Type "absent" deletes the key (value is ignored).
readonly MACOS_KEYBOARD_DEFAULTS=(
    "-g|KeyRepeat|int|1"
    "-g|InitialKeyRepeat|int|11"
    "-g|ApplePressAndHoldEnabled|bool|false"
    "-g|com.apple.keyboard.fnState|bool|false"
    "-g|AppleKeyboardUIMode|int|0"
    "-g|NSAutomaticCapitalizationEnabled|bool|false"
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
    "-g|AppleInterfaceStyle|absent|"
    "com.apple.finder|ShowPathbar|bool|true"
    "com.apple.finder|FXEnableExtensionChangeWarning|bool|false"
    "com.apple.finder|FXRemoveOldTrashItems|bool|true"
    "com.apple.finder|ShowRecentTags|bool|false"
)

readonly MACOS_DOCK_DEFAULTS=(
    "com.apple.dock|tilesize|int|42"
    "com.apple.dock|magnification|bool|false"
)

# Tap to click and three-finger drag, for the built-in trackpad and a Magic
# Trackpad alike. Three-finger drag takes three fingers, so the three-finger
# swipes are turned off and Mission Control / Space switching stay on four.
readonly MACOS_TRACKPAD_DEFAULTS=(
    "com.apple.AppleMultitouchTrackpad|Clicking|bool|true"
    "com.apple.AppleMultitouchTrackpad|TrackpadThreeFingerDrag|bool|true"
    "com.apple.AppleMultitouchTrackpad|TrackpadThreeFingerHorizSwipeGesture|int|0"
    "com.apple.AppleMultitouchTrackpad|TrackpadThreeFingerVertSwipeGesture|int|0"
    "com.apple.driver.AppleBluetoothMultitouch.trackpad|Clicking|bool|true"
    "com.apple.driver.AppleBluetoothMultitouch.trackpad|TrackpadThreeFingerDrag|bool|true"
    "com.apple.driver.AppleBluetoothMultitouch.trackpad|TrackpadThreeFingerHorizSwipeGesture|int|0"
    "com.apple.driver.AppleBluetoothMultitouch.trackpad|TrackpadThreeFingerVertSwipeGesture|int|0"
    "host:-g|com.apple.mouse.tapBehavior|int|1"
)

# pmset values: never idle-sleep on AC, sleep after 3 minutes on battery.
readonly MACOS_PMSET_AC_SLEEP=0
readonly MACOS_PMSET_BATTERY_SLEEP=3

# Which system items appear in the menu bar. Control Center's per-module
# ints live in -currentHost: 2 = show when active, 8 = don't show. The
# "NSStatusItem VisibleCC <item>" bools are what macOS 27 writes when an item
# is toggled; false hides it even where the module int says otherwise.
readonly MACOS_MENUBAR_DEFAULTS=(
    "host:com.apple.controlcenter|BatteryShowPercentage|bool|true"
    "host:com.apple.controlcenter|BatteryShowEnergyMode|bool|true"
    "host:com.apple.controlcenter|Display|int|2"
    "host:com.apple.controlcenter|VPN|int|2"
    "host:com.apple.controlcenter|FocusModes|int|8"
    "host:com.apple.controlcenter|NowPlaying|int|8"
    "host:com.apple.controlcenter|SolariumBentoBox|int|8"
    "host:com.apple.controlcenter|Spotlight|int|8"
    "host:com.apple.controlcenter|Weather|int|8"
    "com.apple.controlcenter|NSStatusItem VisibleCC FocusModes|bool|false"
    "com.apple.Spotlight|NSStatusItem VisibleCC Item-0|bool|false"
)

# Set by _macos_default when anything changed, so services are only restarted
# when there is something for them to pick up.
_MACOS_UI_CHANGED=false
_MACOS_KEYS_CHANGED=false
_MACOS_DOCK_CHANGED=false
_MACOS_LOGOUT_NEEDED=false

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
    [[ "$type" == "absent" ]] && want="<unset>"
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
    if [[ "$type" == "absent" ]]; then
        defaults ${host_flag[@]+"${host_flag[@]}"} delete "$domain" "$key"
        log_info "Removed $domain $key (was $current)"
        return 0
    fi
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

    # Earlier versions re-applied a hidutil mapping from a LaunchAgent at login.
    # The per-keyboard mapping below is what System Settings itself stores, so
    # the agent is no longer needed.
    local old_agent="$MACOS_LAUNCH_AGENTS_DIR/$MACOS_CAPSLOCK_LABEL.plist"
    if [[ -f "$old_agent" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY-RUN] Would remove the old Caps Lock LaunchAgent"
        else
            launchctl bootout "gui/$(id -u)/$MACOS_CAPSLOCK_LABEL" 2>/dev/null || true
            rm -f "$old_agent"
            log_info "Removed the old Caps Lock LaunchAgent"
        fi
    fi

    # One -currentHost key per keyboard, named by vendor and product id — the
    # form System Settings > Keyboard > Modifier Keys writes. Only keyboards
    # attached right now are covered; for a new one, re-run this or set it in
    # System Settings. Other remaps already on a keyboard are kept.
    local changes
    changes=$(python3 - "$MACOS_CAPSLOCK_SRC" "$MACOS_CAPSLOCK_DST" <<'PY'
import plistlib, subprocess, sys
src, dst = int(sys.argv[1]), int(sys.argv[2])
listing = subprocess.run(
    ["hidutil", "list", "--matching", '{"PrimaryUsagePage":1,"PrimaryUsage":6}'],
    capture_output=True, text=True).stdout
keyboards = []
for line in listing.splitlines():
    if line.startswith("Devices"):      # only the Services section is needed
        break
    cols = line.split()
    if len(cols) < 9 or cols[0] == "VendorID" or cols[8].startswith("V-"):
        continue                        # headers, and Universal Control proxies
    key = "com.apple.keyboard.modifiermapping.%d-%d-0" % (int(cols[0], 16), int(cols[1], 16))
    if key not in keyboards:
        keyboards.append(key)
raw = subprocess.run(["defaults", "-currentHost", "export", "-g", "-"], capture_output=True).stdout
current = plistlib.loads(raw) if raw else {}
entry = {"HIDKeyboardModifierMappingSrc": src, "HIDKeyboardModifierMappingDst": dst}
for key in keyboards:
    have = current.get(key, [])
    if entry in have:
        continue
    keep = [m for m in have if m.get("HIDKeyboardModifierMappingSrc") != src]
    items = keep + [entry]
    xml = ["<dict><key>HIDKeyboardModifierMappingDst</key><integer>%d</integer>"
           "<key>HIDKeyboardModifierMappingSrc</key><integer>%d</integer></dict>"
           % (m["HIDKeyboardModifierMappingDst"], m["HIDKeyboardModifierMappingSrc"]) for m in items]
    print(key + "\t" + "\t".join(xml))
PY
    ) || { log_error "Could not read keyboards or modifier mappings"; return 1; }

    if [[ -z "$changes" ]]; then
        log_info "Caps Lock already maps to Control on every attached keyboard"
        track_skipped "Caps Lock -> Control"
    elif [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would map Caps Lock -> Control for: $(cut -f1 <<< "$changes" | sed 's/.*modifiermapping\.//' | tr '\n' ' ')"
        return 0
    else
        local key rest
        local -a items
        while IFS=$'\t' read -r key rest; do
            IFS=$'\t' read -r -a items <<< "$rest"
            defaults -currentHost write -g "$key" -array "${items[@]}"
            log_info "Mapped Caps Lock -> Control on keyboard ${key##*.}"
        done <<< "$changes"
        track_installed "Caps Lock -> Control"
    fi

    # The stored mapping is read at login; apply it to this session too.
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

install_macos_dock() {
    print_section "Dock"

    if _macos_apply_list "${MACOS_DOCK_DEFAULTS[@]}"; then
        _MACOS_DOCK_CHANGED=true
        track_installed "Dock preferences"
    else
        log_info "Dock preferences already set"
        track_skipped "Dock preferences"
    fi
}

install_macos_trackpad() {
    print_section "Trackpad"

    if _macos_apply_list "${MACOS_TRACKPAD_DEFAULTS[@]}"; then
        _MACOS_LOGOUT_NEEDED=true
        track_installed "Trackpad preferences"
    else
        log_info "Trackpad preferences already set"
        track_skipped "Trackpad preferences"
    fi
}

install_macos_menubar() {
    print_section "Menu bar system items"

    if _macos_apply_list "${MACOS_MENUBAR_DEFAULTS[@]}"; then
        _MACOS_UI_CHANGED=true
        track_installed "Menu bar system items"
    else
        log_info "Menu bar system items already set"
        track_skipped "Menu bar system items"
    fi
}

install_macos_power() {
    print_section "Power: sleep on AC and battery"

    # AC: never idle-sleep. Battery: sleep after a few minutes. A Mac without a
    # battery has no Battery Power section and only gets the AC value.
    local custom ac battery
    custom=$(pmset -g custom 2>/dev/null)
    ac=$(awk '/^AC Power:/{s=1;next} /Power:$/{s=0} s && $1=="sleep"{print $2; exit}' <<< "$custom")
    battery=$(awk '/^Battery Power:/{s=1;next} /Power:$/{s=0} s && $1=="sleep"{print $2; exit}' <<< "$custom")

    local -a todo=()
    [[ "$ac" == "$MACOS_PMSET_AC_SLEEP" ]] || todo+=("-c sleep $MACOS_PMSET_AC_SLEEP")
    if grep -q '^Battery Power:' <<< "$custom" && [[ "$battery" != "$MACOS_PMSET_BATTERY_SLEEP" ]]; then
        todo+=("-b sleep $MACOS_PMSET_BATTERY_SLEEP")
    fi

    if [[ ${#todo[@]} -eq 0 ]]; then
        log_info "Sleep already set (AC $ac, battery ${battery:-n/a})"
        track_skipped "pmset sleep"
        return 0
    fi

    local t
    if [[ "$DRY_RUN" == "true" ]]; then
        for t in "${todo[@]}"; do log_info "[DRY-RUN] Would run: sudo pmset $t"; done
        return 0
    fi

    if [[ "$NO_SUDO" == "true" ]] || { ! sudo -n true 2>/dev/null && { [[ ! -t 0 ]] || ! validate_sudo; }; }; then
        for t in "${todo[@]}"; do log_warn "pmset needs sudo — run manually: sudo pmset $t"; done
        track_skipped "pmset sleep (needs sudo)"
        return 0
    fi

    for t in "${todo[@]}"; do
        # shellcheck disable=SC2086
        sudo pmset $t
    done
    track_installed "pmset sleep"
    log_success "Sleep set: AC never, battery ${MACOS_PMSET_BATTERY_SLEEP} min"
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
    if [[ "$_MACOS_DOCK_CHANGED" == "true" ]]; then
        killall Dock 2>/dev/null || true
    fi
    if [[ "$_MACOS_KEYS_CHANGED" == "true" ]]; then
        log_info "Key repeat changes apply to apps as they relaunch (or after logout)"
    fi
    if [[ "$_MACOS_LOGOUT_NEEDED" == "true" ]]; then
        log_info "Trackpad and appearance changes take full effect after logging out and back in"
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
    install_macos_dock
    install_macos_trackpad
    install_macos_menubar
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
