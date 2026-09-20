# Secrets

> **Being replaced.** This engine still restores every machine and is unchanged.
> Its successor is [kitbag](kitbag.md), installed alongside it by
> `./install.sh kitbag`; nothing moves across until you move it.

`./install.sh secrets` restores private material — SSH keys, GPG keys, `.env`
files, host configs that are too sensitive for a public repo, and app state such as aas
accounts, BarShelf data and the OTPeek vault — from a
Bitwarden-compatible vault (Bitwarden or a self-hosted Vaultwarden).

It is **opt-in only**. `secrets` is deliberately absent from `COMPONENTS_ORDER`,
so neither `--all` nor the interactive menu can drop private keys onto a shared
box, a CI runner, or a machine that only wanted dotfiles.

## Why the list lives in the vault

This repository is public. `modules/secrets.sh` therefore contains no item
names, no destination paths, and no indication of which keys exist — only a
generic engine. **What** to restore is a JSON manifest stored inside the vault
itself, behind the master password and verification code.

    public repo   modules/secrets.sh   →  generic engine, publishable as-is
    vault item    bootstrap (notes)    →  your inventory, never leaves the vault

Anyone can reuse this: point `SETTINGS_VAULT_SERVER` at your own vault, write
your own manifest, done. Nothing in this repo needs forking or editing.

## Scopes

One vault, several lives. Every secret declares whose it is, and a machine
restores only the scopes it asks for — so a personal laptop never has to hold an
employer's credentials, and the machine that does can still get everything from
the same place.

| Scope | What it means |
| --- | --- |
| `personal` | Your own accounts and infrastructure |
| `work` | An employer's or client's credentials |
| `shared` | An account someone else owns that you were given access to |
| `mixed` | One blob holding several of the above (aas accounts, an OTP vault, a GPG key with more than one identity) |
| `local` | Machine-only — collected by nothing, pushed by nothing (a cached vault session, for instance) |

The marker lives in the file, never in this repository: a public repo must not
carry the list of which employer or which service each secret belongs to.

```sh
# ~/.envs/<service>.env, ~/.ssh/config.d/*.conf — a comment in the first 5 lines
# scope: work
# owner: acme        # optional, free text, kept as a vault field
```

A private key holds no comments, so it takes a sidecar instead —
`~/.ssh/id_work.scope` containing the word `work`. A key with neither is the
machine owner's own key (`personal`); **every other file without a marker is
skipped and listed**, so a new secret is never filed into the wrong life by
default.

In the vault, scopes become folders under the bootstrap folder and a `scope`
custom field on each item:

    bootstrap/                 manifest
    bootstrap/personal/        env:…, ssh:…
    bootstrap/work/            env:…, ssh:config-…
    bootstrap/shared/          env:…

Changing a file's marker moves the item on the next push; items left in those
folders that no machine pushes any more are reported with the command to delete
them.

## New machine

```bash
# 1. Public settings — unchanged
curl -LsSf https://settings.jiun.dev | bash -s -- --all

# 2. Secrets — separate, explicit command. Personal only, by default.
cd ~/.settings && ./install.sh secrets

# Everything, or a specific set:
SETTINGS_SECRETS_SCOPE=all ./install.sh secrets
SETTINGS_SECRETS_SCOPE=personal,work ./install.sh secrets

# Or decide once per machine, and plain `./install.sh secrets` follows it:
mkdir -p ~/.config/settings && echo all > ~/.config/settings/secrets.scope
```

`./install.sh -n secrets` lists what each entry would do, with its scope, and
writes nothing. `mixed` entries restore under every scope — they cannot be split
from out here.

Step 2 installs the Bitwarden CLI pinned to a version verified against the vault
(`npm install -g @bitwarden/cli@2026.8.0`; override with `SETTINGS_BW_CLI_VERSION`),
then prompts for email, master password, and the TOTP verification code.

> [!WARNING]
> Newer clients can break against Vaultwarden, which trails Bitwarden's API. `bw`
> 2026.9.0 fails during login with `KeyIdBackfillError` (a 404 from an endpoint
> Vaultwarden does not have). If an existing `bw` is a different version the module
> warns; to switch: `bw logout`, remove it (`brew uninstall bitwarden-cli`), and let
> the module install the pinned one. Keep a Homebrew copy from upgrading with
> `brew pin bitwarden-cli`.

## App data

