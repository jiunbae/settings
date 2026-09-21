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

## What has been done, and what has not

The vault holds 39 kitbag items, pushed from this machine. `./install.sh
secrets` restores with kitbag. The round trip has been checked with this
machine's own files, through an `age` store into a throwaway `$HOME`: 36 of 36
came back byte for byte, every one of them `0600`. The public half of the SSH
key is not stored and does not need to be — `ssh-keygen -y` derives it from the
private key, and it matches.

Still true, and worth keeping in view:

Reading back has since been checked against the real vault too, by restoring
into a throwaway `$HOME`: all 36 files came back byte for byte at `0600`,
including the one stored as an attachment. Worth knowing that
`kitbag restore --backend bw --dry-run` does **not** check this — it is fast
precisely because it reads nothing, comparing the store's hashes against the
files here and fetching only what differs.

Still true:

- **No machine has been set up from the vault with kitbag.** Restoring into a
  throwaway home is not the same as a machine coming up on it.
- The other machines still restore with `SETTINGS_SECRETS_ENGINE=bash`, and
  their manifest is untouched. They move across one at a time.
- The `op` and `pass` stores are tested against stub clients, not real accounts.
- `kitbag apply` covers packages, links, macOS defaults, downloads, clones,
  merges and commands. The modules here are not ported to it, and
  `./install.sh` remains what installs a machine.

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
= 38 unchanged   ? 1 not comparable
```

`app:aas` exports credentials that rotate on their own, so its bytes differ
between two exports a moment apart. It is marked `volatile`: kitbag sends it
every time and declines to call that a change, because nothing was observed to
change. An item that can never read `=` would otherwise shout on every run
until the report stopped being read.

The other two application bundles pipe through `gzip -n`. Plain `tar -czf`
stamps the current time into the gzip header, so the same unchanged files
produce different bytes once a second — which two exports run back to back will
not show you.
