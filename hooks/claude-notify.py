#!/usr/bin/env python3
"""Claude Code hook → claude-notify server.

Reads the hook JSON payload on stdin, extracts a human-readable title/body,
and POSTs to the notify server. Never blocks Claude:
  - the parent forks and returns 0 immediately (so Claude Code continues)
  - a detached grandchild does the actual HTTP request in the background
  - all errors are swallowed; the script never returns non-zero
"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

SERVER_URL = os.environ.get("CLAUDE_NOTIFY_URL", "http://127.0.0.1:8080")
SHARED_SECRET = os.environ.get("CLAUDE_NOTIFY_SECRET", "")
USER_ID = os.environ.get("CLAUDE_NOTIFY_USER", "default")


def last_assistant_message(transcript_path: str) -> str:
    """Return the text of the last assistant message in a Claude Code transcript."""
    if not transcript_path:
        return ""
    p = Path(transcript_path)
    if not p.exists():
        return ""
    try:
        lines = p.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return ""
    for line in reversed(lines):
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue
        if entry.get("type") != "assistant":
            continue
        content = entry.get("message", {}).get("content", [])
        chunks = []
        for block in content:
            if isinstance(block, dict) and block.get("type") == "text":
                text = block.get("text", "")
                if text:
                    chunks.append(text)
        joined = "\n".join(chunks).strip()
        if joined:
            return joined
    return ""


def truncate(s: str, n: int) -> str:
    s = s.strip()
    return s if len(s) <= n else s[: n - 1] + "…"


def post(payload: dict) -> None:
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        SERVER_URL.rstrip("/") + "/v1/notify",
        data=data,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {SHARED_SECRET}",
            # Cloudflare blocks default Python-urllib UA — pretend to be a browser.
            "User-Agent": "Mozilla/5.0 (claude-notify-hook)",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            resp.read()
    except (urllib.error.URLError, TimeoutError) as exc:
        sys.stderr.write(f"[claude-notify] post failed: {exc}\n")


def main() -> int:
    try:
        event = json.load(sys.stdin)
    except json.JSONDecodeError:
        return 0

    hook_name = event.get("hook_event_name", "")
    session_id = event.get("session_id", "")
    cwd = event.get("cwd", "")
    project = Path(cwd).name if cwd else ""

    title = project or "Claude Code"

    if hook_name in ("Stop", "SubagentStop"):
        body = last_assistant_message(event.get("transcript_path", "")) or "(Claude finished)"
    elif hook_name == "Notification":
        body = event.get("message") or "Claude needs attention"
    elif hook_name == "SessionStart":
        body = f"Session started ({event.get('source', 'startup')})"
    elif hook_name == "SessionEnd":
        body = f"Session ended ({event.get('reason', '')})".strip()
    elif hook_name == "UserPromptSubmit":
        prompt = (event.get("prompt") or "").strip().replace("\n", " ")
        body = f"You: {prompt}" if prompt else "User submitted"
    elif hook_name == "PreToolUse":
        tool = event.get("tool_name", "?")
        ti = event.get("tool_input", {}) or {}
        # Show a short hint of what the tool will do
        hint = ti.get("command") or ti.get("file_path") or ti.get("path") \
            or ti.get("pattern") or ti.get("url") or ti.get("description") or ""
        if isinstance(hint, str) and hint:
            body = f"→ {tool}: {hint}"
        else:
            body = f"→ {tool}"
    elif hook_name == "PostToolUse":
        tool = event.get("tool_name", "?")
        resp = event.get("tool_response", {}) or {}
        ok = "✓" if not resp.get("is_error") else "✗"
        body = f"{ok} {tool} done"
    else:
        body = hook_name or "event"

    payload = {
        "user_id": USER_ID,
        "event": hook_name.lower(),
        "session_id": session_id,
        "cwd": cwd,
        "title": truncate(title, 60),
        "body": body.strip(),
    }

    # Detach so Claude Code doesn't wait for our HTTP round-trip.
    # Double-fork: parent → child → grandchild; parent exits, grandchild
    # is reparented to init and runs independently.
    try:
        if os.fork() > 0:
            return 0  # parent — Claude continues immediately
    except OSError:
        # fork unsupported (rare); fall back to synchronous send
        post(payload)
        return 0

    # In child — orphan ourselves so we don't keep Claude's session group alive
    try:
        os.setsid()
        if os.fork() > 0:
            os._exit(0)
    except OSError:
        pass

    # Grandchild — close fds and do the HTTP POST. Errors are swallowed.
    try:
        for fd in (0, 1, 2):
            try:
                os.close(fd)
            except OSError:
                pass
        # Reopen /dev/null so accidental prints don't crash
        devnull = os.open(os.devnull, os.O_RDWR)
        for fd in (0, 1, 2):
            try:
                os.dup2(devnull, fd)
            except OSError:
                pass
        post(payload)
    except Exception:
        pass
    finally:
        os._exit(0)


if __name__ == "__main__":
    sys.exit(main())
