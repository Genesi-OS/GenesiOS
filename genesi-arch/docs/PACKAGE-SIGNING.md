# Package signing

## What this fixes

Every Genesi repository was configured `SigLevel = Optional TrustAll`:

```ini
[genesi]
SigLevel = Optional TrustAll
Server = https://raw.githubusercontent.com/Genesi-OS/GenesiOS/main/genesi-arch/repo/$arch
```

`Optional` means pacman does not require a signature. `TrustAll` means that if
one happens to be there, a signature from a key nobody has ever heard of is
accepted anyway. Together they say: **install whatever is at that URL, as root,
without checking who produced it.**

That is defensible while the only user is the person who builds it. It stops
being defensible the moment a stranger installs Genesi, because they are not
trusting Genesi — they are trusting the transport, the hosting, and every path
that could ever put a file at that URL.

Signing closes that: packages carry a detached signature, the database carries
one too, and `genesi-keyring` puts the public key on every machine so it can
tell a Genesi package from a file that merely arrived from the right place.

## The rollout has three steps and they are not interchangeable

The order matters more than any individual piece. Getting it wrong does not
produce a warning — it produces machines that can no longer update, including
past the update that would have fixed them.

| # | Step | State of the world |
|---|---|---|
| 1 | **CI signs** | Packages gain `.sig` files. Clients are still `Optional TrustAll`, so nothing changes for them. |
| 2 | **The keyring reaches machines** | `genesi-keyring` is pulled in by `genesi-desktop` on a normal `pacman -Syu`. Still `Optional TrustAll`. |
| 3 | **`SigLevel` becomes `Required`** | Machines now refuse anything Genesi did not sign. |

Step 3 before step 2 is the catastrophic one: a machine set to `Required` with
no key rejects every Genesi package, including `genesi-keyring` itself. There is
no way out of that from inside the machine except editing `/etc/pacman.conf` by
hand.

## Step 1 — create the key (once)

```bash
./genesi-arch/devtools/genesi-keygen.sh
```

It generates an RSA-4096 key in a throwaway keyring, writes the **public** half
into `genesi-arch/packages/genesi-keyring/`, pushes the **private** half
straight into the `GENESI_SIGNING_KEY` repository secret with `gh`, leaves you a
backup in `$HOME`, and adds `genesi-keyring` to `genesi-desktop`'s dependencies.

Then commit the two together — they are one change:

```bash
git add genesi-arch/packages/genesi-keyring genesi-arch/packages/genesi-desktop
git commit -m "feat(keyring): publish the Genesi repository signing key"
```

**Move the backup off this machine.** A lost private key means a distribution
you can never sign again; every installed machine would have to be walked
through a key rotation by hand.

### Before the key exists

Everything above is already in place and does nothing:

- `publish-packages.yml` publishes **unsigned**, exactly as it always has, and
  logs a warning. A missing key is never a build failure — this pipeline feeds
  the in-OS update notifier, and a distribution that cannot publish updates is a
  worse outcome than one that is not yet signed.
- `genesi-keyring` is skipped by the build (it has no payload yet).
- Nothing depends on it, so no install or ISO build can reference a package that
  does not exist.

`genesi-arch/ci/keyring-wiring-test.sh` enforces exactly that, in both
directions, on every push.

## Step 2 — let the keyring reach machines

Nothing to do but wait for a publish and a normal update cycle. `genesi-keyring`
is a dependency of the `genesi-desktop` meta-package, which every installed
system has, so `pacman -Syu` pulls it.

This is the mechanism `genesi-desktop`'s own header warns about, and it has
failed before: `genesi-mesh` shipped to the repo and reached **no machine at
all** for weeks because it was not listed in the meta (fixed in pkgrel 10). A
plain `-Syu` never installs a brand-new package on its own.

Verify the published repository actually is signed, against the key users
actually have:

```bash
./genesi-arch/ci/repo-signature-test.sh
```

It fetches the live database and every `.sig` over HTTPS and verifies them
against `genesi-keyring`'s public key — not against your personal `~/.gnupg`,
which would prove nothing about what a user can check.

## Step 3 — raise SigLevel

Only when step 2 has verifiably happened. The flip is a one-line change in each
of these, all of which currently read `SigLevel = Optional TrustAll`:

| File | Applies to |
|---|---|
| `genesi-arch/archiso/airootfs/etc/pacman.conf.d/genesi.conf` | fresh installs |
| `genesi-arch/archiso/airootfs/etc/pacman-target.conf` | the target of a Calamares install |
| `genesi-arch/archiso/airootfs/etc/pacman.conf` | the live ISO |
| `genesi-arch/archiso/airootfs/root/customize_airootfs.sh` | the blocks it pre-seeds |
| `genesi-arch/packages/genesi-channel/genesi-channel` | the `[genesi-testing]` block it writes |

Change `Optional TrustAll` to `Required`, or `Required DatabaseOptional` if you
want a grace period on the database only.

**Existing machines are not migrated by this.** Their `/etc/pacman.conf` is
their own file; pacman will not rewrite it, and neither should a package. Fresh
installs get the stricter setting; existing machines keep `Optional TrustAll`
until their owner changes it, which is the conservative failure mode — they keep
updating either way.

## Rotating the key

```bash
./genesi-arch/devtools/genesi-keygen.sh --rotate
```

Adds a new key while **keeping the old public key in the keyring**, because
every package already published is signed by the old one and machines must go on
verifying them.

Only after every published package has been re-signed with the new key should
the old fingerprint go into `genesi-revoked` — revocation makes every artifact
that key signed untrusted immediately.

## What is deliberately not done

- **The live ISO's own packages are not signed by this key.** They come from
  Arch and CachyOS and carry their own signatures; `pacman-target.conf` uses
  `SigLevel = Never` for the base system during pacstrap, which is an installer
  concern separate from this one.
- **`genesi-keyring` is not in the live ISO package list.** The live environment
  installs to the target via `pacman-target.conf`, which does not require a
  signature, so the keyring only needs to be on the installed system — where the
  `genesi-desktop` dependency puts it. One fewer moving part in the ISO build.
- **No existing machine's `/etc/pacman.conf` is edited.** See step 3.
