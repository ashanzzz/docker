from __future__ import annotations

import re
from typing import Iterable

_MULTI_SPACE_RE = re.compile(r"[\t\r\f\v ]+")
_MULTI_BLANK_LINE_RE = re.compile(r"\n{3,}")


def _to_text(value: object) -> str:
    if value in (None, ""):
        return ""
    return str(value)


def normalize_single_line_text(value: object, *, max_length: int | None = None) -> str:
    text = _to_text(value).replace("\r\n", "\n").replace("\r", "\n")
    text = _MULTI_SPACE_RE.sub(" ", text.replace("\n", " "))
    text = text.strip()
    if max_length is not None:
        text = text[:max_length].rstrip()
    return text


def normalize_multiline_text(value: object, *, max_length: int | None = None) -> str:
    text = _to_text(value).replace("\r\n", "\n").replace("\r", "\n")
    lines = []
    for raw_line in text.split("\n"):
        line = _MULTI_SPACE_RE.sub(" ", raw_line).strip()
        lines.append(line)
    text = "\n".join(lines)
    text = _MULTI_BLANK_LINE_RE.sub("\n\n", text).strip()
    if max_length is not None:
        text = text[:max_length].rstrip()
    return text


def join_single_line_parts(parts: Iterable[object], *, separator: str = " / ", max_length: int | None = None) -> str:
    cleaned_parts = [normalize_single_line_text(part) for part in parts]
    text = separator.join(part for part in cleaned_parts if part)
    if max_length is not None:
        text = text[:max_length].rstrip()
    return text
