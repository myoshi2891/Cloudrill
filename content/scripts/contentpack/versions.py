"""SemVer 2.0.0 の優先順位。build metadata は比較に含めない。"""

import re

from contentvalidate.schemas import registry, schema_uri

_SEMVER = re.compile(registry().contents(schema_uri("common"))["$defs"]["SemVer"]["pattern"])


def version_key(value: str) -> tuple:
    if not _SEMVER.fullmatch(value):
        raise ValueError(f"SemVer ではありません: {value}")
    version, plus, metadata = value.partition("+")
    core, separator, prerelease = version.partition("-")
    if plus and any(not part for part in metadata.split(".")):
        raise ValueError(f"SemVer の build metadata が不正です: {value}")
    if separator and any(not part or (part.isdecimal() and len(part) > 1 and part.startswith("0")) for part in prerelease.split(".")):
        raise ValueError(f"SemVer の prerelease が不正です: {value}")
    identifiers = tuple((0, int(part)) if part.isdecimal() else (1, part) for part in prerelease.split(".")) if separator else ()
    return (*map(int, core.split(".")), not separator, identifiers)
