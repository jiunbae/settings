# macOS

Six macOS-only components. On Linux and WSL each one logs a skip and returns.

| Component | What it does |
|---|---|
| `macos` | Keyboard, system shortcuts, Caps Lock → Control, appearance, Finder, Dock, trackpad, menu bar, sleep |
| `fonts` | Nerd Fonts and the Hangul-merged JetBrains Mono used by the terminal config |
| `hammerspoon` | Hammerspoon.app + `init.lua` — see [components.md](components.md#hammerspoon) |
| `cmux` | cmux.app, the Ghostty config it reads, and its theme |
| `git` | Shared git config, global ignore, commit signing |
| `node` | nvm, Node.js 24 LTS as the default, Codex and Claude Code CLIs |

```bash
./install.sh macos fonts hammerspoon cmux git node
./install.sh -n macos          # show what would change
```

Every value was captured from a machine in daily use. Each write reads the current
value first and only writes on a difference, so a re-run is a no-op.

## `macos`

### Keyboard

| Preference | Value | Effect |
|---|---|---|
| `KeyRepeat` | `1` | Repeat rate. Faster than the UI's fastest setting (2). |
| `InitialKeyRepeat` | `11` | Delay before repeat. Shorter than the UI's shortest (15). |
| `ApplePressAndHoldEnabled` | `false` | Holding a key repeats it instead of opening the accent popup. |
| `com.apple.keyboard.fnState` | `false` | F1–F12 are media keys; hold fn for F1–F12. |
| `NSAutomatic{Dash,Period,Quote}SubstitutionEnabled` | `false` | No smart dashes, double-space period or curly quotes. |
| `NSAutomaticSpellingCorrectionEnabled`, `WebAutomaticSpellingCorrectionEnabled` | `false` | No autocorrect. |
| `NSAutomaticCapitalizationEnabled` | `false` | No automatic capitalization. |
| `AppleKeyboardUIMode` | `0` | Keyboard navigation (Tab through every control) off. |
| `TISRomanSwitchState` | `0` | Input-source Caps Lock switch state as captured; moot once Caps Lock is Control. |

Key repeat is read when an app launches — relaunch apps or log out to feel it.

### Caps Lock → Control

Written the way System Settings › Keyboard › Modifier Keys stores it: one
`-currentHost` key per keyboard, `com.apple.keyboard.modifiermapping.<vendor>-<product>-0`,
for every keyboard attached when the module runs (Universal Control `V-*` proxies are
skipped, other remaps on the same keyboard are kept). macOS applies these at login, so
the first run needs a log out and back in; nothing is injected into the running session.
`hidutil list` is used only to read the attached keyboards' vendor and product ids.

A keyboard first connected later is not covered until the module runs again with it
attached, or Caps Lock is set to Control for it in System Settings. Earlier versions
used a `dev.jiun.capslock-to-control` LaunchAgent instead; the module removes it.

### Text key bindings

`configs/macos/DefaultKeyBinding.dict` is linked to
`~/Library/KeyBindings/DefaultKeyBinding.dict`. It makes the `₩` key (what the
backtick key types under the Korean input source) insert `` ` `` in Cocoa text fields.
Relaunch an app to pick it up. Terminal emulators and Electron apps generally do their
own key handling and ignore it.

### System shortcuts

`configs/macos/symbolichotkeys.tsv` is the source of truth. Each row is written into
`com.apple.symbolichotkeys` with `defaults write … -dict-add`, so shortcuts not listed
keep their defaults. `activateSettings -u` applies most of them without logging out;
log out if one does not take effect.

| Shortcut | Action | macOS default |
|---|---|---|
| ⌘Space | Next input source | ⌃⌥Space |
| ⌥Space | Spotlight | ⌘Space |
| ⌃H / ⌃⇧H | Mission Control | ⌃↑ |
| ⌃K / ⌃⇧K | Application windows | ⌃↓ |
| ⌃J / ⌃⇧J | Move one Space left | ⌃← |
| ⌃L / ⌃⇧L | Move one Space right | ⌃→ |
| ⌃' / ⌃⇧' | Show Desktop | F11 |
| ⌃; | Notification Center | — |
| ⌥⇧A | Launchpad / Apps | — |
| *(off)* | ⌘⇧Space previous input source, ⌘F5 VoiceOver, ⌥⌘F5 Accessibility controls | on |

> [!WARNING]
> System shortcuts are taken before any app sees the key. ⌃H, ⌃J, ⌃K and ⌃L never
> reach terminals, shells or editors (backspace, newline, kill-line and clear-screen in
> readline). Show Desktop is on ⌃' rather than ⌃\` so VS Code keeps its terminal toggle.

To change a shortcut, set it in System Settings, then read the new value back into
the table:

```bash
defaults export com.apple.symbolichotkeys - | plutil -p - | less
```

The parameters are `ascii, keycode, modifiers`. The modifier mask is shift 131072,
ctrl 262144, option 524288, cmd 1048576 and fn 8388608, added together.

### Appearance, Finder, windows, menu bar

| Preference | Value | Effect |
|---|---|---|
| `AppleInterfaceStyle` | *(removed)* | Light mode. Takes full effect after logging out. |
| `ShowPathbar` | `true` | Finder path bar. |
| `FXEnableExtensionChangeWarning` | `false` | No warning when renaming an extension. |
| `FXRemoveOldTrashItems` | `true` | Empty items from the Trash after 30 days. |
| `ShowRecentTags` | `false` | No recent tags in the Finder sidebar. |
| `AppleShowAllExtensions` | `true` | Finder shows every file extension. |
| `AppleShowScrollBars` | `WhenScrolling` | Scroll bars only while scrolling. |
| `NSQuitAlwaysKeepsWindows` | `true` | Reopening an app restores its windows. |
| `-currentHost NSStatusItemSpacing` | `6` | Tighter menu bar icon spacing. |
| `-currentHost NSStatusItemSelectionPadding` | `12` | Tighter highlight padding. |

Finder, SystemUIServer and ControlCenter are restarted when these change.
Third-party menu bar apps adopt the spacing when they relaunch. To go back to the default
spacing: `defaults -currentHost delete -g NSStatusItemSpacing` (and `…SelectionPadding`).

> [!WARNING]
> **On macOS 27 Apple's own menu bar icons ignore both keys.** System items are drawn by
> the new `MenuBarAgent`, which does not apply them even after logging out and back in, so
> only third-party icons tighten and the bar looks uneven. Through macOS 26 every icon
> followed the setting. The values are kept on purpose: app icons stay tight, and system
> icons pick them up again if a later release restores the old behavior.

### Dock

| Preference | Value |
|---|---|
| `tilesize` | `42` |
| `magnification` | `false` |

The Dock is restarted when either changes.

### Trackpad

Tap to click and three-finger drag, on the built-in trackpad and a Magic Trackpad
(`com.apple.AppleMultitouchTrackpad`, `com.apple.driver.AppleBluetoothMultitouch.trackpad`,
`-currentHost com.apple.mouse.tapBehavior`). Three-finger drag occupies three fingers, so
the three-finger swipe gestures are off and Mission Control / Space switching use four.
Log out and back in for the trackpad to pick these up.

### Menu bar system items

Which system items show in the menu bar, captured from the old machine.

| Item | Setting |
|---|---|
| Battery | percentage and energy mode shown |
| Display, VPN | shown only while active (`2`) |
| Focus, Now Playing, Spotlight, Weather, `SolariumBentoBox` | hidden (`8`) |

Control Center keeps a per-module int under `-currentHost com.apple.controlcenter`
(`2` show when active, `8` don't show). macOS 27 also writes an
`NSStatusItem VisibleCC <item>` bool when an item is toggled, and that bool wins, so Focus
and Spotlight are additionally set to `false` there.

### Power

| Power | `pmset` |
|---|---|
| AC | `sleep 0` — never idle-sleeps |
| Battery | `sleep 3` — sleeps after 3 minutes (skipped on Macs without a battery) |

Needs sudo: from a terminal it prompts, otherwise it prints the `sudo pmset …` commands
to run by hand. `powermode` (High Power) is left alone, so a machine that uses it keeps it.

#### Lid closed

`pmset sleep` does not cover the lid: a MacBook sleeps when it closes — dropping SSH —
unless it is in clamshell mode with an external display. Keeping it awake on AC is left
to Amphetamine, configured in the app (its preferences live in its sandbox container):

- a Trigger with the *Power Adapter* condition (connected), with *Allow system sleep when
  display is closed* off
- **Power Protect** installed from Amphetamine's settings (Apple Silicon laptops; admin
  password, adds `/etc/sudoers.d/amphetamine_PowerProtect`)

### Default shell

`zsh` sets the login shell to `/bin/zsh` on macOS. It used to take the first `zsh` on
`PATH`, which on a machine with Homebrew's zsh made `/opt/homebrew/bin/zsh` the login
shell.

## `fonts`

| Font | Source | Used by |
|---|---|---|
| JetBrainsMonoHangul Nerd Font Mono | [Jhyub/JetBrainsMonoHangul](https://github.com/Jhyub/JetBrainsMonoHangul) release `20260222`, SHA-256 pinned | `configs/ghostty/config` (Ghostty and cmux) |
| JetBrainsMono Nerd Font | cask `font-jetbrains-mono-nerd-font` | editors |
| MesloLGS Nerd Font | cask `font-meslo-lg-nerd-font` | Powerlevel10k |

Font files are not committed; the old machine's `~/Library/Fonts` was 413 MB. To bump
the Hangul font, change `JBM_HANGUL_VERSION` and `JBM_HANGUL_SHA256` together.

## `cmux`

cmux embeds libghostty and searches the same config paths as Ghostty, including
`~/Library/Application Support/com.mitchellh.ghostty/config`, which the `ghostty`
module links to `configs/ghostty/config`. Font, colors, Option-as-Alt and keybinds are
therefore shared with Ghostty; `cmux` runs that link step itself.

`configs/cmux/config.ghostty` holds only cmux's theme block. It is copied into
`~/Library/Application Support/com.cmuxterm.app/` if absent and never linked, because
cmux rewrites that file when the theme is changed in its UI. cmux updates itself after
the cask installs it.

## `git`

`~/.gitconfig` stays a real, machine-local file. The module puts
`[include] path = <repo>/configs/git/gitconfig` at its top, so anything later in
`~/.gitconfig` wins. `configs/git/ignore` is linked to `~/.config/git/ignore`, git's
default global excludes file.
With `--copy` (and in the release bundle, whose extraction directory is deleted after
installing) the shared file is copied to `~/.config/git/shared.gitconfig` and that copy
is included instead.

`commit.gpgsign = true` is written to `~/.gitconfig` only when the secret key for
`user.signingkey` is in the local keyring. Commits never fail on a machine without the
key.

What stays in `~/.gitconfig` and out of this repo:

- credential helpers written by `gh auth setup-git`
- `includeIf` blocks for work repositories and the identity files they point to

## `node`

| Piece | How |
|---|---|
| nvm | Homebrew formula. `~/.nvm/nvm.sh` is a symlink into the keg, because `configs/.zshrc` loads nvm from `$NVM_DIR/nvm.sh`. |
| Node.js | `nvm install 24` and `nvm alias default 24`. |
| Codex CLI | `npm install -g @openai/codex` under the default Node. |
| Claude Code | Native installer (`curl -fsSL https://claude.ai/install.sh \| bash`), skipped when `claude` is already on PATH. It updates itself and does not depend on Node. |

**Why 24.** It is the Active LTS line, supported until April 2028. Node 22 is already in
maintenance and ends in April 2027. Node 26 becomes LTS in late October 2026; move to it
by changing `NODE_DEFAULT_MAJOR`. The alias is a bare major, so `.zshrc` and
`nvm install` follow that line's latest patch.

Global npm packages belong to one Node version. After the default changes, re-run
`./install.sh node` so Codex is installed under the new version. Anything else installed
globally under the old version is not carried over.

## Not managed

| | Why |
|---|---|
| Privacy grants (Accessibility, Input Monitoring, Screen Recording) | TCC cannot be scripted without MDM. Grant Hammerspoon, cmux and the rest in System Settings › Privacy & Security. |
| Screenshot location | Points into a cloud-synced folder that may not exist yet. |
| Language, region, Siri | Per-machine choice. |
| Dock layout, login items | Depend on which apps are installed. |
| `~/.envs`, `~/.gnupg`, `~/.aws`, `~/.kube` | Secrets. Copy from the old machine over SSH, never into git. |
| Homebrew package list | Differs per machine; not tracked here. |
