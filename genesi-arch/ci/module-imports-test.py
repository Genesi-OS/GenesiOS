"""Every name imported from one Genesi module must exist in that module.

This exists because of a bug that shipped and then sat there. `TURBO` in
genesi_ai_monitor was renamed to `LOCAL_TURBO` when Turbo learned to run on a
mesh peer, and genesi_ai_quick — which imports it — was not updated. Quick Chat
autostarts on every login, so it died on the import line every single time, and
nobody noticed for weeks: an autostarted app that fails leaves no window to
miss.

Nothing here imports anything for real. It reads the files with `ast`, so it
runs on any machine, with no PySide6, no Qt, no display and no daemon — which is
the whole point, since those are exactly the reasons this never got caught.

    python genesi-arch/ci/module-imports-test.py
"""
import ast
import sys
from pathlib import Path

PKGS = Path(__file__).resolve().parents[1] / "packages"

failures = []


def check(name, ok, detail=""):
    print(("  PASS  " if ok else "  FAIL  ") + name + (("  — " + detail) if detail and not ok else ""))
    if not ok:
        failures.append(name)


def parse(path):
    try:
        return ast.parse(path.read_text(encoding="utf-8"))
    except (OSError, SyntaxError) as exc:
        check("%s parses" % path.name, False, str(exc))
        return None


def exported(tree):
    """Every top-level name a module offers: assignments, defs, classes and
    imports it re-exports."""
    names = set()
    for node in tree.body:
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            names.add(node.name)
        elif isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name):
                    names.add(target.id)
        elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
            names.add(node.target.id)
        elif isinstance(node, ast.Import):
            for alias in node.names:
                names.add(alias.asname or alias.name.split(".")[0])
        elif isinstance(node, ast.ImportFrom):
            for alias in node.names:
                names.add(alias.asname or alias.name)
        elif isinstance(node, ast.Try):
            # Optional dependencies are usually imported inside try/except, and
            # the names they bind are still importable by other modules.
            for sub in ast.walk(node):
                if isinstance(sub, (ast.Import, ast.ImportFrom)):
                    for alias in sub.names:
                        names.add(alias.asname or alias.name.split(".")[0])
                elif isinstance(sub, ast.Assign):
                    for target in sub.targets:
                        if isinstance(target, ast.Name):
                            names.add(target.id)
    return names


# Build a map of every first-party module we ship, by module name.
modules = {}
for path in sorted(PKGS.rglob("*.py")):
    if "__pycache__" in path.parts:
        continue
    tree = parse(path)
    if tree is not None:
        modules.setdefault(path.stem, []).append((path, tree, exported(tree)))

print("\n[1] first-party modules found")
for wanted in ("genesi_ai_monitor", "genesi_turbo_ctl", "genesi_ai_assist",
               "genesi_workflow_gen", "genesi_agent"):
    check(wanted, wanted in modules, "not found under packages/")

print("\n[2] every cross-module import resolves")
checked = 0
for stem, entries in sorted(modules.items()):
    for path, tree, _names in entries:
        for node in ast.walk(tree):
            if not isinstance(node, ast.ImportFrom) or node.level:
                continue
            target = (node.module or "").split(".")[0]
            if target not in modules or target == stem:
                continue
            # Compare against every copy of the target we ship; a name existing
            # in any of them is good enough, since only one is installed.
            available = set()
            for _p, _t, names in modules[target]:
                available |= names
            for alias in node.names:
                if alias.name == "*":
                    continue
                checked += 1
                check("%s imports %s from %s" % (path.name, alias.name, target),
                      alias.name in available,
                      "%s does not define it" % target)

check("something was actually checked", checked > 0, "checked=%d" % checked)

print("\n[3] the specific regression that prompted this file")
mon = set()
for _p, _t, names in modules.get("genesi_ai_monitor", []):
    mon |= names
check("genesi_ai_monitor still offers _turbo_base", "_turbo_base" in mon)
check("and OLLAMA", "OLLAMA" in mon)
quick = [t for _p, t, _n in modules.get("genesi_ai_quick", [])]
if quick:
    imported = {alias.name
                for node in ast.walk(quick[0]) if isinstance(node, ast.ImportFrom)
                and (node.module or "") == "genesi_ai_monitor"
                for alias in node.names}
    check("quick chat no longer imports the removed TURBO",
          "TURBO" not in imported, str(sorted(imported)))

print("\n" + ("ALL TESTS PASSED" if not failures
              else "FAILURES: " + ", ".join(failures)))
sys.exit(1 if failures else 0)
