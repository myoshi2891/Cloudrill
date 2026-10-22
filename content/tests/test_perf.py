"""性能: 問題 500 件規模で、リンク確認を除いて 10 秒以内に終わる。"""

from __future__ import annotations

import random
import time
from pathlib import Path

from conftest import materialize
from generate import ALPHA, dump, make_question, question_path
from contentvalidate.config import GlobalConfig
from contentvalidate.engine import run

TOTAL_QUESTIONS = 500
LIMIT_SECONDS = 10.0


def test_500_questions_within_time_limit(config: GlobalConfig, tmp_path: Path) -> None:
    # Arrange: valid(58 問)に練習問題を追加して 500 問にする
    root = materialize(None, tmp_path)
    existing = len(list((root / ALPHA).glob("questions/**/*.yaml")))
    rng = random.Random(500)
    for n in range(TOTAL_QUESTIONS - existing):
        domain = n % 6 + 1
        q = make_question(rng, 2000 + n, domain, f"{domain}.1", correct=[n % 4])
        path = root / ALPHA / question_path(q)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(dump(q), encoding="utf-8")
    assert len(list((root / ALPHA).glob("questions/**/*.yaml"))) == TOTAL_QUESTIONS

    # Act
    started = time.perf_counter()
    issues = run(root, config)
    elapsed = time.perf_counter() - started

    # Assert
    assert [i for i in issues if str(i.severity) == "error"] == []
    assert elapsed < LIMIT_SECONDS, f"{elapsed:.2f}s"
