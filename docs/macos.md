# macOS

Six macOS-only components. On Linux and WSL each one logs a skip and returns.

| Component | What it does |
|---|---|
| `macos` | Keyboard, system shortcuts, Caps Lock → Control, Finder/window/menu bar preferences, AC sleep, lid closed on AC |
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
| `com.apple.keyboard.fnState` | `true` | F1–F12 act as function keys; media keys need fn. |
| `NSAutomatic{Dash,Period,Quote}SubstitutionEnabled` | `false` | No smart dashes, double-space period or curly quotes. |
| `NSAutomaticSpellingCorrectionEnabled`, `WebAutomaticSpellingCorrectionEnabled` | `false` | No autocorrect. |
| `NSAutomaticCapitalizationEnabled` | `true` | Sentence capitalization stays on. |
| `AppleKeyboardUIMode` | `1` | Keyboard navigation mode as captured. |
| `TISRomanSwitchState` | `0` | Input-source Caps Lock switch state as captured; moot once Caps Lock is Control. |

Key repeat is read when an app launches — relaunch apps or log out to feel it.

### Caps Lock → Control

A LaunchAgent, `~/Library/LaunchAgents/dev.jiun.capslock-to-control.plist`, runs
`hidutil property --set` at login and the module applies it once immediately.

System Settings stores this mapping per keyboard model (vendor/product id), so it does
not carry over to a different Mac or a new external keyboard. The hidutil mapping
applies to every keyboard. It does not show up under System Settings › Keyboard ›
Modifier Keys.

To undo:

```bash
launchctl bootout gui/$(id -u)/dev.jiun.capslock-to-control
rm ~/Library/LaunchAgents/dev.jiun.capslock-to-control.plist
hidutil property --set '{"UserKeyMapping":[]}'
```

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
| ⌃\` / ⌃⇧\` | Show Desktop | F11 |
| ⌃; | Notification Center | — |
| ⌥⇧A | Launchpad / Apps | — |
| *(off)* | ⌘⇧Space previous input source, ⌘F5 VoiceOver, ⌥⌘F5 Accessibility controls | on |

> [!WARNING]
> System shortcuts are taken before any app sees the key. ⌃H, ⌃J, ⌃K and ⌃L never
> reach terminals, shells or editors (backspace, newline, kill-line and clear-screen in
> readline), and ⌃\` never reaches VS Code's terminal toggle.

To change a shortcut, set it in System Settings, then read the new value back into
the table:

```bash
defaults export com.apple.symbolichotkeys - | plutil -p - | less
```

The parameters are `ascii, keycode, modifiers`. The modifier mask is shift 131072,
ctrl 262144, option 524288, cmd 1048576 and fn 8388608, added together.

### Finder, windows, menu bar

| Preference | Value | Effect |
|---|---|---|
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

`sudo pmset -c sleep 0`: the system never idle-sleeps on AC power. Battery sleep is left
as is. The step needs sudo. With `--no-sudo`, or without cached sudo credentials, it
prints the command to run by hand.

#### Lid closed on AC

`pmset sleep 0` does not cover closing the lid: a MacBook sleeps on lid close — dropping
SSH and everything else on the network — unless an external display and power are
connected (clamshell mode) or `SleepDisabled` is set. `SleepDisabled` has no per-power-source
form, so the `dev.jiun.ac-lid-awake` LaunchDaemon follows the power source instead:

| Power | Lid closed |
|---|---|
| AC | stays awake (`pmset -a disablesleep 1`) |
| Battery | sleeps as usual (`disablesleep 0`); unplugging with the lid already closed sleeps immediately |

The daemon runs as root, so `configs/macos/ac-lid-awake.sh` is copied to
`/usr/local/libexec/ac-lid-awake` (root-owned) rather than run from the repo. It polls the
power source every 5 seconds. Installing it needs sudo once; from a non-interactive
shell the module skips it and says to run `./install.sh macos` in a terminal.

To remove it:

```bash
sudo launchctl bootout system/dev.jiun.ac-lid-awake
sudo rm /Library/LaunchDaemons/dev.jiun.ac-lid-awake.plist /usr/local/libexec/ac-lid-awake
sudo pmset -a disablesleep 0
```

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
