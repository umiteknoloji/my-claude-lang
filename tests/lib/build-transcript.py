#!/usr/bin/env python3
"""
MCL test transcript builder — emits realistic Claude Code JSONL.

Usage: python3 build-transcript.py <output-path> <kind> [args...]

Transcript kinds:
  user-only "<prompt>"
  assistant-text "<text>"
  spec-correct "<title>"           — canonical 📋 Spec: + 7 H2 sections
  spec-no-emoji-bare               — bare "Spec:" without 📋 prefix
  spec-h2-heading                  — "## Spec" heading instead of 📋
  spec-faz-heading                 — "## Faz 2 — Spec" heading
  spec-codeblock-wrapped           — 📋 Spec: inside triple-backticks
  spec-partial "<missing-csv>"     — 📋 Spec: with some sections missing
  askq-spec-approve <selected>     — pinned body + selected option (TR)
  askq-non-pinned <body> <selected>— paraphrased body
  multi: "<kind>;<arg>" ...        — chain multiple turns

The output is line-delimited JSON; each line is a transcript entry
matching the Claude Code `~/.claude/projects/<key>/<session>.jsonl`
shape: {"type": "user|assistant", "message": {role, content: [...]}}.
"""

import json
import sys
from datetime import datetime, timezone


def _ts(seconds_offset: int = 0) -> str:
    base = datetime(2026, 5, 1, 0, 0, 0, tzinfo=timezone.utc)
    base = base.fromtimestamp(base.timestamp() + seconds_offset, tz=timezone.utc)
    return base.strftime("%Y-%m-%dT%H:%M:%S.000Z")


def user_turn(text: str, idx: int = 0):
    return {
        "type": "user",
        "timestamp": _ts(idx * 10),
        "message": {"role": "user", "content": text},
    }


def assistant_text_turn(text: str, idx: int = 1):
    return {
        "type": "assistant",
        "timestamp": _ts(idx * 10),
        "message": {
            "role": "assistant",
            "content": [{"type": "text", "text": text}],
        },
    }


def assistant_askq_turn(question: str, options: list[str], tu_id: str, idx: int = 2):
    return {
        "type": "assistant",
        "timestamp": _ts(idx * 10),
        "message": {
            "role": "assistant",
            "content": [
                {
                    "type": "tool_use",
                    "id": tu_id,
                    "name": "AskUserQuestion",
                    "input": {
                        "questions": [
                            {
                                "question": question,
                                "options": [{"label": o, "description": ""} for o in options],
                            }
                        ]
                    },
                }
            ],
        },
    }


def user_tool_result_turn(tu_id: str, content: str, idx: int = 3):
    return {
        "type": "user",
        "timestamp": _ts(idx * 10),
        "message": {
            "role": "user",
            "content": [
                {
                    "type": "tool_result",
                    "tool_use_id": tu_id,
                    "content": content,
                }
            ],
        },
    }


# ----- spec body builders -----

CANONICAL_SPEC = """📋 Spec:

## [{title}]

## Objective
{title} build.

## MUST
- Functional core in place

## SHOULD
- Pagination

## Acceptance Criteria
- [ ] Endpoint returns expected payload

## Edge Cases
- empty input handled

## Technical Approach
- React + FastAPI

## Out of Scope
- multi-tenant
"""

NO_EMOJI_BARE = """Spec:
  Project: admin panel
  Pages: /users, /login
  Stack: React + FastAPI
"""

H2_SPEC = """## Spec

Project: admin panel
Stack: React + FastAPI
"""

FAZ_HEADING = """## Faz 2 — Spec

```
Spec:
  Project: Content Management Backoffice
  Stack: React + Node.js
```
"""

CODEBLOCK_WRAPPED = """All bilgiler toplandı. Spec yazıyorum.

```
📋 Spec:

## [Admin Panel]

## Objective
Build it.

## MUST
- auth

## SHOULD
- pagination

## Acceptance Criteria
- [ ] works

## Edge Cases
- empty list

## Technical Approach
- React

## Out of Scope
- multi-tenant
```
"""


