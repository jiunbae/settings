# Windows

`install.sh` cannot run on Windows: `lib/platform.sh` `detect_platform` exits on
anything that is not Linux or Darwin. So every Windows config here follows the same
pattern instead — the file lives in `configs/`, and the steps below place it. Nothing
is installed automatically.

| | |
| :--- | :--- |
| [Windows Terminal](#windows-terminal) | `configs/windows-terminal/settings.json` |
| [rmux](#rmux) | `configs/.rmux.conf` — tmux-compatible, native on Windows |
| [PowerShell](#powershell) | `configs/powershell/` — `.zshrc` ported, starship prompt |
| [NeoVim](#neovim) | `configs/nvim/` — same config as everywhere else |
| [Nextcloud upload](#nextcloud-upload) | `bin/windows/cloud-upload.ps1` |

## Windows Terminal

Configuration for Windows Terminal is available in `configs/windows-terminal/settings.json`.

### How to apply

1. Open Windows Terminal
2. Press `Ctrl + ,` to open Settings
3. Click **Open JSON file** at the bottom of the left sidebar
4. Copy the contents of `configs/windows-terminal/settings.json` and paste them into your `settings.json`

> [!TIP]
> This configuration uses **JetBrainsMonoNL Nerd Font**. Make sure it's installed on your Windows system for the best experience.


## rmux

[rmux](https://github.com/Helvesec/rmux) is a tmux-compatible multiplexer that runs
natively on Windows, where `install.sh` cannot go — `lib/platform.sh` only detects
Linux and Darwin. `configs/.rmux.conf` is the subset of `configs/.tmux.conf` that
works there: mouse, copy-mode, splits, `hjkl` navigation/resize and the Korean
two-set prefix mappings. Plugins (TPM, catppuccin), the `uname`-based `if-shell`
blocks and the muxa popups are omitted.

### How to apply

1. `winget install rmux`
2. Copy `configs/.rmux.conf` to `%USERPROFILE%\.rmux.conf`
3. Start a session: `rmux new-session -A -s main`

rmux reads `%XDG_CONFIG_HOME%\rmux\rmux.conf`, `%USERPROFILE%\.rmux.conf`,
`%APPDATA%\rmux\rmux.conf` and `%RMUX_CONFIG_FILE%`. With none of them present it
falls back to parsing a `tmux.conf`, but only from the standard paths — a bare
Windows box has no `~/.tmux.conf`, so nothing is loaded and every option stays at
its default.

> [!TIP]
> `mouse` is **off** by default in rmux, so wheel scrolling and the scrollback are
> unreachable until `set-option -g mouse on` is loaded — the most common symptom of
> a missing config. To check a running server: `rmux show-options -g mouse`.
> `prefix + R` reloads `~/.rmux.conf`.


## PowerShell

`configs/powershell/profile.ps1` is `.zshrc` ported to PowerShell 7, for the same
reason as `.rmux.conf`: `install.sh` cannot run on Windows. `configs/powershell/starship.toml`
is the prompt that replaces Powerlevel10k, laid out to match the p10k config in
`configs/.p10k.zsh`. Its right half is right-aligned with starship's `fill` module
rather than `right_format`, which PowerShell never renders — see below.

There is no zinit equivalent and none is needed — PSReadLine 2.4 ships prediction
and syntax highlighting natively, which is what `zsh-autosuggestions` and
`fast-syntax-highlighting` were loaded for. The history options, the whole `bindkey`
block, `AUTO_PUSHD`/`cd -`, the `$+commands` tool aliases, `mkcd`, the agent
wrappers and the Korean two-set prefix policy all carry over.

### How to apply

1. Install the tools:
   ```powershell
   winget install --id Starship.Starship --id eza-community.eza --id sharkdp.fd `
     --id BurntSushi.ripgrep.MSVC --id sharkdp.bat --id dandavison.delta `
     --id bootandy.dust --id dalance.procs --id Clement.bottom --id junegunn.fzf `
     --id ajeetdsouza.zoxide --id Neovim.Neovim --id Schniz.fnm --id jqlang.jq
   Install-Module PSFzf -Scope CurrentUser
   ```
2. Point `$PROFILE` at the repo copy — Windows symlinks need elevation or Developer
   Mode, so dot-source instead of linking:
   ```powershell
   @'
   $repoProfile = "$env:USERPROFILE\workspace\settings\configs\powershell\profile.ps1"
   if (Test-Path $repoProfile) { . $repoProfile }
   '@ | Set-Content $PROFILE
   ```
3. Put machine-local additions in `profile.local.ps1` next to `$PROFILE`. The repo
   profile sources it last, the same way `.zshrc` sources `~/.zshrc.local` — this
   repo is public.

### What does not port

| `.zshrc` | Why |
| :--- | :--- |
| p10k instant prompt | No equivalent; starship renders in ~20ms unprimed |
| p10k right prompt | `right_format` is dead under PowerShell: `starship init powershell` never issues the `starship prompt --right` that fish and zsh get. The same segments are right-aligned with the `fill` module inside `format` instead |
| `hishtory` | Supports bash/zsh/fish only, so history is PSReadLine-local |
| `umask 077` | Windows uses ACLs |
| `GPG_TTY` / `updatestartuptty` | pinentry-qt draws a GUI dialog |
| `AUTO_CD` | Needs `CommandNotFoundAction`, already claimed by PowerToys. `zoxide`'s `z` covers the same ground |
| `SHARE_HISTORY` | `SaveIncrementally` appends as you go, but no live in-session sharing |
| nvm lazy-load shims | `fnm --use-on-cd` is already lazy |
| `arch -arch` aliases | macOS only |


> [!NOTE]
> The profile is measured, not guessed: its own cost is 222ms against a 171ms
> bare-shell baseline, down from 1183ms. The techniques and the numbers are in
> [powershell.md](powershell.md).

## NeoVim

`configs/nvim/` needs no Windows variant — nothing in it is POSIX-specific. What it
needs is to be *found*: NeoVim reads `%LOCALAPPDATA%\nvim` on Windows, so installing
the binary alone (`winget install Neovim.Neovim`) leaves a stock editor with no
plugins and no keymaps, which looks like a working install until you notice `vim` has
none of your bindings.

### How to apply

```powershell
winget install --id Neovim.Neovim
npm install -g tree-sitter-cli          # nvim-treesitter compiles parsers with it
New-Item -ItemType Junction -Path "$env:LOCALAPPDATA\nvim" `
         -Target "$env:USERPROFILE\workspace\settings\configs\nvim"
nvim --headless "+Lazy! install" +qa
nvim --headless "+Lazy! restore" +qa
```

A **junction**, not a symlink: a directory junction needs no elevation and no
Developer Mode, where `New-Item -ItemType SymbolicLink` needs one of them. It is the
closest equivalent to the symlink `modules/editor.sh` makes at `~/.config/nvim`, and
it keeps `lazy-lock.json` writable in place, so a plugin update on Windows shows up
as a repo change exactly as it does on macOS and Linux.

`Lazy! restore` after `Lazy! install` is what pins the 35 plugins to the commits in
`lazy-lock.json` rather than to whatever is newest that day, so this machine matches
the others.

There is no winget package for the tree-sitter CLI; npm ships a prebuilt binary,
where `cargo install tree-sitter-cli` would compile it. Without it `mason.nvim`
reports `Failed to install tree-sitter-cli` and `nvim-treesitter` cannot build
parsers.

> [!WARNING]
> `lazy-lock.json` is a tracked file reached through the junction, so lazy.nvim writes
> into the repo. If lazy ever dies while writing it, the file is left truncated to
> `{` — check `git status` in this repo after a plugin operation, and
> `git restore configs/nvim/lazy-lock.json` if it looks short. A line-ending-only diff
> is normal and expected: lazy writes LF, `core.autocrlf` checks out CRLF.

### Repairing an existing lazy.nvim install

The bootstrap in `lua/config/lazy.lua` runs only when `lazypath` does not exist, so
fixing it does **not** heal a machine where lazy.nvim was already installed with a
detached HEAD. Such an install keeps truncating `lazy-lock.json` on every `Lazy!`
command. Check and repair:

```sh
cd "${XDG_DATA_HOME:-$HOME/.local/share}/nvim/lazy/lazy.nvim"   # Windows: %LOCALAPPDATA%\nvim-data\lazy\lazy.nvim
git rev-parse --abbrev-ref HEAD     # "HEAD" means detached — needs repairing
git checkout -B main HEAD           # same commit, now on a branch
```

To find out whether a machine is affected at all, ask lazy.nvim which plugin it cannot
name a branch for:

```sh
nvim --headless -c 'lua local G=require("lazy.manage.git") for _,p in pairs(require("lazy.core.config").plugins) do if p._.installed and not p._.is_local then local i=G.info(p.dir) if not i or not (i.branch or G.get_branch(p)) then print("no branch: "..p.name) end end end' -c 'qa!'
```

> [!NOTE]
> LazyVim needs NeoVim 0.11 or newer (`modules/editor.sh` pins 0.11.2). Check with
> `nvim --version`; a `nvim --version` that works proves only that the editor is
> installed, not that this config is loaded. To check that, run
> `nvim --headless -c 'lua print(pcall(require, "lazyvim"))' -c 'qa!'`.


## Nextcloud upload

`bin/windows/cloud-upload.ps1` uploads files and folders to a Nextcloud instance
over WebDAV, skipping anything already there. `bin/windows/Setup-Nextcloud.ps1`
wires it up: credentials, `rclone`, a mapped drive and the Explorer *Send to* entry.

`bin/windows/` sits outside what `modules/scripts.sh` links, for the same reason as
`configs/powershell/`: `install.sh` cannot run on Windows. Setup points `%USERPROFILE%\bin\cloud-upload.cmd`
at the repo copy rather than copying the script, so there is only ever one version.

### How to apply

```powershell
pwsh -ExecutionPolicy Bypass -File "$env:USERPROFILE\workspace\settings\bin\windows\Setup-Nextcloud.ps1"
```

It prompts for the server URL, user ID and an app password. Nothing it asks for is
stored in the repo — the server and user land in `~/.cloud-upload.json`, the password
in `~/_netrc`, both outside the repo because this one is public. Run it from an
elevated shell to also lift the 50MB WebDAV file size limit.

### Skipping what is already uploaded

Nextcloud exposes no content hash, which is worth stating because it rules out the
obvious design:

- `d:getetag` is a server-internal value, not a digest of the bytes. An empty file
  came back as `254b5e60…`, nothing like the MD5 of an empty string.
- `oc:checksum` is never populated. Uploading with `OC-Checksum: SHA1:…` and then
  with `MD5:…` both left the property returning 404 (Nextcloud 32.0.3).

Comparing real hashes would mean downloading each remote file, which costs more than
re-uploading it. So the comparison is size + mtime, the same basis rclone uses:

- One `PROPFIND` with `Depth: infinity` returns the whole remote tree — 200 entries
  in 62KB, measured at 0.16s. If a server refuses it (Sabre/DAV disables it by
  default; this instance allows it) the script falls back to per-directory `Depth: 1`.
- Uploads carry `X-OC-Mtime`, so the remote timestamp is the local one and the next
  run compares exactly rather than against an upload time.
- Files predating that header have no matching mtime, so "same size and the remote is
  newer" also counts as unchanged. For an upload-only workflow that holds: a remote
  copy written after the local file was last touched has the local content. `-Strict`
  demands an exact mtime match instead; `-Force` uploads regardless.

Re-running over an unchanged 40-file folder went from 4.6s to 0.31s. Parallel PUTs
(`curl -Z`) are also on, but they are close to noise here — 6.0s against 6.9s for 60
small files, with the server's per-request work as the bottleneck. Not transferring
is where the time goes.

| | |
| :--- | :--- |
| `cloud-upload DIR -To sub/nested` | Upload a folder, changed files only; `-To` takes a nested path and creates it |
| `cloud-upload DIR -DryRun` | List what would be uploaded |
| `cloud-upload DIR -Exclude *.tmp,__pycache__` | Skip matching entries |
| `cloud-upload FILE -Share -Expire 7` | Public link to the clipboard, expiring in 7 days |

### Exclude patterns

`-Exclude` reads its patterns the way rclone's `--exclude` does. A pattern with no
`/` is tested against every path segment, so `__pycache__` drops that directory
wherever it sits; a pattern containing `/` is tested against the whole path relative
to the input root, so `dist/*` only drops that one. `*` spans separators — PowerShell
`-like` is plain string matching — so `dist/*` already covers `dist/sub/deep.js` and
there is no separate `**`. Matching is case-insensitive, like the filesystem under it.

Excluded directories are pruned during the walk rather than filtered afterwards, so
the files inside are never enumerated. Over a 4020-file tree whose `node_modules`
holds 4000 of them, `-Exclude node_modules` took 0.11s against 0.91s for the same
run without it.

Patterns may be written as one comma-separated argument (`-Exclude a,b`) or as a
PowerShell array. Both spellings are needed: from a prompt the shell builds the
array itself, but `bin\cloud-upload.cmd` and the *Send to* entry hand arguments to
`pwsh -File`, which takes them literally and never applies array syntax — so the
script splits on commas itself. The cost is that a pattern containing a literal
comma cannot be expressed; no glob needs one.

`-Share` accepts exactly one file or folder (after wildcard expansion) and shares
that item's remote path, including when its files are already uploaded. Multiple
inputs are rejected before uploading; run each separately to create separate links.
A folder link includes its existing remote contents. `-DryRun` also works with
`-Sync` and never creates a public link.
