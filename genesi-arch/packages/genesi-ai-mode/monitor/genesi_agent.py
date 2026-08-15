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
import threading
import unicodedata
from pathlib import Path


MAX_OUTPUT = 16_000
MAX_FILE_READ = 96_000


APPLICATION_ALIASES = (
    (("firefox", "navegador", "browser"), "firefox", "Firefox"),
    (("genesi ai mode monitor", "genesi ai monitor", "monitor do modo ia", "monitor da ia"),
     "genesi-ai-monitor", "Genesi AI Mode Monitor"),
    (("genesi quick chat", "quick chat"), "genesi-ai-quick --show", "Genesi AI Quick Chat"),
    (("genesi code",), "genesi-code", "Genesi Code"),
    (("genesi forge", "forge"), "genesi-forge", "Genesi Forge"),
    (("genesi sandboxes", "sandboxes", "sandbox"), "genesi-sandboxes-gui", "Genesi Sandboxes"),
    (("genesi snapshots", "snapshots", "snapshot"), "genesi-snapshots-gui", "Genesi Snapshots"),
    (("genesi api inspector", "api inspector", "netinspect"),
     "genesi-netinspect-gui", "Genesi API Inspector"),
    (("genesi portscope", "portscope", "dashboard de portas", "portas e processos"),
     "genesi-ports-gui", "Genesi PortScope"),
    (("genesi db explorer", "db explorer"), "genesi-db", "Genesi DB Explorer"),
    (("genesi welcome", "welcome"), "genesi-welcome", "Genesi Welcome"),
    (("terminal", "konsole"), "konsole", "Terminal"),
    (("arquivos", "dolphin", "file manager"), "dolphin", "Files"),
    (("configuracoes", "system settings"), "systemsettings", "System Settings"),
    (("calculadora", "calculator", "kcalc"), "kcalc", "Calculator"),
)


def _normalized(value: str) -> str:
    return unicodedata.normalize("NFKD", str(value or "").lower()).encode("ascii", "ignore").decode()


