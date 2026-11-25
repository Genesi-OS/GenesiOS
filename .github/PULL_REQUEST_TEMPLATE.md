## What this changes

<!-- One or two sentences. What is different afterwards, from a user's point of
     view? If it fixes something, say what was broken. -->

## Why

<!-- The reasoning, not the diff. If a decision here was between two reasonable
     options, say which and why — that is the part nobody can reconstruct later. -->

## How it was tested

<!-- Be specific and honest. "Builds" is not testing. If part of it is untested,
     say which part — a known gap is useful, a surprise gap is not. -->

- [ ] Ran the relevant suites in `genesi-arch/ci/`
- [ ] Tested on real hardware (say which: GPU, desktop, live ISO or install)
- [ ] Not tested: <!-- what, and why -->

## Checklist

- [ ] `pkgrel` bumped for every package whose contents changed
- [ ] The PKGBUILD comment says what changed and why (that log is the project's memory)
- [ ] No credential, token or personal path in the diff
- [ ] Docs updated if behaviour a user can see has changed
