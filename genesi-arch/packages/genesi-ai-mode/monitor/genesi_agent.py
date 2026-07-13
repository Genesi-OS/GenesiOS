#!/usr/bin/env python3
"""Local, dependency-free tool layer for the Genesi AI assistant."""

from __future__ import annotations

import json
import os
import platform
import re
import shlex
import shutil
import signal
import subprocess
import tempfile
import unicodedata
from pathlib import Path


MAX_OUTPUT = 16_000
MAX_FILE_READ = 96_000

TOOLS = [
    {
        "name": "system_info",
        "description": "Inspect the local operating system, user, desktop and available disk space.",
        "arguments": {},
    },
    {
        "name": "list_files",
        "description": "List files and directories in a local path.",
        "arguments": {"path": "absolute path or ~/path"},
    },
    {
        "name": "search_files",
        "description": "Find files below a directory by a case-insensitive name fragment.",
        "arguments": {"path": "directory", "query": "name fragment"},
    },
    {
        "name": "read_file",
        "description": "Read a UTF-8 text file (large files are truncated).",
        "arguments": {"path": "file path"},
    },
    {
        "name": "write_file",
        "description": "Create or replace a UTF-8 text file atomically.",
        "arguments": {"path": "file path", "content": "complete new content"},
    },
    {
        "name": "create_directory",
        "description": "Create a directory and any missing parents.",
        "arguments": {"path": "directory path"},
    },
    {
        "name": "run_command",
        "description": "Run a shell command as the current user in a chosen directory.",
        "arguments": {"command": "shell command", "cwd": "optional working directory", "timeout": "optional seconds, max 120"},
    },
    {
        "name": "launch_app",
        "description": "Launch a desktop application detached from the assistant.",
        "arguments": {"command": "executable and optional arguments"},
    },
    {
        "name": "open_path",
        "description": "Open a file, folder or URL with the system default application.",
        "arguments": {"path": "file, folder or URL"},
    },
    {
        "name": "list_processes",
        "description": "List the current user's running processes.",
        "arguments": {},
    },
    {
        "name": "kill_process",
        "description": "Send SIGTERM to a process owned by the current user.",
        "arguments": {"pid": "numeric process id"},
    },
    {
        "name": "manage_packages",
        "description": "Install or remove Arch Linux packages through the system authorization dialog.",
        "arguments": {"action": "install or remove", "packages": ["package-name"]},
    },
]


def agent_system_prompt() -> str:
    catalog = json.dumps(TOOLS, ensure_ascii=True, separators=(",", ":"))
    return f"""You are Genesi AI, a local operating-system assistant. You can answer normally and can also operate the user's computer through the tools below.

When no computer action is needed, answer normally. When an action is needed, return ONLY one JSON object with this exact shape:
{{"type":"action","tool":"tool_name","arguments":{{}},"reason":"short user-facing explanation"}}

Never invent a tool. Use one action at a time and wait for its result. After receiving a GENESI_TOOL_RESULT message, either request the next action or answer with the final result. Do not wrap action JSON in prose. Ask a clarifying question instead of guessing a destructive target.
Always use launch_app, not run_command, when opening a graphical desktop application.

Tools: {catalog}
"""


def parse_agent_action(text: str):
    """Return a validated action dict, or None for a normal assistant answer."""
    cleaned = str(text or "").replace("\ufeff", "").translate(str.maketrans({
        "\u201c": '"', "\u201d": '"', "\u2018": "'", "\u2019": "'", "\u00a0": " ",
    }))
    cleaned = "".join(ch for ch in cleaned if ch in "\n\r\t" or ord(ch) >= 32)
    candidates = [cleaned.strip()]
    candidates.extend(re.findall(r"```(?:json)?\s*(\{.*?\})\s*```", cleaned, re.S | re.I))
    first = cleaned.find("{")
    last = cleaned.rfind("}")
    if first >= 0 and last > first:
        candidates.append(cleaned[first:last + 1])
    # raw_decode accepts a valid object followed by model stop tokens or prose.
    decoder = json.JSONDecoder()
    for match in re.finditer(r"\{", cleaned):
        try:
            value, _end = decoder.raw_decode(cleaned[match.start():])
            candidates.append(json.dumps(value))
        except ValueError:
            continue
    for candidate in candidates:
        try:
            value = json.loads(candidate)
        except (TypeError, ValueError):
            continue
        if not isinstance(value, dict) or value.get("type") != "action":
            continue
        tool = value.get("tool")
        args = value.get("arguments", {})
        if isinstance(args, str):
            try:
                args = json.loads(args)
            except ValueError:
                args = {}
        if tool not in {item["name"] for item in TOOLS} or not isinstance(args, dict):
            continue
        return {
            "tool": tool,
            "arguments": args,
            "reason": str(value.get("reason") or "Genesi AI wants to perform this action."),
        }
    return None