`scripts/secrets-push.sh` also carries app state that is not a single file. Each
goes up as an **attachment** — Bitwarden notes stop at about 10,000 characters — and
comes back by being piped into a command (`exec`) instead of written to a path.

| Item | Attachment | Restore | Needs first |
| --- | --- | --- | --- |
| `app:aas` | `aas-bundle.json` from `aas export --all` (every account and credential) | `aas import -` | `brew install open330/tap/aas` |
| `app:barshelf` | `barshelf.tar.gz` of `~/Library/Application Support/BarShelf` without `runtime/` and `cache/` | quits BarShelf, extracts into Application Support, starts it again | BarShelf.app |
| `app:otpeek` | `otpeek.tar.gz`: the CLI config and the app-group vault `vault.otpvault` (still encrypted with the OTPeek master password) | extracts into `$HOME`, points `active_vault` at this home | `otpeek` CLI in `~/.cargo/bin` |

- Push from a **Terminal on the Mac itself**. `aas export` reads the Claude credential
  from the login keychain, which an SSH session cannot open.
- `aas import` restores the accounts but not which one is active; pick with
  `aas switch`, and run `aas shim install` if the bare `claude`/`codex` should follow it.
- Re-pushing replaces the attachment and the manifest entry instead of adding copies.
- **OTPeek**: the app (TestFlight) and the `otpeek` CLI — which BarShelf's OTP widget
  runs — share the one vault file. After restoring, run `otpeek unlock` once so the
  master password is cached in the keychain; the widget cannot prompt for it.

A new Mac, in order:

```bash
curl -LsSf https://settings.jiun.dev | bash -s -- --all   # public settings
brew install open330/tap/aas                              # + install BarShelf.app
cd ~/.settings && ./install.sh secrets                     # keys, envs, app data
```

## Seeing where things stand

```bash
scripts/secrets-push.sh            # what this machine holds, grouped by scope. Reads nothing remote.
scripts/secrets-push.sh --status   # the same, marked against the vault. Writes nothing.
scripts/secrets-push.sh --push     # apply
./install.sh -n secrets            # what a restore would write here
```

`--status` unlocks the vault read-only and marks every item with what a push
would do to it:

    + new         the vault has never seen it
    ~ changed     the vault holds something else
    = unchanged   nothing to send
    ? built on push   only building the payload would tell (the aas bundle,
                      whose tokens rotate on their own)

It ends with the items sitting in the vault that this machine no longer sends —
a file that turned `local`, was deleted, or lost its marker — each with the
command to remove it.

## Tracking a path that is not where this script guessed

`~/.envs/*.env`, `~/.ssh/id_*`, `~/.ssh/config.d/*.conf` and
`~/.ssh/authorized_keys` are collected because they are where these things
usually live. Everything else is listed, one per line, in
`~/.config/settings/secrets-paths` (override with `SETTINGS_TRACKED_PATHS`):

```
# <path>  <scope>  [owner]  [item-name]
~/.npmrc                                   personal
~/.aws/config                              work      acme
~/Library/Keychains/x.keychain-db          work      acme   file:x-keychain
```

- A `# scope:` header **inside** the file still wins over the column, so a file
  that can carry its own marker keeps carrying it.
- Text goes up as notes; **anything binary goes up as an attachment** and is
  written back byte for byte, which is how a keychain or a `.db` travels.
- A listed path that is missing on this machine is reported, not silently
  skipped — that is usually a machine that has not been set up yet, not a typo.
- Directories are refused: track the files inside them, so a restore never
  writes a tree you did not look at.

The item name defaults to a slug of the path (`~/.aws/config` → `file:aws-config`).

## Machine trust

`scripts/ssh-trust.sh` keeps one list of the keys your own machines log in with,
so adding a machine does not mean editing `authorized_keys` on every other one.

```bash
scripts/ssh-trust.sh list                   # who is trusted where
scripts/ssh-trust.sh register [--new-key]   # this machine joins the list
scripts/ssh-trust.sh sync [host...]         # collect every host's key, give every host the union
scripts/ssh-trust.sh revoke <fp|comment>    # drop a key here and everywhere
```

Hosts are ssh aliases read from `~/.ssh/trusted-hosts` (one per line), or passed
as arguments — no machine name lives in this repository.

**One key per machine, not one key for all of them.** A key every machine holds
cannot be revoked for one machine, and tells you nothing about which machine
logged in. `register --new-key` gives this machine its own; the list says which
keys are yours.

