"""CI-06: 参照 URL のリンク切れ(--check-links 指定時のみ)。"""

from __future__ import annotations

from collections import defaultdict
from collections.abc import Iterator
from concurrent.futures import ThreadPoolExecutor

import httpx

from ..context import GlobalContext, Rule, walk
from ..model import Issue, JsonPath, Kind, Severity, SourceDoc

RULE_ID = "CI-06"
# URL を持つフィールド名
_URL_KEYS = frozenset({"url", "officialURL"})
_TARGET_KINDS = frozenset({Kind.QUESTION, Kind.CASE, Kind.DOCS})


def collect_urls(ctx: GlobalContext) -> dict[str, list[tuple[SourceDoc, JsonPath]]]:
    found: dict[str, list[tuple[SourceDoc, JsonPath]]] = defaultdict(list)
    for doc in ctx.docs:
        if doc.kind not in _TARGET_KINDS or not doc.schema_ok:
            continue
        for path, value in walk(doc.data):
            if path and path[-1] in _URL_KEYS and isinstance(value, str):
                found[value].append((doc, path))
    return found


def probe(client: httpx.Client, url: str, retry_get_on: frozenset[int]) -> str | None:
    """問題があれば理由を返す。HEAD を送り、指定ステータスなら GET で再試行する。"""
    try:
        response = client.head(url)
        if response.status_code in retry_get_on:
            with client.stream("GET", url) as streamed:
                response = streamed
        if response.status_code >= 400:
            return f"HTTP {response.status_code}"
    except httpx.TimeoutException:
        return "タイムアウト"
    except httpx.HTTPError as e:
        return f"{type(e).__name__}: {e}"
    return None


def check(ctx: GlobalContext) -> Iterator[Issue]:
    if not ctx.check_links:
        return
    cfg = ctx.config.thresholds
    # 同じ URL は、試験をまたいで1回だけ確認し、結果をすべての出現箇所に報告する
    urls = collect_urls(ctx)
    if not urls:
        return
    client = httpx.Client(
        timeout=cfg.link_timeout,
        follow_redirects=True,
        headers={"User-Agent": cfg.link_user_agent},
        transport=ctx.transport,
    )
    with client, ThreadPoolExecutor(max_workers=max(1, cfg.link_concurrency)) as pool:
        ordered = sorted(urls)
        results = pool.map(lambda u: probe(client, u, cfg.link_retry_get_on), ordered)
        for url, reason in zip(ordered, results, strict=True):
            if reason is None:
                continue
            for doc, path in urls[url]:
                yield doc.issue(RULE_ID, Severity.WARNING, f"リンク切れの可能性: {url}({reason})", path)


RULE = Rule(RULE_ID, "リンク切れ", check_global=check)
