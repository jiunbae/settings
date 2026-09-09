# Jiun Bae
# PowerShell profile — ported from configs/.zshrc
# github.com/jiunbae/settings.git
#
# Loaded by $PROFILE, which should contain nothing but a stub pointing here —
# see the README. Machine-local additions go in profile.local.ps1 (sourced at the
# bottom), mirroring the .zshrc / .zshrc.local split: this file is tracked in a
# PUBLIC repo.
#
# zinit has no counterpart and needs none. PSReadLine 2.4 ships prediction and
# syntax highlighting natively, which is what zsh-autosuggestions and
# fast-syntax-highlighting were loaded for.
#
# Not ported, because the platform has no equivalent:
#   umask 077          → Windows uses ACLs, not a umask
#   GPG_TTY / updatestartuptty → pinentry-qt draws a GUI dialog instead
#   hishtory           → supports bash/zsh/fish only; PSReadLine history below
#   p10k instant prompt→ no such concept; starship is fast enough unprimed
#   arch -arch aliases → macOS only
#requires -Version 7

################################
# Console encoding (zsh: LC_ALL / LANG = en_US.UTF-8)
# Without this, Korean output and Nerd Font glyphs mojibake in some hosts.
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
$OutputEncoding = [System.Text.UTF8Encoding]::new()

################################
# Interactive?
# Everything below that exists to serve a human at a keyboard — line editing,
# prediction, key handlers, the prompt — is worthless in a scripted shell: a CI step,
# an agent's shell tool, `pwsh -File`. Those get the environment and skip the rest,
# which is what keeps a scripted `pwsh -Command` cheap.
#
# Decide from HOW THE SHELL WAS LAUNCHED, not how its streams happen to be wired.
# [Console]::IsOutputRedirected looks equivalent and is not: Windows OpenSSH gives a
# child process pipes rather than a console, so a perfectly interactive `pwsh` over
# ssh reports its output as redirected — and silently lost its prompt, its history
# search and its key bindings. Launch arguments do not lie about intent.
$script:Interactive = $true
foreach ($arg in [Environment]::GetCommandLineArgs()) {
    # Exact tokens only. Prefix matching would catch -ConfigurationName, -CustomPipeName
    # and friends; -Login, -NoLogo and -NoProfile must all stay interactive.
    if ($arg -match '^-(c|command|f|file|e|ec|encodedcommand|noninteractive)$') {
        $script:Interactive = $false
        break
    }
}

