# Package signing

## What this fixes

Every Genesi repository was configured `SigLevel = Optional TrustAll`:

```ini
[genesi]
SigLevel = Optional TrustAll
Server = https://raw.githubusercontent.com/Genesi-OS/GenesiOS/main/genesi-arch/repo/$arch
```

`Optional` means pacman does not require a signature, and nothing published
here carried one — so in practice this said: **install whatever is at that URL,
as root, without checking who produced it.**

(`TrustAll` is a weaker statement than it looks, and the next section is about
exactly that. It does not mean "accept any key".)

That is defensible while the only user is the person who builds it. It stops
being defensible the moment a stranger installs Genesi, because they are not
trusting Genesi — they are trusting the transport, the hosting, and every path
that could ever put a file at that URL.

Signing closes that: packages carry a detached signature, the database carries
one too, and `genesi-keyring` puts the public key on every machine so it can
tell a Genesi package from a file that merely arrived from the right place.

## What `Optional TrustAll` actually means

Get this wrong and everything below is wrong. It was gotten wrong on
2026-08-29, and it took the whole fleet's updates down for half an hour.

> **`TrustAll` does NOT mean "accept any key".** It means "accept keys **that are
> in the keyring**, whatever their trust level". The key must still be present.
>
> **`Optional` only forgives an ABSENT signature.** A signature that IS present
> and cannot be verified is a hard error, not a downgrade to unsigned.

So `Optional TrustAll` on a machine with no Genesi key does **not** tolerate a
signed repository. It rejects it, at `pacman -Sy`, before any package is even
considered:

```
error: genesi: key "75C1C18796E7CB85EC89E557E422F2DA85C6BD0E" is unknown
error: failed to synchronize all databases (unexpected error)
```

## The rollout has three steps and the order is the opposite of the obvious one

The obvious order is "sign first, distribute the key second". That is backwards,
and it is what broke: publishing a signature is what makes the key *required*,
so the key has to be there **before** the first signature exists, not after.

| # | Step | State of the world |
|---|---|---|
| 1 | **`genesi-keyring` ships UNSIGNED** | It is an ordinary package. Machines pick it up on a normal `pacman -Syu` and import the key. Nothing is signed yet, so nothing can reject anything. |
| 2 | **Signing is switched on** | Repository variable `GENESI_SIGNING_ENABLED=1`. Only now do signatures appear — and every machine that did step 1 can verify them. |
| 3 | **`SigLevel` becomes `Required`** | Machines now refuse anything Genesi did not sign. |

Two ways to get this wrong, and both are outages:

- **Step 2 before step 1 finishes** — machines cannot verify a signature whose
  key they do not have, and `pacman -Sy` fails. They cannot fetch the keyring to
  fix it, because fetching it needs the repository that is now failing. The only
  escape is editing `/etc/pacman.conf` by hand. *This is the one that happened.*
- **Step 3 before step 1 finishes** — same shape, more permanent.

The switch in step 2 is deliberately a **repository variable a person sets**,
not a condition CI infers from the key existing. CI cannot know whether machines
have picked up the keyring yet; only a person can. Wiring signing to "the secret
exists" is precisely what caused the outage.

## Step 1 — create the key (once), and DO NOT switch signing on

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

## Step 2 — let the keyring reach machines, THEN switch signing on

Nothing to do but wait for a publish and a normal update cycle. `genesi-keyring`
is a dependency of the `genesi-desktop` meta-package, which every installed
system has, so `pacman -Syu` pulls it.

Only when that has actually happened:

```bash
gh variable set GENESI_SIGNING_ENABLED --body 1
```

Until that variable is `1`, all three pipelines publish unsigned no matter what
secrets exist. That is the switch, and it is a person's decision because CI
cannot see whether anyone's machine has the key yet.

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

### One thing that looks wrong and is not

Our database entries carry no `%PGPSIG%` field. Arch's do. If you open
`genesi.db` before flipping `SigLevel` and notice this, it looks like the
packages are unsigned — they are not.

`%PGPSIG%` is an *optimisation*: repo-add can embed each package's signature
into the database so pacman does not have to fetch it. When the field is absent,
pacman downloads `<package>.sig` from the same server instead, which is exactly
what is published — verified end to end on 2026-08-29: 35 of 35 packages had a
`.sig`, and a real published package verified against the shipped public keyring
alone (`Good signature ... using RSA key 75C1C187…85C6BD0E`).

The cost is one extra HTTP request per package during an upgrade. Nothing else.
`ci/repo-signature-test.sh` reports the state either way rather than staying
silent about it.

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
- ~~**`genesi-keyring` is not in the live ISO package list.**~~ **Reversed
  2026-08-29.** The reasoning was that the live environment installs to the
  target via `pacman-target.conf`, which requires no signature, so only the
  installed system needed the key. It missed one line in `calamares-online.sh`:

  ```bash
  sudo pacman -Sy --noconfirm genesi-calamares
  ```

  The installer downloads the installer from `[genesi]`, at the moment the user
  clicks Install. A live medium without the key would fail that download the day
  signing is switched on — breaking **installation**, not updates, in the one
  place it hurts most. The ISO now carries `genesi-keyring`, and
  `calamares-online.sh` names `genesi` in its `--populate` (explicit names
  populate *only* those, so shipping the key file without naming it would leave
  it present and untrusted). `ci/keyring-wiring-test.sh` checks both.
- **No existing machine's `/etc/pacman.conf` is edited.** See step 3.