def looks_like_agent_action(text: str) -> bool:
    compact = str(text or "").lower().replace(" ", "")
    return ("\"type\":\"action\"" in compact or "'type':'action'" in compact
            or ("\"tool\":" in compact and "\"arguments\":" in compact))


def direct_app_action(messages):
    """Resolve unambiguous app-launch requests without trusting model JSON."""
    latest = next((str(m.get("content") or "") for m in reversed(messages)
                   if m.get("role") == "user"), "")
    normalized = unicodedata.normalize("NFKD", latest.lower()).encode("ascii", "ignore").decode()
    launch_words = ("abre", "abra", "abrir", "inicia", "inicie", "executa", "execute",
                    "open", "launch", "start", "roda", "rode")
    if not any(re.search(rf"\b{word}\b", normalized) for word in launch_words):
        return None
    applications = (
        (("firefox", "navegador"), "firefox", "Firefox"),
        (("genesi code",), "genesi-code", "Genesi Code"),
        (("genesi forge", "forge"), "genesi-forge", "Genesi Forge"),
        (("terminal", "konsole"), "konsole", "Terminal"),
        (("arquivos", "dolphin", "file manager"), "dolphin", "Files"),
        (("configuracoes", "system settings"), "systemsettings", "System Settings"),
        (("calculadora", "calculator", "kcalc"), "kcalc", "Calculator"),
    )
    for aliases, command, label in applications:
        if any(alias in normalized for alias in aliases):
            return {
                "tool": "launch_app",
                "arguments": {"command": command},
                "reason": f"Open {label}",
            }
    return None


def action_risk(tool: str) -> str:
    if tool in {"system_info", "list_files", "search_files", "read_file", "list_processes"}:
        return "read-only"
    if tool in {"open_path", "launch_app", "create_directory"}:
        return "local-change"
    return "system-change"


class ToolError(RuntimeError):
    pass