def _desktop_application(query: str):
    """Resolve an installed desktop entry by its human-facing name or id."""
    wanted = _normalized(query).strip()
    if not wanted:
        return None
    roots = [Path.home() / ".local/share/applications", Path("/usr/local/share/applications"),
             Path("/usr/share/applications")]
    matches = []
    for root in roots:
        if not root.is_dir():
            continue
        for path in root.glob("*.desktop"):
            try:
                values = {}
                in_entry = False
                for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
                    if raw.startswith("["):
                        in_entry = raw.strip() == "[Desktop Entry]"
                        continue
                    if in_entry and "=" in raw:
                        key, value = raw.split("=", 1)
                        if key in {"Name", "Exec", "Type", "NoDisplay", "Hidden"}:
                            values[key] = value.strip()
                if (values.get("Type", "Application") != "Application"
                        or values.get("Hidden", "false").lower() == "true"):
                    continue
                name = values.get("Name", path.stem)
                command = re.sub(r"\s+%[fFuUdDnNickvm]", "", values.get("Exec", "")).strip()
                if not command:
                    continue
                fields = {_normalized(name), _normalized(path.stem)}
                try:
                    fields.add(_normalized(Path(shlex.split(command)[0]).name))
                except ValueError:
                    continue
                score = 3 if wanted in fields else 2 if any(wanted == f.replace("-", " ") for f in fields) else 0
                if not score and len(wanted) >= 4 and any(wanted in field or field in wanted for field in fields):
                    score = 1
                if score:
                    matches.append((score, name, command))
            except OSError:
                continue
    if not matches:
        return None
    _score, name, command = max(matches, key=lambda item: (item[0], -len(item[1])))
    return command, name

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
        "description": "Run a non-interactive shell command in the background and return its output to the assistant.",
        "arguments": {"command": "shell command", "cwd": "optional working directory", "timeout": "optional seconds, max 120"},
    },
    {
        "name": "run_in_terminal",
        "description": "Open a visible terminal and run an interactive command, TUI program, sudo command, installer or long-running task.",
        "arguments": {"command": "shell command", "cwd": "optional working directory", "keep_open": "optional boolean"},
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

Answer in the SAME LANGUAGE the user wrote in. Genesi's users are mostly Brazilian, so a message in Portuguese gets a reply in Portuguese.

Read for INTENT, not for literal words. The user is typing fast into a small box, so expect short, informal, abbreviated requests with typos. "abre o navegador" means launch the default browser; "ta lento" is a question about system performance, not an instruction to run a benchmark. If a request has one obvious sensible reading, act on it instead of asking the user to rephrase. Ask a question only when two readings would lead to genuinely different actions, or when the target of a destructive action is unclear.

Be brief. This is a summon bar, not a chat window: two or three sentences unless the user asks for detail. No preamble, no restating the question, no bullet lists for a one-line answer.

If the user is only ASKING something, answer it. Do not reach for a tool just because one exists.

When no computer action is needed, answer normally. When an action is needed, return ONLY one JSON object with this exact shape:
{{"type":"action","tool":"tool_name","arguments":{{}},"reason":"short user-facing explanation"}}

Never invent a tool. Use one action at a time and wait for its result. After receiving a GENESI_TOOL_RESULT message, either request the next action or answer with the final result. Do not wrap action JSON in prose. Ask a clarifying question instead of guessing a destructive target.
Always use launch_app, not run_command, when opening a graphical desktop application.
Use run_in_terminal when the user mentions a terminal, wants to watch the command, or the command is interactive, uses sudo, launches a TUI, or may ask questions. Use run_command only when you need its captured output to continue reasoning.
Use manage_packages for installing or removing Arch Linux packages. You are able to operate the system: do not tell the user to run a command manually when one of these tools can complete it. Privileged actions will be authenticated by the operating system.
Removing, deleting or uninstalling an installed application means manage_packages with action remove. kill_process only stops a currently running process and always requires a numeric PID; it never uninstalls software.
After list_processes returns, answer from that result. Never call list_processes twice for the same request.

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
        if not isinstance(value, dict):
            continue
        # Accept the canonical Genesi envelope, compact envelopes commonly
        # emitted by small models, and OpenAI-compatible tool_calls.
        if isinstance(value.get("action"), dict):
            value = value["action"]
        tool_calls = value.get("tool_calls") or []
        if tool_calls and isinstance(tool_calls[0], dict):
            function = tool_calls[0].get("function") or tool_calls[0]
            value = {
                "tool": function.get("name"),
                "arguments": function.get("arguments", {}),
                "reason": value.get("reason", ""),
            }
        declared_type = value.get("type")
        tool = value.get("tool") or value.get("name")
        if declared_type not in (None, "action", "tool_call", "function"):
            tool = tool or declared_type
        raw_tool = tool
        aliases = {
            "open_application": "launch_app", "open_app": "launch_app",
            "execute_command": "run_command", "shell": "run_command",
            "mkdir": "create_directory", "open_file": "open_path",
            "install_package": "manage_packages", "uninstall_package": "manage_packages",
            "remove_package": "manage_packages",
        }
        tool = aliases.get(tool, tool)
        args = value.get("arguments", value.get("parameters", value.get("input", {})))
        if isinstance(args, str):
            try:
                args = json.loads(args)
            except ValueError:
                args = {}
        if not isinstance(args, dict):
            continue
        if tool == "manage_packages" and raw_tool in {"install_package", "uninstall_package", "remove_package"}:
            package = args.pop("package", args.get("packages", []))
            args["packages"] = package if isinstance(package, list) else [package]
            args["action"] = "install" if raw_tool == "install_package" else "remove"
        if tool not in {item["name"] for item in TOOLS}:
            continue
        if not _valid_tool_arguments(tool, args):
            continue
        return {
            "tool": tool,
            "arguments": args,
            "reason": str(value.get("reason") or "Genesi AI wants to perform this action."),
        }
    return None


def _valid_tool_arguments(tool: str, args: dict) -> bool:
    """Reject incomplete model calls before they reach approval or execution."""
    if tool in {"run_command", "run_in_terminal", "launch_app"}:
        return isinstance(args.get("command"), str) and bool(args["command"].strip())
    if tool in {"read_file", "write_file", "create_directory"}:
        return isinstance(args.get("path"), str) and bool(args["path"].strip())
    if tool == "open_path":
        return isinstance(args.get("path"), str) and bool(args["path"].strip())
    if tool == "kill_process":
        try:
            return int(args.get("pid")) > 1
        except (TypeError, ValueError):
            return False
    if tool == "manage_packages":
        packages = args.get("packages")
        if isinstance(packages, str):
            packages = packages.split()
        return args.get("action") in {"install", "remove"} and bool(packages)
    return True


def looks_like_agent_action(text: str) -> bool:
    compact = str(text or "").lower().replace(" ", "")
    structural = False
    try:
        value = json.loads(str(text or "").strip())
        structural = isinstance(value, dict) and any(
            key in value for key in ("type", "tool", "tool_calls", "action", "arguments", "parameters")
        )
    except (TypeError, ValueError):
        pass
    return (structural or "\"type\":\"action\"" in compact or "'type':'action'" in compact
            or ("\"tool\":" in compact and "\"arguments\":" in compact)
            or any(f'\"type\":\"{tool}\"' in compact for tool in {item["name"] for item in TOOLS})
            or "\"tool_calls\":" in compact)


def direct_app_action(messages):
    """Resolve unambiguous app-launch requests without trusting model JSON."""
    user_messages = [str(m.get("content") or "") for m in messages if m.get("role") == "user"]
    latest = user_messages[-1] if user_messages else ""
    normalized_latest = _normalized(latest)
    repeat_words = ("mesma coisa", "de novo", "novamente", "repete", "repita", "again", "same thing")
    context = latest
    if len(user_messages) > 1 and any(word in normalized_latest for word in repeat_words):
        context = user_messages[-2] + " " + latest
    normalized = _normalized(context)
    launch_words = ("abre", "abra", "abrir", "inicia", "inicie", "executa", "execute",
                    "open", "launch", "start", "roda", "rode")
    if not any(re.search(rf"\b{word}\b", normalized) for word in launch_words):
        return None
    for aliases, command, label in APPLICATION_ALIASES:
        if any(alias in normalized for alias in aliases):
            target = ""
            url_match = re.search(r"https?://[^\s]+", latest, re.I)
            if not url_match:
                url_match = re.search(
                    r"(?:www\.)?[a-z0-9][a-z0-9-]*(?:\.[a-z0-9-]+)+(?:/[^\s]*)?",
                    latest, re.I,
                )
            if not url_match and context != latest:
                url_match = re.search(r"https?://[^\s]+", context, re.I)
                if not url_match:
                    url_match = re.search(
                        r"(?:www\.)?[a-z0-9][a-z0-9-]*(?:\.[a-z0-9-]+)+(?:/[^\s]*)?",
                        context, re.I,
                    )
            if url_match:
                target = url_match.group(0).rstrip(".,;:!?)]}")
                if not re.match(r"^https?://", target, re.I):
                    target = "https://" + target
            full_command = command + (" " + shlex.quote(target) if target else "")
            return {
                "tool": "launch_app",
                "arguments": {"command": full_command},
                "reason": f"Open {label}" + (f" at {target}" if target else ""),
                "completion": f"Opened {target} in {label}." if target else f"Opened {label}.",
            }
    # Finally resolve names exposed by installed .desktop files. This lets the
    # assistant open niche applications without teaching the model executable
    # names, while retaining the deterministic aliases above for Genesi apps.
    requested = re.sub(r"^(?:por favor\s+)?(?:abre|abra|abrir|inicia|inicie|executa|execute|open|launch|start|roda|rode)\s+", "", normalized).strip()
    requested = re.split(r"\s+(?:pra|para|for|at|no|na|em)\s+", requested, maxsplit=1)[0].strip(" .,!?")
    desktop = _desktop_application(requested)
    if desktop:
        command, label = desktop
        return {
            "tool": "launch_app", "arguments": {"command": command},
            "reason": f"Open {label}", "completion": f"Opened {label}.",
        }
    return None


def direct_terminal_action(messages):
    """Recognize requests to run a command in a visible terminal."""
    user_messages = [str(m.get("content") or "") for m in messages if m.get("role") == "user"]
    latest = user_messages[-1].strip() if user_messages else ""
    if not latest:
        return None
    explicit_terminal = re.search(
        r"\b(?:roda|rode|rodar|executa|execute|executar|run|start)\s+(?:o\s+comando\s+)?(.+?)\s+(?:no|num|em\s+um|in\s+the)\s+terminal\b",
        latest, re.I)
    explicit_command = re.search(
        r"\b(?:roda|rode|rodar|executa|execute|executar|run)\s+(?:pra\s+mim\s+|para\s+mim\s+)?(?:o\s+)?comando\s+(.+)$",
        latest, re.I)
    match = explicit_terminal or explicit_command
    if not match:
        return None
    command = re.sub(r"\s+(?:pra mim|para mim|por favor)$", "", match.group(1), flags=re.I)
    command = command.strip().strip("'\"")
    if not command:
        return None
    return {
        "tool": "run_in_terminal",
        "arguments": {"command": command, "cwd": "~", "keep_open": True},
        "reason": f"Run {command} in a visible terminal",
        "completion": f"Started {command} in the terminal.",
    }


def direct_package_action(messages):
    """Resolve simple, explicit package install/remove requests reliably."""
    user_messages = [str(m.get("content") or "") for m in messages if m.get("role") == "user"]
    latest = _normalized(user_messages[-1]).strip() if user_messages else ""
    match = re.search(
        r"\b(instala|instale|instalar|install|desinstala|desinstale|desinstalar|remove|remova|uninstall)\b\s+(.+)$",
        latest,
    )
    parts = []
    action = ""
    if match:
        verb, requested = match.groups()
        action = "remove" if verb in {"desinstala", "desinstale", "desinstalar", "remove", "remova", "uninstall"} else "install"
        requested = re.sub(r"\b(?:no|num|em um|in the)\s+terminal\b.*$", "", requested).strip()
        requested = re.sub(r"^(?:(?:por favor|pra mim|para mim)\s+)*(?:(?:o|a|os|as)\s+)?(?:pacote|pacotes|package|packages)?\s*", "", requested)
        requested = re.sub(r"\s+(?:por favor|pra mim|para mim)$", "", requested).strip(" .,;:")
        parts = [part.strip() for part in re.split(r"\s*(?:,|\be\b|\band\b)\s*", requested) if part.strip()]
        if any(" " in part or not re.fullmatch(r"[a-z0-9@._+:-]+", part) for part in parts):
            parts = []

    # "Delete it from my PC" means uninstalling an installed package, not
    # killing a process. Resolve references against pacman's package database.
    delete_words = r"(?:exclua|excluir|apague|apagar|delete|deletar)"
    system_words = r"(?:pc|computador|sistema|maquina|programa|aplicativo|pacote)"
    if not parts and re.search(rf"\b{delete_words}\b", latest) and re.search(rf"\b{system_words}\b", latest):
        context = _normalized(" ".join(user_messages[-2:]))
        mentioned = []
        for package in _installed_packages():
            pattern = rf"(?<![a-z0-9@._+:-]){re.escape(package)}(?![a-z0-9@._+:-])"
            if re.search(pattern, context):
                mentioned.append(package)
        if len(mentioned) == 1:
            action, parts = "remove", mentioned

    if not action or not parts:
        return None
    label = ", ".join(parts)
    return {
        "tool": "manage_packages", "arguments": {"action": action, "packages": parts},
        "reason": f"{action.capitalize()} {label}",
        "completion": f"Package operation started for {label}.",
    }


def _installed_packages():
    if not shutil.which("pacman"):
        return []
    try:
        result = subprocess.run(["pacman", "-Qq"], text=True, capture_output=True, timeout=8)
    except (OSError, subprocess.SubprocessError):
        return []
    if result.returncode != 0:
        return []
    return [line.strip().lower() for line in result.stdout.splitlines() if line.strip()]


def action_risk(tool: str) -> str:
    if tool in {"system_info", "list_files", "search_files", "read_file", "list_processes"}:
        return "read-only"
    if tool in {"open_path", "launch_app", "create_directory"}:
        return "local-change"
    return "system-change"


def action_presentation(action: dict) -> dict:
    """Build a human-first approval summary while keeping raw details optional."""
    tool = action.get("tool", "action")
    args = action.get("arguments") or {}
    risk = action_risk(tool)
    presentation = {
        "title": "Allow this action?",
        "description": "Genesi AI wants to perform an action on your computer.",
        "icon": "security-high",
        "approve_label": "Allow",
        "risk_label": {
            "read-only": "Only reads information",
            "local-change": "Changes your session or files",
            "system-change": "Changes the system",
        }[risk],
        "details": [],
    }

    if tool == "launch_app":
        parts = shlex.split(str(args.get("command") or ""))
        app = Path(parts[0]).name if parts else "application"
        labels = {
            "firefox": "Firefox", "genesi-code": "Genesi Code",
            "genesi-forge": "Genesi Forge", "konsole": "Terminal",
            "dolphin": "Files", "systemsettings": "System Settings",
            "kcalc": "Calculator", "genesi-ai-monitor": "Genesi AI Mode Monitor",
            "genesi-ai-quick": "Genesi AI Quick Chat",
            "genesi-sandboxes-gui": "Genesi Sandboxes",
            "genesi-snapshots-gui": "Genesi Snapshots",
            "genesi-netinspect-gui": "Genesi API Inspector",
            "genesi-ports-gui": "Genesi PortScope", "genesi-db": "Genesi DB Explorer",
            "genesi-welcome": "Genesi Welcome",
        }
        app_label = labels.get(app, app)
        target = next((part for part in parts[1:] if re.match(r"^https?://", part, re.I)), "")
        presentation.update({
            "title": f"Open {app_label}?",
            "description": (f"{app_label} will open this address."
                            if target else f"Genesi AI will start {app_label}."),
            "icon": "system-run",
            "approve_label": "Open",
            "risk_label": "Opens an application",
            "details": ([{"label": "Application", "value": app_label},
                         {"label": "Address", "value": target}]
                        if target else [{"label": "Application", "value": app_label}]),
        })
    elif tool == "open_path":
        target = str(args.get("path") or "")
        presentation.update({
            "title": "Open this location?", "description": "The default application will open this item.",
            "icon": "document-open", "approve_label": "Open",
            "risk_label": "Opens an item",
            "details": [{"label": "Location", "value": target}],
        })
    elif tool == "create_directory":
        presentation.update({
            "title": "Create this folder?", "description": "A new folder will be created at this location.",
            "icon": "folder-new", "approve_label": "Create folder",
            "risk_label": "Creates a folder",
            "details": [{"label": "Folder", "value": str(args.get("path") or "")}],
        })
    elif tool == "write_file":
        content = str(args.get("content") or "")
        presentation.update({
            "title": "Write this file?", "description": "The file will be created or its current contents replaced.",
            "icon": "document-save", "approve_label": "Write file",
            "risk_label": "Creates or replaces a file",
            "details": [{"label": "File", "value": str(args.get("path") or "")},
                        {"label": "New content", "value": f"{len(content.encode('utf-8'))} bytes"}],
        })
    elif tool == "read_file":
        presentation.update({
            "title": "Read this file?", "description": "Genesi AI will read text from this file to answer your request.",
            "icon": "document-preview", "approve_label": "Read file",
            "risk_label": "Read-only access",
            "details": [{"label": "File", "value": str(args.get("path") or "")}],
        })
    elif tool in {"list_files", "search_files"}:
        details = [{"label": "Folder", "value": str(args.get("path") or "~")}]
        if tool == "search_files":
            details.append({"label": "Search", "value": str(args.get("query") or "")})
        presentation.update({
            "title": "Look through this folder?", "description": "Genesi AI will only inspect names and locations.",
            "icon": "folder-search", "approve_label": "Allow lookup", "details": details,
            "risk_label": "Read-only access",
        })
    elif tool == "run_command":
        presentation.update({
            "title": "Run this command?", "description": "This command will run with your user permissions.",
            "icon": "utilities-terminal", "approve_label": "Run command",
            "risk_label": "Runs with your permissions",
            "details": [{"label": "Command", "value": str(args.get("command") or "")},
                        {"label": "Working folder", "value": str(args.get("cwd") or "~")}],
        })
    elif tool == "run_in_terminal":
        presentation.update({
            "title": "Run this in Terminal?",
            "description": "A visible terminal will open and run this command with your user permissions.",
            "icon": "utilities-terminal", "approve_label": "Open and run",
            "risk_label": "Runs visibly with your permissions",
            "details": [{"label": "Command", "value": str(args.get("command") or "")},
                        {"label": "Working folder", "value": str(args.get("cwd") or "~")}],
        })
    elif tool == "kill_process":
        presentation.update({
            "title": "Stop this process?", "description": "The application or background process may close immediately.",
            "icon": "process-stop", "approve_label": "Stop process",
            "risk_label": "Stops a running process",
            "details": [{"label": "Process ID", "value": str(args.get("pid") or "")}],
        })
    elif tool == "manage_packages":
        packages = args.get("packages") or []
        if isinstance(packages, str):
            packages = packages.split()
        action_name = str(args.get("action") or "change").capitalize()
        presentation.update({
            "title": f"{action_name} system packages?",
            "description": "The system authorization dialog will ask for your password.",
            "icon": "system-software-install", "approve_label": action_name,
            "risk_label": "Changes installed software",
            "details": [{"label": "Packages", "value": ", ".join(map(str, packages))}],
        })
    elif tool == "system_info":
        presentation.update({
            "title": "Inspect system information?",
            "description": "Genesi AI will read basic hardware, session and storage information.",
            "icon": "computer", "approve_label": "Allow inspection",
            "risk_label": "Read-only access",
        })
    elif tool == "list_processes":
        presentation.update({
            "title": "View running processes?",
            "description": "Genesi AI will inspect applications running under your user account.",
            "icon": "utilities-system-monitor", "approve_label": "View processes",
            "risk_label": "Read-only access",
        })

    return {**presentation, "risk": risk}


def summarize_tool_result(tool: str, result: dict) -> str:
    """Deterministic fallback when a model repeats an already completed tool."""
    if not result.get("ok"):
        error = str(result.get("error") or "The action did not complete.")
        return "I did not repeat the action. " + error
    if tool == "list_processes":
        try:
            payload = json.loads(result.get("result") or "{}")
        except (TypeError, ValueError):
            payload = {}
        processes = payload.get("processes") or []
        lines = [f"I found {payload.get('total', len(processes))} processes. Top processes by CPU:"]
        for process in processes[:12]:
            lines.append(
                f"- {process.get('name', 'unknown')} (PID {process.get('pid', '?')}): "
                f"{process.get('cpu', 0)}% CPU, {process.get('memory', 0)}% memory"
            )
        return "\n".join(lines)
    return "That action already completed, so I did not run it a second time."


class ToolError(RuntimeError):
    pass


class LocalToolExecutor:
    _catastrophic = re.compile(
        r"(?:^|[;&|]\s*)(?:sudo\s+|pkexec\s+)?(?:rm\s+-[^\n]*r[^\n]*f\s+/(?:\s|$)|"
        r"mkfs(?:\.|\s)|wipefs\s|fdisk\s+/dev/|parted\s+/dev/|"
        r"dd\s+[^\n]*of=/dev/|chmod\s+-R\s+777\s+/|:\(\)\s*\{)",
        re.I,
    )

    def __init__(self):
        self._process_lock = threading.Lock()
        self._active_process = None

    def cancel(self):
        with self._process_lock:
            process = self._active_process
        if process is not None and process.poll() is None:
            try:
                process.terminate()
            except OSError:
                pass

    def execute(self, tool: str, arguments: dict) -> dict:
        method = getattr(self, f"tool_{tool}", None)
        if method is None:
            raise ToolError(f"Unknown tool: {tool}")
        try:
            result = method(arguments or {})
            if isinstance(result, dict) and int(result.get("exit_code") or 0) != 0:
                output = str(result.get("output") or "").strip()
                return {"ok": False, "tool": tool,
                        "error": self._limit(output or f"Command exited with status {result['exit_code']}"),
                        "result": self._limit(result)}
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
        proc = subprocess.Popen(
            [shell, "-lc", command], cwd=cwd, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            env={**os.environ, "PAGER": "cat", "GIT_PAGER": "cat"},
        )
        with self._process_lock:
            self._active_process = proc
        try:
            output, _ = proc.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            proc.kill()
            output, _ = proc.communicate()
            raise ToolError(f"Command timed out after {timeout} seconds.\n{output or ''}")
        finally:
            with self._process_lock:
                if self._active_process is proc:
                    self._active_process = None
        return {"exit_code": proc.returncode, "output": output or ""}

    def tool_run_in_terminal(self, args):
        command = str(args.get("command") or "").strip()
        if not command:
            raise ToolError("A command is required.")
        if self._catastrophic.search(command):
            raise ToolError("This command is blocked because it can destroy the operating system or a disk.")
        cwd = self._path(args.get("cwd") or "~", must_exist=True)
        shell = shutil.which("bash") or shutil.which("sh")
        if not shell:
            raise ToolError("No POSIX shell was found.")
        keep_open = args.get("keep_open", True) is not False
        script = command
        if keep_open:
            script += "; status=$?; printf '\\n[Genesi AI] Command finished with status %s.\\n' \"$status\"; exec " + shlex.quote(shell)

        launchers = {}
        if shutil.which("konsole"):
            launchers["konsole"] = ["konsole", "--workdir", str(cwd), "-e", shell, "-lc", script]
        if shutil.which("alacritty"):
            launchers["alacritty"] = ["alacritty", "--working-directory", str(cwd), "-e", shell, "-lc", script]
        if shutil.which("xdg-terminal-exec"):
            launchers["xdg"] = ["xdg-terminal-exec", "--", shell, "-lc", script]
        if shutil.which("gnome-terminal"):
            launchers["gnome"] = ["gnome-terminal", f"--working-directory={cwd}", "--", shell, "-lc", script]
        if shutil.which("xfce4-terminal"):
            launchers["xfce"] = ["xfce4-terminal", "--working-directory", str(cwd), "-x", shell, "-lc", script]
        if shutil.which("kitty"):
            launchers["kitty"] = ["kitty", "--directory", str(cwd), shell, "-lc", script]
        if shutil.which("foot"):
            launchers["foot"] = ["foot", "--working-directory", str(cwd), shell, "-lc", script]
        if shutil.which("xterm"):
            launchers["xterm"] = ["xterm", "-e", shell, "-lc", f"cd {shlex.quote(str(cwd))} && {script}"]
        desktop = _normalized(os.environ.get("XDG_CURRENT_DESKTOP", ""))
        if "kde" in desktop or "plasma" in desktop:
            order = ("konsole", "xdg", "alacritty", "kitty", "foot", "gnome", "xfce", "xterm")
        elif "hypr" in desktop or "caelestia" in desktop:
            order = ("alacritty", "kitty", "foot", "xdg", "konsole", "gnome", "xfce", "xterm")
        else:
            order = ("xdg", "gnome", "xfce", "konsole", "alacritty", "kitty", "foot", "xterm")
        candidates = [launchers[name] for name in order if name in launchers]
        if not candidates:
            raise ToolError("No supported terminal emulator is installed.")
        env = {**os.environ, "GENESI_AI_ACTION": "1"}
        proc = subprocess.Popen(candidates[0], cwd=cwd, env=env, stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL, start_new_session=True)
        return {"pid": proc.pid, "terminal": candidates[0][0], "command": command}

    def tool_launch_app(self, args):
        command = str(args.get("command") or "").strip()
        parts = shlex.split(command)
        if not parts:
            raise ToolError("An application command is required.")
        executable = shutil.which(parts[0])
        if not executable:
            desktop = _desktop_application(command)
            if desktop:
                command, _label = desktop
                parts = shlex.split(command)
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
            ["ps", "-u", str(os.getuid()), "-o", "pid=,%cpu=,%mem=,etimes=,comm=", "--sort=-%cpu"],
            text=True, capture_output=True, timeout=10,
        )
        if proc.returncode != 0:
            raise ToolError(proc.stderr.strip() or "Could not inspect running processes.")
        rows = []
        lines = [line.strip() for line in proc.stdout.splitlines() if line.strip()]
        for line in lines[:30]:
            parts = line.split(None, 4)
            if len(parts) < 5:
                continue
            pid, cpu, memory, elapsed, name = parts
            rows.append({
                "pid": int(pid), "cpu": float(cpu), "memory": float(memory),
                "elapsed_seconds": int(elapsed), "name": name[:80],
            })
        return {"total": len(lines), "shown": len(rows), "processes": rows}

    def tool_kill_process(self, args):
        try:
            pid = int(args.get("pid"))
        except (TypeError, ValueError):
            raise ToolError("A numeric process ID is required to stop a process.")
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
        packages = list(map(str, packages))
        if action == "install" and shutil.which("pacman"):
            official = subprocess.run(
                ["pacman", "-Si", "--", *packages], stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL, timeout=30,
            ).returncode == 0
            helper = shutil.which("paru") or shutil.which("yay")
            if not official and helper:
                command = " ".join([
                    shlex.quote(helper), "-S", "--needed", "--noconfirm", "--",
                    *map(shlex.quote, packages),
                ])
                return self.tool_run_in_terminal({"command": command, "cwd": "~", "keep_open": True})
        pacman_args = ["-S", "--needed"] if action == "install" else ["-R"]
        proc = subprocess.run(
            ["pkexec", "pacman", *pacman_args, "--noconfirm", *packages],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=900,
        )
        return {"exit_code": proc.returncode, "output": proc.stdout or ""}