################################
# PSReadLine
# No Import-Module: an interactive host has already loaded PSReadLine by the time a
# profile runs, and in any other case the first Set-PSReadLineOption would autoload
# it anyway. The explicit import only paid ~66ms to do that work non-interactively,
# where none of it is wanted.
if ($script:Interactive) {
    # History (zsh: HIST_IGNORE_DUPS, HIST_FIND_NO_DUPS, INC_APPEND_HISTORY,
    #               HISTSIZE/SAVEHIST=500000)
    # SHARE_HISTORY has no direct equivalent — SaveIncrementally appends as you go,
    # so a second shell sees earlier commands, but not live in-session sharing.
    Set-PSReadLineOption -HistoryNoDuplicates
    Set-PSReadLineOption -HistorySaveStyle SaveIncrementally
    Set-PSReadLineOption -MaximumHistoryCount 500000
    Set-PSReadLineOption -HistorySearchCursorMovesToEnd

    # zsh: HIST_IGNORE_SPACE. Replacing the handler also replaces PSReadLine's
    # built-in sensitive-value filter, so keep an equivalent guard: anything that
    # looks like a secret stays in memory and never reaches the history file.
    Set-PSReadLineOption -AddToHistoryHandler {
        param([string]$line)
        if ($line -match '^\s') {
            return [Microsoft.PowerShell.AddToHistoryOption]::SkipAdding
        }
        if ($line -match '(?i)(password|passwd|secret|token|api[_-]?key|apikey|credential|connectionstring|bw_session)\s*[=:]') {
            return [Microsoft.PowerShell.AddToHistoryOption]::MemoryOnly
        }
        return [Microsoft.PowerShell.AddToHistoryOption]::MemoryAndFile
    }

    # zsh: bindkey -e
    Set-PSReadLineOption -EditMode Emacs

    # zsh: WORDCHARS='' — treat every special char as a word boundary so
    # ESC+Backspace and Ctrl+W stop at punctuation instead of eating a whole path.
    Set-PSReadLineOption -WordDelimiters ' /\()"''-_=+:;,.[]{}<>|!?*&^%$#@~`'

    # zsh: zsh-autosuggestions (ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=7')
    # The one thing above that throws rather than degrades when the console turns out
    # not to support virtual terminal processing after all. Everything else here is
    # harmless in that case, so catch this and carry on instead of printing red.
    try {
        Set-PSReadLineOption -PredictionSource HistoryAndPlugin
        Set-PSReadLineOption -PredictionViewStyle InlineView
        Set-PSReadLineOption -Colors @{ InlinePrediction = "$([char]27)[90m" }
    } catch { }

    # zsh: zstyle ':completion:*' menu select
    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete

    # zsh: bindkey '^[[A' / '^[[B' history-search-backward / forward
    Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward

    # zsh: bindkey Home / End / Delete / Ctrl+Right / Ctrl+Left
    Set-PSReadLineKeyHandler -Key Home            -Function BeginningOfLine
    Set-PSReadLineKeyHandler -Key End             -Function EndOfLine
    Set-PSReadLineKeyHandler -Key Delete          -Function DeleteChar
    Set-PSReadLineKeyHandler -Key Ctrl+RightArrow -Function ForwardWord
    Set-PSReadLineKeyHandler -Key Ctrl+LeftArrow  -Function BackwardWord
}

################################
# Directory stack
# zsh AUTO_PUSHD / PUSHD_IGNORE_DUPS / PUSHD_SILENT need no porting: PowerShell 7
# maintains its own location stack and `cd -` / `cd +` work natively, which also
# covers .zshrc's `alias -- -='cd -'` (a bare `-` cannot be a command here — the
# parser reads it as an operator — so there is nothing to alias).

################################
# Navigation (zsh: alias ..='cd ..')
# These must be functions, not aliases — PowerShell aliases cannot take arguments.
function .. { Set-Location .. }
function ... { Set-Location ../.. }
function .... { Set-Location ../../.. }

# zsh: mkcd()
function mkcd {
    param([Parameter(Mandatory)][string]$Path)
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
    Set-Location -LiteralPath $Path
}

################################
# PATH
# Pick up anything added to the registry PATH since this process tree started.
# Windows only hands a process the PATH that existed when it was created, and an
# installer that writes the Machine PATH (winget puts starship, bottom and Neovim
# there) is invisible to every shell descended from an older session. Over ssh that
# session can be days old, so "just open a new terminal" does not help: the new
# terminal is a child of the same stale cmd.exe, the tools look absent, and the
# features that depend on them — the prompt included — silently do not load.
#
# Append rather than prepend, so entries this process added on purpose keep winning.
foreach ($scope in 'Machine', 'User') {
    foreach ($dir in ([Environment]::GetEnvironmentVariable('Path', $scope) -split ';')) {
        if ($dir -and ($env:PATH -split ';' -notcontains $dir)) { $env:PATH += ";$dir" }
    }
}

# zsh: $HOME/bin:$HOME/.local/bin:$HOME/.scripts
$script:PathPrepend = @(
    "$HOME\bin"
    "$HOME\.local\bin"
    "$HOME\.scripts"
    "$HOME\.cargo\bin"
)
foreach ($p in $script:PathPrepend) {
    # [IO.Directory]::Exists over Test-Path: four Test-Path calls measured ~128ms in a
    # cold session, most of it first-cmdlet discovery overhead, against ~0 for the API.
    if ([System.IO.Directory]::Exists($p) -and ($env:PATH -split ';' -notcontains $p)) {
        $env:PATH = "$p;$env:PATH"
    }
}

