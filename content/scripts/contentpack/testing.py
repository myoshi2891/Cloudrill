"""テスト専用の鍵。秘密鍵は生成物に書き出さず、本番では使わない。"""

import hashlib

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey


def test_signing_key(label: str) -> Ed25519PrivateKey:
    seed = hashlib.sha256(("examprep-test-key:" + label).encode("utf-8")).digest()
    return Ed25519PrivateKey.from_private_bytes(seed)
