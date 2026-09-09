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
# PSReadLine
Import-Module PSReadLine

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

# zsh: WORDCHARS='' — treat every special char as a word boundary so ESC+Backspace
# and Ctrl+W stop at punctuation instead of eating a whole path.
Set-PSReadLineOption -WordDelimiters ' /\()"''-_=+:;,.[]{}<>|!?*&^%$#@~`'

# zsh: zsh-autosuggestions (ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=7')
# Prediction needs a real VT-capable console: it throws when stdout is redirected
# (a piped `pwsh -Command`, a CI step, an agent's shell tool), which would print a
# red error on every such invocation. $Host.UI.SupportsVirtualTerminal stays true in
# that case, so test the redirection directly.
if (-not [Console]::IsOutputRedirected) {
    Set-PSReadLineOption -PredictionSource HistoryAndPlugin
    Set-PSReadLineOption -PredictionViewStyle InlineView
    Set-PSReadLineOption -Colors @{ InlinePrediction = "$([char]27)[90m" }
}

# zsh: zstyle ':completion:*' menu select (+ fzf-tab, wired below if PSFzf is present)
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
# PATH (zsh: $HOME/bin:$HOME/.local/bin:$HOME/.scripts)
$script:PathPrepend = @(
    "$HOME\bin"
    "$HOME\.local\bin"
    "$HOME\.scripts"
    "$HOME\.cargo\bin"
)
foreach ($p in $script:PathPrepend) {
    if ((Test-Path $p) -and ($env:PATH -split ';' -notcontains $p)) {
        $env:PATH = "$p;$env:PATH"
    }
}

################################
# Tool probe (zsh: the $+commands[...] checks below)
# Get-Command is the obvious equivalent but costs ~720ms for the FIRST name it
# cannot find: a miss walks all 42 PATH directories against every PATHEXT. With
# two absent tools that alone was over half this profile's load time. Index the
# PATH once with raw directory enumeration instead — ~120ms for the whole set.
$script:PathExe = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
# Exists() first: a stale PATH entry is normal (this machine has two) and letting
# EnumerateFiles throw on it would leave an entry in $Error on every shell start.
foreach ($dir in ($env:PATH -split ';')) {
    if (-not $dir -or -not [System.IO.Directory]::Exists($dir)) { continue }
    try {
        foreach ($file in [System.IO.Directory]::EnumerateFiles($dir)) {
            [void]$script:PathExe.Add([System.IO.Path]::GetFileNameWithoutExtension($file))
        }
    } catch { }   # unreadable directory
}

# Executables on PATH only — not cmdlets, functions or aliases, which is exactly
# what the checks below mean by "is this tool installed".
function Test-Tool {
    param([Parameter(Mandatory)][string]$Name)
    $script:PathExe.Contains($Name)
}

################################
# Environment
$env:EDITOR = 'nvim'
$env:PNPM_HOME = if ($env:PNPM_HOME) { $env:PNPM_HOME } else { "$env:LOCALAPPDATA\pnpm" }
if ((Test-Path $env:PNPM_HOME) -and ($env:PATH -split ';' -notcontains $env:PNPM_HOME)) {
    $env:PATH = "$env:PNPM_HOME;$env:PATH"
}
$env:BUN_INSTALL = "$HOME\.bun"
if (Test-Path "$env:BUN_INSTALL\bin") { $env:PATH = "$env:BUN_INSTALL\bin;$env:PATH" }

# zsh sets keychain on Darwin, file elsewhere. Windows has no keychain backend.
$env:AWS_VAULT_BACKEND = 'file'

