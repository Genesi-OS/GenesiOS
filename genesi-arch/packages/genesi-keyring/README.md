# genesi-keyring

The public half of the key that signs every Genesi package and repository
database. This package is what lets a machine tell "a package Genesi built"
apart from "a file that appeared at the repository URL".

## The three files

| File | What it is |
|---|---|
| `genesi.gpg` | The exported public keyring. **Not in git until the key exists** — written by `devtools/genesi-keygen.sh`. |
| `genesi-trusted` | `<fingerprint>:4:` — one line per key, `4` meaning full ownertrust. Merely *importing* a key does not make pacman trust it; this file is what does. Also written by the keygen script. |
| `genesi-revoked` | Fingerprints to actively distrust. Intentionally **empty**, and it must stay byte-empty rather than carry explanatory comments — `pacman-key --populate` feeds every line of it to gpg as a key id, so a `#` comment would be parsed as a key. |

`pacman-key --populate genesi` reads exactly this triple from
`/usr/share/pacman/keyrings/`, which is why the names are fixed.

## Before the key exists

This directory is committed **without** `genesi.gpg` and `genesi-trusted`, and
`publish-packages.yml` skips building the package while they are missing (with
a warning in the job summary, not an error). That is deliberate: the publish
pipeline feeds the in-OS update notifier, and it must keep working unchanged
until the maintainer has actually generated a key.

Generate it once, from the repository root:

```bash
./genesi-arch/devtools/genesi-keygen.sh
```

That script is the only place the private key is ever handled. It writes the
public half here, pushes the private half straight into the `GENESI_SIGNING_KEY`
GitHub secret via `gh`, and hands you an offline backup to store somewhere that
is not this repository.

## Why removing this package is loud

`pre_remove` deletes the keys again and prints a warning. On a machine whose
`/etc/pacman.conf` has been moved to `SigLevel = Required`, removing the keyring
means no further Genesi update can ever be verified — the machine is cut off
from its own distribution. The scriptlet cannot prevent that, so it makes sure
nobody does it by accident and wonders why updates broke a week later.

## Rolling the key

If the private key is ever lost or compromised:

1. Run `genesi-keygen.sh --rotate`. It keeps the old public key in `genesi.gpg`
   (so packages already published still verify) and adds the new one.
2. Add the old fingerprint to `genesi-revoked` **only after** every published
   package has been re-signed with the new key — a revoked key makes every
   artifact it signed untrusted immediately.
3. Bump `pkgrel` and let a publish run reach every machine **before** anything
   else changes.

See `genesi-arch/docs/PACKAGE-SIGNING.md` for the full lifecycle.
