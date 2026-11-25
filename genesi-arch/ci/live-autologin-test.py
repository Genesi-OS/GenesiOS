#!/usr/bin/env python3
"""
live-autologin-test.py — the live session's autologin stays on the live ISO.

The live ISO writes an SDDM drop-in that logs `liveuser` straight into the
desktop. The installer copies every /etc/sddm.conf.d drop-in to the target
(for the theme), and that one went along: every install carried an autologin
for a user that removeuser deletes, and it fought the autologin a user set in
System Settings, which then did not stick. A user found it and edited the
file by hand.

This reads the drop-in name the live ISO really writes (so a rename cannot
leave the cleanup pointing at nothing) and checks the installer deletes that
file from the target AFTER the line that copies the drop-ins over.
"""
import os
import re
import sys

import yaml

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CUSTOMIZE = os.path.join(ROOT, "genesi-arch/archiso/airootfs/root/customize_airootfs.sh")
COPY_CONF = os.path.join(ROOT, "genesi-calamares-config-full/etc/calamares/modules/shellprocess_copy_genesi.conf")

fails = []


def check(name, ok, detail=""):
    print(("  ok   " if ok else "  FAIL ") + name + (("  -- " + detail) if detail and not ok else ""))
    if not ok:
        fails.append(name)


if not os.path.exists(COPY_CONF):
    print("FAIL: genesi-calamares-config-full is missing (check out with submodules)")
    sys.exit(1)

# Which drop-ins does the live ISO write with an autologin for liveuser?
src = open(CUSTOMIZE, encoding="utf-8").read()
live = []
for m in re.finditer(r"cat > /etc/sddm\.conf\.d/(\S+) <<\s*'?(\w+)'?\n(.*?)\n\2\n", src, re.S):
    body = m.group(3)
    if "[Autologin]" in body and re.search(r"^User=liveuser$", body, re.M):
        live.append(m.group(1))
check("the live ISO's autologin drop-in is found", bool(live), "no liveuser [Autologin] in customize_airootfs.sh")

script = yaml.safe_load(open(COPY_CONF, encoding="utf-8-sig"))["script"]
lines = [s if isinstance(s, str) else s.get("command", "") for s in script]
copy_at = next((i for i, s in enumerate(lines)
                if re.search(r"cp -rf /etc/sddm\.conf\.d/\. \$\{ROOT\}/etc/sddm\.conf\.d/", s)), None)
check("the installer copies the SDDM drop-ins", copy_at is not None)

for name in live:
    rm_at = next((i for i, s in enumerate(lines)
                  if re.fullmatch(r"-?rm -f \$\{ROOT\}/etc/sddm\.conf\.d/" + re.escape(name), s.strip())), None)
    check("%s is deleted from the target" % name, rm_at is not None)
    if rm_at is not None and copy_at is not None:
        check("...after the drop-ins are copied over", rm_at > copy_at,
              "rm at line %d, copy at %d" % (rm_at, copy_at))

print()
if fails:
    print("live autologin: %d failure(s)" % len(fails))
    sys.exit(1)
print("live autologin: OK")
