#!/usr/bin/env python3
"""
iso-archive-test.py — the per-build archive is the least important thing the
ISO pipeline produces, and it has now taken the pipeline down twice:

  #696  an upload errored after thirteen minutes; the step failed, and the
        three steps after it -- including the one that republishes the
        download page -- were skipped.
  #698  the retry added for #696 was unbounded, so a stalled upload became a
        69-minute stall, the job's 90-minute timeout cancelled the run, and
        the download-page republish was skipped again. Same outcome, one
        layer further in.

What both have in common is that a flake in an ARCHIVE decided the fate of
the download. So the step's contract is now: whatever happens to those
uploads, this step exits 0, inside its budget, and never leaves an archive
that is missing a part.

This runs the step's own `run:` block out of .github/workflows/iso-pipeline.yml
under GitHub's shell, with `gh` and `timeout` stubbed and the ~2GB parts
replaced by a few bytes -- so the contract is tested in about a second,
offline, without uploading anything.

Usage: python3 genesi-arch/ci/iso-archive-test.py
"""
import io
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
WORKFLOW = os.path.join(ROOT, ".github", "workflows", "iso-pipeline.yml")
STEP = "- name: 🗃️ Create per-build archive release (main)"


def step_script():
    """The archive step's run: block, dedented."""
    text = io.open(WORKFLOW, encoding="utf-8").read()
    m = re.search(re.escape(STEP) + r"\n(?:.*\n)*? +run: \|\n"
                  r"((?:(?: {10}.*)?\n)+)", text)
    if not m:
        sys.exit("FAIL  could not find the archive step in iso-pipeline.yml -- "
                 "it was renamed or restructured, and this test now checks "
                 "nothing.")
    return "".join(line[10:] if len(line) > 10 else "\n"
                   for line in m.group(1).splitlines(keepends=True))


# A `gh` that behaves however a case needs it to. `upload` writes the asset
# name and its size into a file the `view` branch reads back, so "what the
# release holds" is answered the way the real endpoint would answer it.
GH_STUB = r"""#!/bin/bash
store="$STORE"
case "$1 $2" in
  "release view")
    if [ "${*#*--json}" != "$*" ]; then
      cat "$store" 2>/dev/null | while read -r name size; do
        [ -n "$name" ] && echo "$name $size"
      done
      exit 0
    fi
    # "does this release exist?"
    [ -f "$store" ] && exit 0
    exit 1 ;;
  "release create")
    : > "$store"; echo "created"; exit 0 ;;
  "release upload")
    f="$4"
    case "$UPLOAD" in
      ok)     echo "$(basename "$f") $(stat -c%s "$f")" >> "$store"; exit 0 ;;
      fail)   echo "Error saving asset" >&2; exit 1 ;;
      stall)  sleep 3600 ;;
      # Uploads the file but truncated: the case a killed upload leaves
      # behind, which counts as missing.
      short)  echo "$(basename "$f") 1" >> "$store"; exit 0 ;;
      # Only the small files land, which is exactly what #696 left on the
      # Releases page.
      parts_fail)
        case "$(basename "$f")" in
          *.part*) echo "Error saving asset" >&2; exit 1 ;;
          *) echo "$(basename "$f") $(stat -c%s "$f")" >> "$store"; exit 0 ;;
        esac ;;
    esac ;;
  "release delete")
    rm -f "$store"; echo "deleted"; exit 0 ;;
esac
echo "unexpected gh call: $*" >&2
exit 1
"""


