#!/usr/bin/env python3
"""テスト用 fixture の生成スクリプト。

    python tests/fixtures/generate.py

valid/(全ルールを error・warning ゼロで通過する一式)と、invalid/<ケース名>/(valid への差分 overlay)を
固定 seed で決定論的に再生成する。生成物はコミットし、test_generate.py で生成結果との一致を確認する。

valid は全体のファイル(vendors.yaml)と試験ディレクトリ(exams/test-alpha/)からなる。
試験のファイルは試験ディレクトリからの相対パスで組み立て、書き出すときに ALPHA を前に付ける。

overlay の構成:
    expected.yaml   … 検出されるべきルール ID と深刻度、テストオプション
    _delete.txt     … valid から削除するファイル(任意)
    その他          … valid に追加・上書きするファイル
"""

from __future__ import annotations

import copy
import random
import shutil
from collections.abc import Callable
from pathlib import Path
from typing import Any

import yaml

SEED = 20261020
HERE = Path(__file__).resolve().parent
EXAM_GUIDE_VERSION = "6.1"
# fixture の試験ディレクトリ(valid のルートからの相対)
ALPHA = "exams/test-alpha"

# 問題文・選択肢の生成に使う語彙(すべてダミー)
WORDS = [
    "青銅", "灯台", "山脈", "水路", "鍵盤", "砂丘", "温室", "風車", "望遠鏡", "羅針盤",
    "時計塔", "果樹園", "製本", "陶器", "織機", "帆船", "氷河", "峡谷", "渡り鳥", "蜂蜜",
    "木版画", "石畳", "噴水", "鐘楼", "竹林", "棚田", "宿場", "灯籠", "茶室", "庭園",
    "銀河", "流星", "惑星", "彗星", "星座", "月面", "潮汐", "珊瑚", "海溝", "火山",
    "樹氷", "雪原", "湿原", "草原", "渓流", "滝壺", "洞窟", "鍾乳石", "化石", "琥珀",
    "楽譜", "合唱", "太鼓", "笛吹", "舞台", "劇場", "画廊", "彫刻", "刺繍", "染物",
]
SUB_OBJECTIVES = {
    1: ["1.1", "1.2", "1.3", "1.4", "1.5"],
    2: ["2.1", "2.2", "2.3", "2.4", "2.5"],
    3: ["3.1", "3.2"],
    4: ["4.1", "4.2", "4.3"],
    5: ["5.1", "5.2"],
    6: ["6.1", "6.2", "6.3", "6.4", "6.5", "6.6"],
}
WEIGHTS = {1: 0.25, 2: 0.18, 3: 0.19, 4: 0.15, 5: 0.115, 6: 0.115}
FEATURES = ["caseStudies", "docs", "flashcards", "decisionTrees", "keywordDrills"]
PILLARS = ["operationalExcellence", "security", "reliability", "costOptimization", "performance", "sustainability"]
TAGS = ["cost", "opsOverhead", "compliance", "scalability", "availability", "latency", "requirementMismatch", "deprecated"]
REFERENCE = {"title": "Google Cloud ドキュメント", "url": "https://cloud.google.com/docs", "license": "link-only"}

# 模試 1(complete)の構成
SET1_DOMAINS = {1: 14, 2: 10, 3: 10, 4: 8, 5: 7, 6: 6}
SET1_CASES = ["ehr", "altostrat"]
SET1_CASE_QUESTIONS = 13
SET1_MULTIPLE = 4
SET1_FIVE_CHOICE_SINGLE = 2
SET1_LONGEST_CORRECT = 14  # 14/55 ≒ 25%
# test-alpha の validation.yaml の examSet(gcp-pca と同じ形)
EXAM_SET_POLICY = {
    "domainDistribution": {"1": 14, "2": 10, "3": 10, "4": 8, "5+6": 13},
    "caseQuestions": {"min": 12, "max": 15},
    "defaultAssignments": {
        "1": {"caseStudies": ["ehr", "altostrat"], "level": "basic"},
        "2": {"caseStudies": ["cymbal", "knightMotives"], "level": "basic"},
        "3": {"caseStudies": ["ehr", "cymbal"], "level": "standard"},
        "4": {"caseStudies": ["altostrat", "knightMotives"], "level": "standard"},
        "5": {"caseStudies": ["ehr", "knightMotives"], "level": "advanced"},
        "6": {"caseStudies": ["altostrat", "cymbal"], "level": "advanced"},
    },
}