`~/.ssh/authorized_keys` carries a `# scope: personal` header, so it rides the
vault like everything else — and that is what closes the loop on a new machine:

1. New machine runs `./install.sh secrets`, which **merges** the list into its
   `authorized_keys`. Your existing machines can now reach it.
2. From any machine, `scripts/ssh-trust.sh sync` collects the new machine's key
   and hands the union to everyone.
3. `scripts/secrets-push.sh --push` puts the updated list back in the vault.

The restore **merges and never deletes**: a host may hold keys the list has
never seen — a CI runner, an agent, a phone — and overwriting the file would
lock them out silently. `revoke` is the only thing that removes, and only what
you name.

## Manifest format

Stored in the **notes** field of the vault item named by
`SETTINGS_VAULT_MANIFEST` (default: `bootstrap`).

```json
{
  "version": 2,
  "entries": [
    {"item": "ssh:id_ed25519", "source": "sshkey",       "dest": "~/.ssh/id_ed25519",     "mode": "600", "scope": "personal"},
    {"item": "ssh:id_ed25519", "source": "field:public", "dest": "~/.ssh/id_ed25519.pub", "mode": "644", "scope": "personal"},
    {"item": "ssh:company",    "source": "attachment:20-company.conf",
                               "dest": "~/.ssh/config.d/20-company.conf", "mode": "600", "scope": "work"},
    {"item": "gpg:primary",    "source": "notes", "exec": "gpg --batch --quiet --import",    "scope": "mixed"},
    {"item": "gpg:ownertrust", "source": "notes", "exec": "gpg --quiet --import-ownertrust", "scope": "mixed"}
  ]
}
```

| Key | Meaning |
| --- | --- |
| `item` | Vault item name or ID |
| `source` | `notes` (default), `sshkey`, `password`, `field:<name>`, `attachment:<filename>` |
| `dest` | File to write. `~` is expanded. Mutually exclusive with `exec` |
| `exec` | Command to pipe the payload into. Mutually exclusive with `dest` |
| `mode` | `chmod` for `dest`, default `600` |
| `scope` | `personal`, `work`, `shared` or `mixed`. Missing (version 1 manifests) is treated as `mixed`, with a warning |

Restores are idempotent: an unchanged `dest` is skipped, and a changed one is
backed up to `<dest>.backup.<timestamp>` before being replaced.

## Populating the vault

```bash
# SSH — use the native SSH Key item type (Vaultwarden 2025.x+ supports it)
#   private key → the SSH key field, public key → a custom field named "public"

# GPG — armored exports into the notes field
gpg --export-secret-keys --armor <KEYID>   # → item "gpg:primary"   notes
gpg --export-ownertrust                     # → item "gpg:ownertrust" notes
```

Prefer notes and fields over attachments where the payload is text; they are
smaller, diff-able in the web vault, and supported by every client.

## Environment

| Variable | Default | Purpose |
| --- | --- | --- |
| `SETTINGS_VAULT_SERVER` | `https://vault.jiun.dev` | Vault base URL |
| `SETTINGS_VAULT_MANIFEST` | `bootstrap` | Item holding the manifest |
| `SETTINGS_VAULT_2FA_METHOD` | `0` | `0` authenticator, `1` email, `3` YubiKey |
| `SETTINGS_SECRETS_SCOPE` | `personal` | Scopes to restore: a comma-separated list, or `all` |
| `SETTINGS_SECRETS_SCOPE_FILE` | `~/.config/settings/secrets.scope` | Per-machine default for the above |
| `SETTINGS_SCOPE_AAS` / `_BARSHELF` / `_OTPEEK` | `mixed` / `personal` / `mixed` | Scope pushed for each app blob |

```bash
SETTINGS_VAULT_SERVER=https://vault.example.com \
SETTINGS_VAULT_MANIFEST=my-bootstrap \
  ./install.sh secrets
```

## Notes

- `--dry-run` never prompts for a password. With an existing `BW_SESSION` it
  enumerates the manifest for real; otherwise it reports that the vault is locked.
- Secret payloads are staged in a `umask 077` temp directory that is removed on
  exit, including on failure.
- `scripts/tests/secrets-scope-smoke.sh` covers collection, scope routing and the
  restore filter against a stubbed `bw`; it touches no vault and no real secret.
- The vault stays unlocked in the calling shell afterwards. Run `bw lock` when
  finished.
- The vault is a single point of failure for bootstrapping. Keep an offline
  `bw export --format encrypted_json` somewhere reachable without it.
