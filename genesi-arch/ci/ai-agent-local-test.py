#!/usr/bin/env python3
"""
ai-agent-local-test.py -- what the agent loop asks a LOCAL model for.

"Local AI is slow as hell and does not work right" (2026-10-09) came down to
the request, not the model: thinking models reasoned before every step, and
Ollama was never told how big a window the tool catalogue needs, so the
instructions could be cut off the front. This pins the request each local
transport gets, and that a reply's <think> block never reaches the parser.
"""
import io
import json
import os
import sys
import urllib.error

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except (AttributeError, OSError):
    pass

HERE = os.path.dirname(os.path.abspath(__file__))
MON = os.path.normpath(os.path.join(HERE, "..", "packages", "genesi-ai-mode", "monitor"))
sys.path.insert(0, MON)
sys.path.insert(1, os.path.normpath(os.path.join(HERE, "..", "packages", "genesi-ai-mode")))

fails = []


def check(name, cond, detail=""):
    print(("  ok   " if cond else "  FAIL ") + name + ("" if cond else "\n         " + str(detail)))
    if not cond:
        fails.append(name)


print("== agent, local models ==")
import genesi_ai_monitor as mon  # noqa: E402

B = mon.Backend


class Fake:
    """Just enough of a Backend for _agent_model_reply."""
    AGENT_CTX = B.AGENT_CTX
    _strip_thinking = staticmethod(B._strip_thinking)

    def __init__(self, turbo, replies):
        self._turbo = turbo
        self._recall = False
        self.sent = []
        self.replies = list(replies)

    def _ensure_ollama(self):
        return True

    def _read_agent_response(self, request):
        body = json.loads(request.data.decode())
        self.sent.append((request.full_url, body))
        reply = self.replies.pop(0)
        if isinstance(reply, Exception):
            raise reply
        return json.dumps(reply).encode()

    _agent_model_reply = B._agent_model_reply


msgs = [{"role": "user", "content": "abre o firefox"}]

# Ollama
f = Fake(False, [{"message": {"content": "<think>hmm, the user wants...</think>\n{\"tool\": \"open_app\"}"}}])
out = f._agent_model_reply("qwen3:8b", msgs)
url, body = f.sent[0]
check("Ollama: thinking is switched off", body.get("think") is False, body)
check("Ollama: the window fits the tool catalogue", body.get("options", {}).get("num_ctx", 0) >= 8192, body.get("options"))
check("Ollama: the output is capped and steady",
      body["options"].get("num_predict") == 768 and body["options"].get("temperature") == 0.2)
check("the system prompt (the tool catalogue) goes first", body["messages"][0]["role"] == "system")
check("a <think> block never reaches the action parser", out == '{"tool": "open_app"}', out)

refusal = urllib.error.HTTPError("http://x", 400, "think not supported", {}, io.BytesIO(b""))
f = Fake(False, [refusal, {"message": {"content": "ok"}}])
out = f._agent_model_reply("llama3.2:3b", msgs)
check("an Ollama that refuses `think` is asked again without it",
      out == "ok" and len(f.sent) == 2 and "think" not in f.sent[1][1], [b for _, b in f.sent])

# Turbo / llama-server
f = Fake(True, [{"choices": [{"message": {"content": "<think>x</think>resposta"}}]}])
mon._turbo_base = lambda: "http://127.0.0.1:1"
out = f._agent_model_reply("gguf:qwen3-8b", msgs)
url, body = f.sent[0]
check("Turbo: thinking is switched off through the chat template",
      body.get("chat_template_kwargs") == {"enable_thinking": False}, body)
check("Turbo: capped, steady, and the prompt cache kept",
      body.get("max_tokens") == 768 and body.get("temperature") == 0.2 and body.get("cache_prompt") is True)
check("Turbo: the reply comes back without its thinking", out == "resposta", out)

check("a reply cut off inside <think> falls back to the raw text, never to an empty answer",
      B._strip_thinking("<think>still thinking when the cap hit") == "<think>still thinking when the cap hit"
      and B._strip_thinking("plain answer") == "plain answer")

print()
if fails:
    print(f"agent local: {len(fails)} FAILURE(S)")
    sys.exit(1)
print("agent local: OK")
