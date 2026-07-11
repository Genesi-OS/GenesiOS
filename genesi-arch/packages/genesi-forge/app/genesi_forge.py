#!/usr/bin/env python3
"""Backend for Genesi Forge — the local project hub, Git dashboard and Forge
Canvas (workflow builder). It scans the user's Git projects, detects each
project's stack, tracks stars / recents / imports, talks to GitHub through the
`gh` CLI, and turns a Forge Canvas graph into a real GitHub Actions workflow."""
import hashlib
import json
import os
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


def run(args, cwd=None, timeout=10):
    try:
        proc = subprocess.run(args, cwd=cwd, text=True, capture_output=True,
                              timeout=timeout, env={**os.environ, "LC_ALL": "C"})
        return proc.returncode, proc.stdout.strip(), proc.stderr.strip()
    except (OSError, subprocess.TimeoutExpired) as exc:
        return 127, "", str(exc)


def git(path, *args, timeout=8):
    return run(["git", "-C", str(path), *args], timeout=timeout)


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
    _, status, _ = git(path, "status", "--porcelain=v1", "--untracked-files=normal")
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
    lines = [
        f"# Generated by Genesi Forge — Forge Canvas workflow for {project_name}",
        "name: Genesi Forge Pipeline",
        "",
        "on:",
        "  push:",
        "    branches: [ main ]",
        "  workflow_dispatch:",
        "",
        "jobs:",
        "  forge:",
        "    runs-on: ubuntu-latest",
        "    steps:",
        "      - name: Checkout",
        "        uses: actions/checkout@v4",
    ]
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
        lines += [
            "      - name: Run script",
            "        run: npm test --if-present && npm run build --if-present",
        ]
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
        binary = shutil.which("genesi-code") or shutil.which("code")
        if not binary:
            self.message.emit("Genesi Code is not installed.")
            return
        self._touch_recent(path)
        subprocess.Popen([binary, path], start_new_session=True)

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
        target = p / ".github/workflows/genesi-forge.yml"
        try:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(yaml, encoding="utf-8")
            self.message.emit("Generated .github/workflows/genesi-forge.yml")
        except OSError as exc:
            self.message.emit(f"Could not write workflow: {exc}")

    @Slot(str, str, result=str)
    def previewWorkflow(self, name, graph_raw):
        try:
            graph = json.loads(graph_raw)
        except ValueError:
            return ""
        return graph_to_yaml(name or "project", graph.get("nodes", []))

    # ── Local workflow runner ───────────────────────────────────────────────
    @staticmethod
    def _step_command(kind, path):
        """Map a node kind to a real local command (or None for a config-only
        step that just resolves instantly). Runs in the project directory."""
        p = Path(path)
        if kind == "install":
            if (p / "package.json").exists():
                return ["npm", "install"]
            if (p / "requirements.txt").exists():
                return ["pip", "install", "-r", "requirements.txt"]
            if (p / "Cargo.toml").exists():
                return ["cargo", "fetch"]
            return None
        if kind == "script":
            if (p / "package.json").exists():
                return ["npm", "run", "build", "--if-present"]
            return None
        if kind == "docker":
            if (p / "Dockerfile").exists():
                return ["docker", "build", "-t", f"{p.name}:forge", "."]
            return None
        return None  # config-only nodes (github, env, readme, …) resolve instantly

    @Slot(str, str)
    def runWorkflow(self, path, graph_raw):
        if self._running:
            return
        try:
            nodes = json.loads(graph_raw).get("nodes", [])
        except ValueError:
            self.message.emit("Could not read the workflow.")
            return
        self._running = True
        self._run_stop.clear()

        def work():
            ok = True
            for node in nodes:
                if self._run_stop.is_set():
                    ok = False
                    break
                nid = node.get("id", "")
                self.workflowStep.emit(json.dumps({"id": nid, "state": "running"}))
                cmd = self._step_command(node.get("kind", ""), path)
                if cmd is None:
                    time.sleep(0.35)  # config step — brief beat so the UI reads
                    self.workflowStep.emit(json.dumps({"id": nid, "state": "done"}))
                    continue
                code, out, err = run(cmd, cwd=path, timeout=600)
                if code == 0:
                    self.workflowStep.emit(json.dumps({"id": nid, "state": "done"}))
                else:
                    self.workflowStep.emit(json.dumps({"id": nid, "state": "failed"}))
                    self.message.emit(f"{node.get('title', 'Step')} failed: {(err or out or '')[:160]}")
                    ok = False
                    break
            self._running = False
            self.workflowDone.emit(ok)
            self.message.emit("Workflow finished." if ok else "Workflow stopped.")

        self._thread(work)

    @Slot()
    def stopWorkflow(self):
        self._run_stop.set()

    # ── Git client (synchronous — local git is fast) ────────────────────────
    @Slot(str, result=str)
    def gitStatusList(self, path):
        _, out, _ = git(Path(path), "status", "--porcelain=v1", "--untracked-files=all")
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
