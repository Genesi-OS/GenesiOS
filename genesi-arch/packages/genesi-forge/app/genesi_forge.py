#!/usr/bin/env python3
"""Backend for Genesi Forge — the local project hub, Git dashboard and Forge
Canvas (workflow builder). It scans the user's Git projects, detects each
project's stack, tracks stars / recents / imports, talks to GitHub through the
`gh` CLI, and turns a Forge Canvas graph into a real GitHub Actions workflow."""
import fnmatch
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path
from urllib.parse import urlparse

from PySide6.QtCore import QObject, QUrl, Signal, Slot
from PySide6.QtGui import QDesktopServices, QGuiApplication, QIcon
from PySide6.QtQml import QQmlApplicationEngine


HOME = Path.home()
STATE = HOME / ".cache/genesi-forge"
CACHE = STATE / "repos.json"
STARS = STATE / "stars.json"
RECENT = STATE / "recent.json"
IMPORTS = STATE / "imports.json"
WORKFLOWS = STATE / "workflows"
SKIP_DIRS = {
    ".cache", ".local", ".npm", ".cargo", ".rustup", ".var", ".Trash",
    "node_modules", "vendor", "target", "dist", "build", ".venv", "venv",
    "__pycache__", ".snapshots",
}


def run(args, cwd=None, timeout=10, strip=True):
    # strip=False is REQUIRED for `git status --porcelain` — its lines are
    # `XY<space>PATH`, and a global strip() eats the first line's leading status
    # space, shifting the parse so the first file loses its initial character.
    try:
        proc = subprocess.run(args, cwd=cwd, text=True, capture_output=True,
                              timeout=timeout, env={**os.environ, "LC_ALL": "C"})
        if strip:
            return proc.returncode, proc.stdout.strip(), proc.stderr.strip()
        return proc.returncode, proc.stdout, proc.stderr.strip()
    except (OSError, subprocess.TimeoutExpired) as exc:
        return 127, "", str(exc)


def git(path, *args, timeout=8, strip=True):
    return run(["git", "-C", str(path), *args], timeout=timeout, strip=strip)


def load_json(path, default):
    try:
        if path.exists():
            return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        pass
    return default


def save_json(path, data):
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data), encoding="utf-8")
    except OSError:
        pass


# ── Stack detection ────────────────────────────────────────────────────────
# Returns {label, kind, color} so the UI can paint a brand-tinted TechLogo. The
# `kind` drives which mark TechLogo.qml draws; the color is the brand accent.
def detect_stack(path):
    p = Path(path)

    def has(name):
        return (p / name).exists()

    if has("pubspec.yaml"):
        return {"label": "Flutter", "kind": "flutter", "color": "#02569B"}

    if has("package.json"):
        deps = {}
        try:
            data = json.loads((p / "package.json").read_text(encoding="utf-8"))
            deps = {**data.get("dependencies", {}), **data.get("devDependencies", {})}
        except (OSError, ValueError):
            pass
        is_ts = has("tsconfig.json")
        if "next" in deps:
            return {"label": "Next.js", "kind": "next", "color": "#E6EDF3"}
        if "nuxt" in deps:
            return {"label": "Nuxt", "kind": "vue", "color": "#42B883"}
        if "@angular/core" in deps:
            return {"label": "Angular", "kind": "angular", "color": "#DD0031"}
        if "svelte" in deps:
            return {"label": "Svelte", "kind": "svelte", "color": "#FF3E00"}
        if "vue" in deps:
            return {"label": "Vue", "kind": "vue", "color": "#42B883"}
        if "react" in deps or "react-native" in deps:
            return {"label": "React", "kind": "react", "color": "#61DAFB"}
        if is_ts:
            return {"label": "TypeScript", "kind": "typescript", "color": "#3178C6"}
        return {"label": "Node.js", "kind": "node", "color": "#5FA04E"}

    if has("Cargo.toml"):
        return {"label": "Rust", "kind": "rust", "color": "#DEA584"}
    if has("go.mod"):
        return {"label": "Go", "kind": "go", "color": "#00ADD8"}
    if has("pyproject.toml") or has("requirements.txt") or has("setup.py") \
            or next(iter(p.glob("*.py")), None):
        return {"label": "Python", "kind": "python", "color": "#3776AB"}
    if has("composer.json"):
        return {"label": "PHP", "kind": "php", "color": "#777BB4"}
    if has("Gemfile"):
        return {"label": "Ruby", "kind": "ruby", "color": "#CC342D"}

    # Styles / static site — shallow check so discovery stays cheap.
    if next(iter(p.glob("*.scss")), None) or next(iter(p.glob("src/*.scss")), None) \
            or next(iter(p.glob("styles/*.scss")), None):
        return {"label": "SCSS", "kind": "scss", "color": "#CD6799"}
    if has("index.html"):
        return {"label": "HTML", "kind": "html", "color": "#E34F26"}

    return {"label": "Git", "kind": "git", "color": "#8A94A6"}


def remote_info(url):
    clean = url.strip()
    host = ""
    slug = ""
    if clean.startswith("git@"):
        left, _, right = clean.partition(":")
        host = left.split("@", 1)[-1]
        slug = right
    elif clean.startswith("ssh://") or clean.startswith("http"):
        parsed = urlparse(clean)
        host = parsed.hostname or ""
        slug = parsed.path.lstrip("/")
    slug = slug.removesuffix(".git")
    provider = "Git"
    if "github" in host:
        provider = "GitHub"
    elif "gitlab" in host:
        provider = "GitLab"
    elif "bitbucket" in host:
        provider = "Bitbucket"
    web = f"https://{host}/{slug}" if host and slug else ""
    return provider, slug, web


def integration_rows(path):
    checks = [
        ("Vercel", [".vercel/project.json", "vercel.json"], "https://vercel.com/dashboard"),
        ("Netlify", ["netlify.toml", ".netlify/state.json"], "https://app.netlify.com"),
        ("Render", ["render.yaml", "render.yml"], "https://dashboard.render.com"),
        ("Railway", ["railway.json", "railway.toml"], "https://railway.app/dashboard"),
        ("Fly.io", ["fly.toml"], "https://fly.io/dashboard"),
        ("Docker", ["Dockerfile", "compose.yaml", "docker-compose.yml"], ""),
    ]
    rows = []
    for name, files, url in checks:
        found = next((item for item in files if (path / item).exists()), "")
        if found:
            detail = found
            if name == "Vercel" and found == ".vercel/project.json":
                try:
                    data = json.loads((path / found).read_text(encoding="utf-8"))
                    detail = data.get("projectId", found)
                except (OSError, ValueError):
                    pass
            rows.append({"name": name, "detail": detail, "url": url})
    workflow_dir = path / ".github/workflows"
    if workflow_dir.is_dir():
        count = len(list(workflow_dir.glob("*.y*ml")))
        rows.append({"name": "GitHub Actions", "detail": f"{count} workflow(s)", "url": ""})
    if (path / ".gitlab-ci.yml").exists():
        rows.append({"name": "GitLab CI", "detail": ".gitlab-ci.yml", "url": ""})
    return rows


def discover_repos():
    found = set()
    for root in [HOME]:
        for current, dirs, _files in os.walk(root, topdown=True, followlinks=False):
            here = Path(current)
            try:
                depth = len(here.relative_to(root).parts)
            except ValueError:
                continue
            dirs[:] = [d for d in dirs if d not in SKIP_DIRS and not d.startswith(".")]
            if (here / ".git").exists():
                found.add(str(here))
                dirs[:] = []
                continue
            if depth >= 7:
                dirs[:] = []
    for cached in load_json(CACHE, []):
        if Path(cached, ".git").exists():
            found.add(cached)
    save_json(CACHE, sorted(found))
    # Imported projects may not have a .git — keep them if the folder still exists.
    extra = [p for p in load_json(IMPORTS, []) if Path(p).is_dir()]
    return sorted(found), extra