class LocalToolExecutor:
    _catastrophic = re.compile(
        r"(?:^|[;&|]\s*)(?:sudo\s+|pkexec\s+)?(?:rm\s+-[^\n]*r[^\n]*f\s+/(?:\s|$)|"
        r"mkfs(?:\.|\s)|wipefs\s|fdisk\s+/dev/|parted\s+/dev/|"
        r"dd\s+[^\n]*of=/dev/|chmod\s+-R\s+777\s+/|:\(\)\s*\{)",
        re.I,
    )

    def execute(self, tool: str, arguments: dict) -> dict:
        method = getattr(self, f"tool_{tool}", None)
        if method is None:
            raise ToolError(f"Unknown tool: {tool}")
        try:
            result = method(arguments or {})
            return {"ok": True, "tool": tool, "result": self._limit(result)}
        except Exception as exc:
            return {"ok": False, "tool": tool, "error": self._limit(str(exc))}

    @staticmethod
    def _limit(value):
        text = value if isinstance(value, str) else json.dumps(value, ensure_ascii=False)
        if len(text) > MAX_OUTPUT:
            return text[:MAX_OUTPUT] + "\n[output truncated]"
        return text

    @staticmethod
    def _path(value, must_exist=False) -> Path:
        if not value:
            raise ToolError("A path is required.")
        path = Path(os.path.expandvars(os.path.expanduser(str(value)))).resolve()
        if must_exist and not path.exists():
            raise ToolError(f"Path does not exist: {path}")
        return path

    def tool_system_info(self, _args):
        home = Path.home()
        try:
            disk = shutil.disk_usage(home)
        except OSError:
            disk = shutil.disk_usage(Path.cwd())
        return {
            "os": platform.platform(),
            "kernel": platform.release(),
            "architecture": platform.machine(),
            "user": os.environ.get("USER") or os.environ.get("LOGNAME") or "unknown",
            "home": str(home),
            "desktop": os.environ.get("XDG_CURRENT_DESKTOP", "unknown"),
            "session": os.environ.get("XDG_SESSION_TYPE", "unknown"),
            "disk_free_gib": round(disk.free / (1024 ** 3), 1),
        }

    def tool_list_files(self, args):
        path = self._path(args.get("path", "~"), must_exist=True)
        if not path.is_dir():
            raise ToolError(f"Not a directory: {path}")
        entries = []
        for item in sorted(path.iterdir(), key=lambda p: (not p.is_dir(), p.name.lower()))[:300]:
            try:
                size = item.stat().st_size if item.is_file() else None
            except OSError:
                size = None
            entries.append({"name": item.name, "type": "directory" if item.is_dir() else "file", "size": size})
        return {"path": str(path), "entries": entries}

    def tool_search_files(self, args):
        root = self._path(args.get("path", "~"), must_exist=True)
        query = str(args.get("query") or "").strip().lower()
        if not query:
            raise ToolError("A search query is required.")
        matches = []
        for current, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in {".git", "node_modules", ".cache"}]
            for name in dirs + files:
                if query in name.lower():
                    matches.append(str(Path(current, name)))
                    if len(matches) >= 250:
                        return matches
        return matches

    def tool_read_file(self, args):
        path = self._path(args.get("path"), must_exist=True)
        if not path.is_file():
            raise ToolError(f"Not a file: {path}")
        with path.open("rb") as handle:
            data = handle.read(MAX_FILE_READ + 1)
        if b"\0" in data:
            raise ToolError("Binary files cannot be read with this tool.")
        text = data[:MAX_FILE_READ].decode("utf-8", errors="replace")
        return text + ("\n[file truncated]" if len(data) > MAX_FILE_READ else "")

    def tool_write_file(self, args):
        path = self._path(args.get("path"))
        content = args.get("content")
        if not isinstance(content, str):
            raise ToolError("File content must be text.")
        path.parent.mkdir(parents=True, exist_ok=True)
        fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                handle.write(content)
            os.replace(temporary, path)
        finally:
            if os.path.exists(temporary):
                os.unlink(temporary)
        return f"Wrote {len(content.encode('utf-8'))} bytes to {path}"

    def tool_create_directory(self, args):
        path = self._path(args.get("path"))
        path.mkdir(parents=True, exist_ok=True)
        return f"Directory ready: {path}"

    def tool_run_command(self, args):
        command = str(args.get("command") or "").strip()
        if not command:
            raise ToolError("A command is required.")
        if self._catastrophic.search(command):
            raise ToolError("This command is blocked because it can destroy the operating system or a disk.")
        cwd = self._path(args.get("cwd") or "~", must_exist=True)
        timeout = max(1, min(int(args.get("timeout") or 60), 120))
        shell = shutil.which("bash") or shutil.which("sh")
        if not shell:
            raise ToolError("No POSIX shell was found.")
        proc = subprocess.run(
            [shell, "-lc", command], cwd=cwd, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout,
            env={**os.environ, "PAGER": "cat", "GIT_PAGER": "cat"},
        )
        return {"exit_code": proc.returncode, "output": proc.stdout or ""}

    def tool_launch_app(self, args):
        command = str(args.get("command") or "").strip()
        parts = shlex.split(command)
        if not parts:
            raise ToolError("An application command is required.")
        executable = shutil.which(parts[0])
        if not executable:
            raise ToolError(f"Application not found: {parts[0]}")
        proc = subprocess.Popen(
            [executable, *parts[1:]], stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL, start_new_session=True,
        )
        return {"pid": proc.pid, "application": executable}

    def tool_open_path(self, args):
        value = str(args.get("path") or "").strip()
        if not value:
            raise ToolError("A path or URL is required.")
        target = value if re.match(r"^[a-z][a-z0-9+.-]*://", value, re.I) else str(self._path(value, must_exist=True))
        opener = shutil.which("xdg-open")
        if not opener:
            raise ToolError("xdg-open is not installed.")
        proc = subprocess.Popen([opener, target], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        return {"pid": proc.pid, "opened": target}

    def tool_list_processes(self, _args):
        proc = subprocess.run(
            ["ps", "-u", str(os.getuid()), "-o", "pid=,etimes=,comm=,args="],
            text=True, capture_output=True, timeout=10,
        )
        return proc.stdout.strip()

    def tool_kill_process(self, args):
        pid = int(args.get("pid"))
        if pid <= 1 or pid == os.getpid():
            raise ToolError("Refusing to terminate this process.")
        status = Path(f"/proc/{pid}/status")
        if not status.exists():
            raise ToolError(f"Process {pid} does not exist.")
        uid_line = next((line for line in status.read_text(errors="replace").splitlines() if line.startswith("Uid:")), "")
        if not uid_line or int(uid_line.split()[1]) != os.getuid():
            raise ToolError("Only processes owned by the current user can be terminated.")
        os.kill(pid, signal.SIGTERM)
        return f"SIGTERM sent to process {pid}"

    def tool_manage_packages(self, args):
        action = str(args.get("action") or "").lower()
        packages = args.get("packages") or []
        if isinstance(packages, str):
            packages = packages.split()
        if action not in {"install", "remove"}:
            raise ToolError("Package action must be install or remove.")
        if not packages or any(not re.fullmatch(r"[a-zA-Z0-9@._+:-]+", str(p)) for p in packages):
            raise ToolError("One or more package names are invalid.")
        pacman_args = ["-S", "--needed"] if action == "install" else ["-R"]
        proc = subprocess.run(
            ["pkexec", "pacman", *pacman_args, "--noconfirm", *map(str, packages)],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=900,
        )
        return {"exit_code": proc.returncode, "output": proc.stdout or ""}