################################
# Scoped environment file loader (zsh: _source_env_file)
# Deliberately not a loop over every ~/.envs/*.env — most of those hold secrets
# that would otherwise be inherited by every child process.
function Import-EnvFile {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    foreach ($line in Get-Content -LiteralPath $Path) {
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
# lights up its aliases with no edit here. ls and ps must have their built-in
# aliases removed first — aliases outrank functions in PowerShell's resolution.
if (Test-Tool eza) {
    Remove-Alias ls -Force -ErrorAction SilentlyContinue
    function ls { eza --icons @args }
    function ll { eza -la --icons --git @args }
    function la { eza -a --icons @args }
    function lt { eza -T --icons @args }
}

if (Test-Tool fd) { function find { fd @args } }
if (Test-Tool rg) { function grep { rg @args } }
if (Test-Tool delta) { $env:GIT_PAGER = 'delta' }
if (Test-Tool dust) { function du { dust @args } }

if (Test-Tool procs) {
    Remove-Alias ps -Force -ErrorAction SilentlyContinue
    function ps { procs @args }
}

if (Test-Tool btm) {
    function top { btm @args }
    function htop { btm @args }
}

if (Test-Tool nvim) {
    function vim { nvim @args }
    function vi { nvim @args }
    function vimdiff { nvim -d @args }
}

################################
# fzf (zsh: ~/.fzf.zsh + Aloxaf/fzf-tab)
# PSFzf is the closest analogue: Ctrl+T file picker, Alt+C directory jump, Ctrl+R
# over history, and Tab expansion standing in for fzf-tab.
# Install with: Install-Module PSFzf -Scope CurrentUser
#
# Importing it costs ~400ms, the largest single item left in this profile, and all
# of it buys interactive key handlers. A redirected shell — a script, a CI step, an
# agent's shell tool — has no use for them, so skip the import there.
if ((Test-Tool fzf) -and -not [Console]::IsInputRedirected -and
    (Get-Module PSFzf -ListAvailable -ErrorAction Ignore)) {
    Import-Module PSFzf -ErrorAction SilentlyContinue
    Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' `
                    -PSReadlineChordReverseHistory 'Ctrl+r' `
                    -PSReadlineChordSetLocation 'Alt+c' `
                    -TabExpansion
}

################################
# zoxide — no .zshrc counterpart, but it is the better answer to AUTO_CD, which
# PowerShell cannot express without taking over CommandNotFoundAction (already
# claimed by the PowerToys WinGet module).
if (Test-Tool zoxide) {
    Invoke-Expression (& { (zoxide init powershell --cmd z | Out-String) })
}

################################
# fnm (zsh: NVM_DIR lazy-load block)
# nvm has no Windows build. fnm is the native equivalent and is already lazy —
# `--use-on-cd` switches versions per directory, so the lazy-load shims that
# .zshrc defines for node/npm/npx/pnpm/nvm/tsx are unnecessary.
if (Test-Tool fnm) {
    fnm env --use-on-cd --shell powershell | Out-String | Invoke-Expression
}

################################
# uv — cached completion (zsh: regenerate at most once a day)
if (Test-Tool uv) {
    $uvComp = Join-Path ([System.IO.Path]::GetTempPath()) 'uv-completion.ps1'
    $stale = -not (Test-Path $uvComp) -or
             ((Get-Item $uvComp).LastWriteTime -lt (Get-Date).AddHours(-24))
    if ($stale) { uv generate-shell-completion powershell > $uvComp 2>$null }
    if (Test-Path $uvComp) { . $uvComp }
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
}

################################
# starship prompt (replaces Powerlevel10k)
# STARSHIP_CONFIG is pinned so this never picks up ~/.config/starship.toml,
# which belongs to the cship statusline and is not a shell prompt.
if (Test-Tool starship) {
    $starshipConfig = Join-Path $PSScriptRoot 'starship.toml'
    if (Test-Path $starshipConfig) { $env:STARSHIP_CONFIG = $starshipConfig }
    Invoke-Expression (& starship init powershell)
}

################################
# Machine-local additions. This file is tracked in a PUBLIC repo, so anything
# work-specific — and anything an installer wants to append — belongs here.
$localProfile = Join-Path (Split-Path -Parent $PROFILE) 'profile.local.ps1'
if (Test-Path $localProfile) { . $localProfile }
