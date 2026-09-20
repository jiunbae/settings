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

## What has not been tried yet

- **Nothing has been pushed to the real vault with kitbag** — see below.
- The `op` and `pass` stores are tested against stub clients, not against real
  accounts — neither client is installed here.
- `kitbag apply` covers packages, links, macOS defaults, downloads, clones,
  merges and commands. The modules in this repository are not ported to it, and
  `./install.sh` remains what installs a machine.

The restore path is switched, but a restore reads what a push wrote, and that
push needs the master password:

```bash
export BW_SESSION=$(bw unlock --raw)
kitbag push --backend bw --dry-run     # 39 items expected
kitbag push --backend bw
kitbag status --backend bw             # every item '=' against the store
```

Until that runs, `./install.sh secrets` finds nothing of kitbag's in the vault,
and the machine to restore is the one to run it from.
