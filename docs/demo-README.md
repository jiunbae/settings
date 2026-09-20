# The README GIF — how to regenerate

`docs/demo.gif` is checked into the repo rather than built by CI. Re-record it
whenever the installer's visible surface changes: the progress box, the
spinner, the component names, the summary sections, the `--core` preset.

## Files

| File | Role |
| :--- | :--- |
| [`demo.tape`](demo.tape) | [VHS](https://github.com/charmbracelet/vhs) script. Sets the terminal, types one command, waits out the run. |
| [`demo-setup.sh`](demo-setup.sh) | The sandbox: a fake `HOME`, and a directory of shims that leads `PATH`. Prints the exports the recording shell needs. |
| [`demo-teardown.sh`](demo-teardown.sh) | Removes all of it. Safe at any time, including after a render that died halfway. |
| `demo.gif` | The output. 1000×510, ~290 KB, ~24 s. |

## Recording

```bash
vhs docs/demo.tape          # writes docs/demo.gif, ~35s
```

That is the whole loop. The tape builds the sandbox in its hidden prelude and
tears it down in its hidden postlude, so nothing is left behind and an
interrupted render does not poison the next one — `demo-setup.sh` tears down
before it builds.

To clean up by hand after a render you killed:

```bash
docs/demo-teardown.sh
```

### What you need

* **VHS — pinned to v0.11.0.** See the version note below; this matters.
* **ttyd and ffmpeg**, which VHS drives (`brew install ttyd ffmpeg`).
* **JetBrains Mono Nerd Font** (`brew install --cask font-jetbrains-mono-nerd-font`).
  Without it the terminal falls back to a font with different metrics and the
  braille spinner, the box-drawing characters and the `✓ ○ ⟶ ℹ` glyphs all
  degrade — usually to dashes, sometimes to double-width boxes that break the
  column count the tape depends on.

> [!IMPORTANT]
> **VHS v0.12.0 cannot produce a GIF.** It runs, prints `Creating
> docs/demo.gif...`, exits 0, and writes nothing. In that release
> `evaluator.go` cancels the recording context in `teardown()` and then hands
> that same cancelled context to `Render()`, which builds the encoder with
> `exec.CommandContext`. Go returns `context canceled` from that without ever
> starting ffmpeg, and VHS prints the error as `log.Println(string(out))` — an
> empty line. It looks exactly like a font or a permissions problem, and it is
> neither.
>
> Checked rather than assumed: building v0.12.0 from the tag reproduces it, so
> it is not a packaging problem, and the same build with that one line changed
> to `context.WithoutCancel(ctx)` writes the GIF. Upstream has it as
> [#787][787], with four open fix PRs ([#788][788], #789, #790, [#791][791]).
> Un-pin once one of them ships in a release, but do not plan around it: the
> fix for the `Wait` bug below has been sitting open since August 2025.
>
> Pin the previous release:
>
> ```bash
> brew uninstall vhs                                   # if installed from brew
> go install github.com/charmbracelet/vhs@v0.11.0      # lands in ~/go/bin
> ln -sf ~/go/bin/vhs ~/.local/bin/vhs                 # ~/.local/bin is on PATH
> vhs --version                                        # expect v0.11.0
> ```
>
> `ttyd` and `ffmpeg` were pulled in as Homebrew dependencies of `vhs`, so
> after uninstalling it they are only kept by having been installed on request
> — `brew install ttyd ffmpeg` marks them that way and stops a later
> `brew autoremove` from taking them.

## What is real, and what is not

Everything the viewer sees the *installer* do is real: the real
`progress_draw_header` box, the real `run_with_spinner` braille frames, real
symlinks, and a summary counted from what actually happened. `install.sh` is
not in on the recording and has no demo mode.

What is faked is everything *outside* it. `demo-setup.sh` points `HOME` at
`/tmp/settings-demo/home` and puts `/tmp/settings-demo/bin` at the front of
`PATH`, holding shims for `brew`, `git`, `curl`, `rustup`, `cargo`, `chsh` and
the rest — each one sleeps for a believable moment and exits 0. Three reasons,
any one of them sufficient:

* a README GIF must not install software on the machine that renders it;
* it must not touch the operator's `$HOME`, which is the one thing a dotfiles
  installer exists to rewrite;
* a real `--core` run takes minutes, and nobody watches a two-minute GIF.

This is why the recording shows `/tmp/settings-demo/home/.zshrc` in the
symlink summary rather than `~/.zshrc`. Left visible on purpose: it is a
truthful frame, and faking the path would be the one dishonest pixel in an
otherwise real recording.

Four details in the sandbox are load-bearing, and each one cost a take:

* **`brew list` must fail.** `pkg_installed` asks Homebrew whether a package is
  present, and a shim that answered 0 there would make every component report
  "(already installed)" — a progress display with nothing to display.
* **`PATH` drops Homebrew and every user bin directory.** Not tidiness: with
  the operator's real `eza`, `nvim` and `tmux` on `PATH`, the tools component
  skips everything and the recording is a wall of green skips.
* **`sudo` is shimmed, not passed through.** A recording that can escalate is a
  recording that can do the one thing the sandbox exists to prevent.
* **`chsh` is shimmed even though `--core` never reaches it.** `install.sh`
  changes the login shell through `lib/platform.sh`, and a missed shim there is
  not a broken GIF — it is a changed login shell on the machine that rendered
  it.

## Tuning the tape

* **Timing is a fixed `Sleep`, and `Wait` is not an option.**
  `Wait+Screen /Installation Complete!/` is the obvious way to write this, and
  it cannot work at any timeout — see the note below. If you change a shim
  delay in `demo-setup.sh`, re-time the run and move the `Sleep` with it:

  ```bash
  eval "$(docs/demo-setup.sh)" && time ./install.sh --core && docs/demo-teardown.sh
  ```

  Do that in a throwaway shell — the `eval` replaces `HOME` and `PATH` in the
  shell that runs it.

* **`SETTINGS_DEMO_SCALE` stretches or compresses every shim delay at once**
  (`SETTINGS_DEMO_SCALE=0.15` builds a sandbox that runs the whole thing in
  three seconds, which is the right way to test a change to the fixture). The
  tape itself always records at scale 1.

* **Terminal size is not cosmetic.** 1000×510 at font 14 is 103×25. The width
  is set by the longest line the installer prints — the `✓ Linked:` lines and
  their echo in the summary reach ~91 columns. The height is set from the other
  end: component output starts on row 8, the longest component (zsh) ends on
  row 21, so nothing scrolls mid-run while the closing summary scrolls until it
  lands on the completion box. Verify new numbers with a throwaway tape that
  echoes `tput cols` rather than trusting the arithmetic.

* **Size.** ~290 KB, which is small enough to leave alone. If the tape ever
  grows enough to matter, VHS emits a 256-colour GIF of content that uses
  maybe forty, and rebuilding it on a 64-colour palette takes ~18% off with no
  visible difference:

  ```bash
  ffmpeg -i docs/demo.gif -vf "palettegen=max_colors=64:stats_mode=diff" -y /tmp/pal.png
  ffmpeg -i docs/demo.gif -i /tmp/pal.png \
    -lavfi "paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" -y /tmp/demo.gif
  ```

## Why the tape cannot use `Wait`

VHS reads the terminal for `Wait+Screen` in `testing.go`:

```js
() => Array(term.rows).fill(0).map((e, i) =>
        term.buffer.active.getLine(i).translateToString().trimEnd())
```

`getLine` takes an **absolute** buffer index, so this is lines `0 … rows-1` of
the buffer — not of the viewport. `CurrentLine()`, the function directly below
it, gets this right (`getLine(cursorY + viewportY)`). Before the terminal has
scrolled the two are the same, which is why `Wait` looks like it works.

The installer's summary is longer than a screen. The moment it scrolls, `Wait`
is comparing against a frozen snapshot of the first screenful — which ends at
`• NeoVim` — and `Installation Complete!` is never in it. Timeouts of 45s and
300s fail on the byte-identical 25 lines — ~28s and ~283s after the run had in
fact finished.

Demonstrated rather than deduced, if you want to check it yourself: a tape that
waits for a string which has already scrolled off *matches*, while one that
waits for the string at the bottom of the live screen *times out* and reports
buffer line 0 as the last value it saw. Rebuild VHS with `getLine(i)` changed
to `getLine(term.buffer.active.viewportY + i)` and both results invert — and
this tape then passes with `Wait+Screen`.

Upstream: [charmbracelet/vhs#659][659], open since August 2025, with the same
diagnosis and the same line. Two fixes for it are already open and unmerged —
[#658][658], which renames `Buffer` to `VisibleLines`, and [#704][704], the
one-line `viewportY` offset — so there is nothing left for us to contribute
there. The unfixed `getLine(i)` is still in v0.11.0, v0.12.0 and `main`, so
pinning a version does not help either; only the fixed `Sleep` does.

Worth knowing even if one of them lands: the discussion on #658 points out that
`Wait+Screen` polls every 10ms, so output that scrolls past the viewport
between two polls can be missed anyway. A summary that prints 38 lines at once
is exactly that race, and a fixed `Sleep` is not in it.

[659]: https://github.com/charmbracelet/vhs/issues/659
[658]: https://github.com/charmbracelet/vhs/pull/658
[704]: https://github.com/charmbracelet/vhs/pull/704
[787]: https://github.com/charmbracelet/vhs/issues/787
[788]: https://github.com/charmbracelet/vhs/pull/788
[791]: https://github.com/charmbracelet/vhs/pull/791

## Troubleshooting

| Symptom | Cause | Fix |
| :--- | :--- | :--- |
| `Creating docs/demo.gif...`, then no file, exit 0 | VHS v0.12.0. | Pin v0.11.0 — see the version note above. |
| `parser: N error(s)`, `Invalid command: tmp` | An absolute path in `Output`. VHS parses it as commands. | Use a repo-relative path and run `vhs` from the repo root. |
| Spinner and box-drawing render as dashes | JetBrains Mono Nerd Font is missing and the terminal fell back. | Install the cask; re-render. |
| Every component says "(already installed)" | The sandbox `PATH` or the `brew` shim was bypassed — usually a tape edited to skip the prelude. | Check that the prelude's `eval` ran before `./install.sh`. |
| The recording cuts off mid-run | A shim delay grew, or the machine is slower than the one that timed the tape. | Re-time the run and raise the `Sleep` in `demo.tape`. |
| `Wait+Screen` times out on text that is plainly on screen | VHS matches against buffer lines `0 … rows-1`, which stop being the viewport as soon as the terminal scrolls. | Not fixable from the tape — use `Sleep`. See the section above. |
| `refusing to remove /tmp/...: no .settings-demo marker` | `SETTINGS_DEMO_ROOT` points at something the setup script did not build. | Correct the variable. The teardown will not delete a directory it does not recognise. |
