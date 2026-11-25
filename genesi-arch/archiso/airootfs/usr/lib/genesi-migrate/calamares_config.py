#!/usr/bin/env python3
"""
Turn the live system's normal Calamares setup into the MIGRATION one.

Run by calamares-online.sh (as root) after it has laid down Genesi's Calamares
configuration, and only when the ISO was booted by Genesi Migrate. It reads
the plan the user made on their old system and rewrites four files in place:

  settings.conf      no partitioning page; the exec phase partitions with
                     genesimigratedisk (from the plan) instead of `partition`,
                     and genesimigraterestore runs before `umount`
  users.conf         full name + login name pre-filled (still editable; the
                     password is still typed: it never left the old system)
  packagechooser.conf  ONLY the desktop chosen in Genesi Migrate. Pre-selecting
                     one item and leaving the rest is the netinstall-select leak
                     the file's own header describes (two desktops installed);
                     a list of one cannot leak.
  locale.conf        the old system's time zone, no geoip guess

Text edits, not YAML round-trips: the live ISO has no PyYAML, and these files
are Genesi's own, so their shape is known -- ci/migrate-test.py runs this
against the real files to keep it that way.

    calamares_config.py <manifest.json> <calamares dir, e.g. /etc/calamares>
"""
import json
import os
import re
import sys

MODULES_DIR = "/usr/lib/genesi-migrate/calamares"


def q(value):
    """A YAML double-quoted scalar."""
    return '"' + str(value).replace("\\", "\\\\").replace('"', '\\"') + '"'


def settings(text):
    out, phase = [], None
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("modules-search:"):
            line = "modules-search: [ local, %s ]" % MODULES_DIR
        if stripped == "- show:":
            phase = "show"
        elif stripped == "- exec:":
            phase = "exec"
        if stripped == "- partition":
            if phase == "show":
                continue                      # the page: gone
            if phase == "exec":
                line = line.replace("partition", "genesimigratedisk")
        if stripped == "- umount" and phase == "exec":
            out.append(line.replace("umount", "genesimigraterestore"))
        out.append(line)
    result = "\n".join(out) + "\n"
    for needed in ("genesimigratedisk", "genesimigraterestore", MODULES_DIR):
        if needed not in result:
            raise ValueError("settings.conf has an unexpected shape: no place for %s" % needed)
    return result


def users(text, full_name, login):
    login = re.sub(r"[^a-z0-9_-]", "", (login or "").lower())[:31]
    if not login or not re.match(r"[a-z_]", login):
        login = ""

    for block, value in (("fullName", full_name), ("loginName", login)):
        if not value:
            continue
        m = re.search(r"^([ \t]*)%s:[ \t]*\n" % block, text, re.M)
        if m:
            line = "%s    value: %s\n" % (m.group(1), q(value))
            text = text[:m.end()] + line + text[m.end():]
    return text


def packagechooser(text, desktop_id):
    """Keep the header and the one chosen item; make it the default."""
    head, sep, items = text.partition("\nitems:\n")
    if not sep:
        raise ValueError("packagechooser.conf has no items list")
    blocks = re.split(r"(?m)^(?=    - id:)", items)
    keep = [b for b in blocks if re.match(r'    - id:\s*"?%s"?\s*$' % re.escape(desktop_id), b.splitlines()[0] if b else "")]
    if not keep:
        raise ValueError("desktop %s is not in packagechooser.conf" % desktop_id)
    head = re.sub(r'(?m)^default:.*$', "default: %s" % q(desktop_id), head)
    return head + sep + keep[0].rstrip() + "\n"


def locale(timezone):
    region, _, zone = (timezone or "").partition("/")
    if not zone:
        region, zone = "America", "New_York"
    return ("# Written by Genesi Migrate from the old system's time zone.\n"
            "---\nregion: %s\nzone: %s\n" % (q(region), q(zone)))


def apply(manifest, cala_dir):
    st, ch = manifest["settings"], manifest["choices"]
    mod = os.path.join(cala_dir, "modules")
    edits = {
        os.path.join(cala_dir, "settings.conf"): lambda t: settings(t),
        os.path.join(mod, "users.conf"): lambda t: users(t, st["user"].get("fullName"), st["user"].get("name")),
        os.path.join(mod, "packagechooser.conf"): lambda t: packagechooser(t, ch["desktop"]),
    }
    # Everything is computed before anything is written: a half-rewritten
    # setup (settings.conf expecting genesimigratedisk, the rest stock) would
    # be worse than either installer.
    out = {}
    for path, fn in edits.items():
        with open(path, encoding="utf-8") as f:
            out[path] = fn(f.read())
    out[os.path.join(mod, "locale.conf")] = locale(st.get("timezone"))
    for path, text in out.items():
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)
    return list(out)


if __name__ == "__main__":
    with open(sys.argv[1], encoding="utf-8") as f:
        m = json.load(f)
    for p in apply(m, sys.argv[2]):
        print("genesi-migrate: wrote", p)
