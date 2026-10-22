"""CI-02: 模試の構成(問題数・ドメイン配分・ケース問題・双方向の一致・既定の割り当て)。"""

from __future__ import annotations

from collections import Counter
from collections.abc import Iterator
from typing import Any

from ..context import ExamContext, Rule, set_questions, status_severity
from ..model import Issue, Severity, SourceDoc, get_list, get_str

RULE_ID = "CI-02"


def check(ctx: ExamContext) -> Iterator[Issue]:
    for doc, exam_sets in ctx.exam_sets:
        yield from _check_exam(ctx, doc, exam_sets)


def _check_exam(ctx: ExamContext, doc: SourceDoc, exam_sets: list[tuple[int, dict[str, Any]]]) -> Iterator[Issue]:
    # 試験ごとの validation.yaml に examSet がなければ、配分・ケース問題数・既定の割り当ての確認を省略する
    policy = ctx.config.exam_set_policy
    # exam.yaml が Schema 違反なら、exam.yaml の値を使う確認を省略する
    definition = ctx.definition
    question_by_id = ctx.question_by_id
    sets_by_id = {s.get("id"): (i, s) for i, s in exam_sets}
    question_count = definition.mock_question_count if definition is not None else None
    per_set = definition.case_studies_per_set if definition is not None else None
    set_count = definition.mock_set_count if definition is not None else None
    # ケースがない試験(caseStudiesPerSet: 0)ではケース問題も 0 問
    case_range = (0, 0) if per_set == 0 else (policy.case_min, policy.case_max) if policy is not None else None

    for i, exam_set in exam_sets:
        set_id = exam_set.get("id")
        sev = status_severity(exam_set)
        base = ("examSets", i)
        label = f"模試 {set_id}({exam_set.get('status')})"
        questions = set_questions(ctx, exam_set)

        if set_count is not None and isinstance(set_id, int) and set_id > set_count:
            yield doc.issue(
                RULE_ID, Severity.ERROR,
                f"{label}: id が exam.yaml の setCount({set_count})を超えています",
                (*base, "id"),
            )

        if question_count is not None and len(questions) != question_count:
            yield doc.issue(RULE_ID, sev, f"{label}: 問題数が {len(questions)} です(期待値 {question_count})", (*base, "questionIDs"))

        by_domain = Counter(q.data.get("domain") for q in questions)
        for domains, expected in policy.domain_distribution if policy is not None else ():
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
        if case_range is not None and not case_range[0] <= len(case_questions) <= case_range[1]:
            yield doc.issue(
                RULE_ID, sev,
                f"{label}: ケース問題数が {len(case_questions)} です(期待範囲 {case_range[0]}〜{case_range[1]})",
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

        default = policy.default_assignments.get(set_id) if policy is not None and isinstance(set_id, int) else None
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

    # 問題 → exam-sets.yaml の方向
    for q in ctx.questions:
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
