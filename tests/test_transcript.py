"""hooks/lib/transcript.py birim testleri.

JSONL fixture'lar test içinde inline yazılır — gerçek Claude Code
formatına yakın.
"""

from __future__ import annotations

import json
from pathlib import Path

from hooks.lib import transcript


def write_jsonl(path: Path, messages: list[dict]) -> None:
    """Mesaj listesini JSONL olarak yaz."""
    with path.open("w", encoding="utf-8") as f:
        for m in messages:
            f.write(json.dumps(m) + "\n")


# ---------- iter_messages ----------


def test_iter_messages_empty_when_missing(tmp_path):
    p = tmp_path / "nope.jsonl"
    assert list(transcript.iter_messages(p)) == []


def test_iter_messages_skips_blank_and_invalid(tmp_path):
    p = tmp_path / "t.jsonl"
    p.write_text(
        '{"type": "user", "message": {"role": "user", "content": "ok"}}\n'
        "\n"
        "not valid json\n"
        '{"type": "assistant", "message": {"role": "assistant", "content": [{"type":"text","text":"hi"}]}}\n',
        encoding="utf-8",
    )
    msgs = list(transcript.iter_messages(p))
    assert len(msgs) == 2
    assert msgs[0]["type"] == "user"
    assert msgs[1]["type"] == "assistant"


# ---------- last_assistant_text ----------


def test_last_assistant_text_basic(tmp_path):
    p = tmp_path / "t.jsonl"
    write_jsonl(
        p,
        [
            {"type": "user", "message": {"role": "user", "content": "merhaba"}},
            {
                "type": "assistant",
                "message": {
                    "role": "assistant",
                    "content": [{"type": "text", "text": "Merhaba!"}],
                },
            },
            {
                "type": "assistant",
                "message": {
                    "role": "assistant",
                    "content": [{"type": "text", "text": "İkinci tur"}],
                },
            },
        ],
    )
    assert transcript.last_assistant_text(p) == "İkinci tur"


def test_last_assistant_text_concats_multiple_text_blocks(tmp_path):
    p = tmp_path / "t.jsonl"
    write_jsonl(
        p,
        [
            {
                "type": "assistant",
                "message": {
                    "role": "assistant",
                    "content": [
                        {"type": "text", "text": "Birinci."},
                        {"type": "text", "text": "İkinci."},
                    ],
                },
            },
        ],
    )
    assert transcript.last_assistant_text(p) == "Birinci.\nİkinci."


def test_last_assistant_text_skips_non_text_blocks(tmp_path):
    p = tmp_path / "t.jsonl"
    write_jsonl(
        p,
        [
            {
                "type": "assistant",
                "message": {
                    "role": "assistant",
                    "content": [
                        {"type": "tool_use", "id": "x", "name": "Read", "input": {}},
                        {"type": "text", "text": "Sadece bu görünmeli"},
                    ],
                },
            },
        ],
    )
    assert transcript.last_assistant_text(p) == "Sadece bu görünmeli"


def test_last_assistant_text_none_when_no_assistant(tmp_path):
    p = tmp_path / "t.jsonl"
    write_jsonl(p, [{"type": "user", "message": {"role": "user", "content": "x"}}])
    assert transcript.last_assistant_text(p) is None


def test_last_assistant_text_string_content_fallback(tmp_path):
    """Eski format: content string olabilir."""
    p = tmp_path / "t.jsonl"
    write_jsonl(
        p,
        [{"type": "assistant", "message": {"role": "assistant", "content": "düz string"}}],
    )
    assert transcript.last_assistant_text(p) == "düz string"


# ---------- find_last_assistant_text_matching ----------


def test_find_predicate_matches_correct_turn(tmp_path):
    p = tmp_path / "t.jsonl"
    write_jsonl(
        p,
        [
            {
                "type": "assistant",
                "message": {
                    "role": "assistant",
                    "content": [{"type": "text", "text": "📋 Spec:\nbody1"}],
                },
            },
            {
                "type": "assistant",
                "message": {
                    "role": "assistant",
                    "content": [{"type": "text", "text": "Kod yazıyorum"}],
                },
            },
            {
                "type": "assistant",
                "message": {
                    "role": "assistant",
                    "content": [{"type": "text", "text": "📋 Spec (revised):\nbody2"}],
                },
            },
        ],
    )
    spec_text = transcript.find_last_assistant_text_matching(
        lambda t: "📋 Spec" in t, p
    )
    assert spec_text is not None
    assert "body2" in spec_text


def test_find_predicate_no_match_returns_none(tmp_path):
    p = tmp_path / "t.jsonl"
    write_jsonl(
        p,
        [
            {
                "type": "assistant",
                "message": {
                    "role": "assistant",
                    "content": [{"type": "text", "text": "merhaba"}],
                },
            },
        ],
    )
    assert transcript.find_last_assistant_text_matching(lambda _: False, p) is None


# ---------- AskUserQuestion eşleştirme ----------


def test_iter_askq_uses_filters_by_tool_name(tmp_path):
    p = tmp_path / "t.jsonl"
    write_jsonl(
        p,
        [
            {
                "type": "assistant",
                "message": {
                    "role": "assistant",
                    "content": [
                        {"type": "tool_use", "id": "u1", "name": "Read", "input": {}},
                        {
                            "type": "tool_use",
                            "id": "u2",
                            "name": "AskUserQuestion",
                            "input": {"questions": [{"question": "?"}]},
                        },
                    ],
                },
            },
        ],
    )
    uses = list(transcript.iter_askq_uses(p))
    assert len(uses) == 1
    assert uses[0]["id"] == "u2"


