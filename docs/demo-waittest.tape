# Settings installer — the README GIF.
#
#   vhs docs/demo.tape   →   docs/demo.gif
#
# What the viewer sees is the real installer: the real progress box, the real
# braille spinner, the real symlinks, the real summary. What it installs is
# nothing at all — docs/demo-setup.sh puts a fake HOME and a directory of
# shims in front of it. docs/demo-README.md has the whole story.
#
# Arc:
#   0–2s    the command      — `./install.sh --core`, the line from the README
#   2–18s   the run          — five components, the bar filling behind them
#   18–23s  the summary      — what was installed, what was skipped, what was
#                              symlinked, and the completion box
#
# The run's length is the sum of the shim delays in demo-setup.sh, so the
# single `Sleep` below is timed against it rather than against real work.
# Change one and re-time the other.

Output docs/demo-waittest.gif

# ffmpeg is what turns the captured frames into the GIF, and VHS reports its
# absence in a way that reads like a font problem. Fail on the tape instead.
Require bash
Require ffmpeg

Set Shell bash
Set FontFamily "JetBrainsMono Nerd Font Mono"
Set FontSize 14
# 1000x510 at font 14 is 103x25, and neither number is cosmetic.
#
# The width is set by the longest line the installer prints: the `✓ Linked:
# <repo path> -> <sandbox path>` lines and their echo in the summary reach
# ~91 columns, and wrapping them turns the tidiest frames in the recording
# into ragged ones.
#
# The height is set from the other end. Component output starts on row 8,
# under the header, and the longest component (zsh, 14 lines) ends on row
# 21 — so 25 rows means nothing scrolls mid-run, while the closing summary,
# longer than any screen, scrolls until it ends on the completion box. Give
# it 36 rows and two thirds of every mid-run frame is empty, which at README
# scale costs the text its legibility.
#
# Re-measure with a throwaway tape that echoes `tput cols` before changing
# either number.
Set Width 1000
Set Height 510
Set Padding 20
Set Theme "GitHub Dark"
Set TypingSpeed 55ms

# ── Prelude — invisible setup ────────────────────────────────────────────
# Everything here is typed at 1ms and hidden. demo-setup.sh owns the whole
# fixture; keeping it out of the visible recording matters because every
# line here is one vhs types, at typing speed, on every render.
Hide
Set TypingSpeed 1ms
Type `eval "$(bash docs/demo-setup.sh 2>/dev/null)"`
Enter
Type "PS1='$ '"
Enter
Type "clear"
Enter
Set TypingSpeed 55ms
Show

# ── 1. The command (0–2s) ────────────────────────────────────────────────
Sleep 800ms
Type "./install.sh --core"
Sleep 700ms
Enter

# ── 2. The run, then the summary (2–22s) ─────────────────────────────────
# base → zsh → nvim → tmux → tools, with the bar redrawn at each step and
# the spinner running under it. The run takes ~17s — the sum of the shim
# delays in demo-setup.sh, not of any real work — and the remaining ~5s
# hold on the summary and the completion box.
#
# This is a fixed sleep rather than `Wait+Screen /Installation Complete!/`
# because Wait and the recorder contend for the same CDP connection: the
# terminal stops draining partway through the run, the screen freezes
# mid-summary, and the wait times out on a recording that had in fact
# already finished. If you change a shim delay, re-time the run and change
# this number with it.
Wait+Screen@300s /Installation Complete!/
Sleep 2s

# ── Postlude — remove the sandbox ────────────────────────────────────────
Hide
Set TypingSpeed 1ms
Type "bash docs/demo-teardown.sh"
Enter
Sleep 2s
Show
