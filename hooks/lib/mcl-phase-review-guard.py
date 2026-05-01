#!/usr/bin/env python3
"""mcl-phase-review-guard.py

Inspect the LAST assistant turn in a JSONL transcript and report whether:
  - code-mutating tools (Write, Edit, MultiEdit, NotebookEdit, Bash)
    were used — meaning Phase 4 code was written this turn.
  - AskUserQuestion was used — meaning Phase 4 review dialog
    was started OR is continuing this turn.

stdout: JSON {"code_written": bool, "askuq_present": bool}
"""
import json
import sys

CODE_TOOLS = {"Write", "Edit", "MultiEdit", "NotebookEdit"}


def last_assistant_tool_uses(path: str) -> list:
    """Return list of tool_use dicts from the LAST assistant turn."""
    last_tools: list = []
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            for raw in f:
                raw = raw.strip()
                if not raw:
                    continue
                try:
                    obj = json.loads(raw)
                except Exception:
                    continue
                msg = obj.get("message") or obj
                if not isinstance(msg, dict):
                    continue
                if msg.get("role") != "assistant":
                    continue
                content = msg.get("content")
                if not isinstance(content, list):
                    continue
                tools = [
                    item
                    for item in content
                    if isinstance(item, dict) and item.get("type") == "tool_use"
                ]
                if tools:
                    last_tools = tools
    except Exception:
        pass
    return last_tools


def main() -> None:
    path = sys.argv[1] if len(sys.argv) > 1 else None
    if not path:
        print(json.dumps({"code_written": False, "askuq_present": False}))
        return

    tools = last_assistant_tool_uses(path)
    names = {t.get("name", "") for t in tools}

    code_written = bool(names & CODE_TOOLS)
    askuq_present = "AskUserQuestion" in names

    print(json.dumps({"code_written": code_written, "askuq_present": askuq_present}))


if __name__ == "__main__":
    main()
