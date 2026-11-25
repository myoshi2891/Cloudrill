"""公開アドレスにだけ接続する httpx の transport(CI-06 用)。"""

from __future__ import annotations

import ipaddress
import socket

import httpx

_NAT64 = ipaddress.IPv6Network("64:ff9b::/96")


class NonPublicAddressError(httpx.RequestError):
    """宛先が公開されていないアドレスなので、要求を送らなかった。"""


def resolve_host(host: str, port: int) -> list[str]:
    """ホストの全アドレスを、重複を除いて名前解決の順で返す。"""
    infos = socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)
    return list(dict.fromkeys(str(info[4][0]) for info in infos))


def is_public(address: str) -> bool:
    ip = ipaddress.ip_address(address)
    if isinstance(ip, ipaddress.IPv6Address):
        # IPv4 を埋め込む形式は、実際の宛先になる IPv4 で判断する
        embedded = ip.ipv4_mapped or ip.sixtofour
        if embedded is None and ip in _NAT64:
            embedded = ipaddress.IPv4Address(int(ip) & 0xFFFFFFFF)
        if embedded is not None:
            return is_public(str(embedded))
        if ip.is_site_local:
            return False
    return ip.is_global and not (ip.is_multicast or ip.is_reserved)


class PublicOnlyTransport(httpx.BaseTransport):
    """名前解決の結果がすべて公開アドレスの場合だけ、確認したアドレスに接続する。

    確認後の再解決で別のアドレスに接続しないよう、URL のホストを IP に置き換える。
    Host ヘッダーと SNI(証明書の検証)には元のホスト名を使う。
    """

    def __init__(self, inner: httpx.BaseTransport) -> None:
        self._inner = inner

    def handle_request(self, request: httpx.Request) -> httpx.Response:
        host = request.url.raw_host.decode("ascii")
        port = request.url.port or (443 if request.url.scheme == "https" else 80)
        try:
            addresses = resolve_host(host, port)
        except (OSError, UnicodeError) as e:
            raise httpx.ConnectError(f"名前解決に失敗しました: {e}", request=request) from e
        # 公開と非公開が混ざる名前も拒否する
        if not all(is_public(a) for a in addresses):
            raise NonPublicAddressError("公開されていないアドレスです", request=request)
        failure: httpx.ConnectError | httpx.ConnectTimeout | None = None
        for address in addresses:
            pinned = httpx.Request(
                request.method,
                request.url.copy_with(host=address),
                headers=request.headers,
                stream=request.stream,
                extensions={**request.extensions, "sni_hostname": host},
            )
            try:
                return self._inner.handle_request(pinned)
            except (httpx.ConnectError, httpx.ConnectTimeout) as e:
                failure = e  # 接続できなければ次のアドレス(IPv6 が使えない環境など)を試す
        raise failure or httpx.ConnectError("アドレスがありません", request=request)

    def close(self) -> None:
        self._inner.close()