def test_latest_askq_pair_matches_tool_use_id(tmp_path):
    p = tmp_path / "t.jsonl"
    write_jsonl(
        p,
        [
            {
                "type": "assistant",
                "message": {
                    "role": "assistant",
                    "content": [
                        {
                            "type": "tool_use",
                            "id": "ask-1",
                            "name": "AskUserQuestion",
                            "input": {"questions": [{"question": "İlk?"}]},
                        }
                    ],
                },
            },
            {
                "type": "user",
                "message": {
                    "role": "user",
                    "content": [
                        {
                            "type": "tool_result",
                            "tool_use_id": "ask-1",
                            "content": "Onayla",
                        }
                    ],
                },
            },
            {
                "type": "assistant",
                "message": {
                    "role": "assistant",
                    "content": [
                        {
                            "type": "tool_use",
                            "id": "ask-2",
                            "name": "AskUserQuestion",
                            "input": {"questions": [{"question": "Spec onayı?"}]},
                        }
                    ],
                },
            },
            {
                "type": "user",
                "message": {
                    "role": "user",
                    "content": [
                        {
                            "type": "tool_result",
                            "tool_use_id": "ask-2",
                            "content": "Onayla",
                        }
                    ],
                },
            },
        ],
    )
    use, result = transcript.latest_askq_pair(p)
    assert use is not None
    assert use["id"] == "ask-2"
    assert result is not None
    assert result["tool_use_id"] == "ask-2"
    assert result["content"] == "Onayla"


def test_latest_askq_pair_no_uses(tmp_path):
    p = tmp_path / "t.jsonl"
    write_jsonl(
        p,
        [{"type": "user", "message": {"role": "user", "content": "merhaba"}}],
    )
    use, result = transcript.latest_askq_pair(p)
    assert use is None
    assert result is None


def test_latest_askq_pair_pending_no_result(tmp_path):
    """Askq açıldı ama henüz cevap gelmedi (kullanıcı bekliyor)."""
    p = tmp_path / "t.jsonl"
    write_jsonl(
        p,
        [
            {
                "type": "assistant",
                "message": {
                    "role": "assistant",
                    "content": [
                        {
                            "type": "tool_use",
                            "id": "pending",
                            "name": "AskUserQuestion",
                            "input": {"questions": [{"question": "?"}]},
                        }
                    ],
                },
            },
        ],
    )
    use, result = transcript.latest_askq_pair(p)
    assert use is not None
    assert use["id"] == "pending"
    assert result is None


# ---------- robustness ----------


def test_missing_file_returns_empty(tmp_path):
    p = tmp_path / "no.jsonl"
    assert transcript.last_assistant_text(p) is None
    assert list(transcript.iter_askq_uses(p)) == []
    use, result = transcript.latest_askq_pair(p)
    assert use is None and result is None


def test_handles_top_level_role_format(tmp_path):
    """`type` yok, `message.role` var — bazı Claude Code sürümleri bu formatı verir."""
    p = tmp_path / "t.jsonl"
    write_jsonl(
        p,
        [
            {
                "message": {
                    "role": "assistant",
                    "content": [{"type": "text", "text": "alt seviye role"}],
                }
            },
        ],
    )
    assert transcript.last_assistant_text(p) == "alt seviye role"


# ---------- H-2 fix: last_user_text ----------


def test_last_user_text_plain_chat(tmp_path):
    """H-2 fix: AskQ olmadan gönderilen düz user text'i okunabilir."""
    p = tmp_path / "t.jsonl"
    write_jsonl(
        p,
        [
            {
                "type": "assistant",
                "message": {
                    "role": "assistant",
                    "content": [{"type": "text", "text": "Spec'i onaylamak ister misin?"}],
                },
            },
            {
                "type": "user",
                "message": {
                    "role": "user",
                    "content": [{"type": "text", "text": "tamam"}],
                },
            },
        ],
    )
    result = transcript.last_user_text(p)
    assert result == "tamam"


def test_last_user_text_skips_tool_result_turns(tmp_path):
    """H-2 fix: tool_result içeren user turn atlanır (AskQ cevabı)."""
    p = tmp_path / "t.jsonl"
    write_jsonl(
        p,
        [
            {
                "type": "assistant",
                "message": {
                    "role": "assistant",
                    "content": [
                        {
                            "type": "tool_use",
                            "id": "q1",
                            "name": "AskUserQuestion",
                            "input": {"questions": [{"question": "Onay?"}]},
                        }
                    ],
                },
            },
            {
                "type": "user",
                "message": {
                    "role": "user",
                    "content": [
                        {
                            "type": "tool_result",
                            "tool_use_id": "q1",
                            "content": "evet",
                        }
                    ],
                },
            },
        ],
    )
    # tool_result olan turn atlanmalı → None
    result = transcript.last_user_text(p)
    assert result is None


def test_last_user_text_returns_last_of_multiple(tmp_path):
    """H-2: birden fazla plain user turn → en son döner."""
    p = tmp_path / "t.jsonl"
    write_jsonl(
        p,
        [
            {
                "type": "user",
                "message": {
                    "role": "user",
                    "content": [{"type": "text", "text": "ilk mesaj"}],
                },
            },
            {
                "type": "user",
                "message": {
                    "role": "user",
                    "content": [{"type": "text", "text": "tamam, onaylıyorum"}],
                },
            },
        ],
    )
    result = transcript.last_user_text(p)
    assert result == "tamam, onaylıyorum"