def run(upload, budget="4", upload_timeout="1"):
    """-> (exit code, output, assets left on the release or None if deleted)"""
    d = tempfile.mkdtemp()
    bin_dir = os.path.join(d, "bin")
    os.makedirs(os.path.join(d, "parts"))
    os.makedirs(bin_dir)
    for name in ("genesi-os.iso.part00", "genesi-os.iso.part01",
                 "genesi-os.iso.sha256", "REJOIN.txt"):
        io.open(os.path.join(d, "parts", name), "w").write(name + "\n")
    io.open(os.path.join(d, "CHANGELOG_BUILD.md"), "w").write("notes\n")

    store = os.path.join(d, "assets")
    gh = os.path.join(bin_dir, "gh")
    io.open(gh, "w", encoding="utf-8", newline="\n").write(GH_STUB)
    os.chmod(gh, 0o755)
    # pacman does not exist on the machine running this test, and the step
    # tolerates that with `|| true` -- but the stub keeps the run quiet.
    pacman = os.path.join(bin_dir, "pacman")
    io.open(pacman, "w", encoding="utf-8", newline="\n").write("#!/bin/sh\nexit 0\n")
    os.chmod(pacman, 0o755)

    sh = os.path.join(d, "step.sh")
    io.open(sh, "w", encoding="utf-8", newline="\n").write(step_script())
    env = dict(os.environ,
               PATH=bin_dir + os.pathsep + os.environ.get("PATH", ""),
               GITHUB_REPOSITORY="Genesi-OS/GenesiOS",
               GITHUB_SHA="0" * 40,
               BUILD_TAG="build-0123456",
               BUILD_NAME="Genesi OS build 0123456",
               STORE=store,
               UPLOAD=upload,
               ARCHIVE_BUDGET=budget,
               ARCHIVE_UPLOAD_TIMEOUT=upload_timeout)
    p = subprocess.run(["bash", "--noprofile", "--norc", "-e", "-o", "pipefail", sh],
                       cwd=d, env=env, capture_output=True, text=True, timeout=300)
    assets = None
    if os.path.exists(store):
        assets = [l.split(" ")[0] for l in
                  io.open(store, encoding="utf-8").read().splitlines() if l]
    return p.returncode, p.stdout + p.stderr, assets


fails = 0


def ck(name, ok, detail=""):
    global fails
    if ok:
        print("  PASS  %s" % name)
    else:
        fails += 1
        print("  FAIL  %s%s" % (name, ("\n        " + detail.strip()[-700:])
                                if detail else ""))


print("== the per-build archive step ==")

rc, out, assets = run("ok")
ck("a clean run uploads every part", rc == 0 and assets is not None
   and len(assets) == 4 and "holds every part" in out, out)

rc, out, assets = run("parts_fail")
ck("the #696 case (parts fail, small files land) exits 0",
   rc == 0, out)
ck("...and the half archive is deleted, not published",
   assets is None, out)

rc, out, assets = run("stall")
ck("the #698 case (uploads that hang) still exits 0", rc == 0, out)
ck("...and says it ran out of time rather than hanging on",
   "out of time for the archive" in out or "failed or stalled" in out, out)
ck("...and leaves no archive behind", assets is None, out)

rc, out, assets = run("short")
ck("an asset that arrived truncated counts as missing",
   rc == 0 and assets is None, out)

rc, out, assets = run("fail")
ck("uploads that fail outright exit 0 and drop the archive",
   rc == 0 and assets is None, out)

# The two things that made #698 a 69-minute step: no per-upload timeout, and
# no overall budget. Both are read out of the step's text, comments stripped,
# because a comment mentioning `timeout` is not a timeout.
code = "\n".join(l for l in step_script().splitlines()
                 if not l.strip().startswith("#"))
ck("each upload is bounded by `timeout`",
   re.search(r'timeout\s+"?\$\{?ARCHIVE_UPLOAD_TIMEOUT', code) is not None
   or re.search(r"\btimeout \d+\s", code) is not None, code)
ck("the step as a whole has a deadline",
   # The deadline has to be COMPARED, not merely computed. Taking the check
   # out while leaving `deadline=$(( SECONDS + ... ))` behind is a real edit
   # somebody could make, and the first version of this line passed on it.
   re.search(r"deadline=\$\(\(\s*SECONDS", code) is not None
   and re.search(r'-ge\s+"?\$\{?deadline', code) is not None, code)

print()
if fails:
    print("iso archive: %d failure(s)" % fails)
    sys.exit(1)
print("iso archive: OK")
