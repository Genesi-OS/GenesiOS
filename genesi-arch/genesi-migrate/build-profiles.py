"""Build native migration package profiles from the installer's YAML sources."""
import json
from pathlib import Path
import yaml

ROOT = Path(__file__).resolve().parents[2]
MODULES = ROOT / "genesi-calamares-config-full/etc/calamares/modules"
base = yaml.safe_load((MODULES / "pacstrap.conf").read_text(encoding="utf-8"))["basePackages"]
groups = yaml.safe_load((MODULES / "netinstall.yaml").read_text(encoding="utf-8"))
chooser = yaml.safe_load((MODULES / "packagechooser.conf").read_text(encoding="utf-8"))
desktops = {item["id"] for item in chooser["items"]}


def packages(node):
    result = list(node.get("packages", []))
    for child in node.get("subgroups", []):
        if child.get("selected", True):
            result += packages(child)
    return result


profiles = {}
for desktop in sorted(desktops):
    if desktop not in {g["name"] for g in groups}:
        continue
    chosen = list(base)
    for group in groups:
        if group["name"] == desktop or (group["name"] not in desktops and group.get("selected", True)):
            # Noncritical translation/printer groups cannot block migration.
            if group.get("critical", True):
                chosen += packages(group)
    profiles[desktop] = sorted(set(chosen + ["rsync", "arch-install-scripts", "btrfs-progs"]))
(Path(__file__).parent / "app/native-profiles.json").write_text(
    json.dumps(profiles, indent=2) + "\n", encoding="utf-8")
