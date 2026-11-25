"""公開アドレスだけに接続する transport と、CI-06 のリダイレクトの扱い(SEC-05-10)。"""

from __future__ import annotations

import socket
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import httpx
import pytest
from conftest import VALID
from contentvalidate import public_transport
from contentvalidate.config import GlobalConfig
from contentvalidate.engine import run
from contentvalidate.public_transport import NonPublicAddressError, PublicOnlyTransport, is_public
from contentvalidate.rules.ci06_links import probe

URL = "https://example.com/page"
PUBLIC = "93.184.216.34"
PUBLIC6 = "2606:4700::1111"


def client_for(handler, **kwargs) -> httpx.Client:
    return httpx.Client(transport=PublicOnlyTransport(httpx.MockTransport(handler)), trust_env=False, **kwargs)


def resolve_to(monkeypatch, *addresses: str) -> None:
    monkeypatch.setattr(public_transport, "resolve_host", lambda host, port: list(addresses))


@pytest.mark.parametrize("address", [
    "127.0.0.1", "10.0.0.1", "172.16.0.1", "192.168.0.1", "100.64.0.1", "169.254.169.254", "0.0.0.0",
    "224.0.1.1", "240.0.0.1", "255.255.255.255", "::", "::1", "fe80::1", "fe80::1%en0", "fc00::1", "fec0::1",
    "ff0e::1", "::ffff:127.0.0.1", "64:ff9b::a00:1", "2002:a00:1::", "2001:db8::1",
])
def test_non_public_is_rejected_before_sending(monkeypatch, address):
    sent = []
    # 公開アドレスが混ざっていても拒否する
    resolve_to(monkeypatch, PUBLIC, address)
    assert not is_public(address)
    with client_for(lambda r: sent.append(r) or httpx.Response(200)) as client:
        for method in ("HEAD", "GET"):
            with pytest.raises(NonPublicAddressError):
                client.request(method, URL)
        assert probe(client, URL, frozenset({405})) == "公開されていないアドレスです"
    assert sent == []


@pytest.mark.parametrize("address", [PUBLIC, PUBLIC6, "::ffff:8.8.8.8", "64:ff9b::808:808"])
def test_public_addresses(address):
    assert is_public(address)


@pytest.mark.parametrize("host", ["127.0.0.1", "[::1]", "2130706433"])
def test_ip_literals_use_real_resolution(monkeypatch, host):
    monkeypatch.undo()  # conftest の差し替えを外し、実際の getaddrinfo を使う
    with client_for(lambda r: pytest.fail("送信してはいけない")) as client, pytest.raises(NonPublicAddressError):
        client.head(f"https://{host}/")


@pytest.mark.parametrize("address", [PUBLIC, PUBLIC6])
def test_connects_to_checked_address_with_original_host(monkeypatch, address):
    sent = []
    resolve_to(monkeypatch, address)
    with client_for(lambda r: sent.append(r) or httpx.Response(200)) as client:
        assert probe(client, URL, frozenset()) is None
    assert sent[0].url.host == address
    assert sent[0].headers["host"] == "example.com"
    assert sent[0].extensions["sni_hostname"] == "example.com"


def test_connection_is_not_reused_for_another_host(monkeypatch):
    # Arrange: 同じ IP の別ホスト。keep-alive が有効な実際のプールを使う
    peers = []

    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def do_HEAD(self):
            peers.append((self.headers["Host"], self.client_address))
            self.send_response(200)
            self.send_header("Content-Length", "0")
            self.end_headers()

        def log_message(self, *args):
            pass

    resolve_to(monkeypatch, "127.0.0.1")
    monkeypatch.setattr(public_transport, "is_public", lambda address: True)
    with ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
        threading.Thread(target=server.serve_forever, daemon=True).start()
        port = server.server_address[1]
        hosts = [f"a.example:{port}", f"b.example:{port}", f"a.example:{port}"]
        # Act
        try:
            with httpx.Client(transport=PublicOnlyTransport(httpx.HTTPTransport()), trust_env=False) as client:
                for host in hosts:
                    assert probe(client, f"http://{host}/", frozenset()) is None
        finally:
            server.shutdown()
    # Assert: 要求ごとに別の接続になる
    assert [host for host, _ in peers] == hosts
    assert len({address for _, address in peers}) == len(hosts)


def test_falls_back_to_next_address(monkeypatch):
    resolve_to(monkeypatch, PUBLIC6, PUBLIC)

    def handler(request):
        if request.url.host == PUBLIC6:
            raise httpx.ConnectError("unreachable", request=request)
        return httpx.Response(200)

    with client_for(handler) as client:
        assert probe(client, URL, frozenset()) is None


def test_get_retry_is_resolved_and_checked_again(monkeypatch):
    answers = iter([[PUBLIC], ["127.0.0.1"]])
    monkeypatch.setattr(public_transport, "resolve_host", lambda host, port: next(answers))
    methods = []
    with client_for(lambda r: methods.append(r.method) or httpx.Response(405)) as client:
        assert probe(client, URL, frozenset({405})) == "公開されていないアドレスです"
    assert methods == ["HEAD"]


@pytest.mark.parametrize("error", [socket.gaierror("unknown"), UnicodeError("label too long")])
def test_resolution_failure_is_reported(monkeypatch, error):
    def fail(host, port):
        raise error

    monkeypatch.setattr(public_transport, "resolve_host", fail)
    with client_for(lambda r: httpx.Response(200)) as client:
        assert "ConnectError" in (probe(client, URL, frozenset()) or "")


@pytest.mark.parametrize("status", [301, 302, 303, 307, 308])
@pytest.mark.parametrize("via_get", [False, True])
@pytest.mark.parametrize("location", ["https://other.example/", "https://127.0.0.1/"])
def test_rule_reports_redirect_without_following(
    config: GlobalConfig, monkeypatch, status, via_get, location
):
    # プロキシの環境変数があっても、渡した transport を通る
    monkeypatch.setenv("HTTPS_PROXY", "http://127.0.0.1:9")
    sent = []

    def handler(request):
        sent.append(request)
        if via_get and request.method == "HEAD":
            return httpx.Response(405)
        return httpx.Response(status, headers={"location": location})

    issues = run(VALID, config, only={"CI-06"}, check_links=True, transport=httpx.MockTransport(handler))
    assert issues
    assert sent
    assert all(i.rule == "CI-06" and f"HTTP {status}: リダイレクト" in i.message for i in issues)
    assert not {r.headers["host"] for r in sent} & {"other.example", "127.0.0.1"}
