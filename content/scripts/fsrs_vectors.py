"""FSRS のテストベクタを、リファレンス実装(py-fsrs)から生成する(DDD-P1 P1-S08a)。

開発時だけ使う(CI では使わない)。py-fsrs は uv の依存グループ `fsrs` で入れる:

    uv sync --project content --group fsrs
    content/.venv/bin/python content/scripts/fsrs_vectors.py \
        --out packages/Domain/Tests/FSRSTests/Vectors/fsrs-vectors.json

結果は決定論的にする(間隔のゆらぎは無効、カード ID と時刻は固定、JSON はキーを並べて出力する)。
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from importlib.metadata import version
from pathlib import Path

from fsrs import Card, Rating, Scheduler, State

FSRS_VERSION = "FSRS-6"
START = datetime(2026, 1, 1, 9, 0, tzinfo=timezone.utc)
PHASE_NAMES = {State.Learning: "learning", State.Review: "review", State.Relearning: "relearning"}


@dataclass(frozen=True)
class Step:
    """1回の評価。`at` は、前回の評価で決まった期限からのずれ(`from_due=True`)か、前回の評価の時刻からのずれ"""

    rating: Rating
    offset: timedelta = timedelta(0)
    from_due: bool = True


def at_due(rating: Rating, offset: timedelta = timedelta(0)) -> Step:
    return Step(rating, offset, from_due=True)


def after_last(rating: Rating, offset: timedelta) -> Step:
    return Step(rating, offset, from_due=False)


GOOD, AGAIN, HARD, EASY = Rating.Good, Rating.Again, Rating.Hard, Rating.Easy

# ケースの一覧。1回目の評価は常に START に行う(新規カードの期限は START)。
CASES: dict[str, list[Step]] = {
    # 4 種類の初回評価
    "new-again": [at_due(AGAIN)],
    "new-hard": [at_due(HARD)],
    "new-good": [at_due(GOOD)],
    "new-easy": [at_due(EASY)],
    # 学習ステップを経て review に入り、正解を続ける(長い間隔)
    "good-streak": [at_due(GOOD)] * 10,
    "easy-streak": [at_due(EASY)] * 6,
    "hard-streak": [at_due(GOOD), at_due(GOOD)] + [at_due(HARD)] * 6,
    # 忘却(Again)を含む
    "lapse-and-recover": [at_due(GOOD)] * 4 + [at_due(AGAIN)] + [at_due(GOOD)] * 4,
    "repeated-lapses": [at_due(GOOD), at_due(GOOD), at_due(AGAIN), at_due(AGAIN), at_due(GOOD), at_due(AGAIN), at_due(GOOD), at_due(GOOD)],
    "learning-again": [at_due(GOOD), at_due(AGAIN), at_due(GOOD), at_due(GOOD), at_due(GOOD)],
    # 予定より早い復習と遅い復習
    "early-review": [at_due(GOOD)] * 4 + [at_due(GOOD, -timedelta(days=3)), at_due(GOOD)],
    "late-review": [at_due(GOOD)] * 4 + [at_due(GOOD, timedelta(days=30)), at_due(GOOD)],
    "late-review-again": [at_due(GOOD)] * 4 + [at_due(AGAIN, timedelta(days=60)), at_due(GOOD)],
    # 同じ日の2回目の復習(review の状態で、期限の数時間後にもう一度)
    "same-day-review": [at_due(GOOD)] * 4 + [after_last(GOOD, timedelta(hours=2)), after_last(EASY, timedelta(hours=3)), at_due(GOOD)],
    # 評価を混ぜる
    "mixed": [at_due(HARD), at_due(GOOD), at_due(EASY), at_due(HARD), at_due(AGAIN), at_due(HARD), at_due(GOOD), at_due(EASY)],
}


def iso(value: datetime) -> str:
    if value.tzinfo != timezone.utc or value.microsecond != 0:
        raise ValueError(f"UTC の秒単位の時刻だけを出力する: {value!r}")
    return value.strftime("%Y-%m-%dT%H:%M:%SZ")


def make_scheduler() -> Scheduler:
    # 既定のパラメータ・目標保持率 0.9・既定の学習ステップ。ゆらぎだけを無効にする
    return Scheduler(desired_retention=0.9, enable_fuzzing=False)


def run_case(scheduler: Scheduler, steps: list[Step]) -> tuple[list[dict[str, object]], list[dict[str, object]]]:
    card = Card(card_id=1, due=START)
    last_review: datetime | None = None
    reviews: list[dict[str, object]] = []
    expected: list[dict[str, object]] = []
    for step in steps:
        if step.from_due or last_review is None:
            at = card.due + step.offset
        else:
            at = last_review + step.offset
        card, _ = scheduler.review_card(card, step.rating, review_datetime=at)
        last_review = at
        if card.stability is None or card.difficulty is None:
            raise ValueError("評価の後は stability と difficulty が決まっているはず")
        reviews.append({"rating": int(step.rating), "at": iso(at)})
        expected.append({
            "phase": PHASE_NAMES[card.state],
            "step": card.step,
            "stability": card.stability,
            "difficulty": card.difficulty,
            "due": iso(card.due),
            "retrievabilityAtDue": scheduler.get_card_retrievability(card, card.due),
        })
    return reviews, expected


def build() -> dict[str, object]:
    scheduler = make_scheduler()
    cases = []
    for name, steps in CASES.items():
        reviews, expected = run_case(scheduler, steps)
        cases.append({"name": name, "start": iso(START), "reviews": reviews, "expected": expected})
    return {
        "generator": {"library": "py-fsrs", "version": version("fsrs"), "fsrsVersion": FSRS_VERSION},
        "parameters": {
            "w": list(scheduler.parameters),
            "desiredRetention": scheduler.desired_retention,
            "learningSteps": [int(s.total_seconds()) for s in scheduler.learning_steps],
            "relearningSteps": [int(s.total_seconds()) for s in scheduler.relearning_steps],
            "maximumInterval": scheduler.maximum_interval,
            "enableFuzzing": scheduler.enable_fuzzing,
        },
        "cases": cases,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--out", type=Path, required=True, help="出力する JSON のパス")
    args = parser.parse_args(argv)
    text = json.dumps(build(), ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(text, encoding="utf-8", newline="\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
