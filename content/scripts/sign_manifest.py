#!/usr/bin/env python3
"""manifest.json のバイト列に署名する。成功 0 / 引数・入力・I/O の不備 2。"""

import argparse
import base64
import os
import sys
from pathlib import Path

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

from contentpack.sign import SigningError, sign_manifest
from contentpack.testing import test_signing_key


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="パックの manifest に Ed25519 署名を付ける")
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--key-id", required=True)
    keys = parser.add_mutually_exclusive_group(required=True)
    keys.add_argument("--key-env", help="32 バイトの seed(Base64)を含む環境変数の名前")
    keys.add_argument("--test-key", help="テスト専用の決定論的な鍵の label")
    args = parser.parse_args(argv)
    try:
        if args.key_env is not None:
            try:
                seed = base64.b64decode(os.environ.get(args.key_env, ""), validate=True)
                key = Ed25519PrivateKey.from_private_bytes(seed)
            except ValueError:
                # seed や環境変数の値をエラーに含めない。
                raise SigningError("--key-env には32バイトの seed を Base64 で設定してください") from None
        else:
            key = test_signing_key(args.test_key)
        sign_manifest(args.manifest, args.key_id, key)
    except (SigningError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