def project_summary(path_text, stars, recents):
    path = Path(path_text)
    has_git = (path / ".git").exists()
    stack = detect_stack(path)
    base = {
        "id": str(path), "name": path.name, "path": str(path),
        "shortPath": _short(path), "hasGit": has_git,
        "stack": stack["label"], "stackKind": stack["kind"], "stackColor": stack["color"],
        "starred": str(path) in stars, "lastOpened": recents.get(str(path), 0),
        "branch": "", "provider": "None", "slug": "", "remote": "", "web": "",
        "changed": 0, "staged": 0, "modified": 0, "untracked": 0,
        "ahead": 0, "behind": 0, "lastHash": "", "lastSubject": "", "lastTime": 0,
        "integrations": integration_rows(path), "pipelineCount": 0, "deployCount": 0,
    }
    base["deployCount"] = sum(1 for i in base["integrations"]
                              if i["name"] in {"Vercel", "Netlify", "Render", "Railway", "Fly.io"})
    base["pipelineCount"] = sum(1 for i in base["integrations"]
                                if "Actions" in i["name"] or "CI" in i["name"])
    if not has_git:
        return base

    _, branch, _ = git(path, "branch", "--show-current")
    if not branch:
        _, branch, _ = git(path, "rev-parse", "--short", "HEAD")
    _, status, _ = git(path, "status", "--porcelain=v1", "--untracked-files=normal", strip=False)
    lines = status.splitlines() if status else []
    base["staged"] = sum(1 for line in lines if line and line[0] not in (" ", "?"))
    base["modified"] = sum(1 for line in lines if not line.startswith("??") and len(line) > 1 and line[1] != " ")
    base["untracked"] = sum(1 for line in lines if line.startswith("??"))
    _, remote, _ = git(path, "remote", "get-url", "origin")
    provider, slug, web = remote_info(remote)
    ahead = behind = 0
    code, counts, _ = git(path, "rev-list", "--left-right", "--count", "@{upstream}...HEAD")
    if code == 0 and counts:
        try:
            behind, ahead = (int(v) for v in counts.split())
        except ValueError:
            pass
    _, last, _ = git(path, "log", "-1", "--format=%h%x1f%s%x1f%ct")
    last_hash = last_subject = ""
    last_time = 0
    if last:
        parts = last.split("\x1f", 2)
        if len(parts) == 3:
            last_hash, last_subject, raw_time = parts
            try:
                last_time = int(raw_time)
            except ValueError:
                pass
    base.update({
        "branch": branch or "detached", "provider": provider, "slug": slug,
        "remote": remote, "web": web, "changed": len(lines),
        "ahead": ahead, "behind": behind, "lastHash": last_hash,
        "lastSubject": last_subject, "lastTime": last_time,
    })
    return base


def _short(path):
    try:
        rel = path.relative_to(HOME)
        return "~/" + str(rel).replace(os.sep, "/")
    except ValueError:
        return str(path)


# ── Forge Canvas → GitHub Actions YAML ──────────────────────────────────────
def graph_to_yaml(project_name, nodes):
    kinds = [n.get("kind", "") for n in nodes]
    has = kinds.__contains__
    events = [n.get("config", {}).get("event", "push") for n in nodes
              if n.get("kind") == "event"]
    branches = [n.get("config", {}).get("branch", "main") for n in nodes
                if n.get("kind") == "event"] or ["main"]
    branch_list = ", ".join(json.dumps(branch) for branch in branches)
    lines = [
        f"# Generated by Genesi Forge — Forge Canvas workflow for {project_name}",
        "name: Genesi Forge Pipeline",
        "",
        "on:",
        "  workflow_dispatch:",
    ]
    if not events or "push" in events or "commit" in events or "branch_created" in events:
        lines += ["  push:", f"    branches: [ {branch_list} ]"]
    if "pull_request" in events:
        lines += ["  pull_request:", f"    branches: [ {branch_list} ]"]
    if "schedule" in events:
        lines += ["  schedule:", "    - cron: '0 6 * * 1-5'"]
    lines += [
        "", "jobs:",
        "  forge:",
        "    runs-on: ubuntu-latest",
        "    steps:",
        "      - name: Checkout",
        "        uses: actions/checkout@v4",
    ]
    if "branch_created" in events and len(events) == 1:
        lines.insert(lines.index("    runs-on: ubuntu-latest"), "    if: github.event.created == true")
    if has("node") or has("install") or has("react") or has("next") or has("typescript"):
        lines += [
            "      - name: Setup Node.js",
            "        uses: actions/setup-node@v4",
            "        with:",
            "          node-version: '20'",
            "          cache: npm",
        ]
    if has("python"):
        lines += [
            "      - name: Setup Python",
            "        uses: actions/setup-python@v5",
            "        with:",
            "          python-version: '3.12'",
        ]
    if has("install"):
        lines += [
            "      - name: Install dependencies",
            "        run: npm ci",
        ]
    if has("database"):
        lines += [
            "      - name: Provision database",
            "        run: echo 'Set up your database service here'",
        ]
    if has("script"):
        scripts = [n.get("config", {}).get("command", "npm test --if-present && npm run build --if-present")
                   for n in nodes if n.get("kind") == "script"]
        lines += [
            "      - name: Run script",
            "        run: " + (scripts[0] if scripts else "npm test --if-present"),
        ]
    if has("quality"):
        lines += ["      - name: Code quality", "        run: npm run lint --if-present"]
    if has("tests"):
        lines += ["      - name: Tests", "        run: npm test --if-present"]
    if has("docker"):
        lines += [
            "      - name: Build Docker image",
            f"        run: docker build -t {project_name}:latest .",
        ]
    return "\n".join(lines) + "\n"


