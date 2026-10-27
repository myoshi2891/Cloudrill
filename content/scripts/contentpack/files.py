"""配信 JSON の共通書式と、署名・カタログのアトミックな書き込み。"""

import json
import os
import tempfile
from pathlib import Path
from typing import Any


def canonical_json(data: Any) -> bytes:
    return json.dumps(data, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def atomic_write(target: Path, data: bytes) -> None:
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=target.parent, delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(data)
        os.replace(temporary, target)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
