"""manifest のバイト列を Ed25519 で署名する。"""

import base64
import json
from pathlib import Path

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

from contentvalidate.schemas import validator_for
from .files import atomic_write
from .versions import version_key


class SigningError(ValueError):
    """鍵または manifest の不備。CLI は終了コード 2 を返す。"""


def sign_manifest(manifest: Path, key_id: str, key: Ed25519PrivateKey) -> Path:
    raw = manifest.read_bytes()
    try:
        data = json.loads(raw)
    except (ValueError, UnicodeError) as error:
        raise SigningError("manifest をデコードできません") from error
    if not validator_for("manifest").is_valid(data):
        raise SigningError("manifest が Schema に適合しません")
    try:
        version_key(data["packVersion"])
        version_key(data["minAppVersion"])
    except ValueError as error:
        raise SigningError("manifest の版が SemVer ではありません") from error
    if data["keyID"] != key_id:
        raise SigningError("manifest の keyID と --key-id が一致しません")
    signature = base64.b64encode(key.sign(raw))
    target = manifest.with_name("manifest.sig")
    atomic_write(target, signature)
    return target
