# kitbag

The secrets engine in this repository has been replaced by
[kitbag](https://github.com/Open330/kitbag), a tool that does the same job with
values, errors and types instead of shell.

`./install.sh secrets` restores with kitbag now. `modules/secrets.sh` still
supplies what it always did — the vault server, the login, the 2FA, and this
machine's scope — and hands the restore over.

```bash
./install.sh kitbag            # the binary on its own (pinned, checksummed)
scripts/kitbag-config.sh       # show the config it would build for this machine
scripts/kitbag-config.sh --write
kitbag status                  # what it makes of this machine — reads only
kitbag doctor                  # and whether anything is unmarked or loose
kitbag push --backend bw       # the inverse; replaces scripts/secrets-push.sh
kitbag diff --backend bw       # what differs from the store — shapes, never values
kitbag resolve --backend bw    # settle what neither side can settle alone
kitbag programs                # what is installed here, as a list
```

## Why

Every bug this repository's secrets engine has had came from the same place.
From one week of use:

| What happened | Why |
| --- | --- |
| The list of skipped files printed empty | a variable filled inside `$( )` dies with the subshell |
| A display column shifted by one | bash counts tab as IFS whitespace, so empty fields collapse |
| A push died mid-way, half the vault written and the manifest stale | `set -e` plus one network error |
| Key revocation needed hand-verified quoting every time it changed | ssh inside ssh inside awk |
| A key rotation locked the machine out of the step that completes it | no way to say "these two operations are one" |

None of that is bash used badly. It is bash without values, errors or types,
doing work that needs all three: state comparison, hashing, partial failure,
remote fan-out, and an inventory that has to stay true to what is stored.

## What carries over unchanged

The important thing is that **the markers are the same**. Every file already
says whose it is:

```sh
# scope: work
# owner: acme
```

kitbag reads exactly those, with the same rule that a marker inside a file
beats any table that names the file. So `scripts/kitbag-config.sh` is a
translation, not a migration: it writes down which directories hold marked
files, and the markers already in them do the rest.

Also unchanged: collection is by pattern and never by name, merging never
deletes, and nothing prints a secret's value.

## What is different

| | the older engine | kitbag |
| --- | --- | --- |
| Inventory | a JSON manifest in the vault | each item carries its own scope, owner and path |
| Stores | Bitwarden / Vaultwarden | that, plus 1Password, `pass`, and an `age`-encrypted file with no server at all |
| Machine config | `~/.config/settings/{secrets.scope,secrets-paths}` | `~/.config/kitbag/machine.toml` |
| App state | three hardcoded cases in the push script | any `command = { export, restore }` pair |
| Reports | text | text, and `--json` on every command |

The two write different items, so one vault holds both while machines move
across. Neither deletes what the other wrote.

## The machine that has not moved across

Every machine that already has this repository restores from the manifest, and
that path is still here, reached by name:

```bash
SETTINGS_SECRETS_ENGINE=bash ./install.sh secrets
```

It stays until every machine is across. Then it, `scripts/secrets-push.sh`, and
the manifest go together — except that one machine cannot move across at all.

## The machine that cannot

kitbag publishes `aarch64`/`x86_64` binaries for Darwin and Linux, and nothing for
Windows. The Windows machine restores from the manifest through
`bin/windows/Restore-Secrets.ps1` ([windows.md](windows.md#secrets)), which reads
the same items, the same entries and the same scopes as
`SETTINGS_SECRETS_ENGINE=bash` does everywhere else.

So the manifest and the push that writes it are not only a migration leftover:
they are what one supported machine runs on. They can be retired when kitbag
ships a Windows build, and not before.

## Declaring a machine's scope

This decides what `push` sends and what `restore` takes, so it is worth being
explicit:

```bash
echo personal > ~/.config/settings/secrets.scope    # or: work / shared / all
```

A machine that declares nothing used to fall back to `personal`. That is right
for an empty machine and wrong for a full one — this machine held work and
shared files and would have pushed **16 of its 39 items**, reporting only that
it sent what it sent. So `scripts/kitbag-config.sh` now reads the scopes off
the markers already on disk when nothing is declared, and says that it did.

## Starting from nothing

```bash
kitbag backup
```

One command: which store, which scopes this machine takes, then what it found —
one item at a time. It runs nothing that `discover`, `push` and `resolve` do not,
so there is no second behaviour to keep in step with them.

`scripts/kitbag-config.sh` is still what this repository's machines use. It
knows things a general walkthrough cannot: which tracks are macOS-only, which
app exports need quitting first, which installers arrive as `curl … | sh`. The
walkthrough is for a machine that is not this repository's.

## What this repository already keeps, and kitbag does not

`bin/`, `scripts/`, `configs/` and `modules/` live in git here, and `~/.zshrc`,
`~/.tmux.conf`, `~/.config/nvim` and nine scripts in `~/.local/bin` are
symlinks into them. They are backed up — by this repository — and kitbag says
so rather than keeping a second copy:

```
14 already kept by a git repository, so not proposed:
  ~/.zshrc                               ~/workspace/settings
  ~/.local/bin/mkln                      ~/workspace/settings
Whatever keeps that repository keeps these.
```

It is asked of every file a pattern matches, not the first, so a `bin`
directory holding one linked script and one loose one offers the loose one.

The installed binaries in the same directory — `kitbag`, `starship`, `cship` —
are never offered at all. A track can say `only = "scripts"`, which takes the
files beginning `#!`: a store has no business keeping a binary built for one
architecture, and `programs` already carries it as a name.

So on these machines kitbag keeps the secrets and the program lists, and git
keeps the rest. On a machine that is *not* this repository's, `kitbag backup`
offers both halves — that is what v0.16.0 added.

## What has been done, and what has not

Four Macs run it: june-mba, june-mbp, jiun-mini and jiun-mbp. Each pushed its
own state, took what it was behind on, and settled what was left by hand; all
four now report nothing outstanding. The round trip was checked before any of
that, through an `age` store into a throwaway `$HOME`: 36 of 36 files came back
byte for byte, every one of them `0600`, including the one stored as an
attachment. The public half of the SSH key is not stored and does not need to
be — `ssh-keygen -y` derives it from the private key, and it matches.

Worth knowing that `kitbag restore --backend bw --dry-run` does **not** check
that — it is fast precisely because it reads nothing, comparing the store's
hashes against the files here and fetching only what differs.

Still true:

- **No machine has been set up from bare metal with kitbag.** Four machines
  that already had their files took kitbag over; that is not the same as one
  coming up on it from nothing.
- **Windows still restores with the shell engine**, and that machine needs
  `ssh:id_ed25519` in its own `secrets.skip` before it restores anything — see
  [windows.md](windows.md).
- **The Linux server has not moved across** and has no settings repo on it yet.
- The two engines share one vault *and one set of item names*. Every reader
  filters on the `kitbag` field to tell one namespace from the other; a tool
  that forgets to will show you two of everything, or delete the wrong one.
- The `op` and `pass` stores are tested against stub clients, not real accounts.
- `kitbag apply` covers packages, links, macOS defaults, downloads, clones,
  merges and commands. The modules here are not ported to it, and
  `./install.sh` remains what installs a machine.

## Things only one machine should own

Four machines keep a private key at `~/.ssh/id_ed25519`. Four different keys,
one path — so one item name, and whoever pushed last would have been the only
one backed up. Refusing to exchange it at all was the first answer, and it left
three of the four keys stored nowhere; a key that exists in one place is gone
with the machine it is on.

```toml
[[track]]
path = "~/.ssh/id_ed25519"
scope = "personal"
per_machine = true
```

What moves is the **item name**, to `ssh:id_ed25519@jiun-mini`, and the
`machine:` header travels with it. The path does not move: the key is written
back to `~/.ssh/id_ed25519`, where ssh looks for it. Each machine backs up its
own and takes nobody else's.

`skip` is the other half of the same question and is not the same answer. It
says *this machine exchanges this item in neither direction* — right for a
machine whose key must never be touched by a restore, wrong as a way of keeping
four keys apart, because it keeps them apart by keeping three of them unsaved.

## Programs, as a list

Binaries do not belong in a vault. They are large, built for one architecture,
and whoever published them will hand them over again. What is worth keeping is
the list:

```bash
kitbag programs
```

```
kitbag/programs 1
brew	ripgrep
cask	ghostty
cargo	kitbag	0.16.0
npm	@bitwarden/cli	2026.8.0
```

Seventy-one entries here, a little over a kilobyte. `scripts/kitbag-config.sh`
emits it as a `per_machine` track — four machines hold four different sets, and
a shared item would mean whoever pushed last decided what the others were
supposed to have.

Restoring it installs what is missing and **removes nothing**: the list is what
a machine must not lack, not what it may not exceed. A manager kitbag cannot
drive is named rather than guessed at, because installing a plausible thing is
worse than saying nothing. It reaches the network and it can take a while, so a
machine that would rather not do this can name `programs` in
`~/.config/settings/secrets.skip` like any other item.

`brew leaves` rather than `brew list`, so what comes back is what somebody
asked for rather than that plus everything dragged in behind it. Sorted, too —
an unordered list differs from itself between two runs, and the store would
report a machine as changed for having named the same things in another order.

### Reading another machine's

```bash
kitbag programs --list                              # which machines wrote one
kitbag programs --from jiun-mbp --backend bw        # read it
kitbag programs --from jiun-mbp --backend bw --restore   # or become it
```

The last one is the point of keeping the list at all: the machine worth copying
is usually the one that is gone.

### Restoring asks first

```
The store holds 39 item(s) for this machine.
Restoring writes over files here and runs the restore commands
the store carries — which can install software.
`kitbag restore --dry-run` says exactly what, and writes nothing.

Go ahead? [y/N]
```

`apply` always asked and `restore` never did, which was fine while restoring
meant writing files — each one is backed up before it is written over, and a
backup can be put back. A `programs` item made restore able to install
software, which reaches the network, takes minutes, and no backup undoes.

`-y` answers in advance and `--only` is already an answer. With no terminal it
writes nothing and says which flag to add, so `./install.sh secrets` passes
`--yes` — the intent belongs where the decision was made, not inferred from
what a pipe means.

### The things no manager will list

`rustup`, `uv`, `cargo-binstall`, `claude`, kitbag itself — everything this
repository installs with `curl … | sh`, which is roughly the fifth of a machine
that no package list describes. `scripts/kitbag-config.sh` declares them:

```toml
[[program]]
name = "uv"
install = "curl -LsSf https://astral.sh/uv/install.sh | sh"
version_from = "uv --version"
```

Each is written out **only if it is actually here** — a declaration nobody has
acted on is a plan, not a fact. The install line travels with the item, for the
same reason a restore command does: the machine that has to run it is the one
being rebuilt, and it has no config yet. kitbag prints the line before running
it.

This is the same list the modules here have always kept, in the one form that
survives the machine they are on. Needs kitbag v0.14.1 or newer.

## Where an item belongs

Scope decides whose an item is. `platform` decides whether a machine has
anywhere to put it:

```toml
[[track]]
name = "app:barshelf"
scope = "personal"
platform = ["macos"]
```

Four items here are macOS and nowhere else — the `aws-vault` keychain and the
aas, OTPeek and BarShelf bundles, all of which restore into `~/Library`.
Without the `platform` tag, the Linux server would take them, write them, and
report a restore that worked.

`platform` travels **in the envelope**, like `path` and for the same reason: the
machine that has to act on it is the one being restored, and that machine has
no config yet. `~/.config/settings/secrets-paths` takes it as a fifth,
comma-separated column.

The words are `macos`, `linux` and `windows` — the same ones the manifest uses,
so one vault answers both engines the same way.

## How application state gets back

Three items here are not files: the aas bundle, the OTPeek vault and
BarShelf's data. They come out of an application and go back into one, so
each track names both ends:

```toml
command = { export = "aas export --all", restore = "aas import -" }
```

The restore half travels **with the item**, because the machine that has to
run it is the one being restored — and a machine being restored does not have
the application installed, so its own config cannot know. A machine that does
already track the item uses its own command; local knowledge is newer.

This means kitbag runs a command it read out of the vault. The vault already
holds every secret on this machine, so it is not a new thing to trust, but it
is a new thing it can do — so the command is named before it runs:

```
+ app:otpeek   into `tar -xzf - -C "$HOME" && sed -i "" ...`  (from the store)
```

Two of those commands do more than untar, and both reasons are easy to lose
in a rewrite:

- **OTPeek** finds its vault through `active_vault`, an absolute path. The
  restore rewrites it for the restoring user, or the CLI goes on looking in
  this machine's home.
- **BarShelf** writes its own state on the way out, so it is quit before its
  data is written over and started again afterwards. Extracting over a running
  app leaves the app to undo the restore.

## When two machines disagree

`status` says an item changed. It cannot say what changed, and moving the
other machines across is where that stops being enough — one of them held
`DOCS_HOST DOCS_URL` where the store held those two plus `DOCS_USER
DOCS_ROOT`, and pushing from it would have dropped two keys with nothing
saying so.

```bash
kitbag diff --backend bw
```

```
~ env:docs-publish
    here   3 lines
    store  5 lines
    only there:  DOCS_ROOT DOCS_USER
    differ:      DOCS_URL
```

Key names, counts, sizes and hashes — never a value from either side. A key
holding something different is named; what it holds is not.

Most of what used to look like a question is not one. kitbag records the
fingerprint at the last exchange — the third point git calls a merge base —
so a difference sorts itself:

```
>  this machine moved, the store did not     push sends it
<  the store moved, this machine did not     restore takes it
!  both moved since they agreed              yours to settle
~  differs, and nothing recorded when        as before
```

A push no longer sends a `<` and a restore no longer takes a `>`: both were
writing an older copy over a newer one. A `!` stops both, writes nothing
over anything, and waits.

```bash
kitbag resolve --backend bw
```

```
! env:one  (1/2)
    here   3 lines
    store  2 lines
    only here:   EXTRA
    differ:      A
    [m]ine  [t]heirs  [s]kip  [q]uit >
```

An answer that is not understood is a skip, and so is an empty line: one of
the two real answers writes over a credential, so the key easiest to hit by
accident does nothing. With no terminal it asks nothing and lists what is
left.

## Four machines pushing at the same moment

That is the ordinary case here, not the unlucky one, and the first time all
four ran together two of them came back refused:

```
✗ app:barshelf   bw edit: The client copy of this cipher is out of date.
```

Which is the store being right. Another machine wrote between this one's
decision and its write. What kitbag does about it now is look again rather
than send again: it re-reads the store and compares the item afresh, and the
comparison decides.

```
still this machine's to send   →  sent, second time
the other machine sent this    →  already there, and recorded
both moved, differently        →  held as a conflict
```

The difference matters. An item that became a conflict four seconds ago is a
conflict, and a retry that just pushed harder would write somebody's work away
with nothing saying so.

One kind of item is exempt, and it is the one that collided hardest.
`app:barshelf` and `app:aas` are `volatile`: they are sent on every push,
because no comparison can say they were not needed. Four machines doing that
to one item collide by design, and there is nothing to win — nobody can
compare those bytes, so a copy that arrived from another machine four seconds
ago is exactly as good as this one. A refused write on a volatile item yields:

```
? app:barshelf                 another machine's copy landed first
1 left to another machine's copy: app:barshelf
```

Not an error, not a retry, and not a fight that resumes on the next push.

The other half of that run was worse and easier to fix: two machines reported
the reason as `(node:73029) [DEP0040] DeprecationWarning: the punycode module
is deprecated`. Node's chatter arrives on the same stream as the reason, and
being first, it was read as the reason. It is skipped now.

All of this needs kitbag v0.12.3 or newer.

Then one item, one direction:

```bash
kitbag restore --backend bw --only env:docs-publish   # take the store's
kitbag push    --backend bw --only app:barshelf       # send this machine's
```

That is different from `skip`, which says *never exchange this* and is right
for a machine's own SSH key. `--only` is for an item that has to go one way,
once.

What neither does is decide. Which side should win is not a thing a tool can
know: of those two machines one had been through a credential split and the
other had not.

## One item reads `?`, and that is the answer

```
= 38 unchanged   ? 2 not comparable
```

`app:aas` exports credentials that rotate on their own, so its bytes differ
between two exports a moment apart. It is marked `volatile`: kitbag sends it
every time and declines to call that a change, because nothing was observed to
change. An item that can never read `=` would otherwise shout on every run
until the report stopped being read.

`app:barshelf` is the second, and it took longer to accept. The app rewrites
its files while it runs — the same bytes, a new mtime — and `tar` records
mtimes, so the archive differs when its contents do not. Two files that are
pure runtime bookkeeping are excluded outright, and the AppleDouble `._name`
entries with them, but the mtimes cannot be normalised: macOS `tar` is bsdtar
and has no `--mtime`, and there is no GNU tar on any of these machines. So the
track says what is true rather than pretending otherwise.

`app:otpeek` nearly became the third, and the reason it did not is worth
keeping. Four machines held a byte-identical OTP vault and produced four
different archives. Comparing the archives to each other, rather than each
machine to itself, found four separate causes stacked on one another:

| Cause | Fix |
| --- | --- |
| gzip stamps the current time into its own header | `gzip -n` |
| `tar` writes `._name` companions for extended attributes, which differ between identical copies | `COPYFILE_DISABLE=1 tar --no-mac-metadata` |
| the archive records who owns the file, and these machines do not all run under one user name | `--uid 0 --gid 0 --uname '' --gname ''` |
| bsdtar writes **pax** by default, and pax headers carry `atime` and `ctime`, which differ on any machine that has so much as read the file | `--format ustar` |

The last one was the largest and the least visible: an export is byte-stable on
one machine all day and still differs from every other machine's.

The fifth cause was not a tar flag. `config.toml` holds one line — an absolute
path to the vault — which the restore has to rewrite for the restoring user
anyway, so shipping it carried no information and one guaranteed difference.
It is no longer in the archive; the restore writes that line, editing in place
if the file already exists so that a machine keeping other settings there keeps
them.

Every one of those was applied to `app:barshelf` too, and it still differs
four ways, which is what settled it: the app rewrites its files as it runs and
tar records mtimes. That is `volatile`, and no flag fixes it.