################################
# Tool probe (zsh: the $+commands[...] checks below)
# Get-Command is the obvious equivalent but costs ~720ms for the FIRST name it
# cannot find: a miss walks all 42 PATH directories against every PATHEXT. With
# two absent tools that alone was over half this profile's load time. Index the
# PATH once with raw directory enumeration instead — ~120ms for the whole set.
# Enumerating every file in every PATH directory walked 13,688 entries here, almost
# all of them DLLs; restricting the pattern to what Windows will actually execute
# leaves 993 and cuts the pass from ~200ms to ~66ms. Keep the resolved path too -
# Import-CachedInit below needs the binary's mtime.
# Exists() first: a stale PATH entry is normal (this machine has two) and letting
# EnumerateFiles throw on it would leave an entry in $Error on every shell start.
$script:ToolPath = [System.Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($dir in ($env:PATH -split ';')) {
    if (-not $dir -or -not [System.IO.Directory]::Exists($dir)) { continue }
    foreach ($pattern in '*.exe', '*.com', '*.cmd', '*.bat', '*.ps1') {
        try {
            foreach ($file in [System.IO.Directory]::EnumerateFiles($dir, $pattern)) {
                $name = [System.IO.Path]::GetFileNameWithoutExtension($file)
                # First hit wins, so the dictionary follows PATH precedence.
                if (-not $script:ToolPath.ContainsKey($name)) { $script:ToolPath[$name] = $file }
            }
        } catch { }   # unreadable directory
    }
}

# Executables on PATH only - not cmdlets, functions or aliases, which is exactly
# what the checks below mean by "is this tool installed".
function Test-Tool {
    param([Parameter(Mandatory)][string]$Name)
    $script:ToolPath.ContainsKey($Name)
}

# Shell-init scripts (starship, zoxide, fnm, uv) are identical on every launch, so
# running the generator per shell spends a process spawn - two, for starship, whose
# `init powershell` only emits a line that re-runs starship with --print-full-init -
# to print bytes we already had. Cache to TEMP and invalidate on the tool's own
# mtime, which is what an upgrade changes.
function Import-CachedInit {
    param(
        [Parameter(Mandatory)][string]$Tool,
        [Parameter(Mandatory)][scriptblock]$Generate
    )
    $cache = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "pwsh-init-$Tool.ps1")
    $fresh = [System.IO.File]::Exists($cache) -and
             [System.IO.File]::GetLastWriteTimeUtc($cache) -gt
             [System.IO.File]::GetLastWriteTimeUtc($script:ToolPath[$Tool])
    if (-not $fresh) {
        $generated = & $Generate | Out-String
        if ($generated.Trim()) { [System.IO.File]::WriteAllText($cache, $generated) }
    }
    if ([System.IO.File]::Exists($cache)) { . $cache }
}

################################
# Environment
$env:EDITOR = 'nvim'
$env:PNPM_HOME = if ($env:PNPM_HOME) { $env:PNPM_HOME } else { "$env:LOCALAPPDATA\pnpm" }
# .NET rather than Test-Path, for the same reason as the PATH block above: these were
# the first cmdlets in the session and cost ~175ms between them.
if ([System.IO.Directory]::Exists($env:PNPM_HOME) -and ($env:PATH -split ';' -notcontains $env:PNPM_HOME)) {
    $env:PATH = "$env:PNPM_HOME;$env:PATH"
}
$env:BUN_INSTALL = "$HOME\.bun"
if ([System.IO.Directory]::Exists("$env:BUN_INSTALL\bin")) { $env:PATH = "$env:BUN_INSTALL\bin;$env:PATH" }

# zsh sets keychain on Darwin, file elsewhere. Windows has no keychain backend.
$env:AWS_VAULT_BACKEND = 'file'

################################
# Scoped environment file loader (zsh: _source_env_file)
# Deliberately not a loop over every ~/.envs/*.env — most of those hold secrets
# that would otherwise be inherited by every child process.
function Import-EnvFile {
    param([Parameter(Mandatory)][string]$Path)
    if (-not [System.IO.File]::Exists($Path)) { return $false }
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        if ($line -match '^\s*(#|$)') { continue }
        $kv = $line -replace '^\s*export\s+', ''
        $i = $kv.IndexOf('=')
        if ($i -lt 1) { continue }
        $name = $kv.Substring(0, $i).Trim()
        $value = $kv.Substring($i + 1).Trim().Trim('"', "'")
        Set-Item -Path "Env:$name" -Value $value
    }
    return $true
}

