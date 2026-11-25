#!/usr/bin/env python3
"""
genesi-center-set writes shell.json without eating it.

Three bugs shipped together in one function, and every symptom the user saw
came out of them:

  * three separate invocations for one drop, each rewriting the whole file from
    its own copy -- so two of the three changes were lost, and a widget dragged
    across the desktop snapped back the moment it was released;
  * all of them writing through a temporary file at the SAME path, so a second
    process truncated the first one's scratch file mid-write and what got
    renamed over shell.json was two JSON documents spliced together;
  * and a reader that treated an unparseable shell.json as "no configuration
    at all", which is why Genesi Center's pages came up blank afterwards
    instead of saying what was wrong.

The interesting one is the second, because os.replace IS atomic and the code
looked correct on that basis. Atomicity of the rename says nothing about who
else is writing the thing being renamed.

So this test does not read the source looking for the fix. It runs the real
program, concurrently, and then parses what is on disk -- which is the only
statement worth making about a file format.
"""
import io
import json
import os
import subprocess
import sys
import tempfile

# The box drawing below is not decoration -- it is how every guard in ci/ reads
# -- and a Windows console defaults to cp1252, where printing it is a crash.
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except (AttributeError, OSError):
    pass

HERE = os.path.dirname(os.path.abspath(__file__))
SET = os.path.join(HERE, "..", "packages", "genesi-center", "genesi-center-set")

fails = []


def check(name, cond, detail=""):
    print(("  ok   " if cond else "  FAIL ") + name + (
        "" if cond else "\n         " + detail))
    if not cond:
        fails.append(name)


def fakehome(home):
    """
    An environment whose "~" is `home`, on Linux AND on Windows.

    HOME alone is not enough: os.path.expanduser resolves ~ from USERPROFILE on
    Windows and ignores HOME entirely. The first version of this file set only
    HOME, so every "temporary" write landed in the developer's real home
    directory -- it created a caelestia config on a machine that has never run
    caelestia, and the assertions failed reading the temp dir it had never
    touched.
    """
    env = dict(os.environ)
    env["HOME"] = home
    env["USERPROFILE"] = home
    env["XDG_CONFIG_HOME"] = os.path.join(home, ".config")
    # Nothing here should reach the compositor, but a stray hyprctl in a test
    # environment is a hang rather than a failure.
    env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
    return env


def run(home, *args):
    env = fakehome(home)
    return subprocess.run([sys.executable, SET] + list(args),
                          capture_output=True, text=True, env=env, timeout=60)


def shell_json(home):
    return os.path.join(home, ".config", "caelestia", "shell.json")


def read(home):
    return io.open(shell_json(home), encoding="utf-8").read()


print("── one call, several values " + "─" * 36)
with tempfile.TemporaryDirectory() as home:
    os.makedirs(os.path.dirname(shell_json(home)))
    io.open(shell_json(home), "w", encoding="utf-8", newline="\n").write("{}\n")
    p = run(home, "caelestia",
            "background.widgets.cpu.x", "0.4200",
            "background.widgets.cpu.y", "0.1300",
            "background.widgets.cpu.position", "free")
    check("three values in one invocation are accepted", p.returncode == 0,
          p.stderr.strip())
    cfg = json.loads(read(home))
    w = ((cfg.get("background") or {}).get("widgets") or {}).get("cpu") or {}
    # All three, from one process. This is the whole point: a drop that writes
    # x without position is a widget that goes back to its corner on reload.
    check("all three landed", w.get("position") == "free"
          and abs(w.get("x", 0) - 0.42) < 1e-6
          and abs(w.get("y", 0) - 0.13) < 1e-6, repr(w))

    p = run(home, "caelestia", "background.widgets.cpu.x")
    check("a path with no value is refused", p.returncode != 0)

    p = run(home, "caelestia", "background.widgets.cpu.x", "0.5",
            "border.nonsense", "3")
    check("one bad path rejects the WHOLE batch", p.returncode != 0,
          "a partial write is worse than none: the caller believes all of it "
          "landed")
    cfg = json.loads(read(home))
    w = ((cfg.get("background") or {}).get("widgets") or {}).get("cpu") or {}
    check("and nothing from that batch was written",
          abs(w.get("x", 0) - 0.42) < 1e-6, repr(w))