def spec_partial(missing_csv: str) -> str:
    """Build a 📋 Spec: block with the named sections REMOVED."""
    missing = set(s.strip() for s in missing_csv.split(",") if s.strip())
    full = {
        "Objective": "## Objective\nBuild admin panel.\n",
        "MUST": "## MUST\n- Auth required\n",
        "SHOULD": "## SHOULD\n- Pagination\n",
        "Acceptance Criteria": "## Acceptance Criteria\n- [ ] Works\n",
        "Edge Cases": "## Edge Cases\n- empty list\n",
        "Technical Approach": "## Technical Approach\n- React + FastAPI\n",
        "Out of Scope": "## Out of Scope\n- multi-tenant\n",
    }
    parts = ["📋 Spec:\n", "## [Admin Panel]\n"]
    for name, body in full.items():
        if name not in missing:
            parts.append(body)
    return "\n".join(parts)


def main():
    if len(sys.argv) < 3:
        print("usage: build-transcript.py <output> <kind> [args...]", file=sys.stderr)
        sys.exit(2)
    out, kind = sys.argv[1], sys.argv[2]
    args = sys.argv[3:]
    turns = []

    if kind == "user-only":
        turns.append(user_turn(args[0] if args else "build it", 0))

    elif kind == "assistant-text":
        turns.append(user_turn("build it", 0))
        turns.append(assistant_text_turn(args[0], 1))

    elif kind == "spec-correct":
        title = args[0] if args else "Admin Panel"
        turns.append(user_turn("build it", 0))
        turns.append(assistant_text_turn(CANONICAL_SPEC.format(title=title), 1))

    elif kind == "spec-no-emoji-bare":
        turns.append(user_turn("build it", 0))
        turns.append(assistant_text_turn(NO_EMOJI_BARE, 1))

    elif kind == "spec-h2-heading":
        turns.append(user_turn("build it", 0))
        turns.append(assistant_text_turn(H2_SPEC, 1))

    elif kind == "spec-faz-heading":
        turns.append(user_turn("build it", 0))
        turns.append(assistant_text_turn(FAZ_HEADING, 1))

    elif kind == "spec-codeblock-wrapped":
        # Note: the raw 📋 Spec: line inside the code block IS still
        # detected by line-anchored regex. Code-block wrapping is a UX
        # mistake but not a hook-blocking failure mode in current scanner.
        turns.append(user_turn("build it", 0))
        turns.append(assistant_text_turn(CODEBLOCK_WRAPPED, 1))

    elif kind == "spec-partial":
        missing = args[0] if args else "Edge Cases,Out of Scope"
        turns.append(user_turn("build it", 0))
        turns.append(assistant_text_turn(spec_partial(missing), 1))

    elif kind == "spec-then-askq":
        # Realistic: assistant turn 1 emits spec, turn 2 emits askq+tool_use,
        # next user turn carries tool_result.
        title = args[0] if args else "Admin Panel"
        question = args[1] if len(args) > 1 else "MCL 9.2.1 | Spec'i onaylıyor musun?"
        selected = args[2] if len(args) > 2 else "Evet, onayla"
        tu_id = "toolu_test01canonical"
        turns.append(user_turn("build it", 0))
        turns.append(assistant_text_turn(CANONICAL_SPEC.format(title=title), 1))
        turns.append(
            assistant_askq_turn(
                question, [selected, "Hayır, değişiklik var", "İptal"], tu_id, 2
            )
        )
        turns.append(
            user_tool_result_turn(
                tu_id,
                f'User has answered your questions: "{question}"="{selected}".',
                3,
            )
        )

    elif kind == "askq-only":
        # askq alone without preceding spec
        question = args[0] if args else "MCL 9.2.1 | Spec'i onaylıyor musun?"
        selected = args[1] if len(args) > 1 else "Evet, onayla"
        tu_id = "toolu_test01askonly"
        turns.append(user_turn("build it", 0))
        turns.append(assistant_askq_turn(question, [selected, "Hayır"], tu_id, 1))
        turns.append(
            user_tool_result_turn(
                tu_id,
                f'User has answered your questions: "{question}"="{selected}".',
                2,
            )
        )

    else:
        print(f"unknown kind: {kind}", file=sys.stderr)
        sys.exit(2)

    with open(out, "w") as f:
        for turn in turns:
            f.write(json.dumps(turn) + "\n")


if __name__ == "__main__":
    main()