def stem_text(rng: random.Random) -> str:
    return "【ダミー】" + "・".join(rng.sample(WORDS, 5)) + "に関する設問。"


def choice_text(rng: random.Random, length: int) -> str:
    text = ""
    while len(text) < length:
        text += rng.choice(WORDS)
    return text[:length]


def loc(ja: str, en: str | None) -> dict[str, str]:
    return {"ja": ja, "en": en} if en is not None else {"ja": ja}


def make_question(
    rng: random.Random,
    serial: int,
    domain: int,
    sub: str,
    *,
    correct: list[int],
    n_choices: int = 4,
    longest_correct: bool = False,
    case: str | None = None,
    exam_sets: list[int] | None = None,
    multiple: bool = False,
    stem: str | None = None,
) -> dict[str, Any]:
    """条件を指定してダミー問題を作る。correct は正解の位置(0 始まり)。"""
    qid = f"Q-{sub}-{serial:04d}"
    lengths = sorted(rng.sample(range(12, 32), n_choices))
    longest = lengths.pop()
    wrong = [i for i in range(n_choices) if i not in correct]
    holder = rng.choice(correct) if longest_correct else rng.choice(wrong)
    rng.shuffle(lengths)
    assigned = {holder: longest}
    for i in range(n_choices):
        if i != holder:
            assigned[i] = lengths.pop()

    choices = []
    for i in range(n_choices):
        letter = "abcdef"[i]
        is_correct = i in correct
        choice: dict[str, Any] = {
            "id": letter,
            "text": loc(choice_text(rng, assigned[i]), f"Dummy choice {letter.upper()} of {qid}"),
            "isCorrect": is_correct,
            "rationale": loc(
                f"選択肢{letter.upper()}が{'正しい' if is_correct else '誤り'}理由(ダミー)",
                f"Why choice {letter.upper()} is {'correct' if is_correct else 'incorrect'} (dummy)",
            ),
        }
        if not is_correct:
            choice["mistakeTags"] = [TAGS[(serial + i) % len(TAGS)]]
        choices.append(choice)

    qtype: dict[str, Any] = {"kind": "multiple", "count": len(correct)} if multiple else {"kind": "single"}
    return {
        "id": qid,
        "revision": 1,
        "examGuideVersion": EXAM_GUIDE_VERSION,
        "domain": domain,
        "subObjective": sub,
        "caseStudy": case,
        "type": qtype,
        "difficulty": serial % 5 + 1,
        "wafPillars": [PILLARS[serial % len(PILLARS)]],
        "keywords": ["ダミー", WORDS[serial % len(WORDS)]],
        "examSets": exam_sets if exam_sets is not None else [],
        "stem": loc(stem if stem is not None else stem_text(rng), f"Dummy question stem for {qid}."),
        "choices": choices,
        "references": [dict(REFERENCE)],
    }


def question_path(q: dict[str, Any]) -> str:
    return f"questions/domain{q['domain']}/{q['id']}.yaml"