print()
print("── concurrent writers " + "─" * 42)
with tempfile.TemporaryDirectory() as home:
    os.makedirs(os.path.dirname(shell_json(home)))
    io.open(shell_json(home), "w", encoding="utf-8", newline="\n").write("{}\n")
    env = fakehome(home)
    env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
    # Twelve at once, all writing the same file. With a shared scratch path
    # this produced a spliced document within a couple of runs.
    procs = [subprocess.Popen(
        [sys.executable, SET, "caelestia",
         f"background.widgets.{n}.x", f"0.{i:02d}00"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
        for i, n in enumerate(
            ["cpu", "memory", "storage", "network", "battery", "calendar",
             "weather", "forecast", "media", "uptime", "greeting",
             "notifications"])]
    for p in procs:
        p.wait(timeout=60)
    text = read(home)
    try:
        json.loads(text)
        parsed = True
        why = ""
    except json.JSONDecodeError as e:
        parsed = False
        why = f"{e} -- {len(text)} bytes on disk"
    # The claim is ONLY this. Which of the twelve won is a race and always was;
    # a file that no longer parses is a broken desktop.
    check("shell.json still parses after twelve concurrent writers",
          parsed, why)
    leftovers = [f for f in os.listdir(os.path.dirname(shell_json(home)))
                 if ".genesi-tmp" in f]
    check("no scratch files left behind", not leftovers, repr(leftovers))

print()
print("── a broken file is salvaged, not discarded " + "─" * 20)
with tempfile.TemporaryDirectory() as home:
    os.makedirs(os.path.dirname(shell_json(home)))
    good = {"border": {"thickness": 7}, "launcher": {"position": "centre"}}
    # Exactly the damage the old code did: a whole document, then the head of
    # a second one written over the top of it.
    spliced = json.dumps(good, indent=2) + '\n{\n  "border": {\n    "thi'
    io.open(shell_json(home), "w", encoding="utf-8",
            newline="\n").write(spliced)
    p = run(home, "caelestia", "dock.enabled", "true")
    check("a spliced shell.json does not stop the write", p.returncode == 0,
          p.stderr.strip())
    cfg = json.loads(read(home))
    check("the settings in the good half survived",
          cfg.get("border", {}).get("thickness") == 7
          and cfg.get("launcher", {}).get("position") == "centre", repr(cfg))
    check("and the new value is there", cfg.get("dock", {}).get("enabled") is True,
          repr(cfg.get("dock")))
    check("the damaged file was kept, not deleted",
          os.path.exists(shell_json(home) + ".broken"))
    check("and it said so on stderr", "not valid JSON" in p.stderr, p.stderr)

print()
print("── the reader agrees with the writer " + "─" * 27)
with tempfile.TemporaryDirectory() as home:
    os.makedirs(os.path.dirname(shell_json(home)))
    io.open(shell_json(home), "w", encoding="utf-8", newline="\n").write(
        json.dumps({"launcher": {"position": "centre"}}, indent=2)
        + '\n{"launcher"')
    env = fakehome(home)
    data = os.path.join(HERE, "..", "packages", "genesi-center",
                        "genesi-center-data")
    p = subprocess.run([sys.executable, data, "launcher"], capture_output=True,
                       text=True, env=env, timeout=60)
    try:
        d = json.loads(p.stdout)
    except json.JSONDecodeError:
        d = {}
    # This is the bug that made the Hub's pages blank. `available` gates the
    # entire body of every caelestia page; hanging it on a successful parse
    # meant one bad byte hid every setting in the app.
    check("a damaged shell.json still reports available",
          d.get("available") is True, p.stdout[:200])
    check("and the salvaged value is what the page will show",
          (d.get("options") or {}).get("position") == "centre",
          repr(d.get("options")))

print()
if fails:
    print(f"{len(fails)} check(s) failed:")
    for f in fails:
        print("  - " + f)
    sys.exit(1)
print("shell.json survives what broke it.")
