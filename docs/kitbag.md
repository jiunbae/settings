# kitbag

The secrets engine in this repository is being replaced by
[kitbag](https://github.com/Open330/kitbag), a tool that does the same job with
values, errors and types instead of shell.

**Nothing in this change alters what `./install.sh secrets` does.** kitbag is
installed alongside it. Until a vault has been pushed with kitbag, the bash
engine is still the one that restores a machine.

```bash
./install.sh kitbag            # install the binary (pinned, checksummed)
scripts/kitbag-config.sh       # show the config it would build for this machine
scripts/kitbag-config.sh --write
kitbag status                  # what it makes of this machine — reads only
kitbag doctor                  # and whether anything is unmarked or loose
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

| | bash engine | kitbag |
| --- | --- | --- |
| Inventory | a JSON manifest in the vault | each item carries its own scope, owner and path |
| Stores | Bitwarden / Vaultwarden | that, plus 1Password, `pass`, and an `age`-encrypted file with no server at all |
| Machine config | `~/.config/settings/{secrets.scope,secrets-paths}` | `~/.config/kitbag/machine.toml` |
| App state | three hardcoded cases in the push script | any `command = { export, restore }` pair |
| Reports | text | text, and `--json` on every command |

The two write different items, so a vault can hold both while a machine moves
across. Nothing is deleted from a vault by either of them.

## The cutover, when you want it

1. `./install.sh kitbag` and `scripts/kitbag-config.sh --write` on one machine.
2. `kitbag status --backend bw` and `kitbag doctor` — both read only. Compare
   with `./scripts/secrets-push.sh` (its dry run) and see that the same items
   are found.
3. `kitbag push --backend bw --dry-run`, then without it when the list looks
   right. The vault now holds kitbag items *as well as* the bash manifest.
4. On another machine, `kitbag restore --backend bw --dry-run`.
5. When every machine is across, the bash engine and its manifest can go.

Step 5 is not part of this change, and there is no hurry: a machine that never
moves across keeps working exactly as it does now.

## What has not been tried yet

- **Nothing has been pushed to the real vault with kitbag.** Everything above
  has been exercised against an `age` store and a stubbed client.
- The `op` and `pass` stores are tested against stub clients, not against real
  accounts — neither client is installed here.
- `kitbag apply` covers packages, links, macOS defaults, downloads, clones,
  merges and commands. The modules in this repository are not ported to it, and
  `./install.sh` remains what installs a machine.
