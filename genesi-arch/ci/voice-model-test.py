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

# ── The languages ──────────────────────────────────────────────────────────
#
# The voice ids as they are in voices-v1.0.bin, listed from the file itself
# when the language picker was written -- kept here as a second opinion,
# apart from genesi-ai-voice's own table, because a guard that reads its
# answer out of the thing it checks is not a guard. A voice the file does not
# have is a language picked in a settings page and a synthesis that fails the
# first time anything is said.
#
# Downloading the 28 MB file on every CI run to re-list it would be the
# honest way and a wasteful one; this list changes only with the pinned
# release tag above, and a new tag means re-listing it.
REAL_VOICES = set("""
af_alloy af_aoede af_bella af_heart af_jessica af_kore af_nicole af_nova
af_river af_sarah af_sky am_adam am_echo am_eric am_fenrir am_liam am_michael
am_onyx am_puck am_santa bf_alice bf_emma bf_isabella bf_lily bm_daniel
bm_fable bm_george bm_lewis ef_dora em_alex em_santa ff_siwis hf_alpha hf_beta
hm_omega hm_psi if_sara im_nicola jf_alpha jf_gongitsune jf_nezumi
jf_tebukuro jm_kumo pf_dora pm_alex pm_santa zf_xiaobei zf_xiaoni
zf_xiaoxiao zf_xiaoyi zm_yunjian zm_yunxi zm_yunxia zm_yunyang
""".split())

if "model-files-v1.0" not in voice.RELEASE:
    bad("the voice list below matches the pinned release",
        f"RELEASE is now {voice.RELEASE}; re-list voices-v1.0.bin from that "
        "release and update REAL_VOICES before trusting this check")

for lid, (espeak, label, voices) in voice.LANGUAGES.items():
    unknown = [v for v in voices if v not in REAL_VOICES]
    wrong_prefix = [v for v in voices if voice.PREFIX.get(v[:1]) != lid]
    if not voices:
        bad(f"{lid} has a voice", "an empty list has no default to speak with")
    elif unknown:
        bad(f"{lid}'s voices are in the voices file",
            f"{unknown} {'is' if len(unknown) == 1 else 'are'} not -- picking "
            f"{label} would fail on the first sentence")
    elif wrong_prefix:
        bad(f"{lid}'s voices speak {lid}",
            f"{wrong_prefix}: a voice's first letter is its language, and "
            "`say --voice` works the language out from it")
    else:
        ok(f"{lid} ({espeak}): {len(voices)} voice(s), all in the file")

print()
if failures:
    print(f"{len(failures)} check(s) failed:")
    for f in failures:
        print(f"  - {f}")
    sys.exit(1)
print("speech model: OK")
