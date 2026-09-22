# chezmoi

The dotfiles in this repository are moving from `install.sh`'s symlinks to
[chezmoi](https://www.chezmoi.io/). This page says where that stands and how to
work with it. The move is staged, one pull request per stage, and every machine
keeps working in between.

| Stage | What | State |
| --- | --- | --- |
| 1 | `configs/` and `bin/` become chezmoi's source tree | **this PR** |
| 2 | Component and platform selection in `.chezmoiignore` | next |
| 3 | Applied on every machine | after 2 |
| 4 | `modules/` become `run_once_` scripts, one per PR | after 3 |
| 5 | `install.sh`, `lib/` and `bootstrap.sh` retire | last |

## Where things are

`.chezmoiroot` contains `home`, so chezmoi reads its source from `home/` and
nothing else. `modules/`, `scripts/`, `docs/` and CI stay outside its view.

Files are named the way chezmoi places them:

| In the repo | On the machine |
| --- | --- |
| `home/dot_zshrc` | `~/.zshrc` |
| `home/dot_config/nvim/` | `~/.config/nvim/` |
| `home/dot_local/bin/executable_mkln` | `~/.local/bin/mkln`, mode 755 |
| `home/private_dot_ssh/private_config` | `~/.ssh/config`, mode 600 |

## Working with it

chezmoi writes real files, not symlinks. Editing `~/.zshrc` no longer edits the
repository — which is the point, and the one habit that has to change.

```bash
chezmoi edit ~/.zshrc          # edit the source, then:
chezmoi diff                   # what apply would change
chezmoi apply                  # make the machine match

# or edit the file in place, then take the change back:
chezmoi re-add ~/.zshrc
```

A machine needs to know where the source is, once:

```bash
echo 'sourceDir = "~/workspace/settings"' > ~/.config/chezmoi/chezmoi.toml
chezmoi diff                   # before the first apply, always
```

`./install.sh` still works until stage 5. It links from `home/` now, with the
chezmoi prefixes taken off the names — so a machine on either path ends up with
the same files. Run one or the other on a given machine, not both: `install.sh`
makes symlinks, and chezmoi will want to replace them with files.

## What chezmoi must never do here

**Never mark these directories `exact_`.** `exact_` deletes whatever chezmoi
does not manage, and something else writes into each of them:

- `~/.ssh/config.d/` — the vault restores `20-company.conf` and
  `30-internal.conf` there.
- `~/.local/bin/` — holds `kitbag`, `starship`, `cship`, `uv` and `claude`.
- `~/.claude/` — Claude Code rewrites its own files constantly.

**Never `chezmoi add` a vault-restored file.** `home/.chezmoiignore` refuses the
two ssh fragments above, and `.gitignore` refuses them under the name
`chezmoi add` would give them, so both layers say no:

```console
$ chezmoi add ~/.ssh/config.d/20-company.conf
chezmoi: warning: ignoring .ssh/config.d/20-company.conf
```

## What is not moving

Secrets stay where they are — `modules/secrets.sh`, kitbag, and on Windows
`bin/windows/Restore-Secrets.ps1` — for three reasons, any one of which is enough:

1. **The inventory rule** ([secrets.md](secrets.md)). A chezmoi source tree names
   every file it manages, so moving `~/.envs/*` into it would publish the list of
   which secrets exist and whose they are. That list lives in the vault.
2. **chezmoi has no push.** It goes from source to machine only. Collecting from
   a machine, per-machine items and conflict resolution are kitbag's job.
3. **Windows.** kitbag ships no Windows build, so the PowerShell engine is the
   only one there — and most of what it does is Windows ACLs, which chezmoi does
   not manage.

Also still with `install.sh` until stage 4, because they are merges into files an
application owns rather than files to place: `~/.gitconfig`,
`~/.codex/config.toml`, `~/.claude/settings.json` (Claude Code flips its plugin
flags in the live file), the cmux seed, and the hishtory env template.