################################
# Modern CLI Tools
# Guarded the same way as .zshrc's $+commands checks, so installing a tool later
# lights up its aliases with no edit here.
#
# Split by whether the name SHADOWS something that already exists. The additive
# names below are new words — nothing can be expecting them to mean anything else —
# so they are defined unconditionally and work in scripts and agent shells too.
if (Test-Tool eza) {
    function ll { eza -la --icons --git @args }
    function la { eza -a --icons @args }
    function lt { eza -T --icons @args }
}

if (Test-Tool delta) { $env:GIT_PAGER = 'delta' }

if (Test-Tool nvim) {
    function vim { nvim @args }
    function vi { nvim @args }
    function vimdiff { nvim -d @args }
}

# The shadowing ones are interactive-only, and this is a correctness line, not a
# performance one. `ps` as procs returns text where Get-Process returns objects, so
# any `ps | Where-Object Name -eq ...` in a script breaks; `find` and `grep` as fd and
# rg take different flags than anything calling them would expect. At a prompt those
# are exactly what is wanted, which is also why .zshrc — sourced by interactive zsh
# alone — was never in a position to affect a script in the first place.
# Remove-Alias first: aliases outrank functions in PowerShell's command resolution.
if ($script:Interactive) {
    if (Test-Tool eza) {
        Remove-Alias ls -Force -ErrorAction SilentlyContinue
        function ls { eza --icons @args }
    }
    if (Test-Tool procs) {
        Remove-Alias ps -Force -ErrorAction SilentlyContinue
        function ps { procs @args }
    }
    if (Test-Tool fd) { function find { fd @args } }
    if (Test-Tool rg) { function grep { rg @args } }
    if (Test-Tool dust) { function du { dust @args } }
    if (Test-Tool btm) {
        function top { btm @args }
        function htop { btm @args }
    }
}

