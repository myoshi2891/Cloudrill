"""CI-13: カタログにある試験 ID の実在と重複。"""

from collections.abc import Iterator

from ..context import GlobalContext, Rule
from ..loader import exam_dirs
from ..model import Issue, Kind, Severity


def check(ctx: GlobalContext) -> Iterator[Issue]:
    # --exam で絞られた ctx.exams ではなく、全試験のディレクトリを参照する。
    known = {path.name for path in exam_dirs(ctx.root)}
    for doc in ctx.docs:
        if doc.kind is not Kind.CATALOG_SOURCE or not doc.schema_ok:
            continue
        seen: set[str] = set()
        for index, entry in enumerate(doc.data["exams"]):
            exam_id = entry["id"]
            path = ("exams", index, "id")
            if exam_id not in known:
                yield doc.issue("CI-13", Severity.ERROR, f"試験 {exam_id} がありません", path)
            if exam_id in seen:
                yield doc.issue("CI-13", Severity.ERROR, f"試験 {exam_id} が重複しています", path)
            seen.add(exam_id)


RULE = Rule("CI-13", "カタログの試験 ID", check_global=check)
