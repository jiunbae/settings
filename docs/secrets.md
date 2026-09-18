# Secrets

`./install.sh secrets` restores private material — SSH keys, GPG keys, `.env`
files, host configs that are too sensitive for a public repo, and app state such as aas
accounts and BarShelf data — from a
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

## New machine

```bash
# 1. Public settings — unchanged
curl -LsSf https://settings.jiun.dev | bash -s -- --all

# 2. Secrets — separate, explicit command
cd ~/.settings && ./install.sh secrets
```

Step 2 installs the Bitwarden CLI through the normal package manager
(`brew install bitwarden-cli`; `npm i -g @bitwarden/cli` on Debian/Ubuntu, which
has no apt package), then prompts for email, master password, and the TOTP
verification code. Nothing else has to be installed by hand.

## App data

`scripts/secrets-push.sh` also carries app state that is not a single file. Each
goes up as an **attachment** — Bitwarden notes stop at about 10,000 characters — and
comes back by being piped into a command (`exec`) instead of written to a path.

| Item | Attachment | Restore | Needs first |
| --- | --- | --- | --- |
| `app:aas` | `aas-bundle.json` from `aas export --all` (every account and credential) | `aas import -` | `brew install open330/tap/aas` |
| `app:barshelf` | `barshelf.tar.gz` of `~/Library/Application Support/BarShelf` without `runtime/` and `cache/` | quits BarShelf, extracts into Application Support, starts it again | BarShelf.app |

- Push from a **Terminal on the Mac itself**. `aas export` reads the Claude credential
  from the login keychain, which an SSH session cannot open.
- `aas import` restores the accounts but not which one is active; pick with
  `aas switch`, and run `aas shim install` if the bare `claude`/`codex` should follow it.
- Re-pushing replaces the attachment and the manifest entry instead of adding copies.
- **OTPeek** needs nothing here: its accounts sync through iCloud (CloudKit and iCloud
  Keychain). Install it from TestFlight with the same Apple ID.

A new Mac, in order:

```bash
curl -LsSf https://settings.jiun.dev | bash -s -- --all   # public settings
brew install open330/tap/aas                              # + install BarShelf.app
cd ~/.settings && ./install.sh secrets                     # keys, envs, app data
```

## Manifest format

Stored in the **notes** field of the vault item named by
`SETTINGS_VAULT_MANIFEST` (default: `bootstrap`).

```json
{
  "version": 1,
  "entries": [
    {"item": "ssh:id_ed25519", "source": "sshkey",       "dest": "~/.ssh/id_ed25519",     "mode": "600"},
    {"item": "ssh:id_ed25519", "source": "field:public", "dest": "~/.ssh/id_ed25519.pub", "mode": "644"},
    {"item": "ssh:company",    "source": "attachment:20-company.conf",
                               "dest": "~/.ssh/config.d/20-company.conf", "mode": "600"},
    {"item": "gpg:primary",    "source": "notes", "exec": "gpg --batch --quiet --import"},
    {"item": "gpg:ownertrust", "source": "notes", "exec": "gpg --quiet --import-ownertrust"}
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
- The vault stays unlocked in the calling shell afterwards. Run `bw lock` when
  finished.
- The vault is a single point of failure for bootstrapping. Keep an offline
  `bw export --format encrypted_json` somewhere reachable without it.
