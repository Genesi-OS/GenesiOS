#!/usr/bin/env python3
"""
iso-gate-test.py — the ISO pipeline's gate decides whether an ISO gets built
at all, and it decides it in shell, inside a YAML file nothing runs locally.

A wrong `true` there costs one ISO built a few minutes early. A wrong `false`
costs EVERY ISO, silently: the pipeline reports success with its two real jobs
skipped, and the download page keeps serving last week's image while every
build says green. That is the failure this file exists to make impossible.

So the step's own `run:` block is pulled out of .github/workflows/iso-pipeline.yml
and executed here, under the same shell GitHub uses (`bash -e -o pipefail`),
with the `${{ }}` expressions filled in the way Actions fills them. Nothing is
re-implemented; the lines under test are the lines that will run in CI.

`gh` is replaced by a stub on PATH that prints a chosen list of filenames, so
this runs offline, in about a second, and tests the DECISION rather than
GitHub's API. The case where the API says nothing at all is covered too: the
gate must fall back to building, never to skipping.

Usage: python3 genesi-arch/ci/iso-gate-test.py
"""
import io
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
WORKFLOW = os.path.join(ROOT, ".github", "workflows", "iso-pipeline.yml")

# Two lists, as the compare endpoint would print them.
ISO_INPUT = "genesi-arch/archiso/packages.x86_64\n.github/workflows/iso-pipeline.yml\n"
PACKAGE = "genesi-arch/packages/genesi-center/PKGBUILD\ngenesi-arch/repo/x86_64/x.pkg.tar.zst\n"
BOTH = ISO_INPUT + PACKAGE


def decide_script():
    """The gate's decide step, dedented -- ten spaces of YAML indentation."""
    text = io.open(WORKFLOW, encoding="utf-8").read()
    m = re.search(r"- name: Decidir se a ISO deve rodar agora\n(?:.*\n)*?"
                  r" +run: \|\n((?:(?: {10}.*)?\n)+)", text)
    if not m:
        sys.exit("FAIL  could not find the gate's decide step in "
                 "iso-pipeline.yml -- it was renamed or restructured, and "
                 "this test is now checking nothing.")
    return "".join(line[10:] if len(line) > 10 else "\n"
                   for line in m.group(1).splitlines(keepends=True))


def render(body, event, ref, before):
    """What Actions substitutes before the shell sees the script."""
    return (body
            .replace("${{ github.event_name }}", event)
            .replace("${{ startsWith(github.ref, 'refs/tags/') }}",
                     "true" if ref.startswith("refs/tags/") else "false")
            .replace("${{ github.ref }}", ref)
            .replace("${{ github.event.before }}", before))


def run(body, event, ref, before, files):
    """-> (run output, exit code). `files` is what the gh stub prints."""
    d = tempfile.mkdtemp()
    bin_dir = os.path.join(d, "bin")
    os.makedirs(bin_dir)
    gh = os.path.join(bin_dir, "gh")
    io.open(gh, "w", encoding="utf-8", newline="\n").write(
        "#!/bin/sh\n"
        # An empty list is how "the API could not answer" looks to the script.
        + ("exit 1\n" if files is None else
           "cat <<'EOF'\n" + files + "EOF\n"))
    os.chmod(gh, 0o755)

    out = os.path.join(d, "out")
    io.open(out, "w").close()
    step = os.path.join(d, "step.sh")
    io.open(step, "w", encoding="utf-8", newline="\n").write(
        render(body, event, ref, before))

    env = dict(os.environ,
               PATH=bin_dir + os.pathsep + os.environ.get("PATH", ""),
               GITHUB_REPOSITORY="Genesi-OS/GenesiOS",
               GITHUB_SHA="0123456789abcdef0123456789abcdef01234567",
               GITHUB_OUTPUT=out)
    p = subprocess.run(["bash", "--noprofile", "--norc", "-e", "-o", "pipefail",
                        step], cwd=ROOT, env=env, capture_output=True,
                       text=True, timeout=120)
    got = ""
    for line in io.open(out, encoding="utf-8"):
        if line.startswith("run="):
            got = line.strip()[4:]
    return got, p.returncode, p.stdout + p.stderr


ZEROS = "0" * 40
CASES = [
    # name, event, ref, before, files, expected run=
    ("an ISO input alone builds now",
     "push", "refs/heads/main", "a" * 40, ISO_INPUT, "true"),
    ("a push that also touched packages/ defers to publish",
     "push", "refs/heads/main", "a" * 40, BOTH, "false"),
    ("a push that only touched packages/ defers to publish",
     "push", "refs/heads/main", "a" * 40, PACKAGE, "false"),
    ("no usable `before` still decides",
     "push", "refs/heads/main", ZEROS, ISO_INPUT, "true"),
    ("a tag builds whatever it touched",
     "push", "refs/tags/v1.2.3", "a" * 40, PACKAGE, "true"),
    ("workflow_run builds -- the packages are already published",
     "workflow_run", "refs/heads/main", "", PACKAGE, "true"),
    ("manual dispatch builds",
     "workflow_dispatch", "refs/heads/main", "", PACKAGE, "true"),
    # The one that must never become a skip.
    ("an API that will not answer builds anyway",
     "push", "refs/heads/main", "a" * 40, None, "true"),
]

fails = 0
body = decide_script()
print("== the ISO gate's decision ==")
for name, event, ref, before, files, want in CASES:
    got, rc, log = run(body, event, ref, before, files)
    if got == want and rc == 0:
        print("  PASS  %s" % name)
    else:
        fails += 1
        print("  FAIL  %s (got run=%r exit=%d, want run=%s)"
              % (name, got, rc, want))
        print("        " + log.strip().replace("\n", "\n        ")[-600:])

# The gate cannot go back to cloning the repository to answer this. That fetch
# hung twice (2026-08-20, 2026-09-17) and the second time it cancelled the run
# that carried the fix for another CI bug.
def gate_job():
    """The gate job's own CODE: from `  gate:` to the next job key, comments
    stripped.

    Stripped because the comments in that job explain, by name, the very
    checkout this looks for -- and a guard that reads its own explanation as
    the thing it forbids is a guard that fails on the fix. (It did, once, in
    the minute before this line was written; three guards in this repository
    have shipped with the inverse of that bug, passing on the problem because
    a comment carried the string being grepped.)"""
    lines = io.open(WORKFLOW, encoding="utf-8").read().splitlines()
    start = next(i for i, l in enumerate(lines) if l == "  gate:")
    out = []
    for l in lines[start + 1:]:
        # Job keys are the only things at exactly two spaces.
        if re.match(r"^  [A-Za-z_][\w-]*:", l):
            break
        if l.strip().startswith("#"):
            continue
        out.append(l)
    return "\n".join(out)


if "actions/checkout" in gate_job():
    fails += 1
    print("  FAIL  the gate job checks out the repository again -- that fetch "
          "is what hung twice; ask the API instead")
else:
    print("  PASS  the gate needs no checkout")

print()
if fails:
    print("iso gate: %d failure(s)" % fails)
    sys.exit(1)
print("iso gate: OK")
