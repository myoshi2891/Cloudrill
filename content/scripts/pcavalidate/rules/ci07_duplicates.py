"""CI-07: ID の重複(error)と、問題文の類似(warning)。"""

from __future__ import annotations

import unicodedata
from collections.abc import Iterator

from ..context import Context, Rule, ja_of
from ..model import Issue, JsonPath, Kind, Severity, SourceDoc, get_list, get_str

RULE_ID = "CI-07"

# 重複を確認する種別と、メッセージに使うラベル
_LABELS = {
    Kind.QUESTION: "問題 ID",
    Kind.FLASHCARD: "カード ID",
    Kind.DRILL: "ドリル ID",
    Kind.CASE: "ケース ID",
    Kind.DECISION: "ツリー ID",
}


def _ids(doc: SourceDoc) -> Iterator[tuple[str, JsonPath]]:
    match doc.kind:
        case Kind.FLASHCARD:
            items, key = get_list(doc.data, "cards"), "cards"
        case Kind.DRILL:
            items, key = get_list(doc.data, "drills"), "drills"
        case _:
            if (value := get_str(doc.data, "id")) is not None:
                yield value, ("id",)
            return
    for i, item in enumerate(items):
        if (value := get_str(item, "id")) is not None:
            yield value, (key, i, "id")


def _duplicate_ids(ctx: Context) -> Iterator[Issue]:
    for kind, label in _LABELS.items():
        first: dict[str, SourceDoc] = {}
        for doc in ctx.of_kind(kind, valid_only=False):
            for value, path in _ids(doc):
                if value in first:
                    yield doc.issue(RULE_ID, Severity.ERROR, f"{label} '{value}' が重複しています(最初の定義: {first[value].path})", path)
                else:
                    first[value] = doc


def ngrams(text: str, n: int) -> frozenset[str]:
    normalized = "".join(unicodedata.normalize("NFKC", text).split())
    if len(normalized) < n:
        return frozenset({normalized}) if normalized else frozenset()
    return frozenset(normalized[i : i + n] for i in range(len(normalized) - n + 1))


def _similar_stems(ctx: Context) -> Iterator[Issue]:
    threshold = ctx.config.jaccard_threshold
    items = [(ngrams(ja_of(doc.data.get("stem")), ctx.config.ngram), doc) for doc in ctx.questions]
    items = [(grams, doc) for grams, doc in items if grams]
    # サイズ昇順に並べ、|A|/|B| <= 閾値 になった時点で以降の組は Jaccard <= 閾値 なので打ち切る
    items.sort(key=lambda x: (len(x[0]), x[1].path))
    for i, (a, doc_a) in enumerate(items):
        for b, doc_b in items[i + 1 :]:
            if len(a) / len(b) <= threshold:
                break
            inter = len(a & b)
            jaccard = inter / (len(a) + len(b) - inter)
            if jaccard > threshold:
                first, second = sorted((doc_a, doc_b), key=lambda d: d.path)
                yield second.issue(
                    RULE_ID, Severity.WARNING,
                    f"問題文が {first.path} と類似しています(Jaccard {jaccard:.2f} > {threshold})",
                    ("stem",),
                )


def check(ctx: Context) -> Iterator[Issue]:
    yield from _duplicate_ids(ctx)
    yield from _similar_stems(ctx)


RULE = Rule(RULE_ID, "ID 重複と問題文の類似", check)