def build_set1(rng: random.Random) -> list[dict[str, Any]]:
    """complete の模試 1 回分(55 問)。"""
    slots = [(d, SUB_OBJECTIVES[d][k % len(SUB_OBJECTIVES[d])]) for d, n in SET1_DOMAINS.items() for k in range(n)]
    total = len(slots)
    multiple_idx = set(rng.sample(range(total), SET1_MULTIPLE))
    singles = [i for i in range(total) if i not in multiple_idx]
    five_idx = set(rng.sample(singles, SET1_FIVE_CHOICE_SINGLE))
    case_idx = sorted(rng.sample(range(total), SET1_CASE_QUESTIONS))
    case_of = {i: SET1_CASES[k % 2] for k, i in enumerate(case_idx)}
    longest_idx = set(rng.sample(range(total), SET1_LONGEST_CORRECT))

    # 単一選択の正解位置を A〜D にほぼ均等に配る(51 問 → 13/13/13/12)
    positions = [p for p in range(4) for _ in range(len(singles) // 4)]
    positions += list(range(len(singles) - len(positions)))
    rng.shuffle(positions)
    position_of = dict(zip(singles, positions, strict=True))

    questions = []
    for i, (domain, sub) in enumerate(slots):
        serial = i + 1
        if i in multiple_idx:
            q = make_question(
                rng, serial, domain, sub, correct=sorted(rng.sample(range(5), 2)), n_choices=5,
                longest_correct=i in longest_idx, case=case_of.get(i), exam_sets=[1], multiple=True,
            )
        else:
            q = make_question(
                rng, serial, domain, sub, correct=[position_of[i]], n_choices=5 if i in five_idx else 4,
                longest_correct=i in longest_idx, case=case_of.get(i), exam_sets=[1],
            )
        questions.append(q)
    return questions


def build_practice(rng: random.Random) -> list[dict[str, Any]]:
    """練習専用(examSets: [])の問題。"""
    return [
        make_question(rng, 101, 2, "2.2", correct=[1]),
        make_question(rng, 102, 4, "4.1", correct=[2]),
        make_question(rng, 103, 6, "6.2", correct=[0, 3], n_choices=5, multiple=True),
    ]


def build_vendors() -> dict[str, Any]:
    """valid/vendors.yaml。"""
    return {
        "vendors": [
            {
                "id": "google-cloud",
                "name": "Google Cloud",
                "trademarkNotice": loc("ダミーの商標表示", "Dummy trademark notice"),
                "defaultReferenceLicense": "CC-BY-4.0",
            }
        ]
    }


def build_exam_definition() -> dict[str, Any]:
    """test-alpha の exam.yaml。既存の SUB_OBJECTIVES・WEIGHTS・PILLARS と模試 1 の構成から作る。"""
    return {
        "id": "test-alpha",
        "vendor": "google-cloud",
        "name": loc("テスト試験 Alpha", "Test exam Alpha"),
        "shortName": "ALPHA",
        "guideVersion": EXAM_GUIDE_VERSION,
        "guideURL": "https://cloud.google.com/learn/certification/cloud-architect",
        "format": {
            "durationMinutes": 120,
            "officialQuestionCount": {"min": 50, "max": 60},
            "questionKinds": ["single", "multiple"],
            "mockExam": {"questionCount": sum(SET1_DOMAINS.values()), "setCount": 6, "caseStudiesPerSet": len(SET1_CASES)},
        },
        "scoring": {"policy": "allOrNothing"},
        "domains": [
            {
                "id": domain,
                "name": loc(f"ダミーのドメイン {domain}", f"Dummy domain {domain}"),
                "weight": WEIGHTS[domain],
                "subObjectives": [{"id": sub, "name": loc(f"ダミーのサブ項目 {sub}", f"Dummy sub-objective {sub}")} for sub in subs],
            }
            for domain, subs in SUB_OBJECTIVES.items()
        ],
        "features": dict.fromkeys(FEATURES, True),
        "taxonomies": {"wafPillars": [{"id": p, "name": loc(f"ダミーの柱 {p}", f"Dummy pillar {p}")} for p in PILLARS]},
        "caseStudies": list(SET1_CASES),
    }


def build_valid() -> dict[str, Any]:
    """test-alpha の全ファイル(試験ディレクトリからの相対パス → データ。docs は文字列)。"""
    rng = random.Random(SEED)
    set1 = build_set1(rng)
    practice = build_practice(rng)
    files: dict[str, Any] = {question_path(q): q for q in set1 + practice}

    files["exam.yaml"] = build_exam_definition()
    files["validation.yaml"] = {"version": 1, "examSet": copy.deepcopy(EXAM_SET_POLICY)}
    files["exam-sets.yaml"] = {
        "examSets": [
            {"id": 1, "status": "complete", "level": "basic", "caseStudies": list(SET1_CASES), "questionIDs": [q["id"] for q in set1]},
        ]
    }
    files["flashcards/domain1.yaml"] = {
        "cards": [
            {
                "id": "C-1.1-0001", "domain": 1, "subObjective": "1.1",
                "front": loc("ダミーカード 1 の表", "Dummy card 1 front"),
                "back": loc("ダミーカード 1 の裏", "Dummy card 1 back"),
                "relatedQuestionIDs": [set1[0]["id"]],
            },
            {
                "id": "C-1.2-0002", "domain": 1, "subObjective": "1.2",
                "front": loc("ダミーカード 2 の表", "Dummy card 2 front"),
                "back": loc("ダミーカード 2 の裏", "Dummy card 2 back"),
                "relatedQuestionIDs": [],
            },
        ]
    }
    for case_id in SET1_CASES:
        files[f"cases/{case_id}.yaml"] = {
            "id": case_id,
            "name": loc(f"ダミーケース {case_id}", f"Dummy case {case_id}"),
            "summary": loc("ダミーの概要", "Dummy summary"),
            "businessRequirements": [loc("ダミーのビジネス要件", "Dummy business requirement")],
            "technicalRequirements": [loc("ダミーの技術要件", "Dummy technical requirement")],
            "existingEnvironment": loc("ダミーの既存環境", "Dummy existing environment"),
            "officialURL": "https://cloud.google.com/learn/certification/cloud-architect",
            "requirementMappings": [
                {
                    "requirement": loc("ダミーの要件", "Dummy requirement"),
                    "recommendedServices": ["Cloud Run"],
                    "rationale": loc("ダミーの理由", "Dummy rationale"),
                    "rejectedOptions": [{"service": "Compute Engine", "reason": loc("ダミーの不採用理由", "Dummy reason")}],
                }
            ],
        }
    files["decisions/dummy-tree.yaml"] = {
        "id": "dummy-tree",
        "title": loc("ダミーのツリー", "Dummy tree"),
        "rootNodeID": "root",
        "nodes": [
            {
                "id": "root",
                "question": loc("ダミーの質問 1", "Dummy question 1"),
                "options": [
                    {"label": loc("はい", "Yes"), "next": "second"},
                    {"label": loc("いいえ", "No"), "result": {"service": "Cloud Run", "rationale": loc("ダミー", "Dummy")}},
                ],
            },
            {
                "id": "second",
                "question": loc("ダミーの質問 2", "Dummy question 2"),
                "options": [
                    {"label": loc("はい", "Yes"), "result": {"service": "GKE", "rationale": loc("ダミー", "Dummy")}},
                    {"label": loc("いいえ", "No"), "result": {"service": "Compute Engine", "rationale": loc("ダミー", "Dummy")}},
                ],
            },
        ],
    }
    files["drills/keywords.yaml"] = {
        "drills": [
            {
                "id": "K-0001", "phrase": loc("ダミーのフレーズ 1", "Dummy phrase 1"),
                "correct": "Cloud Spanner", "distractor": "Cloud SQL",
                "explanation": loc("ダミーの解説 1", "Dummy explanation 1"),
            },
            {
                "id": "K-0002", "phrase": loc("ダミーのフレーズ 2", "Dummy phrase 2"),
                "correct": "BigQuery", "distractor": "Bigtable",
                "explanation": loc("ダミーの解説 2", "Dummy explanation 2"),
            },
        ]
    }
    files["docs/1.1.md"] = docs_markdown("1.1", "ダミーのドキュメント")
    return files


def docs_markdown(sub: str, title: str) -> str:
    front = dump({"title": title, "subObjective": sub, "references": [dict(REFERENCE)]})
    return f"---\n{front}---\n\n# {title}\n\nダミーの本文です。\n"


# ---- invalid overlay ----------------------------------------------------------


def _set1(valid: dict[str, Any]) -> list[dict[str, Any]]:
    ids = valid["exam-sets.yaml"]["examSets"][0]["questionIDs"]
    by_id = {v["id"]: v for k, v in valid.items() if k.startswith("questions/")}
    return [by_id[i] for i in ids]


def _practice(serial: int, **kwargs: Any) -> dict[str, Any]:
    rng = random.Random(SEED + serial)
    params: dict[str, Any] = {"domain": 2, "sub": "2.1", "correct": [1]}
    params.update(kwargs)
    return make_question(rng, serial, params.pop("domain"), params.pop("sub"), **params)


def _with_question(q: dict[str, Any]) -> dict[str, Any]:
    return {question_path(q): q}


def _relabel(q: dict[str, Any]) -> None:
    for i, c in enumerate(q["choices"]):
        c["id"] = "abcdef"[i]


def ov_ci01_schema(valid: dict[str, Any]) -> dict[str, Any]:
    q = _practice(901)
    q["difficulty"] = 9
    return _with_question(q)


def ov_ci01_domain(valid: dict[str, Any]) -> dict[str, Any]:
    q = _practice(902, domain=2, sub="3.1")
    return _with_question(q)


def ov_ci01_two_correct(valid: dict[str, Any]) -> dict[str, Any]:
    q = _practice(903, correct=[0, 1])
    return _with_question(q)


def ov_ci01_mistake_tags(valid: dict[str, Any]) -> dict[str, Any]:
    q = _practice(904, correct=[0])
    q["choices"][0]["mistakeTags"] = ["cost"]
    del q["choices"][1]["mistakeTags"]
    return _with_question(q)


def ov_ci01_yaml(valid: dict[str, Any]) -> dict[str, Any]:
    return {"questions/domain2/Q-2.1-0905.yaml": "id: Q-2.1-0905\nstem: [unclosed\n"}


def ov_ci01_exam_id(valid: dict[str, Any]) -> dict[str, Any]:
    exam = copy.deepcopy(valid["exam.yaml"])
    exam["id"] = "test-other"
    return {"exam.yaml": exam}


def ov_ci02_case(valid: dict[str, Any]) -> dict[str, Any]:
    """試験にはあるが模試 1 にはないケース(cymbal)の問題を模試 1 に入れる。"""
    exam = copy.deepcopy(valid["exam.yaml"])
    exam["caseStudies"].append("cymbal")
    case = copy.deepcopy(valid["cases/ehr.yaml"])
    case["id"] = "cymbal"
    q = copy.deepcopy(next(q for q in _set1(valid) if q["caseStudy"] == "ehr"))
    q["caseStudy"] = "cymbal"
    return {"exam.yaml": exam, "cases/cymbal.yaml": case, **_with_question(q)}


def ov_ci02_bidirectional(valid: dict[str, Any]) -> dict[str, Any]:
    return _with_question(_practice(906, exam_sets=[1]))


def ov_ci02_draft(valid: dict[str, Any]) -> dict[str, Any]:
    sets = copy.deepcopy(valid["exam-sets.yaml"])
    sets["examSets"][0]["status"] = "draft"
    sets["examSets"][0]["level"] = "standard"
    return {"exam-sets.yaml": sets}


def ov_ci02_cases_per_set(valid: dict[str, Any]) -> dict[str, Any]:
    exam = copy.deepcopy(valid["exam.yaml"])
    exam["format"]["mockExam"]["caseStudiesPerSet"] = 3
    return {"exam.yaml": exam}


def ov_ci02_set_count(valid: dict[str, Any]) -> dict[str, Any]:
    exam = copy.deepcopy(valid["exam.yaml"])
    exam["format"]["mockExam"]["setCount"] = 1
    sets = copy.deepcopy(valid["exam-sets.yaml"])
    sets["examSets"].append(
        {"id": 2, "status": "draft", "level": "basic", "caseStudies": ["cymbal", "knightMotives"], "questionIDs": []}
    )
    return {"exam.yaml": exam, "exam-sets.yaml": sets}


def ov_ci03(valid: dict[str, Any]) -> dict[str, Any]:
    """正解が B の単一選択問題 5 問の正解を A に移す(選択肢ごと入れ替えるので長さの条件は変わらない)。"""
    out: dict[str, Any] = {}
    targets = [q for q in _set1(valid) if q["type"]["kind"] == "single" and q["choices"][1]["isCorrect"]][:5]
    for q in targets:
        q = copy.deepcopy(q)
        q["choices"][0], q["choices"][1] = q["choices"][1], q["choices"][0]
        _relabel(q)
        out.update(_with_question(q))
    return out


def ov_ci04(valid: dict[str, Any]) -> dict[str, Any]:
    """最長でない正解 8 問について、正解と最長の選択肢の文言を入れ替える(位置は変えない)。"""
    out: dict[str, Any] = {}
    count = 0
    for q in _set1(valid):
        if q["type"]["kind"] != "single":
            continue
        texts = [len(c["text"]["ja"]) for c in q["choices"]]
        ci = next(i for i, c in enumerate(q["choices"]) if c["isCorrect"])
        li = texts.index(max(texts))
        if ci == li:
            continue
        q = copy.deepcopy(q)
        q["choices"][ci]["text"], q["choices"][li]["text"] = q["choices"][li]["text"], q["choices"][ci]["text"]
        out.update(_with_question(q))
        count += 1
        if count == 8:
            break
    return out


def ov_ci05_empty(valid: dict[str, Any]) -> dict[str, Any]:
    q = copy.deepcopy(_set1(valid)[0])
    q["choices"][2]["rationale"] = {"ja": "", "en": "Empty in Japanese"}
    return _with_question(q)


def ov_ci05_blank(valid: dict[str, Any]) -> dict[str, Any]:
    q = _practice(907)
    q["choices"][0]["rationale"]["ja"] = "   "
    del q["choices"][3]["rationale"]
    return _with_question(q)


def ov_ci06(valid: dict[str, Any]) -> dict[str, Any]:
    q = _practice(908)
    q["references"] = [{"title": "存在しないページ", "url": "https://broken.invalid/missing", "license": "link-only"}]
    return _with_question(q)


def ov_ci07_question_id(valid: dict[str, Any]) -> dict[str, Any]:
    q = copy.deepcopy(valid["questions/domain2/Q-2.2-0101.yaml"])
    return {"questions/domain2/Q-2.2-0101-copy.yaml": q}


def ov_ci07_card_id(valid: dict[str, Any]) -> dict[str, Any]:
    cards = copy.deepcopy(valid["flashcards/domain1.yaml"])
    cards["cards"] = cards["cards"][:1]
    return {"flashcards/domain1-copy.yaml": cards}


def ov_ci07_similar(valid: dict[str, Any]) -> dict[str, Any]:
    base = valid["questions/domain2/Q-2.2-0101.yaml"]["stem"]["ja"]
    return _with_question(_practice(909, stem=base.replace("設問。", "設問です。")))


def ov_ci08(valid: dict[str, Any]) -> dict[str, Any]:
    q = _practice(910, correct=[0, 1, 2], n_choices=5, multiple=True)
    q["type"]["count"] = 2
    return _with_question(q)


def ov_ci09_related(valid: dict[str, Any]) -> dict[str, Any]:
    cards = copy.deepcopy(valid["flashcards/domain1.yaml"])
    cards["cards"][1]["relatedQuestionIDs"] = ["Q-1.1-9999"]
    return {"flashcards/domain1.yaml": cards}


def ov_ci09_next(valid: dict[str, Any]) -> dict[str, Any]:
    tree = copy.deepcopy(valid["decisions/dummy-tree.yaml"])
    tree["nodes"][0]["options"][0]["next"] = "missing-node"
    return {"decisions/dummy-tree.yaml": tree}


def ov_ci09_docs(valid: dict[str, Any]) -> dict[str, Any]:
    return {"docs/1.1.md": docs_markdown("6.9", "ダミーのドキュメント")}


def ov_ci09_exam_set(valid: dict[str, Any]) -> dict[str, Any]:
    sets = copy.deepcopy(valid["exam-sets.yaml"])
    sets["examSets"].append(
        {"id": 2, "status": "draft", "level": "basic", "caseStudies": ["cymbal", "knightMotives"], "questionIDs": ["Q-1.1-9999"]}
    )
    return {"exam-sets.yaml": sets}


def ov_ci09_unknown_domain(valid: dict[str, Any]) -> dict[str, Any]:
    return _with_question(_practice(912, domain=7))


def ov_ci09_unknown_case_study(valid: dict[str, Any]) -> dict[str, Any]:
    return _with_question(_practice(913, case="acmeBank"))


def ov_ci09_unknown_waf_pillar(valid: dict[str, Any]) -> dict[str, Any]:
    q = _practice(914)
    q["wafPillars"] = ["resilience"]
    return _with_question(q)


def ov_ci10(valid: dict[str, Any]) -> dict[str, Any]:
    exam = copy.deepcopy(valid["exam.yaml"])
    exam["domains"][4]["weight"] = 0.1
    return {"exam.yaml": exam}


def ov_ci11(valid: dict[str, Any]) -> dict[str, Any]:
    q = _practice(911)
    del q["stem"]["en"]
    return _with_question(q)


# (ディレクトリ名, 説明, 期待するルール → 深刻度の一覧, overlay 生成関数, オプション)
INVALID_CASES: list[tuple[str, str, dict[str, list[str]], Callable[[dict[str, Any]], dict[str, Any]], dict[str, Any]]] = [
    ("CI-01-schema-violation", "difficulty が範囲外", {"CI-01": ["error"]}, ov_ci01_schema, {}),
    ("CI-01-domain-mismatch", "subObjective と domain の不一致", {"CI-01": ["error"]}, ov_ci01_domain, {}),
    ("CI-01-single-two-correct", "single なのに正解が 2 つ", {"CI-01": ["error"]}, ov_ci01_two_correct, {}),
    ("CI-01-mistake-tags", "正解に mistakeTags、誤答に mistakeTags なし", {"CI-01": ["error"]}, ov_ci01_mistake_tags, {}),
    ("CI-01-yaml-syntax", "YAML の構文エラー", {"CI-01": ["error"]}, ov_ci01_yaml, {}),
    ("CI-01-exam-id-mismatch", "exam.yaml の id がディレクトリ名と異なる", {"CI-01": ["error"]}, ov_ci01_exam_id, {}),
    ("CI-02-case-mismatch", "模試のケース外の caseStudy", {"CI-02": ["error"]}, ov_ci02_case, {}),
    ("CI-02-bidirectional", "問題の examSets にあるが questionIDs にない", {"CI-02": ["error"]}, ov_ci02_bidirectional, {}),
    ("CI-02-draft-default-level", "draft の模試で既定と異なる level", {"CI-02": ["warning"]}, ov_ci02_draft, {}),
    ("CI-02-case-studies-per-set", "模試のケース数が caseStudiesPerSet と異なる", {"CI-02": ["error"]}, ov_ci02_cases_per_set, {}),
    ("CI-02-set-count", "模試の id が setCount を超える", {"CI-02": ["error", "warning"]}, ov_ci02_set_count, {}),
    ("CI-03-answer-position", "正解位置が A に偏る", {"CI-03": ["error"]}, ov_ci03, {}),
    ("CI-04-longest-choice", "最長の選択肢が正解の割合が 35% 超", {"CI-04": ["error"]}, ov_ci04, {}),
    ("CI-05-empty-rationale", "rationale.ja が空文字", {"CI-05": ["error"]}, ov_ci05_empty, {}),
    ("CI-05-blank-or-missing-rationale", "rationale.ja が空白のみ・rationale なし", {"CI-05": ["error"]}, ov_ci05_blank, {}),
    ("CI-06-broken-link", "参照 URL が 404", {"CI-06": ["warning"]}, ov_ci06, {"checkLinks": True}),
    ("CI-07-duplicate-question-id", "問題 ID の重複(同一内容のため類似警告も出る)", {"CI-07": ["error", "warning"]}, ov_ci07_question_id, {}),
    ("CI-07-duplicate-card-id", "カード ID の重複", {"CI-07": ["error"]}, ov_ci07_card_id, {}),
    ("CI-07-similar-stem", "問題文がほぼ同一", {"CI-07": ["warning"]}, ov_ci07_similar, {}),
    ("CI-08-count-mismatch", "count 2 に対して正解 3", {"CI-08": ["error"]}, ov_ci08, {}),
    ("CI-09-related-question", "カードの relatedQuestionIDs が存在しない", {"CI-09": ["error"]}, ov_ci09_related, {}),
    ("CI-09-decision-next", "ツリーの next が存在しない", {"CI-09": ["error"]}, ov_ci09_next, {}),
    ("CI-09-docs-sub-objective", "docs の subObjective が一覧にない", {"CI-09": ["error"]}, ov_ci09_docs, {}),
    (
        "CI-09-exam-set-question",
        "questionIDs が存在しない(draft の模試のため CI-02 の warning も出る)",
        {"CI-09": ["error"], "CI-02": ["warning"]},
        ov_ci09_exam_set,
        {},
    ),
    ("CI-09-unknown-domain", "exam.yaml にないドメイン 7 の問題", {"CI-09": ["error"]}, ov_ci09_unknown_domain, {}),
    ("CI-09-unknown-case-study", "exam.yaml にないケース acmeBank の問題", {"CI-09": ["error"]}, ov_ci09_unknown_case_study, {}),
    ("CI-09-unknown-waf-pillar", "exam.yaml にない WAF の柱 resilience の問題", {"CI-09": ["error"]}, ov_ci09_unknown_waf_pillar, {}),
    ("CI-10-weights-sum", "exam.yaml の比重の合計が 0.985", {"CI-10": ["error"]}, ov_ci10, {}),
    ("CI-11-missing-en", "stem.en の欠落", {"CI-11": ["warning"]}, ov_ci11, {}),
]


# ---- 書き出し -----------------------------------------------------------------


def dump(data: Any) -> str:
    return yaml.safe_dump(data, allow_unicode=True, sort_keys=False, width=1000, default_flow_style=False)


def write_tree(base: Path, files: dict[str, Any]) -> None:
    for rel, data in sorted(files.items()):
        path = base / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(data if isinstance(data, str) else dump(data), encoding="utf-8")


def in_exam(exam_dir: str, files: dict[str, Any]) -> dict[str, Any]:
    """試験ディレクトリからの相対パスを、valid のルートからの相対パスにする。"""
    return {f"{exam_dir}/{rel}": data for rel, data in files.items()}


def generate(out: Path = HERE) -> None:
    valid = build_valid()
    for name in ("valid", "invalid"):
        shutil.rmtree(out / name, ignore_errors=True)
    write_tree(out / "valid", {"vendors.yaml": build_vendors(), **in_exam(ALPHA, valid)})
    for name, description, expect, overlay, options in INVALID_CASES:
        files = in_exam(ALPHA, overlay(valid))
        files["expected.yaml"] = {"description": description, "expect": expect, "options": options}
        write_tree(out / "invalid" / name, files)


if __name__ == "__main__":
    generate()
    print(f"generated: {HERE / 'valid'}, {HERE / 'invalid'}")