################################
# fzf (zsh: ~/.fzf.zsh + Aloxaf/fzf-tab)
# PSFzf is the closest analogue: Ctrl+T file picker, Alt+C directory jump, Ctrl+R
# over history. Install with: Install-Module PSFzf -Scope CurrentUser
#
# Importing it costs ~396ms, by far the largest item in this profile, and every bit
# of it buys three key handlers that most shells never press. So register stubs that
# import on first press and then hand off to PSFzf's own handler - its
# Invoke-FzfPsReadlineHandler* functions are exported, which is what makes the
# hand-off possible without knowing the scriptblock PSFzf would have bound.
#
# -TabExpansion is deliberately not enabled: it rebinds Tab to TabCompleteNext
# (cycling), and fzf only engages on a `**` token. MenuComplete above is the closer
# match to the `zstyle menu select` being ported here, and Ctrl+T already covers
# fuzzy file insertion.
if ($script:Interactive -and (Test-Tool fzf) -and
    (Get-Module PSFzf -ListAvailable -ErrorAction Ignore)) {
    $global:PsFzfHandlers = [ordered]@{
        'Ctrl+t' = 'Invoke-FzfPsReadlineHandlerProvider'
        'Ctrl+r' = 'Invoke-FzfPsReadlineHandlerHistory'
        'Alt+c'  = 'Invoke-FzfPsReadlineHandlerSetLocation'
    }
    foreach ($chord in @($global:PsFzfHandlers.Keys)) {
        # The handler name is baked into each stub rather than looked up from $key at
        # press time: the handler's $key is a [ConsoleKeyInfo], whose ToString() is
        # "System.ConsoleKeyInfo", not a chord name, so a lookup by key cannot work.
        $stub = @"
if (-not (Get-Module PSFzf)) {
    Import-Module PSFzf -ErrorAction SilentlyContinue
    foreach (`$c in @(`$global:PsFzfHandlers.Keys)) {
        Set-PSReadLineKeyHandler -Chord `$c -ScriptBlock ([scriptblock]::Create(`$global:PsFzfHandlers[`$c]))
    }
}
$($global:PsFzfHandlers[$chord])
"@
        Set-PSReadLineKeyHandler -Chord $chord `
            -BriefDescription "PSFzf $chord (loads on first press)" `
            -ScriptBlock ([scriptblock]::Create($stub))
    }
}

################################
# zoxide — no .zshrc counterpart, but it is the better answer to AUTO_CD, which
# PowerShell cannot express without taking over CommandNotFoundAction (already
# claimed by the PowerToys WinGet module).
if (Test-Tool zoxide) {
    Import-CachedInit zoxide { zoxide init powershell --cmd z }
}

################################
# fnm (zsh: NVM_DIR lazy-load block)
# nvm has no Windows build. fnm is the native equivalent and is already lazy —
# `--use-on-cd` switches versions per directory, so the lazy-load shims that
# .zshrc defines for node/npm/npx/pnpm/nvm/tsx are unnecessary.
if (Test-Tool fnm) {
    Import-CachedInit fnm { fnm env --use-on-cd --shell powershell }
}

################################
# uv — cached completion (zsh: regenerate at most once a day)
# 736KB of generated completion, and it only registers tab completion, so a
# redirected shell pays ~67ms to parse something it can never use.
if ($script:Interactive -and (Test-Tool uv)) {
    Import-CachedInit uv { uv generate-shell-completion powershell }
}

################################
# Stand-in for `command env VAR=... cmd`: set, run, restore. PowerShell has no
# per-command environment prefix, and these tokens must not leak into the shell.
function Invoke-WithEnv {
    param(
        [Parameter(Mandatory)][hashtable]$Env,
        [Parameter(Mandatory)][scriptblock]$Script,
        [object[]]$Arguments = @()
    )
    $saved = @{}
    foreach ($k in $Env.Keys) {
        $saved[$k] = [System.Environment]::GetEnvironmentVariable($k)
        Set-Item -Path "Env:$k" -Value $Env[$k]
    }
    try { & $Script @Arguments }
    finally {
        foreach ($k in $Env.Keys) {
            if ($null -eq $saved[$k]) { Remove-Item -Path "Env:$k" -ErrorAction SilentlyContinue }
            else { Set-Item -Path "Env:$k" -Value $saved[$k] }
        }
    }
}

################################
# Agent CLIs (zsh: aliases c / cx / oc and the codex trust-sync wrapper)
function c { claude --dangerously-skip-permissions @args }
if (Test-Tool codex) {
    function cx { codex --yolo @args }
}
if (Test-Tool opencode) {
    function oc { opencode @args }
}

# zsh: claude_with_kimi_env / alias cck
function Invoke-ClaudeWithKimi {
    Import-EnvFile "$HOME\.envs\kimi.env" | Out-Null
    if (-not $env:KIMI_K3_TOKEN) {
        Write-Error 'KIMI_K3_TOKEN is not set (expected in ~/.envs/kimi.env). Create a key at https://www.kimi.com/code'
        return
    }
    $model = if ($env:KIMI_MODEL) { $env:KIMI_MODEL } else { 'k3[1m]' }
    $ctx = if ($env:KIMI_CONTEXT_TOKENS) { $env:KIMI_CONTEXT_TOKENS } else { '1048576' }
    Invoke-WithEnv -Env @{
        ANTHROPIC_BASE_URL            = if ($env:KIMI_BASE_URL) { $env:KIMI_BASE_URL } else { 'https://api.kimi.com/coding/' }
        ANTHROPIC_API_KEY             = ''
        CLAUDE_CODE_OAUTH_TOKEN       = ''
        ANTHROPIC_AUTH_TOKEN          = $env:KIMI_K3_TOKEN
        ANTHROPIC_MODEL               = $model
        ANTHROPIC_DEFAULT_FABLE_MODEL = $model
        ANTHROPIC_DEFAULT_OPUS_MODEL  = $model
        ANTHROPIC_DEFAULT_SONNET_MODEL = $model
        ANTHROPIC_DEFAULT_HAIKU_MODEL = $model
        CLAUDE_CODE_SUBAGENT_MODEL    = $model
        CLAUDE_CODE_EFFORT_LEVEL      = 'high'
        CLAUDE_CODE_AUTO_COMPACT_WINDOW = $ctx
        CLAUDE_CODE_MAX_CONTEXT_TOKENS  = $ctx
        API_TIMEOUT_MS                = '3000000'
    } -Script { claude --dangerously-skip-permissions @args } -Arguments $args
}
Set-Alias cck Invoke-ClaudeWithKimi -Force

# zsh: claude_with_glm_env / alias ccg
function Invoke-ClaudeWithGlm {
    Import-EnvFile "$HOME\.envs\glm.env" | Out-Null
    if (-not $env:GLM_AUTH_TOKEN -or -not $env:GLM_BASE_URL) {
        Write-Error 'GLM_AUTH_TOKEN and GLM_BASE_URL must be set in ~/.envs/glm.env.'
        return
    }
    $model = if ($env:GLM_MODEL) { $env:GLM_MODEL } else { 'glm-5.2-superglm' }
    $ctx = if ($env:GLM_CONTEXT_TOKENS) { $env:GLM_CONTEXT_TOKENS } else { '262144' }
    $note = "This Claude Code session uses the API backend model $model. If asked for your model name or identity, report the API model identifier $model; do not claim to be Claude Fable."
    Invoke-WithEnv -Env @{
        ANTHROPIC_BASE_URL            = $env:GLM_BASE_URL
        ANTHROPIC_API_KEY             = ''
        CLAUDE_CODE_OAUTH_TOKEN       = ''
        ANTHROPIC_AUTH_TOKEN          = $env:GLM_AUTH_TOKEN
        API_TIMEOUT_MS                = '3000000'
        ANTHROPIC_MODEL               = $model
        ANTHROPIC_DEFAULT_FABLE_MODEL = $model
        ANTHROPIC_DEFAULT_OPUS_MODEL  = $model
        ANTHROPIC_DEFAULT_SONNET_MODEL = $model
        ANTHROPIC_DEFAULT_HAIKU_MODEL = $model
        CLAUDE_CODE_SUBAGENT_MODEL    = $model
        CLAUDE_CODE_AUTO_COMPACT_WINDOW = $ctx
        CLAUDE_CODE_MAX_CONTEXT_TOKENS  = $ctx
    } -Script { claude --dangerously-skip-permissions --append-system-prompt $note @args } -Arguments $args
}
Set-Alias ccg Invoke-ClaudeWithGlm -Force

################################
# Bitwarden (zsh: bw_with_session / alias bwx)
# BW_SESSION stays out of the global environment so child processes cannot
# unlock the vault through an inherited variable.
if (Test-Tool bw) {
    function bwx {
        $sessionFile = "$HOME\.bw_session"
        if (-not (Test-Path $sessionFile)) {
            Write-Error "No session file at $sessionFile"
            return
        }
        Invoke-WithEnv -Env @{ BW_SESSION = (Get-Content -Raw $sessionFile).Trim() } `
                       -Script { bw @args } -Arguments $args
    }
}

################################
# rmux (Windows stand-in for the zellij zs/za/zl/zx aliases)
if (Test-Tool rmux) {
    function rs { rmux new-session -A -s @args }
    function ra { rmux attach-session -t @args }
    function rl { rmux list-sessions }
    function rx { rmux kill-session -t @args }

    # The t* names from the oh-my-zsh tmux plugin, backed by rmux. This mirrors the
    # block configs/.zshrc sets up in the same spirit, so the same shortcuts work on
    # every machine — including `ts` meaning `new-session -s` and `to` meaning
    # `new-session -A -s`, which is the plugin's split and not an obvious one.
    #
    # Both call shapes the plugin accepted: a bare name (`ta work`) gets the name flag
    # inserted, anything starting with a dash (`ta -t work`) is passed straight through.
    # Every argument is passed by name. Positionally, PowerShell reads a value like
    # '-t' as an attempt to name a parameter and the binding fails outright.
    function Invoke-RmuxSession {
        param(
            [string]$Action,
            [string]$NameFlag,
            [string]$ExtraFlag,
            [string[]]$Rest
        )
        $argv = @($Action)
        if ($ExtraFlag) { $argv += $ExtraFlag }
        if ($Rest -and $Rest.Count -gt 0 -and $Rest[0] -notlike '-*') { $argv += $NameFlag }
        if ($Rest) { rmux @argv @Rest } else { rmux @argv }
    }

    function ta   { Invoke-RmuxSession -Action attach-session -NameFlag '-t' -ExtraFlag ''   -Rest $args }
    function tad  { Invoke-RmuxSession -Action attach-session -NameFlag '-t' -ExtraFlag '-d' -Rest $args }
    function ts   { Invoke-RmuxSession -Action new-session    -NameFlag '-s' -ExtraFlag ''   -Rest $args }
    function to   { Invoke-RmuxSession -Action new-session    -NameFlag '-s' -ExtraFlag '-A' -Rest $args }
    function tkss { Invoke-RmuxSession -Action kill-session   -NameFlag '-t' -ExtraFlag ''   -Rest $args }
    function tl   { rmux list-sessions @args }
    function tksv { rmux kill-server @args }

    # tds: one stable session per directory. .zshrc derives the suffix with `cksum`,
    # which has no PowerShell equivalent worth reimplementing bit-for-bit; sessions are
    # per-machine anyway, so this uses a truncated MD5 of the path instead. Same
    # property — same directory, same session — different name than on zsh.
    function tds {
        $leaf = Split-Path -Leaf $PWD.Path
        # At a drive root the leaf is the root itself ("C:\"), and rmux does not reject
        # a name containing ':' — it silently rewrites it ("C:\-abc" becomes "C_\\-abc"),
        # leaving a session that `tkss` cannot find under the name you asked for. Reduce
        # a root to its drive letter and replace anything else rmux would rewrite.
        if (-not $leaf -or $leaf -match '^[A-Za-z]:\\?$') { $leaf = $PWD.Drive.Name }
        $leaf = $leaf -replace '[^\w.-]', '_'

        $md5 = [System.Security.Cryptography.MD5]::Create()
        try {
            $hash = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($PWD.Path))
        } finally { $md5.Dispose() }
        $digest = -join ($hash[0..3] | ForEach-Object { $_.ToString('x2') })

        rmux new-session -A -s ("{0}-{1}" -f $leaf, $digest)
    }
}

################################
# starship prompt (replaces Powerlevel10k)
# STARSHIP_CONFIG is pinned so this never picks up ~/.config/starship.toml,
# which belongs to the cship statusline and is not a shell prompt.
# Interactive only, and not just to save the ~160ms: starship's init registers an
# Enter key handler and calls Set-PSReadLineOption, which drags PSReadLine into a
# shell that the guard above just finished keeping it out of. Note the 160ms is
# mostly starship's own doing - its init spawns starship once more to fetch the
# continuation prompt, which caching the init cannot avoid.
if ($script:Interactive -and (Test-Tool starship)) {
    $starshipConfig = [System.IO.Path]::Combine($PSScriptRoot, 'starship.toml')
    if ([System.IO.File]::Exists($starshipConfig)) { $env:STARSHIP_CONFIG = $starshipConfig }
    # --print-full-init is what `init powershell` shells out to anyway, so asking for
    # it directly is one process instead of two, and the cache makes it none.
    Import-CachedInit starship { starship init powershell --print-full-init }
}

################################
# Machine-local additions. This file is tracked in a PUBLIC repo, so anything
# work-specific — and anything an installer wants to append — belongs here.
$localProfile = [System.IO.Path]::Combine([System.IO.Path]::GetDirectoryName($PROFILE), 'profile.local.ps1')
if ([System.IO.File]::Exists($localProfile)) { . $localProfile }
