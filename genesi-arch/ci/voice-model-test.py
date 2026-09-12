#!/usr/bin/env python3
"""Are the files genesi-ai-voice downloads actually there?

The installer built its Python environment correctly, resolved every
dependency, reported each one satisfied -- and then answered

    could not download kokoro-v1.0.onnx: HTTP Error 404: Not Found

because the release tag was written `model-v1.0` from memory and is
`model-files-v1.0`. Everything that could be checked locally was right. The
one thing that could not be is the one thing that was wrong.

So this asks GitHub. A HEAD request per file, and:

  * a 404 (or any other 4xx) FAILS the build. A URL that is definitely not
    there is not a network problem, and shipping it means shipping an
    uninstallable feature.

  * a network error does NOT fail it. A build runner with no route to
    github.com must not turn into a red build about a URL that is fine, and a
    check that goes red for reasons unrelated to the change is a check people
    learn to ignore.

The difference between those two is the whole design of this file.
"""
import importlib.machinery
import importlib.util
import os
import sys
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
VOICE = os.path.join(ROOT, "packages", "genesi-ai-mode", "genesi-ai-voice")

failures = []


def ok(what):
    print(f"  ok   {what}")


def bad(what, why):
    print(f"  FAIL {what}")
    print(f"         {why}")
    failures.append(what)


print("== the speech model's downloads ==")

spec = importlib.util.spec_from_loader(
    "voice", importlib.machinery.SourceFileLoader("voice", VOICE))
voice = importlib.util.module_from_spec(spec)
spec.loader.exec_module(voice)

if not voice.FILES:
    bad("genesi-ai-voice lists the files it downloads",
        "FILES is empty, so `install` fetches nothing and `have_files()` is "
        "vacuously true -- it would report ready and be unable to speak")

for name, url, expected in voice.FILES:
    req = urllib.request.Request(url, method="HEAD")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            size = int(r.headers.get("Content-Length") or 0)
            code = r.status
    except urllib.error.HTTPError as e:
        # Definite: the server answered, and the answer was no.
        bad(f"{name} is where genesi-ai-voice looks for it",
            f"{url}\n         answered {e.code} {e.reason}. The install "
            "builds its whole environment before it gets here, so this is a "
            "download that fails after several minutes of apparent success.")
        continue
    except (urllib.error.URLError, OSError, TimeoutError) as e:
        # Indefinite: no answer at all. Not this change's problem.
        print(f"  note {name}: no answer from the network ({e}); "
              "not treated as a failure")
        continue

    if code != 200:
        bad(f"{name} is fetchable", f"{url} answered {code}")
    elif size and size < expected * 0.8:
        # The size is also the installer's own truncation test: it rejects
        # anything under 80% of `expected`, so a file that really is smaller
        # than that would be downloaded in full and then deleted as a
        # fragment.
        bad(f"{name}'s expected size is right",
            f"the server says {size} bytes, genesi-ai-voice expects about "
            f"{expected} and rejects anything under 80% of it -- a complete "
            "download would be thrown away as truncated")
    else:
        ok(f"{name}: {code}, {size // 1_000_000} MB "
           f"(expected about {expected // 1_000_000})")

print()
if failures:
    print(f"{len(failures)} check(s) failed:")
    for f in failures:
        print(f"  - {f}")
    sys.exit(1)
print("speech model: OK")
