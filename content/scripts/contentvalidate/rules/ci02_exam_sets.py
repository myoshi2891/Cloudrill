"""CI-02: 模試の構成(問題数・ドメイン配分・ケース問題・双方向の一致・既定の割り当て)。"""

from __future__ import annotations

from collections import Counter
from collections.abc import Iterator
from typing import Any

from ..context import Context, Rule, set_questions, status_severity
from ..model import Issue, Severity, SourceDoc, get_list, get_str

RULE_ID = "CI-02"


def _case_studies_per_set(ctx: Context, exam_id: str | None) -> int | None:
    """exam.yaml の format.mockExam.caseStudiesPerSet。exam.yaml が Schema 違反なら None。"""
    exam = ctx.exam_by_id.get(exam_id)
    if exam is None:
        return None
    value = exam.data["format"]["mockExam"]["caseStudiesPerSet"]
    return value if isinstance(value, int) else None


def _set_count(ctx: Context, exam_id: str | None) -> int | None:
    """exam.yaml の format.mockExam.setCount。exam.yaml が Schema 違反なら None。"""
    exam = ctx.exam_by_id.get(exam_id)
    if exam is None:
        return None
    value = exam.data["format"]["mockExam"]["setCount"]
    return value if isinstance(value, int) else None


def check(ctx: Context) -> Iterator[Issue]:
    for doc, exam_sets in ctx.exam_sets:
        yield from _check_exam(ctx, doc, exam_sets)


def _check_exam(ctx: Context, doc: SourceDoc, exam_sets: list[tuple[int, dict[str, Any]]]) -> Iterator[Issue]:
    cfg = ctx.config
    exam_id = doc.exam_id
    question_by_id = ctx.question_by_id(exam_id)
    sets_by_id = {s.get("id"): (i, s) for i, s in exam_sets}
    per_set = _case_studies_per_set(ctx, exam_id)
    set_count = _set_count(ctx, exam_id)
    # ケースがない試験(caseStudiesPerSet: 0)ではケース問題も 0 問
    case_min, case_max = (0, 0) if per_set == 0 else (cfg.case_min, cfg.case_max)

    for i, exam_set in exam_sets:
        set_id = exam_set.get("id")
        sev = status_severity(exam_set)
        base = ("examSets", i)
        label = f"模試 {set_id}({exam_set.get('status')})"
        questions = set_questions(ctx, exam_id, exam_set)

        if set_count is not None and isinstance(set_id, int) and set_id > set_count:
            yield doc.issue(
                RULE_ID, Severity.ERROR,
                f"{label}: id が exam.yaml の setCount({set_count})を超えています",
                (*base, "id"),
            )

        if len(questions) != cfg.question_count:
            yield doc.issue(RULE_ID, sev, f"{label}: 問題数が {len(questions)} です(期待値 {cfg.question_count})", (*base, "questionIDs"))

        by_domain = Counter(q.data.get("domain") for q in questions)
        for domains, expected in cfg.domain_distribution:
            actual = sum(by_domain.get(d, 0) for d in domains)
            if actual != expected:
                name = "+".join(f"D{d}" for d in domains)
                yield doc.issue(RULE_ID, sev, f"{label}: {name} の問題数が {actual} です(期待値 {expected})", (*base, "questionIDs"))

        case_studies = get_list(exam_set, "caseStudies")
        if per_set is not None and len(case_studies) != per_set:
            yield doc.issue(
                RULE_ID, Severity.ERROR,
                f"{label}: ケースが {len(case_studies)} 個です(exam.yaml の caseStudiesPerSet は {per_set})",
                (*base, "caseStudies"),
            )

        allowed = set(case_studies)
        case_questions = [q for q in questions if q.data.get("caseStudy") is not None]
        if not case_min <= len(case_questions) <= case_max:
            yield doc.issue(
                RULE_ID, sev,
                f"{label}: ケース問題数が {len(case_questions)} です(期待範囲 {case_min}〜{case_max})",
                (*base, "caseStudies"),
            )
        for q in case_questions:
            if q.data.get("caseStudy") not in allowed:
                yield q.issue(
                    RULE_ID, sev,
                    f"{label} に収録されていますが、caseStudy '{q.data.get('caseStudy')}' は模試のケース {sorted(allowed)} に含まれません",
                    ("caseStudy",),
                )

        # exam-sets.yaml → 問題 の方向
        for j, qid in enumerate(get_list(exam_set, "questionIDs")):
            q = question_by_id.get(qid) if isinstance(qid, str) else None
            if q is not None and set_id not in get_list(q.data, "examSets"):
                yield doc.issue(RULE_ID, sev, f"{label}: {qid} の examSets に {set_id} がありません", (*base, "questionIDs", j))

        default = cfg.default_assignments.get(set_id) if isinstance(set_id, int) else None
        if default is not None:
            if frozenset(allowed) != default.case_studies:
                yield doc.issue(
                    RULE_ID, Severity.WARNING,
                    f"{label}: ケース {sorted(allowed)} が既定の割り当て {sorted(default.case_studies)} と異なります",
                    (*base, "caseStudies"),
                )
            if exam_set.get("level") != default.level:
                yield doc.issue(
                    RULE_ID, Severity.WARNING,
                    f"{label}: level '{exam_set.get('level')}' が既定値 '{default.level}' と異なります",
                    (*base, "level"),
                )

    # 問題 → exam-sets.yaml の方向(同じ試験の問題だけ)
    for q in ctx.questions:
        if q.exam_id != exam_id:
            continue
        qid = get_str(q.data, "id")
        for k, set_id in enumerate(get_list(q.data, "examSets")):
            entry = sets_by_id.get(set_id)
            if entry is None:
                yield q.issue(RULE_ID, Severity.ERROR, f"examSets の模試 {set_id} は exam-sets.yaml に定義されていません", ("examSets", k))
                continue
            _, exam_set = entry
            if qid not in get_list(exam_set, "questionIDs"):
                yield q.issue(
                    RULE_ID, status_severity(exam_set),
                    f"examSets に {set_id} がありますが、exam-sets.yaml の模試 {set_id} の questionIDs に {qid} がありません",
                    ("examSets", k),
                )


RULE = Rule(RULE_ID, "模試の構成", check)
