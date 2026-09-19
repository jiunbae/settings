# Secrets

`./install.sh secrets` restores private material — SSH keys, GPG keys, `.env`
files, host configs that are too sensitive for a public repo, and app state such as aas
accounts, BarShelf data and the OTPeek vault — from a
Bitwarden-compatible vault (Bitwarden or a self-hosted Vaultwarden).

On Windows, where `install.sh` cannot run at all, `bin/windows/Restore-Secrets.ps1`
is the restoring half — see [Windows](#windows).

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

- All three are tagged `"platform": ["macos"]` by `secrets-push.sh`. They restore into
  `~/Library` and shell out to `open -a` and `pkill`, so a restore anywhere else skips
  them instead of writing paths that mean nothing there.
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
    {"item": "gpg:ownertrust", "source": "notes", "exec": "gpg --quiet --import-ownertrust"},
    {"item": "app:barshelf",   "source": "attachment:barshelf.tar.gz",
                               "exec": "tar -xzf - -C ...", "platform": ["macos"]}
  ]
}
```

| Key | Meaning |
| --- | --- |
| `item` | Vault item name or ID |
| `source` | `notes` (default), `sshkey`, `password`, `field:<name>`, `attachment:<filename>` |
| `dest` | File to write. `~` is expanded. Mutually exclusive with `exec` |
| `exec` | Command to pipe the payload into. Mutually exclusive with `dest` |
| `mode` | `chmod` for `dest`, default `600`. On Windows a mode whose group/other digits are `0` means "strip inherited ACEs, leave only this user" |
| `platform` | Where the entry applies — `macos`, `windows`, `linux`, as a string or an array. Absent means everywhere; WSL matches `linux` too |

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

## Windows

`install.sh` cannot run on Windows — `lib/platform.sh` `detect_platform` exits on
anything that is not Linux or Darwin — so the restoring half is its own script,
placed the way everything else in [windows.md](windows.md) is:

```powershell
$s = "$env:USERPROFILE\workspace\settings\bin\windows\Restore-Secrets.ps1"
pwsh -ExecutionPolicy Bypass -File $s -DryRun   # nothing is written, nothing is prompted
pwsh -ExecutionPolicy Bypass -File $s
```

Same vault, same manifest item, same entries. `jq` is not needed —
`ConvertFrom-Json` replaces it — but `bw` is: `winget install Bitwarden.CLI`, or
`npm install -g @bitwarden/cli@2026.8.0` for the pinned version.

There is no Windows push. `scripts/secrets-push.sh` stays the only writer of the
manifest; a second one would drift from it, and no secret's original copy lives on
Windows anyway.

Three things differ from the bash engine, each forced by the platform:

| | |
| :--- | :--- |
| **ACLs, not `chmod`** | Windows OpenSSH ignores POSIX modes and reads the ACL, so a restored key that still carries inherited ACEs is refused with `UNPROTECTED PRIVATE KEY FILE`. An entry whose `mode` ends in `00` gets inheritance disabled and one ACE for the current user; a `644` public key keeps the inherited ACL. The destination **directory** is left alone — the profile ACL already grants only the user, SYSTEM and Administrators, and OpenSSH checks the key file, not the directory it sits in. |
| **`exec` is not a shell** | There is no `sh` to hand the string to. A command containing a pipe, `;`, `&`, redirection or `$(…)` is refused with a note to tag that entry `"platform": ["macos"]` instead; a plain one such as `gpg --batch --quiet --import` runs directly, with the payload piped to its stdin as bytes rather than as text. |
| **Line endings** | Payloads written to `dest` are normalised to LF, and a final newline is added when one is missing. OpenSSH and GPG both reject a key whose armor carries CRLF, which a note edited in the web vault from a Windows browser can pick up. The trailing newline matters just as much: `secrets-push.sh` stores notes through `$(cat …)`, which strips it, and the bash engine only gets it back because `jq -r` appends one. Without it `ssh-keygen` fails the restored key with `error in libcrypto`. |

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
