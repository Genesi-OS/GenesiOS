#!/usr/bin/env python3
"""Register Ctrl+Alt+Space with the active Genesi desktop session."""

import ast
import os
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET


COMMAND = "genesi-ai-quick --toggle"
NAME = "Genesi AI Quick Chat"


def run(*args):
    try:
        return subprocess.run(args, text=True, capture_output=True, timeout=8)
    except (OSError, subprocess.SubprocessError):
        return None


def has(command):
    from shutil import which
    return which(command) is not None


def register_plasma():
    writer = "kwriteconfig6" if has("kwriteconfig6") else "kwriteconfig5"
    if not has(writer):
        return False
    run(writer, "--file", "kglobalshortcutsrc", "--group", "org.genesi.aiquick.desktop",
        "--key", "_launch", "Ctrl+Alt+Space,Ctrl+Alt+Space,Genesi AI Quick Chat")
    # KGlobalAccel reloads this file at login. This D-Bus nudge applies the new
    # component immediately when supported; failure is harmless.
    if has("qdbus6"):
        run("qdbus6", "org.kde.KGlobalAccel", "/kglobalaccel", "org.kde.KGlobalAccel.blockGlobalShortcuts", "false")
    return True


def gsettings_list(schema, key):
    result = run("gsettings", "get", schema, key)
    if not result or result.returncode:
        return []
    text = result.stdout.strip()
    if text.startswith("@as "):
        text = text[4:]
    try:
        value = ast.literal_eval(text)
        return value if isinstance(value, list) else []
    except (ValueError, SyntaxError):
        return []


def register_gnome():
    if not has("gsettings"):
        return False
    schema = "org.gnome.settings-daemon.plugins.media-keys"
    key = "custom-keybindings"
    path = "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/genesi-ai-quick/"
    entries = gsettings_list(schema, key)
    if path not in entries:
        entries.append(path)
        run("gsettings", "set", schema, key, repr(entries))
    custom = schema + ".custom-keybinding:" + path
    run("gsettings", "set", custom, "name", NAME)
    run("gsettings", "set", custom, "command", COMMAND)
    run("gsettings", "set", custom, "binding", "<Ctrl><Alt>space")
    return True


def register_cinnamon():
    if not has("gsettings"):
        return False
    schema = "org.cinnamon.desktop.keybindings"
    key = "custom-list"
    item = "genesi-ai-quick"
    entries = gsettings_list(schema, key)
    if item not in entries:
        entries.append(item)
        run("gsettings", "set", schema, key, repr(entries))
    custom = "org.cinnamon.desktop.keybindings.custom-keybinding:/org/cinnamon/desktop/keybindings/custom-keybindings/genesi-ai-quick/"
    run("gsettings", "set", custom, "name", NAME)
    run("gsettings", "set", custom, "command", COMMAND)
    run("gsettings", "set", custom, "binding", "<Primary><Alt>space")
    return True


def register_xfce():
    if not has("xfconf-query"):
        return False
    prop = "/commands/custom/<Primary><Alt>space"
    result = run("xfconf-query", "-c", "xfce4-keyboard-shortcuts", "-p", prop,
                 "-n", "-t", "string", "-s", COMMAND)
    if result and result.returncode:
        run("xfconf-query", "-c", "xfce4-keyboard-shortcuts", "-p", prop, "-s", COMMAND)
    return True


def register_hyprland():
    if not has("hyprctl") or not os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        return False
    # Runtime registration is naturally reset with the compositor, while this
    # helper runs at every login. No user config needs to be edited.
    run("hyprctl", "keyword", "bind", "CTRL ALT, SPACE, exec, " + COMMAND)
    run("hyprctl", "keyword", "windowrule", "float class:^(org.genesi.aiquick)$")
    run("hyprctl", "keyword", "windowrule", "center class:^(org.genesi.aiquick)$")
    return True


