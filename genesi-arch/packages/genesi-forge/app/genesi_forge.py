#!/usr/bin/env python3
"""Backend for Genesi Forge, the local Git and delivery dashboard."""
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
CACHE = HOME / ".cache/genesi-forge/repos.json"
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
    roots = [HOME]
    for root in roots:
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
    try:
        if CACHE.exists():
            found.update(p for p in json.loads(CACHE.read_text()) if Path(p, ".git").exists())
    except (OSError, ValueError):
        pass
    try:
        CACHE.parent.mkdir(parents=True, exist_ok=True)
        CACHE.write_text(json.dumps(sorted(found)), encoding="utf-8")
    except OSError:
        pass
    return sorted(found)


def repo_summary(path_text):
    path = Path(path_text)
    _, branch, _ = git(path, "branch", "--show-current")
    if not branch:
        _, branch, _ = git(path, "rev-parse", "--short", "HEAD")
    _, status, _ = git(path, "status", "--porcelain=v1", "--untracked-files=normal")
    lines = status.splitlines() if status else []
    staged = sum(1 for line in lines if line and line[0] not in (" ", "?"))
    modified = sum(1 for line in lines if not line.startswith("??") and len(line) > 1 and line[1] != " ")
    untracked = sum(1 for line in lines if line.startswith("??"))
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
    integrations = integration_rows(path)
    return {
        "id": str(path), "name": path.name, "path": str(path), "branch": branch or "detached",
        "provider": provider, "slug": slug, "remote": remote, "web": web,
        "changed": len(lines), "staged": staged, "modified": modified,
        "untracked": untracked, "ahead": ahead, "behind": behind,
        "lastHash": last_hash, "lastSubject": last_subject, "lastTime": last_time,
        "integrations": integrations, "pipelineCount": sum(1 for i in integrations if "Actions" in i["name"] or "CI" in i["name"]),
        "deployCount": sum(1 for i in integrations if i["name"] in {"Vercel", "Netlify", "Render", "Railway", "Fly.io"}),
    }


class Backend(QObject):
    projectsLoaded = Signal(str)
    pipelinesLoaded = Signal(str)
    busyChanged = Signal(bool)
    message = Signal(str)

    def __init__(self):
        super().__init__()
        self.busy = False

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
                projects = [repo_summary(path) for path in discover_repos()]
                projects.sort(key=lambda item: (item["changed"] == 0, -item["lastTime"], item["name"].lower()))
                self.projectsLoaded.emit(json.dumps({"projects": projects, "scannedAt": int(time.time())}))
            except Exception as exc:
                self.message.emit(f"Could not scan projects: {exc}")
                self.projectsLoaded.emit('{"projects":[]}')
            finally:
                self._set_busy(False)
        self._thread(work)

    @Slot(str)
    def loadPipelines(self, raw):
        try:
            item = json.loads(raw)
        except ValueError:
            return
        slug = item.get("slug", "")
        if item.get("provider") != "GitHub" or not slug:
            self.pipelinesLoaded.emit(json.dumps({"runs": [], "available": False, "reason": "GitHub remote required"}))
            return
        def work():
            code, out, err = run(["gh", "run", "list", "--repo", slug, "--limit", "12", "--json",
                                  "databaseId,name,displayTitle,status,conclusion,workflowName,headBranch,event,createdAt,url"], timeout=20)
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
        subprocess.Popen([binary, path], start_new_session=True)

    @Slot(str)
    def openTerminal(self, path):
        choices = [
            ("konsole", ["--workdir", path]), ("alacritty", ["--working-directory", path]),
            ("foot", ["--working-directory", path]), ("kitty", ["--directory", path]),
        ]
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