class Backend(QObject):
    projectsLoaded = Signal(str)
    statsLoaded = Signal(str)
    pipelinesLoaded = Signal(str)
    busyChanged = Signal(bool)
    message = Signal(str)
    workflowStep = Signal(str)     # {"id","state"} per step, live
    workflowLog = Signal(str)      # {"id","line","level"} one output line
    workflowDone = Signal(bool)    # ran to completion (True) or failed/stopped (False)
    prsLoaded = Signal(str)        # gh pr list JSON
    consoleOut = Signal(str)       # one line of embedded-console output
    consoleDone = Signal(int)      # console command exit code

    def __init__(self):
        super().__init__()
        self.busy = False
        self._run_stop = threading.Event()
        self._running = False

    def _set_busy(self, value):
        self.busy = value
        self.busyChanged.emit(value)

    def _thread(self, fn):
        threading.Thread(target=fn, daemon=True).start()

    @Slot()
    def refresh(self):
        if self.busy:
            return
        self._set_busy(True)

        def work():
            try:
                stars = set(load_json(STARS, []))
                recents = load_json(RECENT, {})
                repos, extra = discover_repos()
                paths = list(dict.fromkeys(repos + extra))
                projects = [project_summary(p, stars, recents) for p in paths]
                projects.sort(key=lambda item: (
                    not item["starred"], item["changed"] == 0,
                    -item["lastTime"], item["name"].lower()))
                git_count = sum(1 for p in projects if p["hasGit"])
                star_count = sum(1 for p in projects if p["starred"])
                recent_count = sum(1 for p in projects if p["lastOpened"] > 0)
                self.statsLoaded.emit(json.dumps({
                    "total": len(projects), "git": git_count,
                    "starred": star_count, "recent": recent_count}))
                self.projectsLoaded.emit(json.dumps({
                    "projects": projects, "scannedAt": int(time.time())}))
            except Exception as exc:
                self.message.emit(f"Could not scan projects: {exc}")
                self.projectsLoaded.emit('{"projects":[]}')
            finally:
                self._set_busy(False)

        self._thread(work)

    @Slot(str)
    def toggleStar(self, path):
        stars = set(load_json(STARS, []))
        if path in stars:
            stars.discard(path)
        else:
            stars.add(path)
        save_json(STARS, sorted(stars))
        self.refresh()

    def _touch_recent(self, path):
        recents = load_json(RECENT, {})
        recents[path] = int(time.time())
        save_json(RECENT, recents)

    @Slot(str)
    def importProject(self, path):
        target = Path(path)
        if not target.is_dir():
            self.message.emit("That folder does not exist.")
            return
        imports = load_json(IMPORTS, [])
        if str(target) not in imports:
            imports.append(str(target))
            save_json(IMPORTS, imports)
        self.message.emit(f"Imported {target.name}.")
        self.refresh()

    @Slot(str)
    def initGit(self, path):
        if self.busy:
            return
        self._set_busy(True)

        def work():
            code, _out, err = git(Path(path), "init")
            self.message.emit("Git initialized." if code == 0 else (err or "git init failed"))
            self._set_busy(False)
            self.refresh()

        self._thread(work)

    @Slot(str, str, bool)
    def createGitHub(self, path, name, private):
        if self.busy:
            return
        self._set_busy(True)

        def work():
            p = Path(path)
            if not (p / ".git").exists():
                git(p, "init")
            visibility = "--private" if private else "--public"
            code, out, err = run(["gh", "repo", "create", name or p.name, visibility,
                                  "--source", str(p), "--remote", "origin", "--push"],
                                 timeout=60)
            self.message.emit("Repository created on GitHub."
                              if code == 0 else (err or out or "Could not create repo"))
            self._set_busy(False)
            self.refresh()

        self._thread(work)

    @Slot(str)
    def loadPipelines(self, raw):
        try:
            item = json.loads(raw)
        except ValueError:
            return
        slug = item.get("slug", "")
        if item.get("provider") != "GitHub" or not slug:
            self.pipelinesLoaded.emit(json.dumps({"runs": [], "available": False,
                                                  "reason": "GitHub remote required"}))
            return

        def work():
            code, out, err = run(["gh", "run", "list", "--repo", slug, "--limit", "12", "--json",
                                  "databaseId,name,displayTitle,status,conclusion,workflowName,headBranch,event,createdAt,url"],
                                 timeout=20)
            if code == 0:
                try:
                    runs = json.loads(out or "[]")
                except ValueError:
                    runs = []
                self.pipelinesLoaded.emit(json.dumps({"runs": runs, "available": True}))
            else:
                reason = err or "Run gh auth login to load GitHub pipelines"
                self.pipelinesLoaded.emit(json.dumps({"runs": [], "available": False, "reason": reason}))

        self._thread(work)

    def _project_action(self, path, args, success):
        if self.busy:
            return
        self._set_busy(True)

        def work():
            code, out, err = git(Path(path), *args, timeout=120)
            self.message.emit(success if code == 0 else (err or out or "Git command failed"))
            self._set_busy(False)
            self.refresh()

        self._thread(work)

    @Slot(str)
    def fetch(self, path): self._project_action(path, ["fetch", "--all", "--prune"], "Remotes refreshed.")

    @Slot(str)
    def pull(self, path): self._project_action(path, ["pull", "--ff-only"], "Project updated.")

    @Slot(str)
    def push(self, path): self._project_action(path, ["push"], "Commits pushed.")

    @Slot(str)
    def openCode(self, path):
        genesi = shutil.which("genesi-code")
        binary = genesi or shutil.which("code") or shutil.which("codium") \
            or shutil.which("vscodium")
        if not binary:
            self.message.emit("Genesi Code isn't installed — install the "
                              "'genesi-code' package to open projects here.")
            return
        self._touch_recent(path)
        try:
            subprocess.Popen([binary, path], start_new_session=True,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            name = "Genesi Code" if genesi else os.path.basename(binary)
            self.message.emit(f"Opening {Path(path).name} in {name}…")
        except OSError as exc:
            self.message.emit(f"Could not launch the editor: {exc}")

    @Slot(str)
    def openTerminal(self, path):
        choices = [
            ("konsole", ["--workdir", path]), ("alacritty", ["--working-directory", path]),
            ("foot", ["--working-directory", path]), ("kitty", ["--directory", path]),
        ]
        self._touch_recent(path)
        for name, args in choices:
            binary = shutil.which(name)
            if binary:
                subprocess.Popen([binary, *args], start_new_session=True)
                return
        self.message.emit("No supported terminal was found.")

    @Slot(str)
    def openUrl(self, url):
        if url:
            QDesktopServices.openUrl(QUrl(url))

    @Slot(str, str)
    def rerun(self, run_id, slug):
        if not run_id or not slug:
            return

        def work():
            code, out, err = run(["gh", "run", "rerun", run_id, "--repo", slug], timeout=20)
            self.message.emit("Pipeline queued." if code == 0 else (err or out or "Could not rerun pipeline"))

        self._thread(work)

    # ── Forge Canvas ────────────────────────────────────────────────────────
    @staticmethod
    def _wf_key(path):
        return hashlib.md5(str(path).encode("utf-8")).hexdigest()

    @Slot(str, str)
    def saveWorkflow(self, path, graph_raw):
        try:
            graph = json.loads(graph_raw)
        except ValueError:
            self.message.emit("Could not read the workflow.")
            return
        save_json(WORKFLOWS / f"{self._wf_key(path)}.json", graph)
        self.message.emit("Workflow saved.")

    @Slot(str, result=str)
    def loadWorkflow(self, path):
        return json.dumps(load_json(WORKFLOWS / f"{self._wf_key(path)}.json", {}))

    def _workflow_store(self, path):
        target = WORKFLOWS / f"{self._wf_key(path)}.json"
        data = load_json(target, {})
        if "workflows" in data:
            return target, data
        if data.get("nodes"):
            legacy = {"id": "main", "name": "Project setup", "graph": data}
            return target, {"active": "main", "workflows": [legacy]}
        return target, {"active": "", "workflows": []}

    @Slot(str, result=str)
    def listCanvases(self, path):
        _target, data = self._workflow_store(path)
        rows = [{"id": w.get("id", ""), "name": w.get("name", "Automation"),
                 "nodes": len(w.get("graph", {}).get("nodes", []))}
                for w in data.get("workflows", [])]
        return json.dumps({"active": data.get("active", ""), "items": rows})

    @Slot(str, str, result=str)
    def loadCanvas(self, path, canvas_id):
        _target, data = self._workflow_store(path)
        for workflow in data.get("workflows", []):
            if workflow.get("id") == canvas_id:
                return json.dumps(workflow.get("graph", {}))
        return "{}"

    @Slot(str, str, str, str)
    def saveCanvas(self, path, canvas_id, name, graph_raw):
        try:
            graph = json.loads(graph_raw)
        except ValueError:
            self.message.emit("Could not read the automation.")
            return
        target, data = self._workflow_store(path)
        workflows = data.setdefault("workflows", [])
        for workflow in workflows:
            if workflow.get("id") == canvas_id:
                workflow.update({"name": name.strip() or "Automation", "graph": graph,
                                 "updated": int(time.time())})
                break
        else:
            workflows.append({"id": canvas_id, "name": name.strip() or "Automation",
                              "graph": graph, "updated": int(time.time())})
        data["active"] = canvas_id
        save_json(target, data)
        self.message.emit("Automation saved.")

    @Slot(str, str, str, result=str)
    def createCanvas(self, path, name, template):
        target, data = self._workflow_store(path)
        canvas_id = "canvas-" + str(int(time.time() * 1000))
        graph = self._canvas_template(template)
        data.setdefault("workflows", []).append({"id": canvas_id,
                                                  "name": name or "New automation",
                                                  "graph": graph,
                                                  "updated": int(time.time())})
        data["active"] = canvas_id
        save_json(target, data)
        return json.dumps({"id": canvas_id, "graph": graph})

    @Slot(str, str, result=str)
    def duplicateCanvas(self, path, canvas_id):
        target, data = self._workflow_store(path)
        for workflow in data.get("workflows", []):
            if workflow.get("id") == canvas_id:
                new_id = "canvas-" + str(int(time.time() * 1000))
                clone = json.loads(json.dumps(workflow))
                clone.update({"id": new_id, "name": workflow.get("name", "Automation") + " copy",
                              "updated": int(time.time())})
                data["workflows"].append(clone)
                data["active"] = new_id
                save_json(target, data)
                return new_id
        return ""

    @Slot(str, str)
    def deleteCanvas(self, path, canvas_id):
        target, data = self._workflow_store(path)
        data["workflows"] = [w for w in data.get("workflows", []) if w.get("id") != canvas_id]
        data["active"] = data["workflows"][0]["id"] if data["workflows"] else ""
        save_json(target, data)
        self.message.emit("Automation deleted.")

    @staticmethod
    def _canvas_template(name):
        bootstrap_stack = "react-vite"
        if name.startswith("bootstrap:"):
            bootstrap_stack = name.split(":", 1)[1]
            name = "bootstrap"
        templates = {
            "ci": [("event", "When commit", {"event": "push", "branch": "main", "mode": "once"}),
                   ("install", "Install dependencies", {"manager": "auto"}),
                   ("quality", "Code quality", {"tool": "auto"}),
                   ("tests", "Run tests", {"command": ""})],
            "deploy": [("event", "When pull request", {"event": "pull_request", "branch": "main", "mode": "once"}),
                       ("tests", "Tests", {}),
                       ("deploy", "Deploy preview", {"provider": "vercel"})],
            "bootstrap": [("bootstrap", "Project template", {"template": bootstrap_stack}),
                          ("github", "GitHub", {}), ("gitignore", "Smart .gitignore", {}),
                          ("install", "Package manager", {"manager": "npm"}),
                          ("frontend", "Frontend tooling", {"tool": "tailwind"}),
                          ("docker", "Docker", {}), ("quality", "Code quality", {}),
                          ("readme", "README", {})],
        }
        specs = templates.get(name, [])
        nodes, links = [], []
        for index, (kind, title, config) in enumerate(specs):
            nid = f"{kind}-{index}"
            nodes.append({"id": nid, "kind": kind, "title": title, "icon": "zap",
                          "accentKey": "green", "x": 70 + index * 270, "y": 220,
                          "lines": [title], "config": config})
            if index:
                links.append({"from": nodes[index - 1]["id"], "to": nid})
        return {"nodes": nodes, "links": links}

    @Slot(str, str)
    def generateWorkflow(self, path, graph_raw):
        try:
            graph = json.loads(graph_raw)
        except ValueError:
            self.message.emit("Could not read the workflow.")
            return
        p = Path(path)
        nodes = graph.get("nodes", [])
        yaml = graph_to_yaml(p.name, nodes)
        canvas_name = graph.get("name", "automation")
        slug = re.sub(r"[^a-z0-9]+", "-", canvas_name.lower()).strip("-") or "automation"
        target = p / f".github/workflows/genesi-forge-{slug}.yml"
        try:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(yaml, encoding="utf-8")
            self.message.emit(f"Generated {target.relative_to(p)}")
        except OSError as exc:
            self.message.emit(f"Could not write workflow: {exc}")

    @Slot(str, str, result=str)
    def previewWorkflow(self, name, graph_raw):
        try:
            graph = json.loads(graph_raw)
        except ValueError:
            return ""
        return graph_to_yaml(name or "project", graph.get("nodes", []))

    # ── Local workflow runner (real per-node actions) ───────────────────────
    @staticmethod
    def _gitignore_for(kind):
        common = ["", "# secrets & noise", ".env", ".env.local", ".DS_Store", "*.log"]
        web = ["# dependencies / build", "node_modules/", "dist/", "build/", ".next/", ".turbo/", "coverage/"]
        if kind in ("next", "react", "node", "typescript", "javascript", "vue", "angular", "svelte"):
            return "\n".join(web + common) + "\n"
        if kind == "python":
            return "\n".join(["__pycache__/", "*.pyc", ".venv/", "venv/", "dist/", "build/",
                              "*.egg-info/", ".pytest_cache/", ".mypy_cache/"] + common) + "\n"
        if kind == "rust":
            return "\n".join(["/target"] + common) + "\n"
        if kind == "go":
            return "\n".join(["/bin/", "*.exe", "vendor/"] + common) + "\n"
        if kind == "flutter":
            return "\n".join([".dart_tool/", "build/", ".packages", ".flutter-plugins",
                              ".flutter-plugins-dependencies"] + common) + "\n"
        return "\n".join(common) + "\n"

    @staticmethod
    def _dockerfile_for(kind):
        if kind == "python":
            return ("FROM python:3.12-slim\nWORKDIR /app\nCOPY requirements.txt ./\n"
                    "RUN pip install --no-cache-dir -r requirements.txt\nCOPY . .\n"
                    "CMD [\"python\", \"main.py\"]\n")
        if kind == "next":
            return ("FROM node:20-alpine\nWORKDIR /app\nCOPY package*.json ./\nRUN npm ci\n"
                    "COPY . .\nRUN npm run build\nEXPOSE 3000\nCMD [\"npm\", \"start\"]\n")
        if kind in ("react", "vue", "angular", "svelte", "html"):
            return ("FROM node:20-alpine AS build\nWORKDIR /app\nCOPY package*.json ./\nRUN npm ci\n"
                    "COPY . .\nRUN npm run build\n\nFROM nginx:alpine\n"
                    "COPY --from=build /app/dist /usr/share/nginx/html\nEXPOSE 80\n")
        if kind in ("node", "typescript", "javascript"):
            return ("FROM node:20-alpine\nWORKDIR /app\nCOPY package*.json ./\nRUN npm ci --omit=dev\n"
                    "COPY . .\nEXPOSE 3000\nCMD [\"npm\", \"start\"]\n")
        if kind == "go":
            return ("FROM golang:1.22 AS build\nWORKDIR /src\nCOPY . .\nRUN go build -o /app ./...\n\n"
                    "FROM gcr.io/distroless/base\nCOPY --from=build /app /app\nCMD [\"/app\"]\n")
        return ("FROM debian:stable-slim\nWORKDIR /app\nCOPY . .\n"
                "CMD [\"echo\", \"Configure your Dockerfile\"]\n")

    @staticmethod
    def _compose_db():
        return ("services:\n  db:\n    image: postgres:16-alpine\n"
                "    environment:\n      POSTGRES_USER: app\n      POSTGRES_PASSWORD: app\n"
                "      POSTGRES_DB: app\n    ports:\n      - \"5432:5432\"\n"
                "    volumes:\n      - pgdata:/var/lib/postgresql/data\n\nvolumes:\n  pgdata:\n")

    def _log(self, nid, line, level="out"):
        self.workflowLog.emit(json.dumps({"id": nid, "line": line, "level": level}))

    def _exec_cmd(self, nid, cmd, cwd):
        self._log(nid, "$ " + " ".join(cmd), "cmd")
        try:
            proc = subprocess.Popen(cmd, cwd=cwd, text=True, bufsize=1,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    env={**os.environ, "LC_ALL": "C"})
            for line in proc.stdout:
                if self._run_stop.is_set():
                    proc.terminate()
                    return 130
                self._log(nid, line.rstrip("\n"), "out")
            proc.wait(timeout=600)
            return proc.returncode
        except Exception as exc:
            self._log(nid, str(exc), "err")
            return 1

    @staticmethod
    def _write_if_missing(path, content):
        if path.exists():
            return False
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        return True

    def _bootstrap_project(self, nid, path, template):
        p = Path(path)
        name = p.name.replace(" ", "-").lower()
        files = {}
        if template == "react-vite":
            files = {
                "package.json": json.dumps({"name": name, "private": True, "version": "0.1.0",
                                             "type": "module", "scripts": {"dev": "vite", "build": "vite build", "test": "vitest"},
                                             "dependencies": {"@vitejs/plugin-react": "latest", "vite": "latest", "react": "latest", "react-dom": "latest"}}, indent=2) + "\n",
                "index.html": '<div id="root"></div><script type="module" src="/src/main.jsx"></script>\n',
                "src/main.jsx": 'import React from "react";\nimport { createRoot } from "react-dom/client";\nimport "./style.css";\n\nfunction App() { return <main><h1>Built with Genesi Forge</h1></main>; }\ncreateRoot(document.getElementById("root")).render(<App />);\n',
                "src/style.css": ':root { font-family: system-ui; color-scheme: dark; }\nbody { margin: 0; padding: 3rem; }\n',
                "vite.config.js": 'import { defineConfig } from "vite";\nimport react from "@vitejs/plugin-react";\nexport default defineConfig({ plugins: [react()] });\n',
            }
        elif template == "next":
            files = {"package.json": json.dumps({"name": name, "private": True,
                                                   "scripts": {"dev": "next dev", "build": "next build", "start": "next start"},
                                                   "dependencies": {"next": "latest", "react": "latest", "react-dom": "latest"}}, indent=2) + "\n",
                     "app/page.jsx": 'export default function Home() { return <main><h1>Built with Genesi Forge</h1></main>; }\n',
                     "app/layout.jsx": 'export default function Layout({ children }) { return <html><body>{children}</body></html>; }\n'}
        elif template == "electron":
            files = {"package.json": json.dumps({"name": name, "main": "main.js", "scripts": {"start": "electron ."},
                                                   "devDependencies": {"electron": "latest"}}, indent=2) + "\n",
                     "main.js": 'const { app, BrowserWindow } = require("electron");\napp.whenReady().then(() => new BrowserWindow({ width: 1100, height: 720 }).loadFile("index.html"));\n',
                     "index.html": "<h1>Built with Genesi Forge</h1>\n"}
        elif template == "react-native":
            files = {"package.json": json.dumps({"name": name, "private": True, "scripts": {"start": "expo start"},
                                                   "dependencies": {"expo": "latest", "react": "latest", "react-native": "latest"}}, indent=2) + "\n",
                     "App.js": 'import { Text, View } from "react-native";\nexport default function App() { return <View><Text>Built with Genesi Forge</Text></View>; }\n'}
        elif template == "rust":
            files = {"Cargo.toml": f'[package]\nname = "{name}"\nversion = "0.1.0"\nedition = "2021"\n',
                     "src/main.rs": 'fn main() { println!("Built with Genesi Forge"); }\n'}
        elif template == "go":
            files = {"go.mod": f"module {name}\n\ngo 1.22\n", "main.go": 'package main\n\nimport "fmt"\nfunc main() { fmt.Println("Built with Genesi Forge") }\n'}
        elif template == "spring":
            files = {"pom.xml": '<project xmlns="http://maven.apache.org/POM/4.0.0"><modelVersion>4.0.0</modelVersion><parent><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-parent</artifactId><version>3.3.0</version></parent><groupId>org.genesi</groupId><artifactId>' + name + '</artifactId><version>0.1.0</version><properties><java.version>21</java.version></properties><dependencies><dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-web</artifactId></dependency><dependency><groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-test</artifactId><scope>test</scope></dependency></dependencies><build><plugins><plugin><groupId>org.springframework.boot</groupId><artifactId>spring-boot-maven-plugin</artifactId></plugin></plugins></build></project>\n',
                     "src/main/java/org/genesi/Application.java": 'package org.genesi;\nimport org.springframework.boot.SpringApplication;\nimport org.springframework.boot.autoconfigure.SpringBootApplication;\n@SpringBootApplication\npublic class Application { public static void main(String[] args) { SpringApplication.run(Application.class, args); } }\n'}
        else:
            files = {"pyproject.toml": f'[project]\nname = "{name}"\nversion = "0.1.0"\nrequires-python = ">=3.11"\n',
                     "src/main.py": 'def main():\n    print("Built with Genesi Forge")\n\nif __name__ == "__main__":\n    main()\n'}
        created = 0
        for relative, content in files.items():
            if self._write_if_missing(p / relative, content):
                self._log(nid, "created " + relative, "ok")
                created += 1
        self._log(nid, f"{template} scaffold ready ({created} files created)", "ok")
        return True

    def _exec_node(self, node, path):
        """Perform a node's real action in the project dir. Returns True on ok."""
        kind = node.get("kind", "")
        nid = node.get("id", "")
        p = Path(path)
        stack = detect_stack(path)
        config = node.get("config", {})

        def wrote(fname):
            self._log(nid, "created " + fname, "ok")
            return True

        if kind in ("start", "complete"):
            self._log(nid, "Project ready to ship 🎉" if kind == "complete" else "Ready", "ok")
            return True

        if kind == "event":
            self._log(nid, "event trigger is generated into CI/CD", "ok")
            return True

        if kind in ("bootstrap", "template"):
            return self._bootstrap_project(nid, path, config.get("template", "react-vite"))

        if kind == "github":
            if not (p / ".git").exists():
                self._exec_cmd(nid, ["git", "init"], path)
            code, _out, _err = git(p, "rev-parse", "--verify", "HEAD")
            if code != 0:
                self._exec_cmd(nid, ["git", "add", "-A"], path)
                c = self._exec_cmd(nid, ["git", "commit", "-m", "Initial commit"], path)
                self._log(nid, "initial commit created" if c == 0 else "nothing to commit", "ok")
            else:
                self._log(nid, "repository already initialized", "ok")
            return True

        if kind == "gitignore":
            f = p / ".gitignore"
            if f.exists():
                self._log(nid, ".gitignore already exists — left untouched", "ok")
                return True
            f.write_text(self._gitignore_for(stack["kind"]), encoding="utf-8")
            return wrote(".gitignore")

        if kind == "env":
            ex = p / ".env.example"
            if not ex.exists():
                values = [v.strip() for v in config.get("variables", "APP_ENV=development").split(",") if "=" in v]
                ex.write_text("# Copy to .env and fill in\n" + "\n".join(values) + "\n", encoding="utf-8")
                wrote(".env.example")
            gi = p / ".gitignore"
            body = gi.read_text(encoding="utf-8") if gi.exists() else ""
            if ".env" not in body:
                with gi.open("a", encoding="utf-8") as fh:
                    fh.write("\n.env\n")
                self._log(nid, "added .env to .gitignore", "ok")
            return True

        if kind == "install":
            if (p / "package.json").exists():
                manager = config.get("manager", "auto")
                if manager == "auto":
                    manager = "pnpm" if (p / "pnpm-lock.yaml").exists() else "yarn" if (p / "yarn.lock").exists() else "bun" if (p / "bun.lockb").exists() else "npm"
                cmd = [manager, "install"]
            elif (p / "requirements.txt").exists():
                cmd = ["pip", "install", "-r", "requirements.txt"]
            elif (p / "pyproject.toml").exists():
                cmd = ["pip", "install", "-e", "."]
            elif (p / "Cargo.toml").exists():
                cmd = ["cargo", "fetch"]
            else:
                self._log(nid, "no dependency manifest found — skipped", "ok")
                return True
            return self._exec_cmd(nid, cmd, path) == 0

        if kind == "script":
            command = config.get("command", "").strip()
            if command:
                return self._exec_cmd(nid, ["/bin/sh", "-lc", command], path) == 0
            if (p / "package.json").exists():
                self._exec_cmd(nid, ["npm", "test", "--if-present"], path)
                return self._exec_cmd(nid, ["npm", "run", "build", "--if-present"], path) == 0
            self._log(nid, "no npm scripts — skipped", "ok")
            return True

        if kind == "git_automation":
            base = config.get("base", "staging")
            branch = config.get("branch", "feature/new-feature")
            for args in (["checkout", base], ["pull", "--ff-only"], ["checkout", "-b", branch]):
                code, out, err = git(p, *args, timeout=60)
                self._log(nid, out or err or "git " + " ".join(args), "ok" if code == 0 else "err")
                if code != 0:
                    return False
            return True

        if kind == "api":
            target = p / "openapi.yaml"
            content = ("openapi: 3.1.0\ninfo:\n  title: " + p.name + " API\n  version: 1.0.0\n"
                       "paths:\n  /health:\n    get:\n      responses:\n        '200':\n          description: Healthy\n")
            return wrote("openapi.yaml") if self._write_if_missing(target, content) else True

        if kind == "backend":
            framework = config.get("framework", "fastapi")
            if framework == "express":
                target, content = p / "server.js", 'const express = require("express");\nconst app = express();\napp.get("/health", (_, res) => res.json({ ok: true }));\napp.listen(process.env.PORT || 3000);\n'
            else:
                target, content = p / "app.py", 'from fastapi import FastAPI\napp = FastAPI()\n@app.get("/health")\ndef health(): return {"ok": True}\n'
            return wrote(target.name) if self._write_if_missing(target, content) else True

        if kind == "quality":
            tool = config.get("tool", "biome")
            target = p / ("biome.json" if tool == "biome" else ".eslintrc.json")
            content = '{ "formatter": { "enabled": true }, "linter": { "enabled": true } }\n' if tool == "biome" else '{ "extends": ["eslint:recommended"] }\n'
            return wrote(target.name) if self._write_if_missing(target, content) else True

        if kind == "frontend":
            tool = config.get("tool", "tailwind")
            if tool == "shadcn":
                target = p / "components.json"
                content = json.dumps({"$schema": "https://ui.shadcn.com/schema.json", "style": "new-york",
                                      "rsc": stack["kind"] == "next", "tsx": True,
                                      "aliases": {"components": "@/components", "utils": "@/lib/utils"}}, indent=2) + "\n"
            else:
                target = p / "tailwind.config.js"
                content = "/** @type {import('tailwindcss').Config} */\nexport default { content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}', './app/**/*.{js,ts,jsx,tsx}'], theme: { extend: {} }, plugins: [] };\n"
            return wrote(target.name) if self._write_if_missing(target, content) else True

        if kind == "tests":
            command = config.get("command", "").strip()
            if command:
                return self._exec_cmd(nid, ["/bin/sh", "-lc", command], path) == 0
            if (p / "package.json").exists():
                return self._exec_cmd(nid, ["npm", "test", "--if-present"], path) == 0
            if (p / "Cargo.toml").exists():
                return self._exec_cmd(nid, ["cargo", "test"], path) == 0
            if (p / "go.mod").exists():
                return self._exec_cmd(nid, ["go", "test", "./..."], path) == 0
            return self._exec_cmd(nid, ["python", "-m", "pytest"], path) == 0

        if kind == "deploy":
            provider = config.get("provider", "vercel")
            if provider == "railway":
                target, content = p / "railway.toml", '[build]\nbuilder = "NIXPACKS"\n[deploy]\nrestartPolicyType = "ON_FAILURE"\n'
            elif provider == "render":
                target, content = p / "render.yaml", "services:\n  - type: web\n    name: " + p.name + "\n    runtime: docker\n"
            else:
                output = ".next" if stack["kind"] == "next" else "dist"
                framework = "vite" if stack["kind"] == "react" else stack["kind"]
                target, content = p / "vercel.json", json.dumps({"framework": framework, "outputDirectory": output}, indent=2) + "\n"
            return wrote(target.name) if self._write_if_missing(target, content) else True

        if kind == "redis":
            target = p / "docker-compose.redis.yml"
            content = "services:\n  redis:\n    image: redis:7-alpine\n    ports:\n      - '6379:6379'\n    volumes:\n      - redis-data:/data\nvolumes:\n  redis-data:\n"
            return wrote(target.name) if self._write_if_missing(target, content) else True

        if kind == "webhook":
            target = p / ".forge/webhooks.json"
            content = json.dumps({"url": config.get("url", ""), "events": ["workflow.completed"]}, indent=2) + "\n"
            return wrote(str(target.relative_to(p))) if self._write_if_missing(target, content) else True

        if kind == "ci":
            target = p / ".github/workflows/ci.yml"
            content = graph_to_yaml(p.name, [node, {"kind": "install"}, {"kind": "tests"}])
            return wrote(".github/workflows/ci.yml") if self._write_if_missing(target, content) else True

        if kind == "docker":
            f = p / "Dockerfile"
            if f.exists():
                self._log(nid, "Dockerfile already exists", "ok")
            else:
                f.write_text(self._dockerfile_for(stack["kind"]), encoding="utf-8")
                wrote("Dockerfile")
            return True

        if kind == "database":
            f = p / "docker-compose.yml"
            if f.exists():
                self._log(nid, "docker-compose.yml already exists", "ok")
                return True
            f.write_text(self._compose_db(), encoding="utf-8")
            return wrote("docker-compose.yml")

        if kind == "readme":
            f = p / "README.md"
            if f.exists():
                self._log(nid, "README.md already exists", "ok")
                return True
            f.write_text(f"# {p.name}\n\n> {stack['label']} project — scaffolded by Genesi Forge.\n\n"
                         "## Getting started\n\n```bash\n# install dependencies\n# run the project\n```\n",
                         encoding="utf-8")
            return wrote("README.md")

        if kind == "license":
            f = p / "LICENSE"
            if f.exists():
                self._log(nid, "LICENSE already exists", "ok")
                return True
            _, author, _ = git(p, "config", "user.name")
            year = time.strftime("%Y")
            f.write_text(
                f"MIT License\n\nCopyright (c) {year} {author or 'The Authors'}\n\n"
                "Permission is hereby granted, free of charge, to any person obtaining a copy\n"
                "of this software and associated documentation files (the \"Software\"), to deal\n"
                "in the Software without restriction, including without limitation the rights\n"
                "to use, copy, modify, merge, publish, distribute, sublicense, and/or sell\n"
                "copies of the Software, and to permit persons to whom the Software is\n"
                "furnished to do so, subject to the following conditions:\n\n"
                "The above copyright notice and this permission notice shall be included in all\n"
                "copies or substantial portions of the Software.\n\n"
                "THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND.\n",
                encoding="utf-8")
            return wrote("LICENSE (MIT)")

        if kind == "contributing":
            f = p / "CONTRIBUTING.md"
            if f.exists():
                self._log(nid, "CONTRIBUTING.md already exists", "ok")
                return True
            f.write_text("# Contributing\n\nThanks for helping out!\n\n"
                         "1. Fork & branch from `main`\n2. Commit with clear messages\n"
                         "3. Open a pull request\n", encoding="utf-8")
            return wrote("CONTRIBUTING.md")

        self._log(nid, "no local action for this node — marked configured", "ok")
        return True

    def _event_snapshot(self, node, path):
        """Capture event state without treating the current state as a trigger."""
        config = node.get("config", {})
        event = config.get("event", "push")
        branch = config.get("branch", "main") or "main"
        if event == "branch_created":
            code, out, _ = git(Path(path), "for-each-ref", "--format=%(refname:short)",
                               "refs/heads")
            return set(out.splitlines()) if code == 0 else set()
        if event == "pull_request":
            args = ["gh", "pr", "list", "--state", "open", "--json", "number"]
            if branch not in ("", "*"):
                args += ["--base", branch]
            code, out, _ = run(args, cwd=path, timeout=15)
            if code != 0:
                return set()
            try:
                return {str(item.get("number")) for item in json.loads(out)}
            except ValueError:
                return set()
        if event == "schedule":
            return time.monotonic()
        ref = "HEAD" if branch in ("", "*") else f"refs/heads/{branch}"
        code, out, _ = git(Path(path), "rev-parse", "--verify", ref)
        return out if code == 0 else ""

    def _event_changed(self, node, path, previous):
        config = node.get("config", {})
        event = config.get("event", "push")
        current = self._event_snapshot(node, path)
        if event == "branch_created":
            pattern = config.get("branch", "*") or "*"
            created = sorted(name for name in current - previous
                             if fnmatch.fnmatch(name, pattern))
            return bool(created), current, ("branch created: " + ", ".join(created))
        if event == "pull_request":
            created = sorted(current - previous)
            return bool(created), current, ("new pull request: #" + ", #".join(created))
        if event == "schedule":
            try:
                minutes = max(0.1, float(config.get("interval", 60)))
            except (TypeError, ValueError):
                minutes = 60
            fired = current - previous >= minutes * 60
            return fired, (current if fired else previous), "scheduled interval reached"
        changed = bool(previous and current and current != previous)
        return changed, current, "new commit detected"

    @Slot(str, str)
    def runWorkflow(self, path, graph_raw):
        if self._running:
            return
        try:
            graph = json.loads(graph_raw)
            nodes = graph.get("nodes", [])
            links = graph.get("links", [])
        except ValueError:
            self.message.emit("Could not read the workflow.")
            self.workflowDone.emit(False)
            return
        self._running = True
        self._run_stop.clear()

        # Execute in dependency order, independent of visual array order.
        by_id = {node.get("id"): node for node in nodes}
        indegree = {nid: 0 for nid in by_id}
        outgoing = {nid: [] for nid in by_id}
        for link in links:
            source, target = link.get("from"), link.get("to")
            if source in by_id and target in by_id:
                outgoing[source].append(target)
                indegree[target] += 1
        queue = [nid for nid in by_id if indegree[nid] == 0]
        ordered = []
        while queue:
            nid = queue.pop(0)
            ordered.append(by_id[nid])
            for target in outgoing[nid]:
                indegree[target] -= 1
                if indegree[target] == 0:
                    queue.append(target)
        if len(ordered) != len(nodes):
            self.message.emit("Workflow contains a cycle. Remove one circular link.")
            self._running = False
            self.workflowDone.emit(False)
            return

        def execute(sequence):
            ok = True
            for node in sequence:
                if self._run_stop.is_set():
                    return False
                nid = node.get("id", "")
                self.workflowStep.emit(json.dumps({"id": nid, "state": "running"}))
                try:
                    good = self._exec_node(node, path)
                except Exception as exc:
                    self._log(nid, str(exc), "err")
                    good = False
                self.workflowStep.emit(json.dumps({"id": nid, "state": "done" if good else "failed"}))
                if not good:
                    return False
            return ok

        event_nodes = [node for node in ordered if node.get("kind") == "event"]

        def work():
            ok = True
            if not event_nodes:
                ok = execute(ordered)
            else:
                states = {}
                for event_node in event_nodes:
                    nid = event_node.get("id", "")
                    states[nid] = {
                        "snapshot": self._event_snapshot(event_node, path),
                        "active": True,
                        "checked": 0.0,
                    }
                    self.workflowStep.emit(json.dumps({"id": nid, "state": "waiting"}))
                    self._log(nid, "listening for a new event", "out")

                while not self._run_stop.is_set() and any(s["active"] for s in states.values()):
                    now = time.monotonic()
                    for event_node in event_nodes:
                        nid = event_node.get("id", "")
                        state = states[nid]
                        if not state["active"]:
                            continue
                        event = event_node.get("config", {}).get("event", "push")
                        poll_seconds = 10 if event == "pull_request" else 1
                        if now - state["checked"] < poll_seconds:
                            continue
                        state["checked"] = now
                        fired, snapshot, detail = self._event_changed(
                            event_node, path, state["snapshot"])
                        state["snapshot"] = snapshot
                        if not fired:
                            continue

                        self.workflowStep.emit(json.dumps({"id": nid, "state": "running"}))
                        self._log(nid, detail, "ok")
                        reachable = set()
                        pending = list(outgoing.get(nid, []))
                        while pending:
                            target = pending.pop(0)
                            if target in reachable:
                                continue
                            reachable.add(target)
                            pending.extend(outgoing.get(target, []))
                        sequence = [node for node in ordered
                                    if node.get("id") in reachable
                                    and node.get("kind") != "event"]
                        if not execute(sequence):
                            ok = False
                            state["active"] = False
                            break
                        if event_node.get("config", {}).get("mode", "once") == "always":
                            self.workflowStep.emit(json.dumps({"id": nid, "state": "waiting"}))
                            self._log(nid, "listening for the next event", "out")
                        else:
                            state["active"] = False
                            self.workflowStep.emit(json.dumps({"id": nid, "state": "done"}))
                    if not ok:
                        break
                    self._run_stop.wait(0.2)

                if self._run_stop.is_set():
                    ok = False

            self._running = False
            self.workflowDone.emit(ok)
            self.message.emit("Workflow finished." if ok else "Workflow stopped or failed.")

        self._thread(work)

    @Slot()
    def stopWorkflow(self):
        self._run_stop.set()

    # ── Git client (synchronous — local git is fast) ────────────────────────
    @Slot(str, result=str)
    def gitStatusList(self, path):
        _, out, _ = git(Path(path), "status", "--porcelain=v1", "--untracked-files=all", strip=False)
        rows = []
        for line in (out.splitlines() if out else []):
            if len(line) < 4:
                continue
            x, y, fp = line[0], line[1], line[3:]
            if " -> " in fp:
                fp = fp.split(" -> ", 1)[1]
            rows.append({"file": fp, "x": x, "y": y,
                         "staged": x not in (" ", "?"),
                         "unstaged": y != " ",
                         "untracked": x == "?"})
        return json.dumps(rows)

    @Slot(str, str, bool, result=str)
    def gitDiff(self, path, file, staged):
        p = Path(path)
        if staged:
            _, out, _ = git(p, "diff", "--cached", "--no-color", "--", file)
        else:
            _, out, _ = git(p, "diff", "--no-color", "--", file)
            if not out:  # untracked file — synthesize an all-added diff
                _, out, _ = git(p, "diff", "--no-color", "--no-index", "--", "/dev/null", file)
        return out[:120000]

    @Slot(str, int, result=str)
    def gitLog(self, path, limit):
        _, out, _ = git(Path(path), "log", f"-{limit}", "--format=%h%x1f%an%x1f%ar%x1f%s")
        rows = []
        for line in (out.splitlines() if out else []):
            parts = line.split("\x1f")
            if len(parts) == 4:
                rows.append({"hash": parts[0], "author": parts[1], "ago": parts[2], "subject": parts[3]})
        return json.dumps(rows)

    @Slot(str, result=str)
    def gitBranches(self, path):
        _, out, _ = git(Path(path), "for-each-ref", "refs/heads",
                        "--format=%(refname:short)%09%(HEAD)%09%(upstream:short)")
        rows = []
        for line in (out.splitlines() if out else []):
            parts = line.split("\t")
            if parts and parts[0]:
                rows.append({"name": parts[0],
                             "current": len(parts) > 1 and parts[1] == "*",
                             "upstream": parts[2] if len(parts) > 2 else ""})
        return json.dumps(rows)

    @Slot(str, result=str)
    def gitStashList(self, path):
        _, out, _ = git(Path(path), "stash", "list", "--format=%gd%x1f%gs")
        rows = []
        for line in (out.splitlines() if out else []):
            parts = line.split("\x1f")
            if len(parts) == 2:
                rows.append({"ref": parts[0], "subject": parts[1]})
        return json.dumps(rows)

    @Slot(str, result=str)
    def gitTags(self, path):
        _, out, _ = git(Path(path), "tag", "--sort=-creatordate")
        return json.dumps(out.splitlines()[:40] if out else [])

    @Slot(str, result=str)
    def gitRemotes(self, path):
        _, out, _ = git(Path(path), "remote", "-v")
        rows, seen = [], set()
        for line in (out.splitlines() if out else []):
            parts = line.split()
            if len(parts) >= 2 and parts[0] not in seen:
                seen.add(parts[0])
                rows.append({"name": parts[0], "url": parts[1]})
        return json.dumps(rows)

    @Slot(str, result=str)
    def gitFiles(self, path):
        _, out, _ = git(Path(path), "ls-files")
        return json.dumps(out.splitlines()[:500] if out else [])

    @Slot(str, int, result=str)
    def gitGraph(self, path, limit):
        # All branches, topo-ordered, with parents + ref decorations — enough to
        # lay out a lane graph on the QML side.
        _, out, _ = git(Path(path), "log", "--all", "--topo-order", f"-{limit}",
                        "--pretty=format:%H%x1f%h%x1f%P%x1f%an%x1f%ar%x1f%D%x1f%s")
        rows = []
        for line in (out.splitlines() if out else []):
            parts = line.split("\x1f")
            if len(parts) == 7:
                full, short, parents, an, ar, refs, subj = parts
                rows.append({"hash": full, "short": short,
                             "parents": parents.split() if parents else [],
                             "author": an, "ago": ar,
                             "refs": [r.strip() for r in refs.split(",") if r.strip()],
                             "subject": subj})
        return json.dumps(rows)

    @Slot(str, str, str, result=str)
    def gitCompare(self, path, a, b):
        code, out, err = git(Path(path), "diff", "--stat", f"{a}...{b}")
        return out if code == 0 else (err or "Could not compare")

    # ── Git mutations ───────────────────────────────────────────────────────
    @Slot(str, str)
    def stageFile(self, path, file):
        git(Path(path), "add", "-A", "--", file)

    @Slot(str, str)
    def unstageFile(self, path, file):
        git(Path(path), "restore", "--staged", "--", file)

    @Slot(str, str)
    def discardFile(self, path, file):
        code, _out, err = git(Path(path), "restore", "--", file)
        if code != 0:
            self.message.emit(err or "Could not discard changes")

    @Slot(str, str, str, result=str)
    def commitFiles(self, path, msg, files_json):
        if not msg.strip():
            return "Commit message required"
        try:
            files = json.loads(files_json)
        except ValueError:
            files = []
        p = Path(path)
        if files:
            git(p, "add", "-A", "--", *files)
            code, out, err = git(p, "commit", "-m", msg, "--", *files, timeout=30)
        else:
            code, out, err = git(p, "commit", "-m", msg, timeout=30)
        if code == 0:
            self.message.emit("Changes committed.")
            self.refresh()
            return ""
        return err or out or "Commit failed"

    @Slot(str, str)
    def checkout(self, path, branch):
        code, out, err = git(Path(path), "checkout", branch, timeout=30)
        self.message.emit(f"Switched to {branch}." if code == 0 else (err or out))
        self.refresh()

    @Slot(str, str)
    def createBranch(self, path, name):
        code, out, err = git(Path(path), "checkout", "-b", name, timeout=30)
        self.message.emit(f"Branch {name} created." if code == 0 else (err or out))
        self.refresh()

    @Slot(str, str)
    def deleteBranch(self, path, name):
        code, out, err = git(Path(path), "branch", "-D", name)
        self.message.emit(f"Branch {name} deleted." if code == 0 else (err or out))

    @Slot(str)
    def stashSave(self, path):
        code, out, err = git(Path(path), "stash", "push", "-u", "-m", "Forge stash", timeout=30)
        self.message.emit("Changes stashed." if code == 0 else (err or out))
        self.refresh()

    @Slot(str, str)
    def stashPop(self, path, ref):
        code, out, err = git(Path(path), "stash", "pop", ref, timeout=30)
        self.message.emit("Stash applied." if code == 0 else (err or out))
        self.refresh()

    @Slot(str, str)
    def stashDrop(self, path, ref):
        code, out, err = git(Path(path), "stash", "drop", ref)
        self.message.emit("Stash dropped." if code == 0 else (err or out))

    @Slot(str, str)
    def createTag(self, path, name):
        code, out, err = git(Path(path), "tag", name)
        self.message.emit(f"Tag {name} created." if code == 0 else (err or out))

    @Slot(str)
    def loadPRs(self, slug):
        if not slug:
            self.prsLoaded.emit("[]")
            return

        def work():
            code, out, _err = run(["gh", "pr", "list", "--repo", slug, "--json",
                                   "number,title,headRefName,state,url", "--limit", "15"], timeout=20)
            self.prsLoaded.emit(out if code == 0 and out else "[]")

        self._thread(work)

    # ── Embedded console (line-streamed; not a PTY — TUI apps won't run) ────
    @Slot(str, str)
    def runCommand(self, path, cmd):
        def work():
            try:
                proc = subprocess.Popen(cmd, shell=True, cwd=path, text=True,
                                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                for line in proc.stdout:
                    self.consoleOut.emit(line.rstrip("\n"))
                proc.wait(timeout=300)
                self.consoleDone.emit(proc.returncode)
            except Exception as exc:
                self.consoleOut.emit(str(exc))
                self.consoleDone.emit(1)

        self._thread(work)

    @Slot(str)
    def copyText(self, text):
        QGuiApplication.clipboard().setText(text)
        self.message.emit("Copied to clipboard.")

    # ── Templates / maintenance ─────────────────────────────────────────────
    @Slot(str, str)
    def cloneTemplate(self, url, dest_parent):
        if self.busy:
            return
        self._set_busy(True)

        def work():
            code, out, err = run(["git", "clone", "--depth", "1", url], cwd=dest_parent, timeout=180)
            self.message.emit("Template cloned." if code == 0 else (err or out or "Clone failed"))
            self._set_busy(False)
            self.refresh()

        self._thread(work)

    @Slot(str)
    def clearData(self, what):
        if what == "recents":
            save_json(RECENT, {})
            self.message.emit("Recent history cleared.")
        elif what == "stars":
            save_json(STARS, [])
            self.message.emit("Stars cleared.")
        elif what == "imports":
            save_json(IMPORTS, [])
            self.message.emit("Imported projects cleared.")
        self.refresh()


def main():
    os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Fusion")
    os.environ.setdefault("QT_QPA_PLATFORMTHEME", "kde")
    app = QGuiApplication(sys.argv)
    app.setApplicationName("Genesi Forge")
    app.setApplicationDisplayName("Genesi Forge")
    app.setOrganizationName("Genesi OS")
    app.setDesktopFileName("org.genesi.forge")
    app.setWindowIcon(QIcon.fromTheme("genesi-forge"))
    engine = QQmlApplicationEngine()
    backend = Backend()
    engine.rootContext().setContextProperty("backend", backend)
    here = Path(__file__).resolve().parent
    engine.load(QUrl.fromLocalFile(str(here / "Main.qml")))
    if not engine.rootObjects():
        return 1
    backend.refresh()
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
