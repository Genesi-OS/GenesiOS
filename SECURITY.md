# Security Policy

Thank you for helping keep Genesi OS and its users safe. This document explains
what to report, how to report it, and what you can expect from us in return.

Genesi OS is a volunteer-run free software project. We do not operate a paid
security team and we cannot offer bug bounties, but every report is read and
taken seriously.

## Reporting a vulnerability

**Do not open a public issue for a security problem.** Public disclosure before
a fix exists puts users at risk.

Use either of these private channels:

1. **GitHub Security Advisories** — on the affected repository, open
   *Security → Report a vulnerability*. This is preferred: it creates a private
   thread and lets us credit you and issue a CVE if warranted.
2. **Email** — <contact@genesios.org>, with `SECURITY` in the subject line.

Please include as much of the following as you can:

- the affected component, package name and version (`pacman -Qi <package>`);
- the type of issue (privilege escalation, RCE, credential exposure, path
  traversal, supply-chain, and so on);
- reproduction steps or a proof of concept;
- what an attacker gains, and any preconditions required;
- your assessment of severity, and whether the issue is already public.

If you need to send sensitive material, say so in your first message and we will
arrange a channel before you send it.

## What is in scope

The code this project writes and the infrastructure it operates:

- first-party packages under `genesi-arch/packages/` — AI Mode, Automations,
  Forge, Sandboxes, Ports, Package Installer, Snapshots, settings and themes;
- the Calamares installer configuration, its shell scripts and the branding in
  `genesi-calamares-config-full/`;
- the ISO build pipeline, `archiso` configuration and package build scripts;
- the update mechanism, the `[genesi]` package repository and its metadata;
- `genesios.org`, the documentation wiki and `forum.genesios.org`.

Findings we are particularly interested in: anything that runs code as another
user or as root without authorisation, anything that lets one forum user act as
another or read data they should not, weaknesses in how packages or ISO images
are fetched or verified, secrets committed to a repository or baked into an
image, and any way to bypass the approval gate in AI Mode or Automations.

## What is out of scope

- **Third-party components.** The Linux kernel, Arch and CachyOS packages,
  desktop environments, drivers and AUR software are maintained upstream. Report
  those to the relevant project; tell us as well if Genesi's configuration makes
  the impact worse than upstream default.
- **Language model output.** A model producing wrong, offensive or unsafe text
  is a quality issue, not a vulnerability. A way to make the agent execute an
  action *without passing the approval gate* is a vulnerability — report it.
- **Documented behaviour.** Automations and the agent are designed to run
  commands you configure with your own privileges. That is the feature. A way
  for someone *else* to inject or trigger them is not.
- Missing hardening headers, or scanner output with no demonstrated impact.
- Social engineering, physical attacks, and denial of service by traffic volume.
- Reports produced solely by an automated tool without validation.

## Our commitments

| Stage | Target |
| --- | --- |
| Acknowledge your report | 72 hours |
| Initial assessment and severity | 7 days |
| Fix or mitigation for critical issues | 30 days where practicable |
| Coordinated public disclosure | after a fix ships, by agreement with you |

These are goals for a volunteer project, not contractual guarantees. If a
deadline slips we will tell you why rather than go quiet.

We will keep you informed as we work, credit you in the advisory and release
notes unless you prefer to stay anonymous, and agree a disclosure date with you.
If we conclude a report is not a vulnerability, we will explain our reasoning.

## Safe harbour

We will not pursue or support legal action against you for security research
carried out in good faith under this policy, provided you:

- only test against systems and installations you own or are authorised to test;
- do not access, modify, exfiltrate or destroy other people's data;
- do not degrade the availability of the service for other users;
- stop as soon as you have enough to demonstrate the issue, and do not pivot
  further into the infrastructure;
- give us a reasonable opportunity to remediate before disclosing publicly.

Reporting in good faith under these conditions is authorised access for the
purposes of the [Terms of Service](https://www.genesios.org/terms), and clause
11.4 of those Terms is read accordingly. This safe harbour cannot bind third
parties whose systems you test.

## Supported versions

Genesi OS is a rolling release. Security fixes are published for the **current**
state of the stable channel only; there are no long-term-support branches and no
backports to older ISO images.

Keeping a system current is part of keeping it secure:

```bash
sudo pacman -Syu
```

An ISO image is a snapshot from its build date and will contain known-fixed
issues shortly after release. Always update after installing.

## Verifying what you install

Install images and packages should be obtained only from the sources linked at
<https://www.genesios.org>. Verify any published checksum before writing an
image, and treat mirrors, torrents and re-uploads from third parties as
unverified unless you can check them against an official checksum.

Packages from the AUR are built from user-supplied instructions and are not
reviewed by this project. Read a `PKGBUILD` before you build it.