def register_niri():
    desktop = (os.environ.get("XDG_CURRENT_DESKTOP") or "").lower()
    if "niri" not in desktop:
        return False
    path = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "niri" / "config.kdl"
    path.parent.mkdir(parents=True, exist_ok=True)
    text = path.read_text(errors="replace") if path.exists() else ""
    marker = 'Ctrl+Alt+Space repeat=false hotkey-overlay-title="Genesi AI Quick Chat"'
    if marker in text:
        return True
    binding = f'    {marker} {{ spawn "genesi-ai-quick" "--toggle"; }}\n'
    lines = text.splitlines(keepends=True)
    for index, line in enumerate(lines):
        if line.strip().startswith("binds") and "{" in line:
            lines.insert(index + 1, binding)
            break
    else:
        if text and not text.endswith("\n"):
            lines.append("\n")
        lines.extend(["\n// Genesi OS global AI shortcut\n", "binds {\n", binding, "}\n"])
    path.write_text("".join(lines))
    if has("niri"):
        run("niri", "msg", "action", "load-config-file", "--path", str(path))
    return True


def register_cosmic():
    desktop = (os.environ.get("XDG_CURRENT_DESKTOP") or "").lower()
    if "cosmic" not in desktop:
        return False
    path = (Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) /
            "cosmic/com.system76.CosmicSettings.Shortcuts/v1/custom")
    path.parent.mkdir(parents=True, exist_ok=True)
    text = path.read_text(errors="replace") if path.exists() else "{}\n"
    if "genesi-ai-quick --toggle" in text:
        return True
    entry = '''    (
        modifiers: [Ctrl, Alt],
        key: "space",
        description: Some("Genesi AI Quick Chat"),
    ): Spawn("genesi-ai-quick --toggle"),
'''
    closing = text.rfind("}")
    text = (text[:closing] + entry + text[closing:]) if closing >= 0 else "{\n" + entry + "}\n"
    path.write_text(text)
    return True


def register_lxde():
    desktop = (os.environ.get("XDG_CURRENT_DESKTOP") or "").lower()
    if "lxde" not in desktop:
        return False
    base = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "openbox"
    candidates = [base / "lxde-rc.xml", base / "rc.xml"]
    path = next((item for item in candidates if item.exists()), candidates[0])
    if not path.exists():
        return False
    try:
        tree = ET.parse(path)
        root = tree.getroot()
        namespace = root.tag.partition("}")[0].lstrip("{")
        tag = (lambda name: f"{{{namespace}}}{name}") if namespace else (lambda name: name)
        keyboard = root.find(tag("keyboard"))
        if keyboard is None:
            keyboard = ET.SubElement(root, tag("keyboard"))
        for keybind in keyboard.findall(tag("keybind")):
            if keybind.get("key") == "C-A-space":
                return True
        keybind = ET.SubElement(keyboard, tag("keybind"), {"key": "C-A-space"})
        action = ET.SubElement(keybind, tag("action"), {"name": "Execute"})
        ET.SubElement(action, tag("command")).text = COMMAND
        tree.write(path, encoding="UTF-8", xml_declaration=True)
        if has("openbox"):
            run("openbox", "--reconfigure")
        return True
    except (OSError, ET.ParseError):
        return False


def main():
    desktop = " ".join(filter(None, [os.environ.get("XDG_CURRENT_DESKTOP"),
                                      os.environ.get("XDG_SESSION_DESKTOP"),
                                      os.environ.get("DESKTOP_SESSION")])).lower()
    # Session-specific handlers first. GNOME's schema is also used by Budgie.
    if register_hyprland() or register_niri() or register_cosmic() or register_lxde():
        return
    if "cinnamon" in desktop:
        register_cinnamon()
    elif "xfce" in desktop:
        register_xfce()
    elif any(name in desktop for name in ("gnome", "budgie")):
        register_gnome()
    elif any(name in desktop for name in ("kde", "plasma")):
        register_plasma()
    else:
        # Conservative fallback for unusual session labels.
        register_plasma() or register_gnome() or register_xfce()


if __name__ == "__main__":
    main()
