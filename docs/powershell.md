# PowerShell profile performance

How `configs/powershell/profile.ps1` got from 1354ms to 394ms, and why each step was
worth it. Setup instructions are in [windows.md](windows.md#powershell).


A profile runs on every shell, so it is measured rather than guessed. Medians of 9
interleaved runs of `pwsh -NoProfile -Command "… ; . profile.ps1"` against a 171ms
bare-shell baseline, on a 42-entry PATH:

| | Scripted shell | Profile's own cost |
| :--- | ---: | ---: |
| First working version | 1354 ms | 1183 ms |
| `Test-Tool` instead of `Get-Command` | 783 ms | 613 ms |
| After the rest of the passes below | **405 ms** | **222 ms** |

~123ms of what remains is engine warm-up, not profile work.

The techniques, in order of what they were worth:

- **Never `Get-Command` a tool that might be absent.** A miss walks every PATH
  directory against every `PATHEXT` — ~720ms for the first one. `Test-Tool` reads a
  dictionary built from a single pass over PATH. Restricting that pass to
  `*.exe,*.com,*.cmd,*.bat,*.ps1` cut it from 13,688 files (~200ms) to 993 (~66ms).
- **Guard everything interactive on `$script:Interactive`.** This is the faithful
  port, not just an optimization: `.zshrc` is only sourced by interactive zsh in the
  first place. It skips PSReadLine, starship (~160ms) and the uv completion (~67ms,
  736KB of generated script) in a scripted shell. Decide it from pwsh's own argv
  (`-Command`, `-File`, `-NonInteractive`), **not** from `[Console]::IsOutputRedirected`
  — Windows OpenSSH gives a child process pipes instead of a console, so the stream
  test calls an interactive ssh session scripted and throws the prompt away.
- **Refresh PATH from the registry first.** A process inherits the PATH that existed
  when it was created, so a tool installed into the Machine PATH afterwards (winget
  does this for starship, bottom and Neovim) is invisible to every shell descended
  from an older session — over ssh, opening a "new terminal" just forks the same
  stale `cmd.exe`. Without this the tool probe reports the tool absent and the prompt
  quietly never loads. ~32ms, appended so deliberate process additions still win.
- **Shadowing aliases are interactive-only; additive ones are not.** `ps` as procs
  prints text where `Get-Process` returns objects, and `find`/`grep` as fd/rg take
  different flags, so those belong behind the same guard on correctness grounds.
  `ll`, `la`, `lt`, `vim`, `z` and the agent wrappers introduce new names that cannot
  collide, so they stay available in scripts and agent shells.
- **Cache shell-init output.** `starship`, `zoxide`, `fnm` and `uv` print the same
  script on every launch. `Import-CachedInit` caches to `$env:TEMP`, invalidated on
  the tool's own mtime. `starship init powershell` is worth special mention: all it
  emits is a line that runs starship *again* with `--print-full-init`, so the
  uncached path spawned it twice.
- **`[System.IO.*]` instead of `Test-Path` / `Get-Content`.** Not for the I/O — for
  the cmdlet. The first cmdlet invocation in a fresh pwsh costs ~123ms of engine
  warm-up no matter which one it is (one cmdlet 123ms, two 124ms, none 2ms), so it
  is only worth paying where a cmdlet is actually needed.
- **Defer PSFzf to its first keypress.** Importing it costs ~396ms for three key
  handlers. Stubs on Ctrl+T / Ctrl+R / Alt+C import on demand and then re-point
  themselves at PSFzf's exported `Invoke-FzfPsReadlineHandler*` functions.

> [!TIP]
> `Measure-Script` from [PSProfiler](https://github.com/IISResetMe/PSProfiler) gives
> per-line costs, and inserting `[Stopwatch]` marks at each section header gives
> per-section ones. Both were needed here: the line-level view found the PATH scan,
> the section view found that starship was still spawning a second process.
