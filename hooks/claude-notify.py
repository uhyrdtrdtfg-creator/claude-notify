#!/usr/bin/env python3
"""Claude Code hook → claude-notify server.

Reads the hook JSON payload on stdin, extracts a human-readable title/body,
and POSTs to the notify server. Never blocks Claude: all failures are logged
to stderr and the script exits 0.
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
    elif hook_name == "SessionEnd":
        body = f"Session ended ({event.get('reason', '')})".strip()
    else:
        body = hook_name or "event"

    post({
        "user_id": USER_ID,
        "event": hook_name.lower(),
        "session_id": session_id,
        "cwd": cwd,
        "title": truncate(title, 60),
        "body": body.strip(),
    })
    return 0


if __name__ == "__main__":
    sys.exit(main())
