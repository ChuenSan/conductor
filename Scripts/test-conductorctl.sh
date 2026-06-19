#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CODEXBAR_AUDIT_PATH="${CODEXBAR_AUDIT_PATH:-/tmp/codexbar-audit}"
if [[ -e "$CODEXBAR_AUDIT_PATH" ]]; then
    python3 Scripts/audit-codexbar-providers.py --codexbar "$CODEXBAR_AUDIT_PATH"
    python3 Scripts/audit-codexbar-pricing.py --codexbar "$CODEXBAR_AUDIT_PATH"
else
    echo "codexbar provider/pricing audits skipped: $CODEXBAR_AUDIT_PATH not found"
fi
python3 Scripts/audit-provider-settings-ui.py

swift build --product conductorctl

python3 - <<'PY'
import http.client
import http.server
import base64
import datetime
import json
import os
import socket
import sqlite3
import ssl
import subprocess
import tempfile
import threading
import time

ROOT = os.getcwd()
BIN = os.path.join(ROOT, ".build/debug/conductorctl")


def make_fake_id_token(email):
    def encode_urlsafe(value):
        return base64.urlsafe_b64encode(
            json.dumps(value, separators=(",", ":")).encode()
        ).rstrip(b"=").decode()

    return ".".join([
        encode_urlsafe({"alg": "none"}),
        encode_urlsafe({"email": email}),
        "signature",
    ])


def response(req, result):
    return json.dumps(
        {"id": req.get("id"), "ok": True, "result": result},
        separators=(",", ":"),
    ).encode() + b"\n"


def error_response(req, code, message):
    return json.dumps(
        {"id": req.get("id"), "ok": False, "error": {"code": code, "message": message}},
        separators=(",", ":"),
    ).encode() + b"\n"


class FakeAppSocket:
    def __init__(self, name, expected, handler):
        self.path = f"/tmp/{name}-{os.getpid()}-{id(self)}.sock"
        self.expected = expected
        self.handler = handler
        self.ready = threading.Event()
        self.errors = []
        self.requests = []
        try:
            os.unlink(self.path)
        except FileNotFoundError:
            pass
        self.thread = threading.Thread(target=self._run, daemon=True)

    def __enter__(self):
        self.thread.start()
        if not self.ready.wait(2):
            raise RuntimeError("fake app socket did not start")
        return self

    def __exit__(self, exc_type, exc, tb):
        deadline = time.time() + 2
        while self.thread.is_alive() and time.time() < deadline:
            time.sleep(0.02)
        try:
            os.unlink(self.path)
        except FileNotFoundError:
            pass
        if self.errors and exc_type is None:
            raise AssertionError(self.errors)

    def _run(self):
        srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            srv.bind(self.path)
            srv.listen(16)
            self.ready.set()
            while len(self.requests) < self.expected:
                conn, _ = srv.accept()
                with conn:
                    data = b""
                    while not data.endswith(b"\n"):
                        chunk = conn.recv(4096)
                        if not chunk:
                            break
                        data += chunk
                    req = json.loads(data.decode())
                    self.requests.append(req)
                    conn.sendall(self.handler(req, len(self.requests)))
        except Exception as exc:
            self.errors.append(repr(exc))
        finally:
            srv.close()
            try:
                os.unlink(self.path)
            except FileNotFoundError:
                pass


def run_cli(args, app, *, input_text=None, timeout=5):
    env = os.environ.copy()
    env["CONDUCTOR_SOCKET_PATH"] = app.path
    proc = subprocess.run(
        [BIN] + args,
        cwd=ROOT,
        env=env,
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
    )
    if proc.returncode != 0:
        raise AssertionError(f"{args} failed: {proc.stderr}")
    return proc.stdout


def run_cli_first_line(args, app, *, timeout=5):
    env = os.environ.copy()
    env["CONDUCTOR_SOCKET_PATH"] = app.path
    proc = subprocess.Popen(
        [BIN] + args,
        cwd=ROOT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    try:
        deadline = time.time() + timeout
        line = ""
        while time.time() < deadline:
            line = proc.stdout.readline()
            if line:
                return line
        stderr = proc.stderr.read() if proc.stderr else ""
        raise AssertionError(f"{args} emitted no line; stderr={stderr}")
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=2)


def free_port():
    probe = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    probe.bind(("127.0.0.1", 0))
    port = probe.getsockname()[1]
    probe.close()
    return port


def wait_port(port):
    deadline = time.time() + 5
    while True:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                return
        except OSError:
            if time.time() > deadline:
                raise RuntimeError("bridge did not listen in time")
            time.sleep(0.05)


def test_run_wait():
    status_calls = {"count": 0}

    def handler(req, _count):
        method = req["method"]
        if method == "agent.run":
            return response(req, {"pane": "p-wait", "jobId": "p-wait", "agent": "codex"})
        if method == "agent.status":
            status_calls["count"] += 1
            status = "running" if status_calls["count"] == 1 else "completed"
            return response(req, {"jobId": "p-wait", "pane": "p-wait", "agent": "codex", "status": status})
        if method == "agent.result":
            return response(req, {
                "jobId": "p-wait",
                "pane": "p-wait",
                "agent": "codex",
                "status": "completed",
                "summary": "done",
                "markdown": "done markdown",
            })
        return error_response(req, "unexpected", method)

    with FakeAppSocket("conductorctl-run-wait", 4, handler) as app:
        out = run_cli(["run", "codex", "--prompt", "hello", "--wait", "--poll", "0.25", "--timeout", "3", "--json"], app)
        payload = json.loads(out)
        assert payload["markdown"] == "done markdown", payload
        assert [req["method"] for req in app.requests] == [
            "agent.run", "agent.status", "agent.status", "agent.result"
        ]


def test_stdin_and_batch():
    def handler(req, _count):
        method = req["method"]
        params = req.get("params") or {}
        if method == "agent.run":
            assert params["prompt"] == "prompt from stdin\n", params
            return response(req, {"pane": "p-stdin", "jobId": "p-stdin", "agent": "codex"})
        if method == "agent.send":
            assert params["text"] == "send from stdin\n", params
            return response(req, True)
        if method == "app.ping":
            return response(req, {"pong": True})
        if method == "missing.method":
            return error_response(req, "unknown-method", "nope")
        return error_response(req, "unexpected", method)

    with FakeAppSocket("conductorctl-stdin-batch", 4, handler) as app:
        run_cli(["run", "codex", "--stdin", "--json"], app, input_text="prompt from stdin\n")
        run_cli(["send", "--stdin"], app, input_text="send from stdin\n")
        batch = '{"id":1,"method":"app.ping"}\n{"id":2,"method":"missing.method"}\n'
        out = run_cli(["batch"], app, input_text=batch)
        lines = [json.loads(line) for line in out.splitlines() if line.strip()]
        assert lines[0]["ok"] is True, lines
        assert lines[1]["error"]["code"] == "unknown-method", lines


def test_bridge_http():
    def handler(req, _count):
        method = req["method"]
        if method == "app.methods":
            return response(req, ["app.ping", "agent.run"])
        if method == "app.ping":
            return response(req, {"pong": True})
        if method == "missing.method":
            return error_response(req, "unknown-method", "nope")
        if method == "events.recent":
            params = req.get("params") or {}
            assert params.get("limit") == 7, params
            return response(req, [{"id": "evt-1", "type": "agent.completed", "payload": {"message": "hello"}}])
        return error_response(req, "unexpected", method)

    with FakeAppSocket("conductorctl-bridge", 4, handler) as app:
        port = free_port()
        env = os.environ.copy()
        env["CONDUCTOR_SOCKET_PATH"] = app.path
        bridge = subprocess.Popen(
            [BIN, "bridge", "--host", "127.0.0.1", "--port", str(port), "--interval", "0.25"],
            cwd=ROOT,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        try:
            wait_port(port)

            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("OPTIONS", "/rpc", headers={"Origin": "http://localhost:3000"})
            resp = conn.getresponse()
            assert resp.status == 204, resp.status
            assert resp.getheader("Access-Control-Allow-Origin") == "*", resp.getheaders()
            assert resp.read() == b""

            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("GET", "/methods")
            resp = conn.getresponse()
            methods = json.loads(resp.read().decode())
            assert methods["result"] == ["app.ping", "agent.run"], methods

            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("GET", "/openapi.json")
            resp = conn.getresponse()
            spec = json.loads(resp.read().decode())
            assert spec["openapi"] == "3.1.0", spec
            assert "/batch" in spec["paths"], spec["paths"]

            body = '{"id":21,"method":"app.ping"}\n{"id":22,"method":"missing.method"}\n'
            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("POST", "/batch", body=body.encode(), headers={"Content-Type": "application/x-ndjson"})
            resp = conn.getresponse()
            lines = [json.loads(line) for line in resp.read().decode().splitlines() if line.strip()]
            assert lines[0]["result"]["pong"] is True, lines
            assert lines[1]["error"]["code"] == "unknown-method", lines

            sock = socket.create_connection(("127.0.0.1", port), timeout=5)
            sock.sendall(
                b"GET /events?limit=7&interval=0.25 HTTP/1.1\r\n"
                b"Host: 127.0.0.1\r\n"
                b"Accept: text/event-stream\r\n\r\n"
            )
            data = b""
            deadline = time.time() + 5
            while b"\n\n" not in data:
                if time.time() > deadline:
                    raise AssertionError("timed out waiting for SSE")
                data += sock.recv(4096)
            text = data.decode(errors="replace")
            assert "Content-Type: text/event-stream\r\n" in text, text
            assert "id: evt-1\n" in text, text
            sock.close()
        finally:
            bridge.terminate()
            try:
                bridge.wait(timeout=3)
            except subprocess.TimeoutExpired:
                bridge.kill()
                bridge.wait(timeout=3)


def test_usage_server_config_validate():
    with tempfile.TemporaryDirectory(prefix="conductorctl-serve-config-") as tmpdir:
        config_path = os.path.join(tmpdir, "config.yaml")
        with open(config_path, "w", encoding="utf-8") as handle:
            handle.write(
                """
usage:
  providers:
    openai:
      sourceMode: oauth
""".lstrip()
            )

        port = free_port()
        env = os.environ.copy()
        env["CONDUCTOR_CONFIG_PATH"] = config_path
        home = os.path.join(tmpdir, "home")
        os.makedirs(home, exist_ok=True)
        codex_home = os.path.join(home, ".codex")
        os.makedirs(os.path.join(codex_home, "sessions"), exist_ok=True)
        os.makedirs(os.path.join(codex_home, "cache"), exist_ok=True)
        os.makedirs(os.path.join(codex_home, "logs"), exist_ok=True)
        with open(os.path.join(codex_home, "sessions", "session.jsonl"), "wb") as handle:
            handle.write(b"codex-session-storage")
        with open(os.path.join(codex_home, "cache", "blob.bin"), "wb") as handle:
            handle.write(b"cache-storage")
        with open(os.path.join(codex_home, "logs", "debug.log"), "wb") as handle:
            handle.write(b"log-storage")
        env["HOME"] = home
        env["CFFIXED_USER_HOME"] = home
        env["CONDUCTOR_USAGE_ABACUS_COOKIE"] = "sessionid=manual"
        server = subprocess.Popen(
            [
                BIN,
                "serve",
                "--port",
                str(port),
                "--request-timeout",
                "2",
                "--refresh-interval",
                "0",
            ],
            cwd=ROOT,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        try:
            wait_port(port)

            def raw_usage_request(raw):
                with socket.create_connection(("127.0.0.1", port), timeout=5) as sock:
                    sock.sendall(raw)
                    chunks = []
                    while True:
                        chunk = sock.recv(4096)
                        if not chunk:
                            break
                        chunks.append(chunk)
                return b"".join(chunks).decode(errors="replace")

            raw = raw_usage_request(b"GET /health HTTP/1.1\r\nHost: example.com\r\n\r\n")
            assert raw.startswith("HTTP/1.1 403 Forbidden"), raw
            assert '"error":"forbidden host"' in raw, raw

            raw = raw_usage_request(b"GET /health HTTP/1.1\r\n\r\n")
            assert raw.startswith("HTTP/1.1 400 Bad Request"), raw
            assert '"error":"invalid request"' in raw, raw

            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("OPTIONS", "/cache/clear", headers={"Origin": "http://localhost:3000"})
            resp = conn.getresponse()
            assert resp.status == 204, resp.status
            assert resp.getheader("Access-Control-Allow-Origin") == "*", resp.getheaders()
            assert "POST" in resp.getheader("Access-Control-Allow-Methods"), resp.getheaders()
            assert resp.read() == b""

            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("GET", "/openapi.json")
            resp = conn.getresponse()
            spec = json.loads(resp.read().decode())
            assert resp.status == 200, spec
            assert "/health" in spec["paths"], spec["paths"]
            assert "/config/validate" in spec["paths"], spec["paths"]
            assert "/config/dump" in spec["paths"], spec["paths"]
            assert "/config/accounts" in spec["paths"], spec["paths"]
            assert "/config/account" in spec["paths"], spec["paths"]
            assert "/config/provider" in spec["paths"], spec["paths"]
            assert "/config/order" in spec["paths"], spec["paths"]
            assert "/cache/clear" in spec["paths"], spec["paths"]
            usage_responses = spec["paths"]["/usage"]["get"]["responses"]
            assert "499" in usage_responses, usage_responses
            error_schema = usage_responses["400"]["content"]["application/json"]["schema"]
            assert error_schema["properties"]["error"]["type"] == "string", error_schema
            for path in [
                "/usage",
                "/diagnose",
                "/storage",
                "/provider-status",
                "/config/providers",
            ]:
                responses = spec["paths"][path]["get"]["responses"]
                assert "400" in responses, (path, responses)
                schema = responses["400"]["content"]["application/json"]["schema"]
                assert schema["properties"]["error"]["type"] == "string", (path, schema)
                params = spec["paths"][path]["get"]["parameters"]
                provider_param = next(item for item in params if item["name"] == "provider")
                assert "IDs/aliases" in provider_param["description"], (path, provider_param)
            cost_params = spec["paths"]["/cost"]["get"]["parameters"]
            cost_provider_param = next(item for item in cost_params if item["name"] == "provider")
            assert "all, both, codex, claude, vertexai, or bedrock" in cost_provider_param["description"], cost_provider_param
            usage_200_schema = usage_responses["200"]["content"]["application/json"]["schema"]
            assert usage_200_schema["items"]["properties"]["provider"]["description"] == "Canonical provider ID", usage_200_schema
            for path in ["/diagnose", "/storage", "/provider-status", "/config/providers", "/config/validate"]:
                response_schema = spec["paths"][path]["get"]["responses"]["200"]["content"]["application/json"]["schema"]
                provider_schema = response_schema["items"]["properties"]["provider"]
                assert provider_schema["description"] == "Canonical provider ID", (path, provider_schema)
            config_accounts_response_schema = (
                spec["paths"]["/config/accounts"]["get"]["responses"]["200"]["content"]["application/json"]["schema"]
            )
            assert config_accounts_response_schema["properties"]["provider"]["description"] == "Canonical provider ID", config_accounts_response_schema
            for path in ["/config/account", "/config/provider"]:
                response_schema = spec["paths"][path]["post"]["responses"]["200"]["content"]["application/json"]["schema"]
                provider_schema = response_schema["properties"]["provider"]
                assert provider_schema["description"] == "Canonical provider ID", (path, provider_schema)
            cache_clear_response_schema = spec["paths"]["/cache/clear"]["post"]["responses"]["200"]["content"]["application/json"]["schema"]
            assert cache_clear_response_schema["items"]["properties"]["provider"]["description"] == "Canonical provider ID", cache_clear_response_schema
            assert "post" in spec["paths"]["/config/account"], spec["paths"]["/config/account"]
            assert "post" in spec["paths"]["/config/provider"], spec["paths"]["/config/provider"]
            provider_schema = (
                spec["paths"]["/config/provider"]["post"]["requestBody"]["content"]["application/json"]["schema"]["properties"]
            )
            assert "ID or alias" in provider_schema["provider"]["description"], provider_schema["provider"]
            for key in [
                "api-key",
                "token",
                "cookieHeader",
                "cookie-header",
                "session",
                "field",
                "configKey",
                "config-key",
                "sourceMode",
                "source-mode",
                "baseURL",
                "base-url",
                "projectID",
                "organizationID",
                "cookieSource",
                "cookie-source",
                "no-enable",
            ]:
                assert key in provider_schema, provider_schema
            assert "post" in spec["paths"]["/config/order"], spec["paths"]["/config/order"]
            order_schema = (
                spec["paths"]["/config/order"]["post"]["requestBody"]["content"]["application/json"]["schema"]["properties"]
            )
            for key in ["providers", "providerOrder", "provider-order"]:
                assert key in order_schema, order_schema
                assert "IDs/aliases" in order_schema[key]["description"], order_schema[key]
                variants = order_schema[key]["oneOf"]
                assert any(item.get("type") == "array" for item in variants), order_schema[key]
                assert any(item.get("type") == "string" for item in variants), order_schema[key]
            assert "post" in spec["paths"]["/cache/clear"], spec["paths"]["/cache/clear"]
            storage_schema = spec["paths"]["/storage"]["get"]["responses"]["200"]["content"]["application/json"]["schema"]
            storage_item_schema = storage_schema["items"]
            assert "missingPaths" in storage_item_schema["properties"]["storage"]["properties"], storage_item_schema

            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("GET", "/health")
            resp = conn.getresponse()
            payload = json.loads(resp.read().decode())
            assert resp.status == 200, payload
            assert payload["status"] == "ok", payload
            assert payload["service"] == "usage", payload

            account_schema = (
                spec["paths"]["/config/account"]["post"]["requestBody"]["content"]["application/json"]["schema"]["properties"]
            )
            assert "ID or alias" in account_schema["provider"]["description"], account_schema["provider"]
            for key in [
                "api-key",
                "cookieHeader",
                "cookie-header",
                "session",
                "organizationID",
                "organization",
                "org",
                "externalIdentifier",
                "external-id",
                "account-index",
                "clearOrganizationID",
                "clear-organization",
                "clearOrg",
                "clear-org",
                "clearExternalIdentifier",
                "clearExternal",
                "clear-external-id",
                "makeActive",
                "make-active",
                "no-select",
                "no-enable",
            ]:
                assert key in account_schema, account_schema
            cache_schema = (
                spec["paths"]["/cache/clear"]["post"]["requestBody"]["content"]["application/json"]["schema"]["properties"]
            )
            assert "ID or alias" in cache_schema["provider"]["description"], cache_schema["provider"]

            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("GET", "/cost?provider=all&days=7")
            resp = conn.getresponse()
            cost_payload = json.loads(resp.read().decode())
            assert resp.status == 200, cost_payload
            assert cost_payload["daysBack"] == 7, cost_payload
            assert "grand" in cost_payload, cost_payload
            assert isinstance(cost_payload["bySource"], list), cost_payload
            assert isinstance(cost_payload["byDay"], list), cost_payload

            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("GET", "/cost?provider=nope")
            resp = conn.getresponse()
            cost_error = json.loads(resp.read().decode())
            assert resp.status == 400, cost_error
            assert cost_error["error"] == "--provider must be all, both, codex, claude, vertexai, or bedrock", cost_error

            for path in ["/cost?days=0", "/cost?days=366"]:
                conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
                conn.request("GET", path)
                resp = conn.getresponse()
                cost_days_error = json.loads(resp.read().decode())
                assert resp.status == 400, (path, cost_days_error)
                assert cost_days_error["error"] == "days must be 1...365", (path, cost_days_error)

            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("GET", "/missing-route")
            resp = conn.getresponse()
            payload = json.loads(resp.read().decode())
            assert resp.status == 404, payload
            assert payload["error"] == "not found", payload

            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("POST", "/usage", body="{}", headers={"Content-Type": "application/json"})
            resp = conn.getresponse()
            payload = json.loads(resp.read().decode())
            assert resp.status == 405, payload
            assert payload["error"] == "method not allowed", payload

            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("GET", "/storage?provider=codex")
            resp = conn.getresponse()
            storage_payload = json.loads(resp.read().decode())
            assert resp.status == 200, storage_payload
            assert len(storage_payload) == 1, storage_payload
            assert storage_payload[0]["provider"] == "codex", storage_payload
            storage = storage_payload[0]["storage"]
            assert storage["hasLocalData"] is True, storage
            assert storage["pathCount"] == 1, storage
            assert storage["totalBytes"] >= 44, storage
            component_names = {item["name"] for item in storage["topComponents"]}
            assert {"sessions", "cache", "logs"}.issubset(component_names), storage
            cleanup_titles = {item["title"] for item in storage["cleanupRecommendations"]}
            assert "Manual cleanup: sessions" in cleanup_titles, storage
            assert "Manual cleanup: cache" in cleanup_titles, storage
            assert all(".codex" in item["path"] for item in storage["topComponents"]), storage

            proc = subprocess.run(
                [BIN, "storage", "--provider", "codex", "--json-only"],
                cwd=ROOT,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
            )
            assert proc.returncode == 0, proc.stdout + proc.stderr
            assert proc.stderr == "", proc.stderr
            cli_storage_payload = json.loads(proc.stdout)
            cli_storage_report = cli_storage_payload[0] if isinstance(cli_storage_payload, list) else cli_storage_payload
            assert cli_storage_report["provider"] == "codex", cli_storage_payload
            cli_storage = cli_storage_report["storage"]
            assert cli_storage["totalBytes"] == storage["totalBytes"], cli_storage_payload
            assert {item["name"] for item in cli_storage["topComponents"]} == component_names, cli_storage_payload
            assert {item["title"] for item in cli_storage["cleanupRecommendations"]} == cleanup_titles, cli_storage_payload

            storage_alias_expectations = [
                ("qwen", "Alibaba"),
                ("glm", "z.ai"),
            ]
            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("GET", "/storage?provider=alibaba,zai")
            resp = conn.getresponse()
            storage_alias_payload = json.loads(resp.read().decode())
            assert resp.status == 200, storage_alias_payload
            assert [
                (item["provider"], item["displayName"])
                for item in storage_alias_payload
            ] == storage_alias_expectations, storage_alias_payload

            proc = subprocess.run(
                [BIN, "storage", "--provider", "alibaba,zai", "--json-only"],
                cwd=ROOT,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
            )
            assert proc.returncode == 0, proc.stdout + proc.stderr
            assert proc.stderr == "", proc.stderr
            cli_storage_alias_payload = json.loads(proc.stdout)
            assert [
                (item["provider"], item["displayName"])
                for item in cli_storage_alias_payload
            ] == storage_alias_expectations, cli_storage_alias_payload

            status_alias_expectations = [
                ("qwen", "Alibaba", "link"),
                ("glm", "z.ai", "none"),
            ]
            proc = subprocess.run(
                [BIN, "provider-status", "--provider", "alibaba,zai", "--json-only"],
                cwd=ROOT,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
            )
            assert proc.returncode == 0, proc.stdout + proc.stderr
            assert proc.stderr == "", proc.stderr
            cli_status_alias_payload = json.loads(proc.stdout)
            assert [
                (item["provider"], item["name"], item["source"])
                for item in cli_status_alias_payload
            ] == status_alias_expectations, cli_status_alias_payload
            assert cli_status_alias_payload[0]["statusLinkURL"] == "https://status.aliyun.com", cli_status_alias_payload
            assert "statusLinkURL" not in cli_status_alias_payload[1], cli_status_alias_payload

            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("GET", "/provider-status?provider=alibaba,zai")
            resp = conn.getresponse()
            http_status_alias_payload = json.loads(resp.read().decode())
            assert resp.status == 200, http_status_alias_payload
            assert [
                (item["provider"], item["name"], item["source"])
                for item in http_status_alias_payload
            ] == status_alias_expectations, http_status_alias_payload
            assert http_status_alias_payload[0]["statusLinkURL"] == "https://status.aliyun.com", http_status_alias_payload
            assert "statusLinkURL" not in http_status_alias_payload[1], http_status_alias_payload

            diagnose_alias_expectations = [
                ("qwen", "Alibaba", "alibaba-coding-plan"),
                ("glm", "z.ai", "zai"),
            ]
            proc = subprocess.run(
                [BIN, "diagnose", "--provider", "alibaba,zai", "--source", "api", "--json-only"],
                cwd=ROOT,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
            )
            assert proc.returncode == 0, proc.stdout + proc.stderr
            assert proc.stderr == "", proc.stderr
            cli_diagnose_payload = json.loads(proc.stdout)
            cli_diagnostics = cli_diagnose_payload["diagnostics"]
            assert [
                (item["provider"], item["displayName"], item["settings"]["cliName"])
                for item in cli_diagnostics
            ] == diagnose_alias_expectations, cli_diagnose_payload
            for item in cli_diagnostics:
                assert item["error"]["category"] == "auth", item
                assert item["repairActions"][0]["command"].startswith(
                    f"conductorctl config set-api-key --provider {item['provider']} "
                ), item

            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("GET", "/diagnose?provider=alibaba,zai&source=api")
            resp = conn.getresponse()
            http_diagnostics = json.loads(resp.read().decode())
            assert resp.status == 200, http_diagnostics
            assert [
                (item["provider"], item["displayName"], item["settings"]["cliName"])
                for item in http_diagnostics
            ] == diagnose_alias_expectations, http_diagnostics
            for item in http_diagnostics:
                assert item["error"]["category"] == "auth", item
                assert item["repairActions"][0]["command"].startswith(
                    f"conductorctl config set-api-key --provider {item['provider']} "
                ), item

            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("GET", "/storage?provider=claude")
            resp = conn.getresponse()
            claude_storage_payload = json.loads(resp.read().decode())
            assert resp.status == 200, claude_storage_payload
            claude_storage = claude_storage_payload[0]["storage"]
            assert claude_storage["hasLocalData"] is False, claude_storage
            assert claude_storage["missingPathCount"] >= 2, claude_storage
            assert "~/.claude" in claude_storage["missingPaths"], claude_storage
            assert all(home not in path for path in claude_storage["missingPaths"]), claude_storage

            for path in [
                "/usage?provider=nope",
                "/diagnose?provider=nope",
                "/storage?provider=nope",
                "/provider-status?provider=nope",
                "/config/providers?provider=nope",
            ]:
                conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
                conn.request("GET", path)
                resp = conn.getresponse()
                payload = json.loads(resp.read().decode())
                assert resp.status == 400, (path, payload)
                assert "Unknown provider 'nope'" in payload["error"], (path, payload)

            proc = subprocess.run(
                [BIN, "storage", "--provider", "claude"],
                cwd=ROOT,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
            )
            assert proc.returncode == 0, proc.stdout + proc.stderr
            assert "missing: ~/.claude" in proc.stdout, proc.stdout
            assert "missing: ~/.config/claude" in proc.stdout, proc.stdout
            assert home not in proc.stdout, proc.stdout

            usage_alias_expectations = [
                ("qwen", "Alibaba"),
                ("glm", "z.ai"),
            ]
            proc = subprocess.run(
                [BIN, "usage", "--provider", "alibaba,zai", "--source", "api", "--json-only"],
                cwd=ROOT,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
            )
            assert proc.returncode == 0, proc.stdout + proc.stderr
            assert proc.stderr == "", proc.stderr
            cli_usage_alias_payload = json.loads(proc.stdout)
            assert [
                (item["provider"], item["name"])
                for item in cli_usage_alias_payload
            ] == usage_alias_expectations, cli_usage_alias_payload
            for item in cli_usage_alias_payload:
                assert item["configured"] is False, item
                assert item["source"] == "api", item
                assert "usage" not in item or item["usage"] is None, item
                assert item["repairActions"][0]["command"].startswith(
                    f"conductorctl config set-api-key --provider {item['provider']} "
                ), item

            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("GET", "/usage?provider=alibaba,zai&source=api")
            resp = conn.getresponse()
            http_usage_alias_payload = json.loads(resp.read().decode())
            assert resp.status == 200, http_usage_alias_payload
            assert [
                (item["provider"], item["name"])
                for item in http_usage_alias_payload
            ] == usage_alias_expectations, http_usage_alias_payload
            for item in http_usage_alias_payload:
                assert item["configured"] is False, item
                assert item["source"] == "api", item
                assert "usage" not in item or item["usage"] is None, item
                assert item["repairActions"][0]["command"].startswith(
                    f"conductorctl config set-api-key --provider {item['provider']} "
                ), item

            claude_home = os.path.join(home, ".claude")
            os.makedirs(claude_home, exist_ok=True)
            unreadable_probe = os.path.join(claude_home, "private-token=diagnose-secret")
            os.makedirs(unreadable_probe, exist_ok=True)
            os.chmod(unreadable_probe, 0)
            try:
                proc = subprocess.run(
                    [BIN, "diagnose", "--provider", "claude", "--source", "api", "--storage"],
                    cwd=ROOT,
                    env=env,
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=10,
                )
                json_proc = subprocess.run(
                    [BIN, "diagnose", "--provider", "claude", "--source", "api", "--storage", "--json-only"],
                    cwd=ROOT,
                    env=env,
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=10,
                )
                conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
                conn.request("GET", "/diagnose?provider=claude&source=api&storage=1")
                http_diag_resp = conn.getresponse()
                http_diag_body = http_diag_resp.read().decode()
            finally:
                os.chmod(unreadable_probe, 0o700)
            assert proc.returncode == 0, proc.stdout + proc.stderr
            assert "storage: no local data across" in proc.stdout, proc.stdout
            assert "storage missing paths:" in proc.stdout, proc.stdout
            assert "storage missing path: ~/.config/claude" in proc.stdout, proc.stdout
            assert "command: conductorctl config set-api-key --provider claude --api-key <key>" in proc.stdout, proc.stdout
            assert "url: https://console.anthropic.com/settings/billing" in proc.stdout, proc.stdout
            assert "diagnose-secret" not in proc.stdout, proc.stdout
            assert home not in proc.stdout, proc.stdout

            assert json_proc.returncode == 0, json_proc.stdout + json_proc.stderr
            assert json_proc.stderr == "", json_proc.stderr
            diagnostic = json.loads(json_proc.stdout)
            assert diagnostic["provider"] == "claude", diagnostic
            assert diagnostic["sourceMode"] == "api", diagnostic
            assert diagnostic["storage"]["missingPathCount"] >= 1, diagnostic
            assert "~/.config/claude" in diagnostic["storage"]["missingPaths"], diagnostic
            assert home not in json_proc.stdout, json_proc.stdout
            assert "diagnose-secret" not in json_proc.stdout, json_proc.stdout
            assert any(
                action.get("command") == "conductorctl config set-api-key --provider claude --api-key <key>"
                for action in diagnostic["repairActions"]
            ), diagnostic["repairActions"]
            assert any(
                action.get("url") == "https://console.anthropic.com/settings/billing"
                for action in diagnostic["repairActions"]
            ), diagnostic["repairActions"]

            assert http_diag_resp.status == 200, http_diag_body
            http_diagnostics = json.loads(http_diag_body)
            assert len(http_diagnostics) == 1, http_diagnostics
            http_diagnostic = http_diagnostics[0]
            assert http_diagnostic["provider"] == "claude", http_diagnostic
            assert http_diagnostic["sourceMode"] == "api", http_diagnostic
            assert "~/.config/claude" in http_diagnostic["storage"]["missingPaths"], http_diagnostic
            assert home not in http_diag_body, http_diag_body
            assert "diagnose-secret" not in http_diag_body, http_diag_body
            assert any(
                action.get("command") == "conductorctl config set-api-key --provider claude --api-key <key>"
                for action in http_diagnostic["repairActions"]
            ), http_diagnostic["repairActions"]
            assert any(
                action.get("url") == "https://console.anthropic.com/settings/billing"
                for action in http_diagnostic["repairActions"]
            ), http_diagnostic["repairActions"]

            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("GET", "/config/dump")
            resp = conn.getresponse()
            payload = json.loads(resp.read().decode())
            assert resp.status == 200, payload
            assert payload["usage"]["providers"]["openai"]["sourceMode"] == "oauth", payload

            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("GET", "/config/account")
            resp = conn.getresponse()
            payload = json.loads(resp.read().decode())
            assert resp.status == 405, payload
            assert payload["error"] == "method not allowed", payload

            for path in ["/config/provider", "/config/order", "/cache/clear"]:
                conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
                conn.request("GET", path)
                resp = conn.getresponse()
                payload = json.loads(resp.read().decode())
                assert resp.status == 405, (path, payload)
                assert payload["error"] == "method not allowed", (path, payload)

            body = json.dumps(
                {
                    "action": "add",
                    "provider": "openai",
                    "token": "sk-http-1",
                    "label": "http-primary",
                    "organizationId": "org-http",
                }
            )
            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("POST", "/config/account", body=body, headers={"Content-Type": "application/json"})
            resp = conn.getresponse()
            raw = resp.read().decode()
            payload = json.loads(raw)
            assert resp.status == 200, payload
            assert "sk-http-1" not in raw, raw
            assert payload["action"] == "add", payload
            assert payload["activeIndex"] == 1, payload
            assert payload["account"]["label"] == "http-primary", payload
            assert payload["account"]["organizationID"] == "org-http", payload

            body = json.dumps(
                {
                    "action": "add",
                    "provider": "openai",
                    "api-key": "sk-http-2",
                    "label": "http-secondary",
                    "external-id": "http@example.com",
                    "no-select": True,
                }
            )
            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("POST", "/config/account", body=body, headers={"Content-Type": "application/json"})
            resp = conn.getresponse()
            raw = resp.read().decode()
            payload = json.loads(raw)
            assert resp.status == 200, payload
            assert "sk-http-2" not in raw, raw
            assert payload["activeIndex"] == 1, payload
            assert payload["account"]["label"] == "http-secondary", payload
            assert payload["account"]["active"] is False, payload

            body = json.dumps(
                {
                    "action": "update",
                    "provider": "openai",
                    "account": "http-secondary",
                    "token": "sk-http-rotated",
                    "label": "http-renamed",
                    "organizationId": "org-http-2",
                    "externalId": "renamed@example.com",
                    "select": True,
                }
            )
            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("POST", "/config/account", body=body, headers={"Content-Type": "application/json"})
            resp = conn.getresponse()
            raw = resp.read().decode()
            payload = json.loads(raw)
            assert resp.status == 200, payload
            assert "sk-http-rotated" not in raw, raw
            assert payload["action"] == "update", payload
            assert payload["activeIndex"] == 2, payload
            assert payload["account"]["label"] == "http-renamed", payload
            assert payload["account"]["externalIdentifier"] == "renamed@example.com", payload
            assert payload["account"]["organizationID"] == "org-http-2", payload
            assert [item["active"] for item in payload["accounts"]] == [False, True], payload

            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("GET", "/config/accounts?provider=openai")
            resp = conn.getresponse()
            payload = json.loads(resp.read().decode())
            assert resp.status == 200, payload
            assert payload["activeIndex"] == 2, payload
            assert [item["label"] for item in payload["accounts"]] == [
                "http-primary",
                "http-renamed",
            ], payload

            for path in ["/config/accounts", "/config/accounts?provider=nope"]:
                conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
                conn.request("GET", path)
                resp = conn.getresponse()
                payload = json.loads(resp.read().decode())
                assert resp.status == 400, payload
                assert payload["error"] == "Unknown or missing provider. Use --provider <name>.", payload

            body = json.dumps({"action": "select", "provider": "openai", "account": "renamed@example.com"})
            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("POST", "/config/account", body=body, headers={"Content-Type": "application/json"})
            resp = conn.getresponse()
            payload = json.loads(resp.read().decode())
            assert resp.status == 200, payload
            assert payload["activeIndex"] == 2, payload
            assert payload["account"]["label"] == "http-renamed", payload

            body = json.dumps({"action": "remove", "provider": "openai", "accountIndex": 1})
            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("POST", "/config/account", body=body, headers={"Content-Type": "application/json"})
            resp = conn.getresponse()
            payload = json.loads(resp.read().decode())
            assert resp.status == 200, payload
            assert payload["account"]["label"] == "http-primary", payload
            assert payload["activeIndex"] == 1, payload
            assert [item["label"] for item in payload["accounts"]] == ["http-renamed"], payload

            body = json.dumps({"action": "add", "provider": "gemini", "token": "nope"})
            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("POST", "/config/account", body=body, headers={"Content-Type": "application/json"})
            resp = conn.getresponse()
            payload = json.loads(resp.read().decode())
            assert resp.status == 400, payload
            assert "gemini does not support token accounts." in payload["error"], payload

            for alias, canonical, display_name in [
                ("alibaba", "qwen", "Alibaba"),
                ("zai", "glm", "z.ai"),
            ]:
                conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
                conn.request("GET", f"/config/providers?provider={alias}")
                resp = conn.getresponse()
                payload = json.loads(resp.read().decode())
                assert resp.status == 200, (alias, payload)
                assert len(payload) == 1, (alias, payload)
                assert payload[0]["provider"] == canonical, (alias, payload)
                assert payload[0]["displayName"] == display_name, (alias, payload)

                body = json.dumps({"action": "enable", "provider": alias})
                conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
                conn.request("POST", "/config/provider", body=body, headers={"Content-Type": "application/json"})
                resp = conn.getresponse()
                payload = json.loads(resp.read().decode())
                assert resp.status == 200, (alias, payload)
                assert payload["action"] == "enable", (alias, payload)
                assert payload["provider"] == canonical, (alias, payload)
                assert payload["displayName"] == display_name, (alias, payload)
                assert payload["enabled"] is True, (alias, payload)

                api_secret = f"{canonical}-http-secret"
                body = json.dumps({"action": "set-api-key", "provider": alias, "apiKey": api_secret})
                conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
                conn.request("POST", "/config/provider", body=body, headers={"Content-Type": "application/json"})
                resp = conn.getresponse()
                raw = resp.read().decode()
                payload = json.loads(raw)
                assert resp.status == 200, (alias, payload)
                assert api_secret not in raw, (alias, raw)
                assert payload["action"] == "set-api-key", (alias, payload)
                assert payload["provider"] == canonical, (alias, payload)
                assert payload["displayName"] == display_name, (alias, payload)
                assert payload["enabled"] is True, (alias, payload)

                if alias == "alibaba":
                    cookie_secret = f"{canonical}-http-cookie-secret"
                    body = json.dumps({"action": "set-cookie", "provider": alias, "cookie": cookie_secret})
                    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
                    conn.request("POST", "/config/provider", body=body, headers={"Content-Type": "application/json"})
                    resp = conn.getresponse()
                    raw = resp.read().decode()
                    payload = json.loads(raw)
                    assert resp.status == 200, (alias, payload)
                    assert cookie_secret not in raw, (alias, raw)
                    assert payload["action"] == "set-cookie", (alias, payload)
                    assert payload["provider"] == canonical, (alias, payload)
                    assert payload["displayName"] == display_name, (alias, payload)
                    assert payload["cookieSource"] == "manual", (alias, payload)
                    assert payload["enabled"] is True, (alias, payload)

                conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
                conn.request("GET", f"/config/accounts?provider={alias}")
                resp = conn.getresponse()
                payload = json.loads(resp.read().decode())
                assert resp.status == 200, (alias, payload)
                assert payload["provider"] == canonical, (alias, payload)
                assert payload["displayName"] == display_name, (alias, payload)
                assert payload["enabled"] is True, (alias, payload)
                assert payload["accounts"] == [], (alias, payload)

                label = f"http-{canonical}-primary"
                renamed = f"http-{canonical}-renamed"
                body = json.dumps(
                    {
                        "action": "add",
                        "provider": alias,
                        "token": f"{canonical}-http-token",
                        "label": label,
                        "external-id": f"{canonical}-http-external",
                    }
                )
                conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
                conn.request("POST", "/config/account", body=body, headers={"Content-Type": "application/json"})
                resp = conn.getresponse()
                payload = json.loads(resp.read().decode())
                assert resp.status == 200, (alias, payload)
                assert payload["provider"] == canonical, (alias, payload)
                assert payload["displayName"] == display_name, (alias, payload)
                assert payload["action"] == "add", (alias, payload)
                assert payload["activeIndex"] == 1, (alias, payload)
                assert payload["account"]["label"] == label, (alias, payload)
                assert payload["account"]["hasToken"] is True, (alias, payload)

                body = json.dumps(
                    {
                        "action": "update",
                        "provider": alias,
                        "accountIndex": 1,
                        "label": renamed,
                        "external-id": f"{canonical}-http-updated",
                    }
                )
                conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
                conn.request("POST", "/config/account", body=body, headers={"Content-Type": "application/json"})
                resp = conn.getresponse()
                payload = json.loads(resp.read().decode())
                assert resp.status == 200, (alias, payload)
                assert payload["provider"] == canonical, (alias, payload)
                assert payload["displayName"] == display_name, (alias, payload)
                assert payload["action"] == "update", (alias, payload)
                assert payload["account"]["label"] == renamed, (alias, payload)
                assert payload["account"]["externalIdentifier"] == f"{canonical}-http-updated", (alias, payload)

                body = json.dumps({"action": "select", "provider": alias, "account": renamed})
                conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
                conn.request("POST", "/config/account", body=body, headers={"Content-Type": "application/json"})
                resp = conn.getresponse()
                payload = json.loads(resp.read().decode())
                assert resp.status == 200, (alias, payload)
                assert payload["provider"] == canonical, (alias, payload)
                assert payload["action"] == "select", (alias, payload)
                assert payload["account"]["label"] == renamed, (alias, payload)

                body = json.dumps({"action": "remove", "provider": alias, "accountIndex": 1})
                conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
                conn.request("POST", "/config/account", body=body, headers={"Content-Type": "application/json"})
                resp = conn.getresponse()
                payload = json.loads(resp.read().decode())
                assert resp.status == 200, (alias, payload)
                assert payload["provider"] == canonical, (alias, payload)
                assert payload["displayName"] == display_name, (alias, payload)
                assert payload["action"] == "remove", (alias, payload)
                assert payload["account"]["label"] == renamed, (alias, payload)
                assert payload["accounts"] == [], (alias, payload)

                body = json.dumps(
                    {
                        "action": "set",
                        "provider": alias,
                        "key": "baseURL",
                        "value": f"https://example.com/{canonical}",
                    }
                )
                conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
                conn.request("POST", "/config/provider", body=body, headers={"Content-Type": "application/json"})
                resp = conn.getresponse()
                payload = json.loads(resp.read().decode())
                assert resp.status == 200, (alias, payload)
                assert payload["provider"] == canonical, (alias, payload)
                assert payload["displayName"] == display_name, (alias, payload)
                assert payload["action"] == "set-field", (alias, payload)
                assert payload["key"] == "baseURL", (alias, payload)
                assert payload["present"] is True, (alias, payload)

                body = json.dumps({"action": "unset", "provider": alias, "key": "baseURL"})
                conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
                conn.request("POST", "/config/provider", body=body, headers={"Content-Type": "application/json"})
                resp = conn.getresponse()
                payload = json.loads(resp.read().decode())
                assert resp.status == 200, (alias, payload)
                assert payload["provider"] == canonical, (alias, payload)
                assert payload["displayName"] == display_name, (alias, payload)
                assert payload["action"] == "unset-field", (alias, payload)
                assert payload["key"] == "baseURL", (alias, payload)
                assert payload["present"] is False, (alias, payload)

            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("GET", "/config/dump")
            resp = conn.getresponse()
            alias_dump = json.loads(resp.read().decode())
            assert resp.status == 200, sorted(alias_dump.get("usage", {}).get("providers", {}).keys())
            alias_providers = alias_dump["usage"]["providers"]
            alias_provider_keys = sorted(alias_providers.keys())
            assert "qwen" in alias_providers, alias_provider_keys
            assert "glm" in alias_providers, alias_provider_keys
            assert "alibaba" not in alias_providers, alias_provider_keys
            assert "zai" not in alias_providers, alias_provider_keys
            assert alias_providers["qwen"]["enabled"] is True, alias_provider_keys
            assert alias_providers["qwen"]["cookieSource"] == "manual", alias_provider_keys
            assert alias_providers["glm"]["enabled"] is True, alias_provider_keys

            body = json.dumps({"action": "disable", "provider": "openai"})
            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("POST", "/config/provider", body=body, headers={"Content-Type": "application/json"})
            resp = conn.getresponse()
            payload = json.loads(resp.read().decode())
            assert resp.status == 200, payload
            assert payload["action"] == "disable", payload
            assert payload["provider"] == "openai", payload
            assert payload["enabled"] is False, payload

            body = json.dumps(
                {
                    "action": "set-api-key",
                    "provider": "openai",
                    "apiKey": "sk-http-admin",
                    "noEnable": True,
                }
            )
            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("POST", "/config/provider", body=body, headers={"Content-Type": "application/json"})
            resp = conn.getresponse()
            raw = resp.read().decode()
            payload = json.loads(raw)
            assert resp.status == 200, payload
            assert "sk-http-admin" not in raw, raw
            assert payload["action"] == "set-api-key", payload
            assert payload["enabled"] is False, payload

            body = json.dumps(
                {
                    "action": "set-key",
                    "provider": "openai",
                    "api-key": "sk-http-kebab",
                    "no-enable": True,
                }
            )
            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("POST", "/config/provider", body=body, headers={"Content-Type": "application/json"})
            resp = conn.getresponse()
            raw = resp.read().decode()
            payload = json.loads(raw)
            assert resp.status == 200, payload
            assert "sk-http-kebab" not in raw, raw
            assert payload["action"] == "set-api-key", payload
            assert payload["enabled"] is False, payload

            body = json.dumps(
                {
                    "action": "set-cookie",
                    "provider": "commandcode",
                    "cookie": "__Secure-better-auth.session_token=http",
                }
            )
            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("POST", "/config/provider", body=body, headers={"Content-Type": "application/json"})
            resp = conn.getresponse()
            raw = resp.read().decode()
            payload = json.loads(raw)
            assert resp.status == 200, payload
            assert "__Secure-better-auth.session_token=http" not in raw, raw
            assert payload["action"] == "set-cookie", payload
            assert payload["provider"] == "commandcode", payload
            assert payload["cookieSource"] == "manual", payload
            assert payload["enabled"] is True, payload

            body = json.dumps(
                {
                    "action": "set",
                    "provider": "commandcode",
                    "key": "sourceMode",
                    "value": "web",
                }
            )
            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("POST", "/config/provider", body=body, headers={"Content-Type": "application/json"})
            resp = conn.getresponse()
            payload = json.loads(resp.read().decode())
            assert resp.status == 200, payload
            assert payload["action"] == "set-field", payload
            assert payload["provider"] == "commandcode", payload
            assert payload["key"] == "sourceMode", payload
            assert payload["present"] is True, payload

            body = json.dumps(
                {
                    "action": "set-field",
                    "provider": "commandcode",
                    "key": "extra.region",
                    "value": "us",
                }
            )
            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("POST", "/config/provider", body=body, headers={"Content-Type": "application/json"})
            resp = conn.getresponse()
            payload = json.loads(resp.read().decode())
            assert resp.status == 200, payload
            assert payload["action"] == "set-field", payload
            assert payload["key"] == "extra.region", payload
            assert payload["present"] is True, payload

            body = json.dumps({"action": "unset", "provider": "commandcode", "key": "extra.region"})
            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("POST", "/config/provider", body=body, headers={"Content-Type": "application/json"})
            resp = conn.getresponse()
            payload = json.loads(resp.read().decode())
            assert resp.status == 200, payload
            assert payload["action"] == "unset-field", payload
            assert payload["key"] == "extra.region", payload
            assert payload["present"] is False, payload

            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("GET", "/config/dump")
            resp = conn.getresponse()
            payload = json.loads(resp.read().decode())
            assert resp.status == 200, payload
            commandcode_config = payload["usage"]["providers"]["commandcode"]
            assert commandcode_config["sourceMode"] == "web", commandcode_config
            assert "region" not in commandcode_config.get("extra", {}), commandcode_config

            body = json.dumps({"providers": ["commandcode", "openai", "codex"]})
            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("POST", "/config/order", body=body, headers={"Content-Type": "application/json"})
            resp = conn.getresponse()
            payload = json.loads(resp.read().decode())
            assert resp.status == 200, payload
            assert payload["action"] == "order", payload
            assert payload["providerOrder"][:3] == ["commandcode", "openai", "codex"], payload

            for key in ["providerOrder", "provider-order"]:
                body = json.dumps({key: "openai, commandcode, codex"})
                conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
                conn.request("POST", "/config/order", body=body, headers={"Content-Type": "application/json"})
                resp = conn.getresponse()
                payload = json.loads(resp.read().decode())
                assert resp.status == 200, payload
                assert payload["action"] == "order", payload
                assert payload["providerOrder"][:3] == ["openai", "commandcode", "codex"], payload

            body = json.dumps({"providers": "zai,alibaba"})
            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("POST", "/config/order", body=body, headers={"Content-Type": "application/json"})
            resp = conn.getresponse()
            payload = json.loads(resp.read().decode())
            assert resp.status == 200, payload
            assert payload["action"] == "order", payload
            assert payload["providerOrder"][:2] == ["glm", "qwen"], payload

            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("POST", "/cache/clear", body=json.dumps({}), headers={"Content-Type": "application/json"})
            resp = conn.getresponse()
            payload = json.loads(resp.read().decode())
            assert resp.status == 400, payload
            assert "Specify cookies, cost, or all." in payload["error"], payload

            body = json.dumps({"cost": True, "provider": "openai"})
            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("POST", "/cache/clear", body=body, headers={"Content-Type": "application/json"})
            resp = conn.getresponse()
            payload = json.loads(resp.read().decode())
            assert resp.status == 400, payload
            assert "--provider only scopes cookie caches" in payload["error"], payload

            body = json.dumps({"cookies": True, "provider": "alibaba"})
            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("POST", "/cache/clear", body=body, headers={"Content-Type": "application/json"})
            resp = conn.getresponse()
            payload = json.loads(resp.read().decode())
            assert resp.status == 200, payload
            assert payload[0]["cache"] == "cookies", payload
            assert payload[0]["provider"] == "qwen", payload
            assert isinstance(payload[0]["cleared"], int), payload

            body = json.dumps({"cookies": True, "provider": "nope"})
            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("POST", "/cache/clear", body=body, headers={"Content-Type": "application/json"})
            resp = conn.getresponse()
            payload = json.loads(resp.read().decode())
            assert resp.status == 400, payload
            assert payload["error"] == "Unknown provider: nope", payload

            body = json.dumps({"cost": True})
            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("POST", "/cache/clear", body=body, headers={"Content-Type": "application/json"})
            resp = conn.getresponse()
            payload = json.loads(resp.read().decode())
            assert resp.status == 200, payload
            assert payload[0]["cache"] == "cost", payload
            assert payload[0].get("provider") is None, payload
            assert isinstance(payload[0]["cleared"], int), payload

            body = json.dumps({"all": True})
            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("POST", "/cache/clear", body=body, headers={"Content-Type": "application/json"})
            resp = conn.getresponse()
            payload = json.loads(resp.read().decode())
            assert resp.status == 200, payload
            assert [item["cache"] for item in payload] == ["cookies", "cost", "usage-snapshots"], payload
            assert all(item.get("provider") is None for item in payload), payload
            assert all(isinstance(item["cleared"], int) for item in payload), payload

            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("GET", "/config/validate")
            resp = conn.getresponse()
            issues = json.loads(resp.read().decode())
            assert resp.status == 200, issues
            assert any(issue["code"] == "unsupported_source" for issue in issues), issues
            assert any(issue["severity"] == "error" for issue in issues), issues

            with open(config_path, "w", encoding="utf-8") as handle:
                handle.write(
                    """
usage:
  providers:
    alibaba:
      enabled: true
    zai:
      enabled: true
""".lstrip()
                )

            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("GET", "/config/validate")
            resp = conn.getresponse()
            alias_issues = json.loads(resp.read().decode())
            assert resp.status == 200, alias_issues
            assert [
                (issue["provider"], issue["code"], issue["message"])
                for issue in alias_issues
            ] == [
                (
                    "alibaba",
                    "unknown_provider",
                    "Unknown provider alias. Use canonical provider ID `qwen` instead of `alibaba` in config.",
                ),
                (
                    "zai",
                    "unknown_provider",
                    "Unknown provider alias. Use canonical provider ID `glm` instead of `zai` in config.",
                ),
            ], alias_issues

            proc = subprocess.run(
                [BIN, "config", "validate", "--json-only"],
                cwd=ROOT,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=5,
            )
            assert proc.returncode != 0, proc.stdout
            assert proc.stderr == "", proc.stderr
            assert json.loads(proc.stdout) == alias_issues, (proc.stdout, alias_issues)

            with open(config_path, "w", encoding="utf-8") as handle:
                handle.write(
                    """
usage:
  providerOrder:
    - alibaba
    - zai
  statusBarOverviewProviderIDs:
    - alibaba
  statusBarOverviewSelectionBasisIDs:
    - zai
  providers:
    qwen:
      enabled: true
    glm:
      enabled: true
""".lstrip()
                )

            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("GET", "/config/validate")
            resp = conn.getresponse()
            provider_list_issues = json.loads(resp.read().decode())
            assert resp.status == 200, provider_list_issues
            assert [
                (issue["field"], issue["code"], issue["message"])
                for issue in provider_list_issues
            ] == [
                (
                    "providerOrder",
                    "provider_alias_in_list",
                    "providerOrder contains provider alias `alibaba`; use canonical provider ID `qwen` instead.",
                ),
                (
                    "providerOrder",
                    "provider_alias_in_list",
                    "providerOrder contains provider alias `zai`; use canonical provider ID `glm` instead.",
                ),
                (
                    "statusBarOverviewProviderIDs",
                    "provider_alias_in_list",
                    "statusBarOverviewProviderIDs contains provider alias `alibaba`; use canonical provider ID `qwen` instead.",
                ),
                (
                    "statusBarOverviewSelectionBasisIDs",
                    "provider_alias_in_list",
                    "statusBarOverviewSelectionBasisIDs contains provider alias `zai`; use canonical provider ID `glm` instead.",
                ),
            ], provider_list_issues
            assert {issue["severity"] for issue in provider_list_issues} == {"warning"}, provider_list_issues

            proc = subprocess.run(
                [BIN, "config", "validate", "--json-only"],
                cwd=ROOT,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=5,
            )
            assert proc.returncode == 0, proc.stdout + proc.stderr
            assert proc.stderr == "", proc.stderr
            assert json.loads(proc.stdout) == provider_list_issues, (proc.stdout, provider_list_issues)

            with open(config_path, "w", encoding="utf-8") as handle:
                handle.write(
                    """
usage:
  providerOrder:
    - nope-order
  statusBarOverviewProviderIDs:
    - nope-overview
  statusBarOverviewSelectionBasisIDs:
    - nope-basis
  providers:
    codex:
      enabled: true
""".lstrip()
                )

            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("GET", "/config/validate")
            resp = conn.getresponse()
            unknown_list_issues = json.loads(resp.read().decode())
            assert resp.status == 200, unknown_list_issues
            assert [
                (issue["field"], issue["code"], issue["message"])
                for issue in unknown_list_issues
            ] == [
                (
                    "providerOrder",
                    "unknown_provider_in_list",
                    "providerOrder contains unknown provider `nope-order` and it will be ignored. Run `conductorctl config providers` to list valid IDs.",
                ),
                (
                    "statusBarOverviewProviderIDs",
                    "unknown_provider_in_list",
                    "statusBarOverviewProviderIDs contains unknown provider `nope-overview` and it will be ignored. Run `conductorctl config providers` to list valid IDs.",
                ),
                (
                    "statusBarOverviewSelectionBasisIDs",
                    "unknown_provider_in_list",
                    "statusBarOverviewSelectionBasisIDs contains unknown provider `nope-basis` and it will be ignored. Run `conductorctl config providers` to list valid IDs.",
                ),
            ], unknown_list_issues
            assert {issue["severity"] for issue in unknown_list_issues} == {"warning"}, unknown_list_issues

            proc = subprocess.run(
                [BIN, "config", "validate", "--json-only"],
                cwd=ROOT,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=5,
            )
            assert proc.returncode == 0, proc.stdout + proc.stderr
            assert proc.stderr == "", proc.stderr
            assert json.loads(proc.stdout) == unknown_list_issues, (proc.stdout, unknown_list_issues)

            with open(config_path, "w", encoding="utf-8") as handle:
                handle.write(
                    """
usage:
  providers:
    openai:
      sourceMode: oauth
""".lstrip()
                )

            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("GET", "/diagnose?provider=abacus&source=api")
            resp = conn.getresponse()
            payload = json.loads(resp.read().decode())
            assert resp.status == 400, payload
            assert "Source api is not supported for abacus" in payload["error"], payload
            assert "auto, web" in payload["error"], payload

            conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
            conn.request("GET", "/usage?provider=abacus&source=api")
            resp = conn.getresponse()
            payload = json.loads(resp.read().decode())
            assert resp.status == 200, payload
            assert len(payload) == 1, payload
            assert payload[0]["provider"] == "abacus", payload
            assert payload[0]["source"] == "api", payload
            assert payload[0]["configured"] is True, payload
            assert payload[0].get("usage") is None, payload
            assert "Source api is not supported for abacus" in payload[0]["error"]["message"], payload
            assert "auto, web" in payload[0]["error"]["message"], payload
            assert any(
                action.get("id") == "adjust-source-mode"
                and action.get("command") == "conductorctl config set --provider abacus --key sourceMode --value <source>"
                for action in payload[0]["repairActions"]
            ), payload[0]["repairActions"]

            for path, expected in [
                ("/usage?provider=codex&status=maybe", "status must be a boolean"),
                ("/diagnose?provider=codex&storage=maybe", "storage must be a boolean"),
                ("/usage?provider=codex&all-accounts=maybe", "all-accounts must be a boolean"),
                (
                    "/usage?provider=codex&account=dev@example.com&all-accounts=true",
                    "all-accounts cannot be combined with account or account-index",
                ),
                (
                    "/diagnose?provider=codex&account-index=1&all-accounts=1",
                    "all-accounts cannot be combined with account or account-index",
                ),
            ]:
                conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
                conn.request("GET", path)
                resp = conn.getresponse()
                payload = json.loads(resp.read().decode())
                assert resp.status == 400, (path, payload)
                assert expected in payload["error"], (path, payload)

            proc = subprocess.run(
                [BIN, "config", "validate", "--json"],
                cwd=ROOT,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=5,
            )
            assert proc.returncode != 0, proc.stdout
            cli_issues = json.loads(proc.stdout)
            assert issues == cli_issues, (issues, cli_issues)
        finally:
            server.terminate()
            try:
                server.wait(timeout=3)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait(timeout=3)


def test_resource_commands():
    expected = [
        "workspace.create",
        "workspace.rename",
        "workspace.tree",
        "tab.rename",
        "pane.split",
        "pane.close",
        "workspace.status.set",
        "workspace.progress.set",
        "workspace.log.append",
    ]

    def handler(req, _count):
        method = req["method"]
        params = req.get("params") or {}
        if method == "workspace.create":
            assert params == {"path": "/tmp/proj", "name": "Proj"}, params
            return response(req, {"id": "w1", "name": "Proj", "path": "/tmp/proj", "active": True, "tabs": 1})
        if method == "workspace.rename":
            assert params == {"workspace": "w1", "name": "Renamed"}, params
            return response(req, True)
        if method == "workspace.tree":
            assert params == {"workspace": "w1"}, params
            return response(req, {"workspace": "w1", "tabs": []})
        if method == "tab.rename":
            assert params == {"tab": "t1", "title": "Build", "workspace": "w1"}, params
            return response(req, True)
        if method == "pane.split":
            assert params == {"pane": "p1", "direction": "down", "cwd": "/tmp/proj"}, params
            return response(req, {"pane": "p2"})
        if method == "pane.close":
            assert params == {"pane": "p2"}, params
            return response(req, True)
        if method == "workspace.status.set":
            assert params == {
                "workspace": "w1",
                "key": "build",
                "text": "Building now",
                "color": "#00ff00",
                "icon": "hammer",
            }, params
            return response(req, True)
        if method == "workspace.progress.set":
            assert params == {"workspace": "w1", "value": 0.5, "label": "half"}, params
            return response(req, True)
        if method == "workspace.log.append":
            assert params == {"workspace": "w1", "text": "hello logs", "level": "warn", "source": "test"}, params
            return response(req, True)
        return error_response(req, "unexpected", method)

    with FakeAppSocket("conductorctl-resources", len(expected), handler) as app:
        run_cli(["workspace", "create", "/tmp/proj", "--name", "Proj", "--json"], app)
        run_cli(["workspace", "rename", "w1", "Renamed"], app)
        run_cli(["workspace", "tree", "w1"], app)
        run_cli(["tab", "rename", "t1", "Build", "--workspace", "w1"], app)
        run_cli(["pane", "split", "--pane", "p1", "--direction", "down", "--cwd", "/tmp/proj", "--json"], app)
        run_cli(["pane", "close", "p2"], app)
        run_cli([
            "workspace", "status", "set", "build", "Building", "now",
            "--workspace", "w1", "--color", "#00ff00", "--icon", "hammer",
        ], app)
        run_cli(["workspace", "progress", "set", "0.5", "--workspace", "w1", "--label", "half"], app)
        run_cli([
            "workspace", "log", "append", "hello", "logs",
            "--workspace", "w1", "--level", "warn", "--source", "test",
        ], app)
        assert [req["method"] for req in app.requests] == expected


def test_cli_command_surface():
    methods = []

    def handler(req, _count):
        method = req["method"]
        methods.append(method)
        params = req.get("params") or {}
        if method == "app.ping":
            return response(req, {"pong": True, "protocol": 1, "socket": "/tmp/fake.sock"})
        if method == "app.status":
            return response(req, {
                "app": "Conductor",
                "version": "test",
                "protocol": 1,
                "active": {"workspace": "w1", "tab": "t1", "pane": "p1"},
                "counts": {"workspaces": 1, "tabs": 1, "panes": 1, "runningAgents": 0, "activities": 1},
                "methods": ["app.ping", "agent.run"],
            })
        if method == "app.methods":
            return response(req, ["app.ping", "app.status", "agent.run"])
        if method == "workspace.list":
            return response(req, [{"id": "w1", "name": "Main", "path": "/tmp/main", "active": True, "tabs": 1}])
        if method == "workspace.current":
            return response(req, {"id": "w1", "name": "Main", "path": "/tmp/main", "active": True, "tabs": 1})
        if method == "workspace.select":
            assert params == {"workspace": "w1"}, params
            return response(req, True)
        if method == "workspace.close":
            assert params == {"workspace": "w-close"}, params
            return response(req, True)
        if method == "workspace.status.clear":
            assert params == {"workspace": "w1", "key": "build"}, params
            return response(req, True)
        if method == "workspace.status.list":
            assert params == {"workspace": "w1"}, params
            return response(req, [{"key": "build", "text": "ok", "color": "#00ff00", "icon": "checkmark"}])
        if method == "workspace.progress.clear":
            assert params == {"workspace": "w1"}, params
            return response(req, True)
        if method == "workspace.log.list":
            assert params == {"workspace": "w1", "limit": 2}, params
            return response(req, [{"time": 1.0, "level": "info", "source": "test", "text": "log"}])
        if method == "workspace.log.clear":
            assert params == {"workspace": "w1"}, params
            return response(req, True)
        if method == "tab.list":
            assert params == {"workspace": "w1"}, params
            return response(req, [{"id": "t1", "index": 1, "title": "Main", "active": True, "panes": []}])
        if method == "tab.select":
            assert params == {"tab": "t1", "workspace": "w1"}, params
            return response(req, True)
        if method == "tab.close":
            assert params == {"tab": "t-close", "workspace": "w1"}, params
            return response(req, True)
        if method == "pane.list":
            return response(req, [{"id": "p1", "title": "shell", "cwd": "/tmp/main", "active": True, "thinking": False}])
        if method == "pane.create":
            assert params == {"cwd": "/tmp/main"}, params
            return response(req, {"tab": "t-new", "pane": "p-new"})
        if method == "pane.focus":
            assert params == {"pane": "p1"}, params
            return response(req, True)
        if method == "pane.read":
            assert params == {"pane": "p1", "scrollback": True}, params
            return response(req, {"text": "screen text"})
        if method == "agent.send":
            assert params == {"pane": "p1", "text": "hello", "submit": True}, params
            return response(req, True)
        if method == "agent.run":
            assert params == {"agent": "codex", "command": "printf hi", "cwd": "/tmp/main", "prompt": "prompt", "submit": False}, params
            return response(req, {"pane": "p-run", "jobId": "p-run", "agent": "codex"})
        if method == "agent.status":
            assert params == {"job": "p-run"}, params
            return response(req, {"jobId": "p-run", "pane": "p-run", "agent": "codex", "status": "completed"})
        if method == "agent.result":
            assert params == {"job": "p-run"}, params
            return response(req, {"jobId": "p-run", "pane": "p-run", "agent": "codex", "status": "completed", "summary": "ok", "markdown": "ok"})
        if method == "activity.list":
            assert params == {"limit": 1} or params == {"limit": 20}, params
            return response(req, [{"id": "act1", "time": 1.0, "title": "Done", "message": "activity", "status": "completed"}])
        if method == "events.recent":
            assert params == {"limit": 1}, params
            return response(req, [{"id": "evt1", "type": "agent.completed", "topic": "agent.completed", "time": 1.0, "payload": {"message": "event"}}])
        if method == "custom.echo":
            assert params == {"hello": "world"}, params
            return response(req, {"echo": True})
        return error_response(req, "unexpected", method)

    expected_calls = 27
    with FakeAppSocket("conductorctl-surface", expected_calls, handler) as app:
        assert "conductorctl:" in subprocess.check_output([BIN, "--help"], cwd=ROOT, text=True)
        assert "Conductor OK" in run_cli(["ping"], app)
        run_cli(["status", "--json"], app)
        run_cli(["methods"], app)
        raw = run_cli(["raw", "custom.echo", '{"hello":"world"}'], app)
        assert json.loads(raw)["echo"] is True
        run_cli(["workspace", "list"], app)
        run_cli(["workspace", "current"], app)
        run_cli(["workspace", "select", "w1"], app)
        run_cli(["workspace", "close", "w-close"], app)
        run_cli(["workspace", "status", "list", "--workspace", "w1"], app)
        run_cli(["workspace", "status", "clear", "build", "--workspace", "w1"], app)
        run_cli(["workspace", "progress", "clear", "--workspace", "w1"], app)
        run_cli(["workspace", "log", "list", "--workspace", "w1", "--limit", "2"], app)
        run_cli(["workspace", "log", "clear", "--workspace", "w1"], app)
        run_cli(["tab", "list", "--workspace", "w1"], app)
        run_cli(["tab", "select", "t1", "--workspace", "w1"], app)
        run_cli(["tab", "close", "t-close", "--workspace", "w1"], app)
        run_cli(["pane", "list"], app)
        run_cli(["pane", "create", "--cwd", "/tmp/main", "--json"], app)
        run_cli(["pane", "focus", "p1"], app)
        assert "screen text" in run_cli(["screen", "--pane", "p1", "--scrollback"], app)
        run_cli(["send", "--pane", "p1", "hello"], app)
        run_cli(["run", "codex", "--command", "printf hi", "--cwd", "/tmp/main", "--prompt", "prompt", "--no-submit", "--json"], app)
        run_cli(["agent", "status", "p-run", "--json"], app)
        run_cli(["agent", "result", "p-run", "--json"], app)
        run_cli(["activity", "--limit", "1", "--json"], app)
        event_line = run_cli_first_line(["events", "--limit", "1", "--interval", "0.25", "--jsonl"], app)
        assert json.loads(event_line)["id"] == "evt1"
        watch_line = run_cli_first_line(["watch", "--interval", "0.25", "--jsonl"], app)
        assert json.loads(watch_line)["id"] == "act1"
        assert len(app.requests) >= expected_calls, len(app.requests)


def test_config_validate_cookie_source_semantics():
    with tempfile.TemporaryDirectory(prefix="conductorctl-config-validate-") as tmpdir:
        warning_config = os.path.join(tmpdir, "warnings.yaml")
        with open(warning_config, "w", encoding="utf-8") as handle:
            handle.write(
                """
usage:
  providers:
    codex:
      cookieSource: manual
""".lstrip()
            )

        env = os.environ.copy()
        env["CONDUCTOR_CONFIG_PATH"] = warning_config

        proc = subprocess.run(
            [BIN, "config", "enable"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode != 0, proc.stdout
        assert proc.stdout == "", proc.stdout
        assert "Unknown or missing provider. Use --provider <name>." in proc.stderr, proc.stderr

        for alias, canonical, display_name in [
            ("alibaba", "qwen", "Alibaba"),
            ("zai", "glm", "z.ai"),
        ]:
            proc = subprocess.run(
                [BIN, "config", "providers", "--provider", alias, "--json"],
                cwd=ROOT,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=5,
            )
            assert proc.returncode == 0, proc.stderr
            providers = json.loads(proc.stdout)
            assert len(providers) == 1, (alias, providers)
            assert providers[0]["provider"] == canonical, (alias, providers)
            assert providers[0]["displayName"] == display_name, (alias, providers)

            proc = subprocess.run(
                [BIN, "config", "enable", "--provider", alias, "--json"],
                cwd=ROOT,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=5,
            )
            assert proc.returncode == 0, proc.stderr
            payload = json.loads(proc.stdout)
            assert payload["provider"] == canonical, (alias, payload)
            assert payload["displayName"] == display_name, (alias, payload)
            assert payload["enabled"] is True, (alias, payload)

            proc = subprocess.run(
                [
                    BIN,
                    "config",
                    "set-api-key",
                    "--provider",
                    alias,
                    "--api-key",
                    f"{canonical}-secret",
                    "--json",
                ],
                cwd=ROOT,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=5,
            )
            assert proc.returncode == 0, (alias, proc.stdout, proc.stderr)
            assert f"{canonical}-secret" not in proc.stdout, (alias, proc.stdout)
            payload = json.loads(proc.stdout)
            assert payload["provider"] == canonical, (alias, payload)
            assert payload["enabled"] is True, (alias, payload)

            if alias == "alibaba":
                cookie_secret = f"{canonical}-cookie-secret"
                proc = subprocess.run(
                    [
                        BIN,
                        "config",
                        "set-cookie",
                        "--provider",
                        alias,
                        "--cookie",
                        cookie_secret,
                        "--json",
                    ],
                    cwd=ROOT,
                    env=env,
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=5,
                )
                assert proc.returncode == 0, (alias, proc.stdout, proc.stderr)
                assert cookie_secret not in proc.stdout, (alias, proc.stdout)
                payload = json.loads(proc.stdout)
                assert payload["provider"] == canonical, (alias, payload)
                assert payload["enabled"] is True, (alias, payload)
                assert payload["cookieSource"] == "manual", (alias, payload)

            proc = subprocess.run(
                [
                    BIN,
                    "config",
                    "set",
                    "--provider",
                    alias,
                    "--key",
                    "baseURL",
                    "--value",
                    f"https://example.com/{canonical}",
                    "--json",
                ],
                cwd=ROOT,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=5,
            )
            assert proc.returncode == 0, (alias, proc.stdout, proc.stderr)
            payload = json.loads(proc.stdout)
            assert payload["provider"] == canonical, (alias, payload)
            assert payload["displayName"] == display_name, (alias, payload)
            assert payload["key"] == "baseURL", (alias, payload)
            assert payload["present"] is True, (alias, payload)

            proc = subprocess.run(
                [
                    BIN,
                    "config",
                    "unset",
                    "--provider",
                    alias,
                    "--key",
                    "baseURL",
                    "--json",
                ],
                cwd=ROOT,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=5,
            )
            assert proc.returncode == 0, (alias, proc.stdout, proc.stderr)
            payload = json.loads(proc.stdout)
            assert payload["provider"] == canonical, (alias, payload)
            assert payload["displayName"] == display_name, (alias, payload)
            assert payload["key"] == "baseURL", (alias, payload)
            assert payload["present"] is False, (alias, payload)

        proc = subprocess.run(
            [BIN, "config", "order", "--provider", "alibaba,zai", "--json"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stderr
        payload = json.loads(proc.stdout)
        assert payload["providerOrder"][:2] == ["qwen", "glm"], payload

        for alias, canonical, display_name in [
            ("alibaba", "qwen", "Alibaba"),
            ("zai", "glm", "z.ai"),
        ]:
            label = f"{canonical}-primary"
            renamed = f"{canonical}-renamed"
            proc = subprocess.run(
                [
                    BIN,
                    "config",
                    "account",
                    "add",
                    "--provider",
                    alias,
                    "--token",
                    f"{canonical}-token",
                    "--label",
                    label,
                    "--external-id",
                    f"{canonical}-external",
                    "--json",
                ],
                cwd=ROOT,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=5,
            )
            assert proc.returncode == 0, (alias, proc.stdout, proc.stderr)
            payload = json.loads(proc.stdout)
            assert payload["provider"] == canonical, (alias, payload)
            assert payload["displayName"] == display_name, (alias, payload)
            assert payload["action"] == "add", (alias, payload)
            assert payload["activeIndex"] == 1, (alias, payload)
            assert payload["account"]["label"] == label, (alias, payload)
            assert payload["account"]["hasToken"] is True, (alias, payload)

            proc = subprocess.run(
                [
                    BIN,
                    "config",
                    "account",
                    "update",
                    "--provider",
                    alias,
                    "--account-index",
                    "1",
                    "--label",
                    renamed,
                    "--external-id",
                    f"{canonical}-updated",
                    "--json",
                ],
                cwd=ROOT,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=5,
            )
            assert proc.returncode == 0, (alias, proc.stdout, proc.stderr)
            payload = json.loads(proc.stdout)
            assert payload["provider"] == canonical, (alias, payload)
            assert payload["displayName"] == display_name, (alias, payload)
            assert payload["action"] == "update", (alias, payload)
            assert payload["account"]["label"] == renamed, (alias, payload)
            assert payload["account"]["externalIdentifier"] == f"{canonical}-updated", (alias, payload)

            proc = subprocess.run(
                [
                    BIN,
                    "config",
                    "account",
                    "select",
                    "--provider",
                    alias,
                    "--account",
                    renamed,
                    "--json",
                ],
                cwd=ROOT,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=5,
            )
            assert proc.returncode == 0, (alias, proc.stdout, proc.stderr)
            payload = json.loads(proc.stdout)
            assert payload["provider"] == canonical, (alias, payload)
            assert payload["action"] == "select", (alias, payload)
            assert payload["account"]["label"] == renamed, (alias, payload)

            proc = subprocess.run(
                [
                    BIN,
                    "config",
                    "account",
                    "remove",
                    "--provider",
                    alias,
                    "--account-index",
                    "1",
                    "--json",
                ],
                cwd=ROOT,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=5,
            )
            assert proc.returncode == 0, (alias, proc.stdout, proc.stderr)
            payload = json.loads(proc.stdout)
            assert payload["provider"] == canonical, (alias, payload)
            assert payload["displayName"] == display_name, (alias, payload)
            assert payload["action"] == "remove", (alias, payload)
            assert payload["account"]["label"] == renamed, (alias, payload)
            assert payload["accounts"] == [], (alias, payload)

        proc = subprocess.run(
            [BIN, "config", "dump", "--json"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stderr
        alias_dump = json.loads(proc.stdout)
        alias_providers = alias_dump["usage"]["providers"]
        alias_provider_keys = sorted(alias_providers.keys())
        assert "qwen" in alias_providers, alias_provider_keys
        assert "glm" in alias_providers, alias_provider_keys
        assert "alibaba" not in alias_providers, alias_provider_keys
        assert "zai" not in alias_providers, alias_provider_keys
        assert alias_providers["qwen"]["enabled"] is True, alias_provider_keys
        assert alias_providers["qwen"]["cookieSource"] == "manual", alias_provider_keys
        assert alias_providers["glm"]["enabled"] is True, alias_provider_keys

        proc = subprocess.run(
            [BIN, "config", "disable", "--provider", "nope"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode != 0, proc.stdout
        assert proc.stdout == "", proc.stdout
        assert "Unknown or missing provider. Use --provider <name>." in proc.stderr, proc.stderr

        proc = subprocess.run(
            [BIN, "config", "set-api-key", "--provider", "nope", "--api-key", "secret"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode != 0, proc.stdout
        assert proc.stdout == "", proc.stdout
        assert "Unknown or missing provider. Use --provider <name>." in proc.stderr, proc.stderr

        proc = subprocess.run(
            [BIN, "config", "set-api-key", "--provider", "openai", "--api-key", "secret", "--stdin"],
            cwd=ROOT,
            env=env,
            input="secret\n",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode != 0, proc.stdout
        assert proc.stdout == "", proc.stdout
        assert "Use either --api-key or --stdin, not both." in proc.stderr, proc.stderr

        proc = subprocess.run(
            [BIN, "config", "set-api-key", "--provider", "openai"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode != 0, proc.stdout
        assert proc.stdout == "", proc.stdout
        assert "Missing API key. Pass --api-key <key> or pipe it with --stdin." in proc.stderr, proc.stderr

        proc = subprocess.run(
            [BIN, "config", "set-cookie", "--provider", "openai", "--cookie", "session=unused"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode != 0, proc.stdout
        assert proc.stdout == "", proc.stdout
        assert "openai does not support config cookies." in proc.stderr, proc.stderr

        proc = subprocess.run(
            [BIN, "config", "set-cookie", "--provider", "commandcode", "--cookie", "secret", "--stdin"],
            cwd=ROOT,
            env=env,
            input="secret\n",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode != 0, proc.stdout
        assert proc.stdout == "", proc.stdout
        assert "Use either --cookie or --stdin, not both." in proc.stderr, proc.stderr

        proc = subprocess.run(
            [BIN, "config", "set-cookie", "--provider", "commandcode"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode != 0, proc.stdout
        assert proc.stdout == "", proc.stdout
        assert "Missing Cookie header. Pass --cookie <cookie> or pipe it with --stdin." in proc.stderr, proc.stderr

        cookie_config = os.path.join(tmpdir, "cookie.yaml")
        env["CONDUCTOR_CONFIG_PATH"] = cookie_config
        proc = subprocess.run(
            [
                BIN,
                "config",
                "set-cookie",
                "--provider",
                "commandcode",
                "--cookie",
                "__Secure-better-auth.session_token=manual",
                "--json",
            ],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stderr
        set_cookie_result = json.loads(proc.stdout)
        assert set_cookie_result["provider"] == "commandcode", set_cookie_result
        assert set_cookie_result["enabled"] is True, set_cookie_result
        assert set_cookie_result["cookieSource"] == "manual", set_cookie_result

        proc = subprocess.run(
            [BIN, "config", "dump", "--json"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stderr
        dumped = json.loads(proc.stdout)
        commandcode_config = dumped["usage"]["providers"]["commandcode"]
        assert commandcode_config["enabled"] is True, commandcode_config
        assert commandcode_config["cookieSource"] == "manual", commandcode_config
        assert commandcode_config["cookieHeader"] == "__Secure-better-auth.session_token=manual", commandcode_config

        proc = subprocess.run(
            [BIN, "config", "validate", "--json"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stderr
        assert json.loads(proc.stdout) == [], proc.stdout

        env["CONDUCTOR_CONFIG_PATH"] = warning_config
        proc = subprocess.run(
            [BIN, "config", "validate", "--json"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stderr
        warnings = json.loads(proc.stdout)
        messages = [issue["message"] for issue in warnings]
        assert any("cookieSource manual is set but cookieHeader is missing for codex" in message for message in messages), messages
        assert {issue["severity"] for issue in warnings} == {"warning"}, warnings
        assert {issue["code"] for issue in warnings} == {"cookie_header_missing"}, warnings

        token_accounts_config = os.path.join(tmpdir, "token-accounts.yaml")
        with open(token_accounts_config, "w", encoding="utf-8") as handle:
            handle.write(
                """
usage:
  providers:
    gemini:
      tokenAccounts:
        accounts:
          - label: unused
            token: secret
""".lstrip()
            )

        env["CONDUCTOR_CONFIG_PATH"] = token_accounts_config
        proc = subprocess.run(
            [BIN, "config", "validate", "--json"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stderr
        token_warnings = json.loads(proc.stdout)
        assert {issue["severity"] for issue in token_warnings} == {"warning"}, token_warnings
        assert any(issue["code"] == "token_accounts_unused" for issue in token_warnings), token_warnings

        account_config = os.path.join(tmpdir, "accounts.yaml")
        env["CONDUCTOR_CONFIG_PATH"] = account_config
        proc = subprocess.run(
            [BIN, "config", "account", "add", "--provider", "gemini", "--token", "nope"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode != 0, proc.stdout
        assert proc.stdout == "", proc.stdout
        assert "gemini does not support token accounts." in proc.stderr, proc.stderr

        proc = subprocess.run(
            [
                BIN,
                "config",
                "account",
                "add",
                "--provider",
                "openai",
                "--token",
                "sk-admin-1",
                "--label",
                "primary",
                "--organization",
                "org-1",
                "--json",
            ],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stderr
        assert "sk-admin-1" not in proc.stdout, proc.stdout
        account_result = json.loads(proc.stdout)
        assert account_result["provider"] == "openai", account_result
        assert account_result["action"] == "add", account_result
        assert account_result["enabled"] is True, account_result
        assert account_result["activeIndex"] == 1, account_result
        assert account_result["account"]["label"] == "primary", account_result
        assert account_result["account"]["organizationID"] == "org-1", account_result
        assert account_result["account"]["hasToken"] is True, account_result
        assert len(account_result["accounts"]) == 1, account_result

        proc = subprocess.run(
            [
                BIN,
                "config",
                "account",
                "add",
                "--provider",
                "openai",
                "--stdin",
                "--label",
                "secondary",
                "--external-id",
                "user@example.com",
                "--no-select",
                "--json",
            ],
            cwd=ROOT,
            env=env,
            input="sk-admin-2\n",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stderr
        assert "sk-admin-2" not in proc.stdout, proc.stdout
        account_result = json.loads(proc.stdout)
        assert account_result["activeIndex"] == 1, account_result
        assert account_result["account"]["label"] == "secondary", account_result
        assert account_result["account"]["active"] is False, account_result
        assert account_result["account"]["externalIdentifier"] == "user@example.com", account_result
        assert [item["label"] for item in account_result["accounts"]] == ["primary", "secondary"], account_result

        proc = subprocess.run(
            [BIN, "config", "accounts", "--provider", "openai", "--json"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stderr
        account_list = json.loads(proc.stdout)
        assert account_list["activeIndex"] == 1, account_list
        assert [item["active"] for item in account_list["accounts"]] == [True, False], account_list
        assert "sk-admin-1" not in proc.stdout, proc.stdout
        assert "sk-admin-2" not in proc.stdout, proc.stdout

        proc = subprocess.run(
            [
                BIN,
                "config",
                "account",
                "update",
                "--provider",
                "openai",
                "--account",
                "secondary",
                "--label",
                "secondary-renamed",
                "--organization",
                "org-2",
                "--external-id",
                "renamed@example.com",
                "--token",
                "sk-admin-2b",
                "--select",
                "--json",
            ],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stderr
        account_result = json.loads(proc.stdout)
        assert "sk-admin-2b" not in proc.stdout, proc.stdout
        assert account_result["action"] == "update", account_result
        assert account_result["activeIndex"] == 2, account_result
        assert account_result["account"]["label"] == "secondary-renamed", account_result
        assert account_result["account"]["organizationID"] == "org-2", account_result
        assert account_result["account"]["externalIdentifier"] == "renamed@example.com", account_result
        assert [item["active"] for item in account_result["accounts"]] == [False, True], account_result

        proc = subprocess.run(
            [BIN, "config", "account", "select", "--provider", "openai", "--account", "secondary-renamed", "--json"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stderr
        account_result = json.loads(proc.stdout)
        assert account_result["action"] == "select", account_result
        assert account_result["activeIndex"] == 2, account_result
        assert account_result["account"]["label"] == "secondary-renamed", account_result
        assert [item["active"] for item in account_result["accounts"]] == [False, True], account_result

        proc = subprocess.run(
            [BIN, "config", "account", "remove", "--provider", "openai", "--account-index", "1", "--json"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stderr
        account_result = json.loads(proc.stdout)
        assert account_result["action"] == "remove", account_result
        assert account_result["account"]["label"] == "primary", account_result
        assert account_result["activeIndex"] == 1, account_result
        assert [item["label"] for item in account_result["accounts"]] == ["secondary-renamed"], account_result
        assert account_result["accounts"][0]["active"] is True, account_result

        proc = subprocess.run(
            [BIN, "config", "dump", "--json"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stderr
        dumped = json.loads(proc.stdout)
        openai_accounts = dumped["usage"]["providers"]["openai"]["tokenAccounts"]
        assert openai_accounts["activeIndex"] == 0, openai_accounts
        assert openai_accounts["accounts"][0]["label"] == "secondary-renamed", openai_accounts
        assert openai_accounts["accounts"][0]["organizationId"] == "org-2", openai_accounts
        assert openai_accounts["accounts"][0]["externalIdentifier"] == "renamed@example.com", openai_accounts
        assert openai_accounts["accounts"][0]["token"] == "sk-admin-2b", openai_accounts

        field_config = os.path.join(tmpdir, "fields.yaml")
        env["CONDUCTOR_CONFIG_PATH"] = field_config
        for key, value in [
            ("sourceMode", "api"),
            ("baseURL", "https://api.openai.com"),
            ("projectID", "proj_123"),
            ("organizationID", "org_123"),
            ("extra.customTag", "alpha"),
        ]:
            proc = subprocess.run(
                [BIN, "config", "set", "--provider", "openai", "--key", key, "--value", value, "--json"],
                cwd=ROOT,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=5,
            )
            assert proc.returncode == 0, proc.stderr
            field_result = json.loads(proc.stdout)
            assert field_result["provider"] == "openai", field_result
            assert field_result["key"] == key, field_result
            assert field_result["present"] is True, field_result

        proc = subprocess.run(
            [BIN, "config", "dump", "--json"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stderr
        dumped = json.loads(proc.stdout)
        openai_config = dumped["usage"]["providers"]["openai"]
        assert openai_config["sourceMode"] == "api", openai_config
        assert openai_config["baseURL"] == "https://api.openai.com", openai_config
        assert openai_config["projectID"] == "proj_123", openai_config
        assert openai_config["organizationID"] == "org_123", openai_config
        assert openai_config["extra"]["customTag"] == "alpha", openai_config

        proc = subprocess.run(
            [BIN, "config", "unset", "--provider", "openai", "--key", "extra.customTag", "--json"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stderr
        field_result = json.loads(proc.stdout)
        assert field_result["key"] == "extra.customTag", field_result
        assert field_result["present"] is False, field_result

        proc = subprocess.run(
            [BIN, "config", "dump", "--json"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stderr
        dumped = json.loads(proc.stdout)
        openai_config = dumped["usage"]["providers"]["openai"]
        assert "customTag" not in openai_config.get("extra", {}), openai_config

        proc = subprocess.run(
            [BIN, "config", "set", "--provider", "openai", "--key", "sourceMode", "--value", "oauth"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode != 0, proc.stdout
        assert proc.stdout == "", proc.stdout
        assert "Source oauth is not supported for openai" in proc.stderr, proc.stderr

        proc = subprocess.run(
            [BIN, "config", "set", "--provider", "openai", "--key", "baseURL", "--value", "ftp://bad"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode != 0, proc.stdout
        assert proc.stdout == "", proc.stdout
        assert "baseURL must be an http or https URL." in proc.stderr, proc.stderr

        minimax_config = os.path.join(tmpdir, "minimax.yaml")
        with open(minimax_config, "w", encoding="utf-8") as handle:
            handle.write(
                """
usage:
  providers:
    minimax:
      sourceMode: web
      cookieSource: manual
      cookieHeader: sid=manual
      baseURL: https://api.minimax.io
      extra:
        region: cn
        remainsURL: https://api.minimax.io/v1/token_plan/remains
        codingPlanURL: https://platform.minimax.io/user-center/payment/coding-plan
        billingHistoryURL: https://www.minimax.io/api/user-center/payment/billing-history
        requireProviderEndpointOverrides: true
""".lstrip()
            )

        env["CONDUCTOR_CONFIG_PATH"] = minimax_config
        proc = subprocess.run(
            [BIN, "config", "validate", "--json"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stderr
        assert json.loads(proc.stdout) == [], proc.stdout

        proc = subprocess.run(
            [BIN, "config", "providers", "--provider", "minimax", "--json"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stderr
        minimax_providers = json.loads(proc.stdout)
        assert minimax_providers[0]["environmentHints"]["apiKey"] == [
            "MINIMAX_CODING_API_KEY",
            "MINIMAX_API_KEY",
        ], minimax_providers
        assert minimax_providers[0]["environmentHints"]["cookieHeader"] == [
            "MINIMAX_COOKIE",
            "MINIMAX_COOKIE_HEADER",
        ], minimax_providers
        assert minimax_providers[0]["environmentHints"]["baseURL"] == ["MINIMAX_HOST"], minimax_providers
        region_env = minimax_providers[0]["environmentHints"]["extra"]["region"]
        assert "MINIMAX_REGION" in region_env, minimax_providers
        assert minimax_providers[0]["environmentHints"]["extra"]["remainsURL"] == ["MINIMAX_REMAINS_URL"], minimax_providers
        assert minimax_providers[0]["environmentHints"]["extra"]["codingPlanURL"] == [
            "MINIMAX_CODING_PLAN_URL"
        ], minimax_providers
        assert minimax_providers[0]["environmentHints"]["extra"]["billingHistoryURL"] == [
            "MINIMAX_BILLING_HISTORY_URL"
        ], minimax_providers
        assert minimax_providers[0]["environmentHints"]["extra"]["requireProviderEndpointOverrides"] == [
            "MINIMAX_REQUIRE_PROVIDER_ENDPOINT_OVERRIDES"
        ], minimax_providers

        glm_config = os.path.join(tmpdir, "glm.yaml")
        with open(glm_config, "w", encoding="utf-8") as handle:
            handle.write(
                """
usage:
  providers:
    glm:
      extra:
        region: bigmodel-cn
""".lstrip()
            )

        env["CONDUCTOR_CONFIG_PATH"] = glm_config
        proc = subprocess.run(
            [BIN, "config", "validate", "--json"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stderr
        assert json.loads(proc.stdout) == [], proc.stdout

        proc = subprocess.run(
            [BIN, "config", "providers", "--provider", "glm", "--json"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stderr
        glm_providers = json.loads(proc.stdout)
        glm_region_env = glm_providers[0]["environmentHints"]["extra"]["region"]
        assert "Z_AI_REGION" in glm_region_env, glm_providers

        invalid_glm_config = os.path.join(tmpdir, "invalid-glm.yaml")
        with open(invalid_glm_config, "w", encoding="utf-8") as handle:
            handle.write(
                """
usage:
  providers:
    glm:
      extra:
        region: cn
""".lstrip()
            )

        env["CONDUCTOR_CONFIG_PATH"] = invalid_glm_config
        proc = subprocess.run(
            [BIN, "config", "validate", "--json"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode != 0, proc.stdout
        invalid_glm_errors = json.loads(proc.stdout)
        assert any(issue["code"] == "invalid_region" for issue in invalid_glm_errors), invalid_glm_errors

        qwen_config = os.path.join(tmpdir, "qwen.yaml")
        with open(qwen_config, "w", encoding="utf-8") as handle:
            handle.write(
                """
usage:
  providers:
    qwen:
      baseURL: https://modelstudio.console.alibabacloud.com
      extra:
        region: cn
        quotaURL: https://modelstudio.console.alibabacloud.com/data/api.json
""".lstrip()
            )

        env["CONDUCTOR_CONFIG_PATH"] = qwen_config
        proc = subprocess.run(
            [BIN, "config", "validate", "--json"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stderr
        assert json.loads(proc.stdout) == [], proc.stdout

        proc = subprocess.run(
            [BIN, "config", "providers", "--provider", "qwen", "--json"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stderr
        qwen_providers = json.loads(proc.stdout)
        qwen_base_env = qwen_providers[0]["environmentHints"]["baseURL"]
        assert "ALIBABA_CODING_PLAN_HOST" in qwen_base_env, qwen_providers
        qwen_region_env = qwen_providers[0]["environmentHints"]["extra"]["region"]
        assert "ALIBABA_CODING_PLAN_REGION" in qwen_region_env, qwen_providers
        assert "QWEN_REGION" in qwen_region_env, qwen_providers
        qwen_quota_url_env = qwen_providers[0]["environmentHints"]["extra"]["quotaURL"]
        assert "ALIBABA_CODING_PLAN_QUOTA_URL" in qwen_quota_url_env, qwen_providers

        invalid_qwen_config = os.path.join(tmpdir, "invalid-qwen.yaml")
        with open(invalid_qwen_config, "w", encoding="utf-8") as handle:
            handle.write(
                """
usage:
  providers:
    qwen:
      extra:
        region: global
""".lstrip()
            )

        env["CONDUCTOR_CONFIG_PATH"] = invalid_qwen_config
        proc = subprocess.run(
            [BIN, "config", "validate", "--json"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode != 0, proc.stdout
        invalid_qwen_errors = json.loads(proc.stdout)
        assert any(issue["code"] == "invalid_region" for issue in invalid_qwen_errors), invalid_qwen_errors

        invalid_qwen_endpoint_config = os.path.join(tmpdir, "invalid-qwen-endpoint.yaml")
        with open(invalid_qwen_endpoint_config, "w", encoding="utf-8") as handle:
            handle.write(
                """
usage:
  providers:
    qwen:
      baseURL: http://modelstudio.console.alibabacloud.com
      extra:
        quotaURL: http://modelstudio.console.alibabacloud.com/data/api.json
""".lstrip()
            )

        env["CONDUCTOR_CONFIG_PATH"] = invalid_qwen_endpoint_config
        proc = subprocess.run(
            [BIN, "config", "validate", "--json"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode != 0, proc.stdout
        invalid_qwen_endpoint_errors = json.loads(proc.stdout)
        endpoint_fields = {issue["field"] for issue in invalid_qwen_endpoint_errors if issue["code"] == "invalid_endpoint_override"}
        assert {"baseURL", "extra.quotaURL"}.issubset(endpoint_fields), invalid_qwen_endpoint_errors

        alibaba_token_plan_config = os.path.join(tmpdir, "alibaba-token-plan.yaml")
        with open(alibaba_token_plan_config, "w", encoding="utf-8") as handle:
            handle.write(
                """
usage:
  providers:
    alibabatokenplan:
      baseURL: https://bailian.console.aliyun.com
      extra:
        quotaURL: https://bailian.console.aliyun.com/data/api.json
""".lstrip()
            )

        env["CONDUCTOR_CONFIG_PATH"] = alibaba_token_plan_config
        proc = subprocess.run(
            [BIN, "config", "validate", "--json"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stderr
        assert json.loads(proc.stdout) == [], proc.stdout

        proc = subprocess.run(
            [BIN, "config", "providers", "--provider", "alibabatokenplan", "--json"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stderr
        token_plan_providers = json.loads(proc.stdout)
        assert token_plan_providers[0]["environmentHints"]["baseURL"] == [
            "ALIBABA_TOKEN_PLAN_HOST"
        ], token_plan_providers
        assert token_plan_providers[0]["supportsAPIKey"] is False, token_plan_providers
        assert token_plan_providers[0]["environmentHints"]["apiKey"] == [], token_plan_providers
        assert token_plan_providers[0]["environmentHints"]["cookieHeader"] == [
            "ALIBABA_TOKEN_PLAN_COOKIE"
        ], token_plan_providers
        assert token_plan_providers[0]["environmentHints"]["extra"]["quotaURL"] == [
            "ALIBABA_TOKEN_PLAN_QUOTA_URL"
        ], token_plan_providers

        proc = subprocess.run(
            [BIN, "config", "providers", "--provider", "perplexity,manus,commandcode", "--json"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stderr
        session_providers = {provider["provider"]: provider for provider in json.loads(proc.stdout)}
        assert session_providers["perplexity"]["supportsAPIKey"] is False, session_providers
        assert session_providers["perplexity"]["environmentHints"]["apiKey"] == [], session_providers
        assert session_providers["perplexity"]["environmentHints"]["cookieHeader"] == [
            "PERPLEXITY_SESSION_TOKEN",
            "perplexity_session_token",
            "PERPLEXITY_COOKIE",
        ], session_providers
        assert session_providers["manus"]["supportsAPIKey"] is False, session_providers
        assert session_providers["manus"]["environmentHints"]["apiKey"] == [], session_providers
        assert session_providers["manus"]["environmentHints"]["cookieHeader"] == [
            "MANUS_SESSION_TOKEN",
            "manus_session_token",
            "MANUS_SESSION_ID",
            "manus_session_id",
            "MANUS_COOKIE",
            "manus_cookie",
        ], session_providers
        assert session_providers["commandcode"]["supportsAPIKey"] is False, session_providers
        assert session_providers["commandcode"]["environmentHints"]["apiKey"] == [], session_providers
        assert session_providers["commandcode"]["environmentHints"]["cookieHeader"] == [
            "COMMANDCODE_SESSION_TOKEN",
            "COMMANDCODE_COOKIE",
            "COMMANDCODE_TOKEN",
        ], session_providers

        invalid_alibaba_token_plan_config = os.path.join(tmpdir, "invalid-alibaba-token-plan.yaml")
        with open(invalid_alibaba_token_plan_config, "w", encoding="utf-8") as handle:
            handle.write(
                """
usage:
  providers:
    alibabatokenplan:
      baseURL: http://bailian.console.aliyun.com
      extra:
        quotaURL: http://bailian.console.aliyun.com/data/api.json
""".lstrip()
            )

        env["CONDUCTOR_CONFIG_PATH"] = invalid_alibaba_token_plan_config
        proc = subprocess.run(
            [BIN, "config", "validate", "--json"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode != 0, proc.stdout
        invalid_token_plan_endpoint_errors = json.loads(proc.stdout)
        endpoint_fields = {
            issue["field"]
            for issue in invalid_token_plan_endpoint_errors
            if issue["code"] == "invalid_endpoint_override"
        }
        assert {"baseURL", "extra.quotaURL"}.issubset(endpoint_fields), invalid_token_plan_endpoint_errors

        invalid_minimax_config = os.path.join(tmpdir, "invalid-minimax.yaml")
        with open(invalid_minimax_config, "w", encoding="utf-8") as handle:
            handle.write(
                """
usage:
  providers:
    minimax:
      baseURL: https://example.com
      extra:
        region: nowhere
        remainsURL: http://api.minimax.io/v1/token_plan/remains
        codingPlanURL: http://platform.minimax.io/user-center/payment/coding-plan
        billingHistoryURL: http://www.minimax.io/api/user-center/payment/billing-history
        requireProviderEndpointOverrides: true
""".lstrip()
            )

        env["CONDUCTOR_CONFIG_PATH"] = invalid_minimax_config
        proc = subprocess.run(
            [BIN, "config", "validate", "--json"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode != 0, proc.stdout
        invalid_minimax_errors = json.loads(proc.stdout)
        assert any(issue["code"] == "invalid_region" for issue in invalid_minimax_errors), invalid_minimax_errors
        minimax_endpoint_fields = {
            issue["field"] for issue in invalid_minimax_errors if issue["code"] == "invalid_endpoint_override"
        }
        assert {"baseURL", "extra.remainsURL", "extra.codingPlanURL", "extra.billingHistoryURL"}.issubset(
            minimax_endpoint_fields
        ), invalid_minimax_errors

        provider_fields_config = os.path.join(tmpdir, "provider-fields.yaml")
        with open(provider_fields_config, "w", encoding="utf-8") as handle:
            handle.write(
                """
usage:
  providers:
    gemini:
      projectID: workspace-123
      organizationID: org-123
      extra:
        enterpriseHost: https://enterprise.example.com
        region: nowhere
        awsSecretAccessKey: secret
""".lstrip()
            )

        env["CONDUCTOR_CONFIG_PATH"] = provider_fields_config
        proc = subprocess.run(
            [BIN, "config", "validate", "--json"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stderr
        provider_field_warnings = json.loads(proc.stdout)
        warning_codes = {issue["code"] for issue in provider_field_warnings}
        assert {
            "workspace_unused",
            "organization_unused",
            "enterprise_host_unused",
            "region_unused",
            "secret_key_unused",
        }.issubset(warning_codes), provider_field_warnings
        assert {issue["severity"] for issue in provider_field_warnings} == {"warning"}, provider_field_warnings

        invalid_region_config = os.path.join(tmpdir, "invalid-region.yaml")
        with open(invalid_region_config, "w", encoding="utf-8") as handle:
            handle.write(
                """
usage:
  providers:
    moonshot:
      extra:
        region: nowhere
""".lstrip()
            )

        env["CONDUCTOR_CONFIG_PATH"] = invalid_region_config
        proc = subprocess.run(
            [BIN, "config", "validate", "--json"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode != 0, proc.stdout
        invalid_region_errors = json.loads(proc.stdout)
        assert any(issue["code"] == "invalid_region" for issue in invalid_region_errors), invalid_region_errors

        error_config = os.path.join(tmpdir, "errors.yaml")
        with open(error_config, "w", encoding="utf-8") as handle:
            handle.write(
                """
usage:
  providers:
    openai:
      sourceMode: oauth
""".lstrip()
            )

        env["CONDUCTOR_CONFIG_PATH"] = error_config
        proc = subprocess.run(
            [BIN, "config", "validate", "--json"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode != 0, proc.stdout
        errors = json.loads(proc.stdout)
        assert any(issue["severity"] == "error" and issue["field"] == "sourceMode" for issue in errors), errors
        assert any(issue["code"] == "unsupported_source" for issue in errors), errors

        web_env = os.environ.copy()
        for key in [
            "MINIMAX_API_KEY",
            "MINIMAX_CODING_API_KEY",
            "MINIMAX_COOKIE",
            "MINIMAX_COOKIE_HEADER",
            "CONDUCTOR_USAGE_MINIMAX_COOKIE",
        ]:
            web_env.pop(key, None)
        web_env["CONDUCTOR_USAGE_MINIMAX_COOKIE_SOURCE"] = "manual"
        proc = subprocess.run(
            [BIN, "usage", "--provider", "minimax", "--source", "web", "--format", "json"],
            cwd=ROOT,
            env=web_env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stderr
        web_reports = json.loads(proc.stdout)
        assert web_reports[0]["provider"] == "minimax", web_reports
        assert web_reports[0]["source"] == "web", web_reports
        assert "MiniMax session was not found" in web_reports[0]["error"]["message"], web_reports


def test_usage_marks_token_account_last_used():
    with tempfile.TemporaryDirectory(prefix="conductorctl-token-last-used-") as tmpdir:
        seen_paths = []
        seen_authorizations = []

        class LiteLLMHandler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                seen_paths.append(self.path)
                seen_authorizations.append(self.headers.get("Authorization"))
                if self.path == "/key/info":
                    payload = {
                        "info": {
                            "user_id": "user-1",
                            "key_name": "primary-key",
                            "spend": 4.25,
                        }
                    }
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json")
                    self.end_headers()
                    self.wfile.write(json.dumps(payload).encode())
                    return
                if self.path.startswith("/user/info"):
                    payload = {
                        "user_id": "user-1",
                        "user_info": {
                            "user_id": "user-1",
                            "user_email": "litellm@example.com",
                            "spend": 4.25,
                            "max_budget": 10.0,
                            "budget_reset_at": "2026-07-01T00:00:00Z",
                        },
                        "teams": [],
                    }
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json")
                    self.end_headers()
                    self.wfile.write(json.dumps(payload).encode())
                    return
                self.send_response(404)
                self.end_headers()

            def log_message(self, *_):
                pass

        httpd = http.server.ThreadingHTTPServer(("127.0.0.1", 0), LiteLLMHandler)
        thread = threading.Thread(target=httpd.serve_forever, daemon=True)
        thread.start()
        try:
            base_url = f"http://127.0.0.1:{httpd.server_port}/v1"
            config_path = os.path.join(tmpdir, "config.yaml")
            with open(config_path, "w", encoding="utf-8") as handle:
                handle.write(
                    f"""
usage:
  providers:
    litellm:
      enabled: true
      baseURL: {base_url}
      tokenAccounts:
        activeIndex: 0
        accounts:
          - id: 11111111-1111-1111-1111-111111111111
            label: Primary
            token: litellm-primary-token
            addedAt: 1
""".lstrip()
                )

            env = os.environ.copy()
            env["CONDUCTOR_CONFIG_PATH"] = config_path
            env["HOME"] = os.path.join(tmpdir, "home")
            os.makedirs(env["HOME"], exist_ok=True)

            before = time.time()
            proc = subprocess.run(
                [BIN, "usage", "--provider", "litellm", "--source", "api", "--json-only"],
                cwd=ROOT,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
            )
            assert proc.returncode == 0, proc.stdout + proc.stderr
            assert proc.stderr == "", proc.stderr
            payload = json.loads(proc.stdout)
            assert payload[0]["provider"] == "litellm", payload
            assert payload[0]["account"] == "Primary", payload
            assert payload[0]["usage"]["accountLabel"] == "litellm@example.com", payload
            assert payload[0]["usage"]["windows"][0]["usedPercent"] == 42.5, payload
            assert seen_paths[0] == "/key/info", seen_paths
            assert seen_paths[1].startswith("/user/info?user_id=user-1"), seen_paths
            assert set(seen_authorizations) == {"Bearer litellm-primary-token"}, seen_authorizations

            proc = subprocess.run(
                [BIN, "config", "dump", "--json"],
                cwd=ROOT,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=5,
            )
            assert proc.returncode == 0, proc.stderr
            dumped = json.loads(proc.stdout)
            account = dumped["usage"]["providers"]["litellm"]["tokenAccounts"]["accounts"][0]
            assert account["token"] == "litellm-primary-token", account
            assert account["lastUsed"] >= before, account

            proc = subprocess.run(
                [BIN, "config", "accounts", "--provider", "litellm"],
                cwd=ROOT,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=5,
            )
            assert proc.returncode == 0, proc.stderr
            assert "* 1. Primary" in proc.stdout, proc.stdout
            assert "last-used=" in proc.stdout, proc.stdout
            assert "token=yes" in proc.stdout, proc.stdout
            assert "litellm-primary-token" not in proc.stdout, proc.stdout
        finally:
            httpd.shutdown()
            httpd.server_close()


def test_usage_repair_actions_include_config_commands():
    with tempfile.TemporaryDirectory(prefix="conductorctl-repair-actions-") as tmpdir:
        home = os.path.join(tmpdir, "home")
        config_path = os.path.join(tmpdir, "config.yaml")
        os.makedirs(home, exist_ok=True)
        with open(config_path, "w", encoding="utf-8") as handle:
            handle.write(
                """
usage:
  providers:
    litellm:
      enabled: true
""".lstrip()
            )

        env = isolated_usage_env(tmpdir, home, config_path=config_path)
        env["LITELLM_API_KEY"] = "litellm-smoke-key"
        env.pop("LITELLM_BASE_URL", None)

        proc = subprocess.run(
            [BIN, "usage", "--provider", "litellm", "--source", "api", "--json-only"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stdout + proc.stderr
        assert proc.stderr == "", proc.stderr
        payload = json.loads(proc.stdout)
        assert payload[0]["provider"] == "litellm", payload
        assert payload[0].get("usage") is None, payload
        assert "LITELLM_BASE_URL" in payload[0]["error"]["message"], payload
        commands = {
            action.get("id"): action.get("command")
            for action in payload[0]["repairActions"]
        }
        assert commands["configure-base-url"] == (
            "conductorctl config set --provider litellm --key baseURL --value <url>"
        ), commands
        assert commands["configureCredential"] == (
            "conductorctl config set-api-key --provider litellm --api-key <key>"
        ), commands

        proc = subprocess.run(
            [BIN, "usage", "--provider", "litellm", "--source", "api", "--format", "text"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stdout + proc.stderr
        assert proc.stderr == "", proc.stderr
        assert "command: conductorctl config set --provider litellm --key baseURL --value <url>" in proc.stdout, proc.stdout
        assert "command: conductorctl config set-api-key --provider litellm --api-key <key>" in proc.stdout, proc.stdout

        proc = subprocess.run(
            [BIN, "diagnose", "--provider", "litellm", "--json-only"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stdout + proc.stderr
        assert proc.stderr == "", proc.stderr
        payload = json.loads(proc.stdout)
        assert payload["provider"] == "litellm", payload
        diagnose_commands = {
            action.get("id"): action.get("command")
            for action in payload["repairActions"]
        }
        assert diagnose_commands["configure-base-url"] == (
            "conductorctl config set --provider litellm --key baseURL --value <url>"
        ), diagnose_commands

        proc = subprocess.run(
            [BIN, "diagnose", "--provider", "litellm", "--format", "text"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stdout + proc.stderr
        assert proc.stderr == "", proc.stderr
        assert "command: conductorctl config set --provider litellm --key baseURL --value <url>" in proc.stdout, proc.stdout


def test_usage_cli_help_has_no_side_effects():
    with tempfile.TemporaryDirectory(prefix="conductorctl-help-") as tmpdir:
        home = os.path.join(tmpdir, "home")
        config_path = os.path.join(tmpdir, "config.yaml")
        env = isolated_usage_env(tmpdir, home, config_path=config_path)
        env["CONDUCTOR_SOCKET_PATH"] = os.path.join(tmpdir, "missing.sock")
        commands = [
            (["--help", "usage"], "Usage: conductorctl usage"),
            (["usage", "--help"], "Usage: conductorctl usage"),
            (["diagnose", "--help"], "Usage: conductorctl diagnose"),
            (["storage", "--help"], "Usage: conductorctl storage"),
            (["provider-status", "--help"], "Usage: conductorctl provider-status"),
            (["cost", "--help"], "Usage: conductorctl cost"),
            (["cache", "--help"], "Usage: conductorctl cache clear"),
            (["cache", "clear", "--help"], "Usage: conductorctl cache clear"),
            (["config", "--help"], "conductorctl config providers"),
            (["config", "validate", "--help"], "conductorctl config validate"),
            (["serve", "--help"], "Usage: conductorctl serve"),
        ]
        for args, expected in commands:
            proc = subprocess.run(
                [BIN] + args,
                cwd=ROOT,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=5,
            )
            assert proc.returncode == 0, (args, proc.stderr)
            assert expected in proc.stdout, (args, proc.stdout)
            if args == ["--help", "usage"] or args == ["usage", "--help"]:
                assert "--web" in proc.stdout, proc.stdout
            if args in [
                ["--help", "usage"],
                ["usage", "--help"],
                ["diagnose", "--help"],
                ["storage", "--help"],
                ["provider-status", "--help"],
                ["cache", "--help"],
                ["cache", "clear", "--help"],
                ["config", "--help"],
            ]:
                assert "ID_OR_ALIAS" in proc.stdout, (args, proc.stdout)
            if args == ["cost", "--help"]:
                assert "--provider all|both|codex|claude|vertexai|bedrock" in proc.stdout, proc.stdout
            if args == ["serve", "--help"]:
                assert "Endpoints:" in proc.stdout, proc.stdout
                assert "GET  /health" in proc.stdout, proc.stdout
                assert "GET  /openapi.json" in proc.stdout, proc.stdout
                assert "GET  /usage?provider=all" in proc.stdout, proc.stdout
                assert "GET  /cost?provider=all" in proc.stdout, proc.stdout
                assert "GET  /config/dump" in proc.stdout, proc.stdout
                assert "GET  /config/accounts?provider=ID_OR_ALIAS" in proc.stdout, proc.stdout
                assert "POST /config/account" in proc.stdout, proc.stdout
                assert "POST /config/provider" in proc.stdout, proc.stdout
                assert "POST /config/order" in proc.stdout, proc.stdout
                assert "POST /cache/clear" in proc.stdout, proc.stdout
            assert proc.stderr == "", (args, proc.stderr)
        version = subprocess.run(
            [BIN, "--version"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert version.returncode == 0, version.stderr
        assert version.stdout.startswith("Conductor"), version.stdout
        assert version.stderr == "", version.stderr
        assert not os.path.exists(config_path), config_path
        assert not os.path.exists(os.path.join(home, "Library", "Caches", "Conductor")), home


def test_usage_cli_json_only_alias():
    with tempfile.TemporaryDirectory(prefix="conductorctl-json-only-") as tmpdir:
        home = os.path.join(tmpdir, "home")
        config_path = os.path.join(tmpdir, "config.yaml")
        os.makedirs(home, exist_ok=True)
        with open(config_path, "w", encoding="utf-8") as handle:
            handle.write(
                """
usage:
  providers:
    openai:
      sourceMode: oauth
""".lstrip()
            )

        env = isolated_usage_env(tmpdir, home, config_path=config_path)
        proc = subprocess.run(
            [BIN, "config", "validate", "--json-only"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode != 0, proc.stdout
        assert proc.stderr == "", proc.stderr
        issues = json.loads(proc.stdout)
        assert any(issue["code"] == "unsupported_source" for issue in issues), issues

        proc = subprocess.run(
            [BIN, "config", "--json-only"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode != 0, proc.stdout
        assert proc.stderr == "", proc.stderr
        default_issues = json.loads(proc.stdout)
        assert default_issues == issues, (default_issues, issues)

        proc = subprocess.run(
            [BIN, "cost", "--provider", "nope", "--json-only"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode != 0, proc.stdout
        assert proc.stderr == "", proc.stderr
        payload = json.loads(proc.stdout)
        assert payload[0]["provider"] == "cli", payload
        assert payload[0]["error"]["message"] == "--provider must be all, both, codex, claude, vertexai, or bedrock", payload

        proc = subprocess.run(
            [BIN, "--provider", "nope", "--json-only"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode != 0, proc.stdout
        assert proc.stderr == "", proc.stderr
        payload = json.loads(proc.stdout)
        assert payload[0]["provider"] == "cli", payload
        assert "Unknown provider 'nope'" in payload[0]["error"]["message"], payload

        proc = subprocess.run(
            [BIN, "-v", "--provider", "nope", "--json-only"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode != 0, proc.stdout
        assert proc.stderr == "", proc.stderr
        payload = json.loads(proc.stdout)
        assert payload[0]["provider"] == "cli", payload
        assert "Unknown provider 'nope'" in payload[0]["error"]["message"], payload

        proc = subprocess.run(
            [BIN, "usage", "-v", "--provider", "nope", "--json-only"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode != 0, proc.stdout
        assert proc.stderr == "", proc.stderr
        payload = json.loads(proc.stdout)
        assert payload[0]["provider"] == "cli", payload
        assert "Unknown provider 'nope'" in payload[0]["error"]["message"], payload

        proc = subprocess.run(
            [BIN, "--log-level", "error", "--json-only", "--provider", "nope"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode != 0, proc.stdout
        assert proc.stderr == "", proc.stderr
        payload = json.loads(proc.stdout)
        assert payload[0]["provider"] == "cli", payload
        assert "Unknown provider 'nope'" in payload[0]["error"]["message"], payload

        proc = subprocess.run(
            [BIN, "usage", "--provider", "both", "--all-accounts", "--json-only"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode != 0, proc.stdout
        assert proc.stderr == "", proc.stderr
        payload = json.loads(proc.stdout)
        assert payload[0]["provider"] == "cli", payload
        assert payload[0]["error"]["message"] == "account selection requires a single provider.", payload

        proc = subprocess.run(
            [BIN, "usage", "--provider", "gemini", "--all-accounts", "--json-only"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode != 0, proc.stdout
        assert proc.stderr == "", proc.stderr
        payload = json.loads(proc.stdout)
        assert payload[0]["provider"] == "cli", payload
        assert payload[0]["error"]["message"] == "gemini does not support token accounts.", payload

        kilo_auth_dir = os.path.join(home, ".local", "share", "kilo")
        os.makedirs(kilo_auth_dir, exist_ok=True)
        with open(os.path.join(kilo_auth_dir, "auth.json"), "w", encoding="utf-8") as handle:
            handle.write('{"kilo":{"access":"cli-token"}}')

        kilo_api_env = env.copy()
        kilo_api_env.pop("KILO_API_KEY", None)
        proc = subprocess.run(
            [BIN, "usage", "--provider", "kilo", "--source", "api", "--json-only"],
            cwd=ROOT,
            env=kilo_api_env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stdout
        assert proc.stderr == "", proc.stderr
        payload = json.loads(proc.stdout)
        assert payload[0]["provider"] == "kilo", payload
        assert payload[0]["source"] == "api", payload
        assert "KILO_API_KEY" in payload[0]["error"]["message"], payload

        kilo_cli_home = os.path.join(tmpdir, "kilo-cli-empty-home")
        os.makedirs(kilo_cli_home, exist_ok=True)
        kilo_cli_env = env.copy()
        kilo_cli_env["HOME"] = kilo_cli_home
        kilo_cli_env["CFFIXED_USER_HOME"] = kilo_cli_home
        kilo_cli_env["KILO_API_KEY"] = "api-token"
        proc = subprocess.run(
            [BIN, "usage", "--provider", "kilo", "--source", "cli", "--json-only"],
            cwd=ROOT,
            env=kilo_cli_env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stdout
        assert proc.stderr == "", proc.stderr
        payload = json.loads(proc.stdout)
        assert payload[0]["provider"] == "kilo", payload
        assert payload[0]["source"] == "cli", payload
        assert "auth.json" in payload[0]["error"]["message"], payload

        copilot_cookie_env = env.copy()
        copilot_cookie_env.pop("COPILOT_API_TOKEN", None)
        copilot_cookie_env["CONDUCTOR_USAGE_COPILOT_COOKIE"] = "user_session=manual"
        proc = subprocess.run(
            [BIN, "usage", "--provider", "copilot", "--json-only"],
            cwd=ROOT,
            env=copilot_cookie_env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stdout
        assert proc.stderr == "", proc.stderr
        payload = json.loads(proc.stdout)
        assert payload[0]["provider"] == "copilot", payload
        assert payload[0]["configured"] is False, payload
        assert "OAuth token" in payload[0]["error"]["message"], payload

        copilot_web_env = env.copy()
        copilot_web_env["COPILOT_API_TOKEN"] = "fake-token"
        proc = subprocess.run(
            [BIN, "usage", "--provider", "copilot", "--source", "web", "--json-only"],
            cwd=ROOT,
            env=copilot_web_env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stdout
        assert proc.stderr == "", proc.stderr
        payload = json.loads(proc.stdout)
        assert payload[0]["provider"] == "copilot", payload
        assert payload[0]["source"] == "web", payload
        assert payload[0]["configured"] is True, payload
        assert "auto" in payload[0]["error"]["message"], payload
        assert "api" in payload[0]["error"]["message"], payload

        ollama_api_env = env.copy()
        ollama_api_env.pop("OLLAMA_API_KEY", None)
        ollama_api_env.pop("OLLAMA_KEY", None)
        ollama_api_env["CONDUCTOR_USAGE_OLLAMA_COOKIE"] = "session=manual"
        proc = subprocess.run(
            [BIN, "usage", "--provider", "ollama", "--source", "api", "--json-only"],
            cwd=ROOT,
            env=ollama_api_env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stdout
        assert proc.stderr == "", proc.stderr
        payload = json.loads(proc.stdout)
        assert payload[0]["provider"] == "ollama", payload
        assert payload[0]["source"] == "api", payload
        assert payload[0]["configured"] is True, payload
        assert "OLLAMA_API_KEY" in payload[0]["error"]["message"], payload

        mimo_paths = []

        class MiMoRedirectHandler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                mimo_paths.append(self.path)
                self.send_response(302)
                self.end_headers()

            def log_message(self, *_):
                pass

        mimo_httpd = http.server.ThreadingHTTPServer(("127.0.0.1", 0), MiMoRedirectHandler)
        mimo_thread = threading.Thread(target=mimo_httpd.serve_forever, daemon=True)
        mimo_thread.start()
        try:
            mimo_env = env.copy()
            mimo_env["MIMO_API_URL"] = f"http://127.0.0.1:{mimo_httpd.server_port}/api/v1"
            mimo_env["CONDUCTOR_USAGE_MIMO_COOKIE"] = "api-platform_serviceToken=expired-token; userId=123"
            proc = subprocess.run(
                [BIN, "usage", "--provider", "mimo", "--source", "web", "--json-only"],
                cwd=ROOT,
                env=mimo_env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=5,
            )
        finally:
            mimo_httpd.shutdown()
            mimo_httpd.server_close()
        assert proc.returncode == 0, proc.stdout
        assert proc.stderr == "", proc.stderr
        payload = json.loads(proc.stdout)
        assert payload[0]["provider"] == "mimo", payload
        assert payload[0]["source"] == "web", payload
        assert payload[0]["configured"] is True, payload
        assert payload[0].get("usage") is None, payload
        assert any(path.endswith("/api/v1/tokenPlan/usage") for path in mimo_paths), mimo_paths
        assert "MiMo" in payload[0]["error"]["message"], payload
        assert (
            "登录" in payload[0]["error"]["message"]
            or "login" in payload[0]["error"]["message"].lower()
            or "sign-in" in payload[0]["error"]["message"].lower()
        ), payload
        assert any(action["kind"] == "signIn" for action in payload[0]["repairActions"]), payload[0]["repairActions"]

        kimi_web_env = env.copy()
        kimi_web_env["KIMI_CODE_API_KEY"] = "fake-code-api-key"
        kimi_web_env.pop("KIMI_AUTH_TOKEN", None)
        kimi_web_env.pop("kimi_auth_token", None)
        kimi_web_env.pop("KIMI_MANUAL_COOKIE", None)
        kimi_web_env["CONDUCTOR_USAGE_KIMI_COOKIE_SOURCE"] = "off"
        proc = subprocess.run(
            [BIN, "usage", "--provider", "kimi", "--source", "web", "--json-only"],
            cwd=ROOT,
            env=kimi_web_env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stdout
        assert proc.stderr == "", proc.stderr
        payload = json.loads(proc.stdout)
        assert payload[0]["provider"] == "kimi", payload
        assert payload[0]["source"] == "web", payload
        assert payload[0]["configured"] is True, payload
        assert "KIMI_AUTH_TOKEN" in payload[0]["error"]["message"], payload

        qwen_web_env = env.copy()
        qwen_web_env["DASHSCOPE_API_KEY"] = "fake-dashscope-key"
        qwen_web_env.pop("ALIBABA_CODING_PLAN_COOKIE", None)
        qwen_web_env["CONDUCTOR_USAGE_QWEN_COOKIE_SOURCE"] = "off"
        proc = subprocess.run(
            [BIN, "usage", "--provider", "qwen", "--source", "web", "--json-only"],
            cwd=ROOT,
            env=qwen_web_env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stdout
        assert proc.stderr == "", proc.stderr
        payload = json.loads(proc.stdout)
        assert payload[0]["provider"] == "qwen", payload
        assert payload[0]["source"] == "web", payload
        assert payload[0]["configured"] is True, payload
        assert "ALIBABA_CODING_PLAN_COOKIE" in payload[0]["error"]["message"], payload

        amp_web_env = env.copy()
        amp_web_env["AMP_API_KEY"] = "fake-amp-token"
        amp_web_env.pop("AMP_COOKIE", None)
        amp_web_env["CONDUCTOR_USAGE_AMP_COOKIE_SOURCE"] = "off"
        proc = subprocess.run(
            [BIN, "usage", "--provider", "amp", "--source", "web", "--json-only"],
            cwd=ROOT,
            env=amp_web_env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stdout
        assert proc.stderr == "", proc.stderr
        payload = json.loads(proc.stdout)
        assert payload[0]["provider"] == "amp", payload
        assert payload[0]["source"] == "web", payload
        assert payload[0]["configured"] is True, payload
        assert "Cookie" in payload[0]["error"]["message"], payload

        amp_bin_dir = os.path.join(tmpdir, "amp-bin")
        os.makedirs(amp_bin_dir, exist_ok=True)
        amp_bin = os.path.join(amp_bin_dir, "amp")
        with open(amp_bin, "w", encoding="utf-8") as fh:
            fh.write("""#!/bin/sh
test "$1" = "usage" || exit 2
cat <<'EOF'
Signed in as amp@example.com (team)
Amp Free: $6/$10 remaining (replenishes +$0.5/hour)
Individual credits: $12.50 remaining
Workspace Alpha: $7.25 remaining
EOF
""")
        os.chmod(amp_bin, 0o755)
        amp_cli_env = env.copy()
        amp_cli_env["PATH"] = amp_bin_dir + os.pathsep + amp_cli_env.get("PATH", "")
        amp_cli_env.pop("AMP_API_KEY", None)
        proc = subprocess.run(
            [BIN, "usage", "--provider", "amp", "--source", "cli", "--json-only"],
            cwd=ROOT,
            env=amp_cli_env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stdout
        assert proc.stderr == "", proc.stderr
        payload = json.loads(proc.stdout)
        usage = payload[0]["usage"]
        assert payload[0]["provider"] == "amp", payload
        assert payload[0]["source"] == "cli", payload
        assert usage["sourceLabel"] == "cli", payload
        assert usage["ampUsage"]["individualCredits"] == 12.5, payload
        assert usage["ampUsage"]["workspaceBalances"][0]["name"] == "Alpha", payload
        assert usage["ampUsage"]["workspaceBalances"][0]["remaining"] == 7.25, payload

        auggie_bin_dir = os.path.join(tmpdir, "auggie-bin")
        os.makedirs(auggie_bin_dir, exist_ok=True)
        auggie_bin = os.path.join(auggie_bin_dir, "auggie")
        with open(auggie_bin, "w", encoding="utf-8") as fh:
            fh.write("""#!/bin/sh
test "$1" = "account" || exit 2
test "$2" = "status" || exit 2
cat <<'EOF'
319,054 credits remaining                     Max Plan
450,000 credits / month
9 days remaining in this billing cycle (ends 7/1/2026)
EOF
""")
        os.chmod(auggie_bin, 0o755)
        augment_cli_env = env.copy()
        augment_cli_env["AUGGIE_CLI_PATH"] = auggie_bin
        proc = subprocess.run(
            [BIN, "usage", "--provider", "augment", "--source", "cli", "--json-only"],
            cwd=ROOT,
            env=augment_cli_env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert proc.returncode == 0, proc.stdout
        assert proc.stderr == "", proc.stderr
        payload = json.loads(proc.stdout)
        assert payload[0]["provider"] == "augment", payload
        assert payload[0]["source"] == "cli", payload
        assert payload[0]["usage"]["sourceLabel"] == "cli", payload
        assert payload[0]["usage"]["planName"] == "450,000 credits/month", payload
        assert payload[0]["usage"]["windows"][0]["usedPercent"] == 29, payload

        claude_bin_dir = os.path.join(tmpdir, "claude-bin")
        os.makedirs(claude_bin_dir, exist_ok=True)
        claude_bin = os.path.join(claude_bin_dir, "claude")
        with open(claude_bin, "w", encoding="utf-8") as fh:
            fh.write("""#!/bin/sh
test "$1" = "/usage" || exit 2
cat <<'EOF'
{"session_5h":{"pct_used":12,"resets":"tomorrow at 9:00 AM"},"week_all_models":{"pct_used":34},"plan":"Max","account_email":"claude@example.com"}
EOF
""")
        os.chmod(claude_bin, 0o755)
        claude_cli_env = env.copy()
        claude_cli_env["CLAUDE_CLI_PATH"] = claude_bin
        claude_cli_env["CONDUCTOR_CLAUDE_AVOID_KEYCHAIN"] = "1"
        proc = subprocess.run(
            [BIN, "usage", "--provider", "claude", "--source", "cli", "--json-only"],
            cwd=ROOT,
            env=claude_cli_env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert proc.returncode == 0, proc.stdout
        assert proc.stderr == "", proc.stderr
        payload = json.loads(proc.stdout)
        assert payload[0]["provider"] == "claude", payload
        assert payload[0]["source"] == "cli", payload
        assert payload[0]["usage"]["sourceLabel"] == "cli", payload
        assert payload[0]["usage"]["windows"][0]["usedPercent"] == 12, payload

        grok_bin_dir = os.path.join(tmpdir, "grok-bin")
        os.makedirs(grok_bin_dir, exist_ok=True)
        grok_bin = os.path.join(grok_bin_dir, "grok")
        with open(grok_bin, "w", encoding="utf-8") as fh:
            fh.write("""#!/bin/sh
test "$1" = "agent" || exit 2
test "$2" = "stdio" || exit 2
IFS= read -r _initialize || exit 1
printf '%s\\n' '{"jsonrpc":"2.0","id":1,"result":{}}'
IFS= read -r _billing || exit 1
printf '%s\\n' '{"jsonrpc":"2.0","id":2,"result":{"billingCycle":{"billingPeriodStart":"2026-06-01T00:00:00Z","billingPeriodEnd":"2026-07-01T00:00:00Z"},"monthlyLimit":{"val":10000},"usage":{"totalUsed":{"val":2500}}}}'
""")
        os.chmod(grok_bin, 0o755)
        grok_cli_env = env.copy()
        grok_cli_env["GROK_CLI_PATH"] = grok_bin
        proc = subprocess.run(
            [BIN, "usage", "--provider", "grok", "--source", "cli", "--json-only"],
            cwd=ROOT,
            env=grok_cli_env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
        assert proc.returncode == 0, proc.stdout
        assert proc.stderr == "", proc.stderr
        payload = json.loads(proc.stdout)
        assert payload[0]["provider"] == "grok", payload
        assert payload[0]["source"] == "grok-cli", payload
        assert payload[0]["usage"]["sourceLabel"] == "grok-cli", payload
        assert payload[0]["usage"]["windows"][0]["usedPercent"] == 25, payload

        cert_path = os.path.join(tmpdir, "antigravity-localhost.crt")
        key_path = os.path.join(tmpdir, "antigravity-localhost.key")
        subprocess.run(
            [
                "openssl",
                "req",
                "-x509",
                "-newkey",
                "rsa:2048",
                "-nodes",
                "-keyout",
                key_path,
                "-out",
                cert_path,
                "-days",
                "1",
                "-subj",
                "/CN=localhost",
            ],
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
        )

        class AntigravityLocalHandler(http.server.BaseHTTPRequestHandler):
            def do_POST(self):
                _ = self.rfile.read(int(self.headers.get("Content-Length", "0") or "0"))
                if self.path.endswith("/RetrieveUserQuotaSummary"):
                    body = {
                        "code": 0,
                        "response": {
                            "groups": [
                                {
                                    "displayName": "Gemini Models",
                                    "buckets": [
                                        {
                                            "bucketId": "gemini-5h",
                                            "displayName": "5-hour",
                                            "remainingFraction": 0.75,
                                            "resetTime": "2026-07-01T00:00:00Z",
                                        }
                                    ],
                                },
                                {
                                    "displayName": "Claude and GPT models",
                                    "buckets": [
                                        {
                                            "bucketId": "claude-weekly",
                                            "displayName": "Weekly",
                                            "remaining": {"case": "remainingFraction", "value": 0.4},
                                            "description": "weekly reset",
                                        }
                                    ],
                                },
                            ]
                        },
                    }
                elif self.path.endswith("/GetUserStatus"):
                    body = {
                        "code": 0,
                        "userStatus": {
                            "email": "ag@example.com",
                            "userTier": {"name": "Pro"},
                            "cascadeModelConfigData": {"clientModelConfigs": []},
                        },
                    }
                else:
                    body = {"code": 0, "clientModelConfigs": []}
                payload_bytes = json.dumps(body, separators=(",", ":")).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(payload_bytes)))
                self.end_headers()
                self.wfile.write(payload_bytes)

            def log_message(self, fmt, *args):
                pass

        antigravity_httpd = http.server.HTTPServer(("127.0.0.1", 0), AntigravityLocalHandler)
        antigravity_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        antigravity_context.load_cert_chain(cert_path, key_path)
        antigravity_httpd.socket = antigravity_context.wrap_socket(
            antigravity_httpd.socket,
            server_side=True,
        )
        antigravity_thread = threading.Thread(target=antigravity_httpd.serve_forever, daemon=True)
        antigravity_thread.start()
        try:
            antigravity_env = env.copy()
            antigravity_env["CONDUCTOR_USAGE_ANTIGRAVITY_LOCAL_PORTS"] = str(
                antigravity_httpd.server_port
            )
            proc = subprocess.run(
                [BIN, "usage", "--provider", "antigravity", "--source", "cli", "--json-only"],
                cwd=ROOT,
                env=antigravity_env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
            )
            assert proc.returncode == 0, proc.stdout
            assert proc.stderr == "", proc.stderr
            payload = json.loads(proc.stdout)
            usage = payload[0]["usage"]
            assert payload[0]["provider"] == "antigravity", payload
            assert payload[0]["source"] == "cli", payload
            assert usage["sourceLabel"] == "cli", payload
            assert usage["accountLabel"] == "ag@example.com", payload
            assert usage["planName"] == "Pro", payload
            used_by_title = {window["title"]: window["usedPercent"] for window in usage["windows"]}
            assert used_by_title["5-hour"] == 25, payload
            assert used_by_title["Weekly"] == 60, payload

            mismatch_env = antigravity_env.copy()
            mismatch_env["ANTIGRAVITY_OAUTH_CREDENTIALS_JSON"] = json.dumps(
                {"email": "selected@example.com", "access_token": "token"},
                separators=(",", ":"),
            )
            proc = subprocess.run(
                [BIN, "usage", "--provider", "antigravity", "--source", "cli", "--json-only"],
                cwd=ROOT,
                env=mismatch_env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
            )
            assert proc.returncode == 0, proc.stdout
            assert proc.stderr == "", proc.stderr
            payload = json.loads(proc.stdout)
            assert payload[0]["provider"] == "antigravity", payload
            assert payload[0]["source"] == "cli", payload
            assert payload[0].get("usage") is None, payload
            message = payload[0]["error"]["message"]
            assert "selected@example.com" in message, payload
            assert "ag@example.com" in message, payload
            assert "mismatch" in message.lower() or "不匹配" in message, payload

            def fake_id_token(email):
                def encode_urlsafe(value):
                    return base64.urlsafe_b64encode(
                        json.dumps(value, separators=(",", ":")).encode()
                    ).rstrip(b"=").decode()

                return ".".join([
                    encode_urlsafe({"alg": "none"}),
                    encode_urlsafe({"email": email}),
                    "signature",
                ])

            id_token_mismatch_env = antigravity_env.copy()
            id_token_mismatch_env["ANTIGRAVITY_OAUTH_CREDENTIALS_JSON"] = json.dumps(
                {
                    "id_token": fake_id_token("selected-id-token@example.com"),
                    "access_token": "token",
                },
                separators=(",", ":"),
            )
            proc = subprocess.run(
                [BIN, "usage", "--provider", "antigravity", "--source", "cli", "--json-only"],
                cwd=ROOT,
                env=id_token_mismatch_env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
            )
            assert proc.returncode == 0, proc.stdout
            assert proc.stderr == "", proc.stderr
            payload = json.loads(proc.stdout)
            assert payload[0].get("usage") is None, payload
            message = payload[0]["error"]["message"]
            assert "selected-id-token@example.com" in message, payload
            assert "ag@example.com" in message, payload
        finally:
            antigravity_httpd.shutdown()
            antigravity_httpd.server_close()

        antigravity_creds_dir = os.path.join(home, ".codexbar", "antigravity")
        os.makedirs(antigravity_creds_dir, exist_ok=True)
        with open(os.path.join(antigravity_creds_dir, "oauth_creds.json"), "w", encoding="utf-8") as fh:
            json.dump({"email": "shared-home@example.com"}, fh, separators=(",", ":"))
        shared_home_env = env.copy()
        shared_home_env.pop("ANTIGRAVITY_CLI_PATH", None)
        shared_home_env.pop("ANTIGRAVITY_LOCAL_PORTS", None)
        shared_home_env.pop("ANTIGRAVITY_OAUTH_CREDENTIALS_JSON", None)
        proc = subprocess.run(
            [BIN, "usage", "--provider", "antigravity", "--source", "oauth", "--json-only"],
            cwd=ROOT,
            env=shared_home_env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stdout
        assert proc.stderr == "", proc.stderr
        payload = json.loads(proc.stdout)
        assert payload[0]["provider"] == "antigravity", payload
        assert payload[0]["source"] == "oauth", payload
        assert payload[0]["configured"] is True, payload
        assert "Antigravity login" in payload[0]["error"]["message"], payload

        class AntigravityOAuthHandler(http.server.BaseHTTPRequestHandler):
            seen_authorization = []

            def do_POST(self):
                length = int(self.headers.get("Content-Length", "0") or "0")
                _ = self.rfile.read(length)
                if self.path == "/token":
                    body = {
                        "access_token": "new-access-token",
                        "expires_in": 3600,
                        "id_token": make_fake_id_token("ag-refresh@example.com"),
                    }
                elif self.path.endswith("/v1internal:loadCodeAssist"):
                    AntigravityOAuthHandler.seen_authorization.append(
                        self.headers.get("Authorization", "")
                    )
                    body = {
                        "planInfo": {"planType": "Pro"},
                        "cloudaicompanionProject": "project-1",
                    }
                elif self.path.endswith("/v1internal:fetchAvailableModels"):
                    AntigravityOAuthHandler.seen_authorization.append(
                        self.headers.get("Authorization", "")
                    )
                    body = {
                        "models": {
                            "claude-test": {
                                "displayName": "Claude Test",
                                "quotaInfo": {
                                    "remainingFraction": 0.5,
                                    "resetTime": "2026-07-01T00:00:00Z",
                                },
                            }
                        }
                    }
                else:
                    body = {}
                payload_bytes = json.dumps(body, separators=(",", ":")).encode()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(payload_bytes)))
                self.end_headers()
                self.wfile.write(payload_bytes)

            def log_message(self, fmt, *args):
                pass

        antigravity_oauth_httpd = http.server.HTTPServer(
            ("127.0.0.1", 0),
            AntigravityOAuthHandler,
        )
        antigravity_oauth_thread = threading.Thread(
            target=antigravity_oauth_httpd.serve_forever,
            daemon=True,
        )
        antigravity_oauth_thread.start()
        try:
            old_token = json.dumps(
                {
                    "access_token": "old-access-token",
                    "refresh_token": "refresh-token",
                    "expiry_date": 0,
                    "email": "ag-refresh@example.com",
                    "client_id": "client-id",
                    "client_secret": "client-secret",
                },
                separators=(",", ":"),
            )
            antigravity_refresh_config = os.path.join(tmpdir, "antigravity-refresh.yaml")
            with open(antigravity_refresh_config, "w", encoding="utf-8") as fh:
                fh.write(
                    f"""
usage:
  providers:
    antigravity:
      tokenAccounts:
        accounts:
          - id: "00000000-0000-0000-0000-0000000000aa"
            label: ag-refresh
            token: '{old_token}'
        activeIndex: 0
""".lstrip()
                )
            refresh_env = isolated_usage_env(
                tmpdir,
                home,
                config_path=antigravity_refresh_config,
            )
            refresh_env["CONDUCTOR_USAGE_ANTIGRAVITY_TOKEN_URL"] = (
                f"http://127.0.0.1:{antigravity_oauth_httpd.server_port}/token"
            )
            refresh_env["CONDUCTOR_USAGE_ANTIGRAVITY_BASE_URL"] = (
                f"http://127.0.0.1:{antigravity_oauth_httpd.server_port}"
            )
            proc = subprocess.run(
                [
                    BIN,
                    "usage",
                    "--provider",
                    "antigravity",
                    "--source",
                    "oauth",
                    "--account",
                    "ag-refresh",
                    "--json-only",
                ],
                cwd=ROOT,
                env=refresh_env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
            )
            assert proc.returncode == 0, proc.stdout + proc.stderr
            assert proc.stderr == "", proc.stderr
            payload = json.loads(proc.stdout)
            usage = payload[0]["usage"]
            assert usage["sourceLabel"] == "oauth", payload
            assert usage["accountLabel"] == "ag-refresh@example.com", payload
            assert usage["windows"][0]["usedPercent"] == 50, payload
            assert "Bearer new-access-token" in AntigravityOAuthHandler.seen_authorization, (
                AntigravityOAuthHandler.seen_authorization,
                payload,
            )
            with open(antigravity_refresh_config, "r", encoding="utf-8") as fh:
                updated_config = fh.read()
            assert "new-access-token" in updated_config, updated_config
            assert "old-access-token" not in updated_config, updated_config
        finally:
            antigravity_oauth_httpd.shutdown()
            antigravity_oauth_httpd.server_close()

        jetbrains_options_dir = os.path.join(
            home,
            "Library",
            "Application Support",
            "JetBrains",
            "WebStorm2026.1",
            "options",
        )
        os.makedirs(jetbrains_options_dir, exist_ok=True)
        with open(os.path.join(jetbrains_options_dir, "AIAssistantQuotaManager2.xml"), "w", encoding="utf-8") as fh:
            fh.write("""<application>
  <component name="AIAssistantQuotaManager2">
    <option name="quotaInfo" value="{&quot;current&quot;:&quot;25&quot;,&quot;maximum&quot;:&quot;100&quot;,&quot;until&quot;:&quot;2026-07-01T00:00:00Z&quot;}" />
    <option name="nextRefill" value="{&quot;next&quot;:&quot;2026-07-01T00:00:00Z&quot;}" />
  </component>
</application>
""")
        proc = subprocess.run(
            [BIN, "usage", "--provider", "jetbrains", "--json-only"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stdout
        assert proc.stderr == "", proc.stderr
        payload = json.loads(proc.stdout)
        assert payload[0]["provider"] == "jetbrains", payload
        assert payload[0]["source"] == "local", payload
        assert payload[0]["usage"]["sourceLabel"] == "local", payload
        assert payload[0]["usage"]["windows"][0]["usedPercent"] == 25, payload

        opencode_dir = os.path.join(home, ".local", "share", "opencode")
        os.makedirs(opencode_dir, exist_ok=True)
        with open(os.path.join(opencode_dir, "auth.json"), "w", encoding="utf-8") as handle:
            handle.write('{"opencode-go":{"type":"api-key","key":"go-key"}}')
        opencode_db = os.path.join(opencode_dir, "opencode.db")
        conn = sqlite3.connect(opencode_db)
        try:
            conn.executescript("""
                CREATE TABLE message (
                  id TEXT PRIMARY KEY,
                  session_id TEXT NOT NULL,
                  data TEXT NOT NULL,
                  time_created INTEGER,
                  time_updated INTEGER
                );
                CREATE TABLE part (
                  id TEXT PRIMARY KEY,
                  message_id TEXT NOT NULL,
                  session_id TEXT NOT NULL,
                  data TEXT NOT NULL,
                  time_created INTEGER,
                  time_updated INTEGER
                );
            """)
            created_ms = int((time.time() - 3600) * 1000)
            message_payload = json.dumps({
                "providerID": "opencode-go",
                "role": "assistant",
                "time": {"created": created_ms},
                "cost": 3.0,
            })
            conn.execute(
                "INSERT INTO message (id, session_id, data, time_created, time_updated) VALUES (?, ?, ?, ?, ?)",
                ("msg-1", "session-1", message_payload, created_ms, created_ms),
            )
            conn.commit()
        finally:
            conn.close()

        opencodego_env = env.copy()
        opencodego_env["CONDUCTOR_USAGE_OPENCODEGO_COOKIE_SOURCE"] = "off"
        proc = subprocess.run(
            [BIN, "usage", "--provider", "opencodego", "--json-only"],
            cwd=ROOT,
            env=opencodego_env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stdout
        assert proc.stderr == "", proc.stderr
        payload = json.loads(proc.stdout)
        assert payload[0]["provider"] == "opencodego", payload
        assert payload[0]["source"] == "local", payload
        assert payload[0]["usage"]["sourceLabel"] == "local", payload
        assert payload[0]["usage"]["windows"][0]["usedPercent"] == 25, payload

        proc = subprocess.run(
            [BIN, "diagnose", "--provider", "opencodego", "--json-only"],
            cwd=ROOT,
            env=opencodego_env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stdout
        assert proc.stderr == "", proc.stderr
        diagnostic = json.loads(proc.stdout)
        assert diagnostic["provider"] == "opencodego", diagnostic
        assert diagnostic["source"] == "local", diagnostic
        assert diagnostic["sourceMode"] == "auto", diagnostic
        assert diagnostic["usage"]["sourceLabel"] == "local", diagnostic

        windsurf_db_dir = os.path.join(
            home,
            "Library",
            "Application Support",
            "Windsurf",
            "User",
            "globalStorage",
        )
        os.makedirs(windsurf_db_dir, exist_ok=True)
        windsurf_db = os.path.join(windsurf_db_dir, "state.vscdb")
        conn = sqlite3.connect(windsurf_db)
        try:
            conn.execute("CREATE TABLE ItemTable (key TEXT PRIMARY KEY, value BLOB)")
            conn.execute(
                "INSERT INTO ItemTable (key, value) VALUES (?, ?)",
                (
                    "windsurf.settings.cachedPlanInfo",
                    json.dumps({
                        "planName": "Pro",
                        "quotaUsage": {
                            "dailyRemainingPercent": 80,
                            "weeklyRemainingPercent": 55,
                            "dailyResetAtUnix": 1893456000,
                            "weeklyResetAtUnix": 1893974400,
                        },
                    }),
                ),
            )
            conn.commit()
        finally:
            conn.close()

        windsurf_cli_env = env.copy()
        windsurf_cli_env["CONDUCTOR_USAGE_WINDSURF_COOKIE_SOURCE"] = "off"
        proc = subprocess.run(
            [BIN, "usage", "--provider", "windsurf", "--source", "cli", "--json-only"],
            cwd=ROOT,
            env=windsurf_cli_env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stdout
        assert proc.stderr == "", proc.stderr
        payload = json.loads(proc.stdout)
        assert payload[0]["provider"] == "windsurf", payload
        assert payload[0]["source"] == "local", payload
        assert payload[0]["usage"]["sourceLabel"] == "local", payload
        assert payload[0]["usage"]["planName"] == "Pro", payload
        assert payload[0]["usage"]["windows"][0]["usedPercent"] == 20, payload
        assert payload[0]["usage"]["windows"][1]["usedPercent"] == 45, payload

        proc = subprocess.run(
            [BIN, "usage", "--provider", "windsurf", "--json-only"],
            cwd=ROOT,
            env=windsurf_cli_env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stdout
        assert proc.stderr == "", proc.stderr
        payload = json.loads(proc.stdout)
        assert payload[0]["provider"] == "windsurf", payload
        assert payload[0]["source"] == "local", payload
        assert payload[0]["usage"]["sourceLabel"] == "local", payload
        assert payload[0]["usage"]["planName"] == "Pro", payload

        proc = subprocess.run(
            [BIN, "diagnose", "--provider", "windsurf", "--json-only"],
            cwd=ROOT,
            env=windsurf_cli_env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stdout
        assert proc.stderr == "", proc.stderr
        diagnostic = json.loads(proc.stdout)
        assert diagnostic["provider"] == "windsurf", diagnostic
        assert diagnostic["source"] == "local", diagnostic
        assert diagnostic["sourceMode"] == "auto", diagnostic
        assert diagnostic["usage"]["sourceLabel"] == "local", diagnostic
        assert diagnostic["fetchAttempts"][0]["kind"] == "local", diagnostic

        windsurf_web_env = env.copy()
        windsurf_web_env["CONDUCTOR_USAGE_WINDSURF_COOKIE_SOURCE"] = "off"
        proc = subprocess.run(
            [BIN, "usage", "--provider", "windsurf", "--source", "web", "--json-only"],
            cwd=ROOT,
            env=windsurf_web_env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stdout
        assert proc.stderr == "", proc.stderr
        payload = json.loads(proc.stdout)
        assert payload[0]["provider"] == "windsurf", payload
        assert payload[0]["source"] == "web", payload
        assert "windsurf.com" in payload[0]["error"]["message"], payload
        assert payload[0].get("usage") is None, payload

        unsupported_source_env = env.copy()
        unsupported_source_env["CONDUCTOR_USAGE_ABACUS_COOKIE"] = "sessionid=manual"
        proc = subprocess.run(
            [BIN, "usage", "--provider", "abacus", "--source", "api", "--json-only"],
            cwd=ROOT,
            env=unsupported_source_env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stdout
        assert proc.stderr == "", proc.stderr
        payload = json.loads(proc.stdout)
        assert payload[0]["provider"] == "abacus", payload
        assert payload[0]["source"] == "api", payload
        assert payload[0]["configured"] is True, payload
        assert "Source api is not supported for abacus" in payload[0]["error"]["message"], payload
        assert "auto, web" in payload[0]["error"]["message"], payload

        proc = subprocess.run(
            [BIN, "diagnose", "--provider", "abacus", "--source", "api", "--json-only"],
            cwd=ROOT,
            env=unsupported_source_env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode != 0, proc.stdout
        assert proc.stderr == "", proc.stderr
        payload = json.loads(proc.stdout)
        assert payload[0]["provider"] == "cli", payload
        assert "Source api is not supported for abacus" in payload[0]["error"]["message"], payload
        assert "auto, web" in payload[0]["error"]["message"], payload

        with open(config_path, "w", encoding="utf-8") as handle:
            handle.write(
                """
usage:
  providers:
    codex:
      enabled: false
    claude:
      enabled: false
""".lstrip()
            )
        proc = subprocess.run(
            [BIN],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode == 0, proc.stderr
        assert proc.stdout.strip() == "", proc.stdout
        assert proc.stderr == "", proc.stderr


def test_cache_cli_provider_scope_errors():
    with tempfile.TemporaryDirectory(prefix="conductorctl-cache-") as tmpdir:
        home = os.path.join(tmpdir, "home")
        env = isolated_usage_env(tmpdir, home)

        proc = subprocess.run(
            [BIN, "cache"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode != 0, proc.stdout
        assert proc.stdout == "", proc.stdout
        assert "Specify --cookies, --cost, or --all." in proc.stderr, proc.stderr

        proc = subprocess.run(
            [BIN, "cache", "--all", "--provider", "codex"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode != 0, proc.stdout
        assert proc.stdout == "", proc.stdout
        assert "--provider only scopes cookie caches. Use --cookies --provider <name>, or omit --provider." in proc.stderr, proc.stderr

        proc = subprocess.run(
            [BIN, "cache", "--cookies", "--provider", "nope"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode != 0, proc.stdout
        assert proc.stdout == "", proc.stdout
        assert "Unknown provider: nope" in proc.stderr, proc.stderr

        for alias, canonical in [("alibaba", "qwen"), ("zai", "glm")]:
            proc = subprocess.run(
                [BIN, "cache", "--cookies", "--provider", alias, "--json-only"],
                cwd=ROOT,
                env=env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=5,
            )
            assert proc.returncode == 0, proc.stdout + proc.stderr
            assert proc.stderr == "", proc.stderr
            payload = json.loads(proc.stdout)
            assert payload[0]["cache"] == "cookies", (alias, payload)
            assert payload[0]["provider"] == canonical, (alias, payload)
            assert isinstance(payload[0]["cleared"], int), (alias, payload)

        proc = subprocess.run(
            [BIN, "cache", "--all", "--provider", "codex", "--json-only"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=5,
        )
        assert proc.returncode != 0, proc.stdout
        assert proc.stderr == "", proc.stderr
        payload = json.loads(proc.stdout)
        assert payload[0]["provider"] == "cli", payload
        assert payload[0]["error"]["message"] == (
            "--provider only scopes cookie caches. Use --cookies --provider <name>, or omit --provider."
        ), payload


def write_fresh_models_dev_cache(home):
    pricing_cache = os.path.join(home, "Library", "Caches", "Conductor", "model-pricing")
    os.makedirs(pricing_cache, exist_ok=True)
    fetched_at = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0)
    with open(os.path.join(pricing_cache, "models-dev-v1.json"), "w", encoding="utf-8") as handle:
        json.dump(
            {
                "version": 1,
                "fetchedAt": fetched_at.isoformat().replace("+00:00", "Z"),
                "catalog": {"providers": {}},
            },
            handle,
            separators=(",", ":"),
        )


def isolated_usage_env(tmpdir, home, *, codex_home=None, config_path=None):
    env = os.environ.copy()
    for key in list(env):
        if key.startswith("CONDUCTOR_USAGE_"):
            env.pop(key, None)
    env["HOME"] = home
    env["CFFIXED_USER_HOME"] = home
    env["CODEX_HOME"] = codex_home or os.path.join(tmpdir, "codex-empty")
    env["CONDUCTOR_CONFIG_PATH"] = config_path or os.path.join(tmpdir, "config.yaml")
    return env


def cached_file_entry(cache, path):
    files = cache["files"]
    candidates = [path, os.path.realpath(path)]
    for candidate in candidates:
        if candidate in files:
            return files[candidate]
    suffix = os.path.join(".claude", "projects", "-Users-cache-tail", "tail.jsonl")
    matches = [entry for key, entry in files.items() if key.endswith(suffix)]
    assert len(matches) == 1, files.keys()
    return matches[0]


def test_cost_scanner_truncated_codex_context():
    with tempfile.TemporaryDirectory(prefix="conductorctl-cost-scan-") as tmpdir:
        home = os.path.join(tmpdir, "home")
        codex_home = os.path.join(tmpdir, "codex")
        session_dir = os.path.join(codex_home, "sessions", "2026", "06", "08")
        os.makedirs(session_dir, exist_ok=True)
        write_fresh_models_dev_cache(home)

        huge_prompt = "x" * 270_000
        session_lines = [
            '{"timestamp":"2026-06-08T09:00:00.000Z","type":"session_meta","payload":{"id":"huge-context","cwd":"/Users/test/huge"}}',
            '{"timestamp":"2026-06-08T09:00:30.000Z","type":"turn_context","payload":{"model":"gpt-5.5","cwd":"/Users/test/huge","prompt":"' + huge_prompt + '"}}',
            '{"timestamp":"2026-06-08T09:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":120,"cached_input_tokens":20,"output_tokens":30}}}}',
        ]
        with open(os.path.join(session_dir, "rollout-huge-context.jsonl"), "w", encoding="utf-8") as handle:
            handle.write("\n".join(session_lines) + "\n")

        config_path = os.path.join(tmpdir, "config.yaml")
        with open(config_path, "w", encoding="utf-8") as handle:
            handle.write(
                """
usage:
  providers:
    codex:
      enabled: true
""".lstrip()
            )

        env = isolated_usage_env(tmpdir, home, codex_home=codex_home, config_path=config_path)

        proc = subprocess.run(
            [BIN, "cost", "--provider", "codex", "--days", "30", "--json"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert proc.returncode == 0, proc.stderr
        payload = json.loads(proc.stdout)
        assert payload["sourceInfo"]["source"] == "file_cache_scan", payload["sourceInfo"]
        assert payload["sourceInfo"]["cachePath"].startswith(home), payload["sourceInfo"]
        assert payload["grand"]["inputTokens"] == 100, payload["grand"]
        assert payload["grand"]["cacheReadTokens"] == 20, payload["grand"]
        assert payload["grand"]["outputTokens"] == 30, payload["grand"]
        assert payload["grand"]["requestCount"] == 1, payload["grand"]
        models = {row["model"]: row for row in payload["byModel"]}
        assert "gpt-5.5" in models, models
        assert "gpt-5-codex" not in models, models
        assert models["gpt-5.5"]["totals"]["inputTokens"] == 100, models["gpt-5.5"]
        day_models = {
            row["model"]: row
            for day in payload["byDay"]
            for row in day.get("modelBreakdowns", [])
        }
        assert day_models["gpt-5.5"]["standardTokens"] == 150, day_models["gpt-5.5"]


def test_cost_scanner_incomplete_tail_append_cache():
    with tempfile.TemporaryDirectory(prefix="conductorctl-cost-tail-") as tmpdir:
        home = os.path.join(tmpdir, "home")
        project_dir = os.path.join(home, ".claude", "projects", "-Users-cache-tail")
        os.makedirs(project_dir, exist_ok=True)
        write_fresh_models_dev_cache(home)

        config_path = os.path.join(tmpdir, "config.yaml")
        with open(config_path, "w", encoding="utf-8") as handle:
            handle.write(
                """
usage:
  providers:
    claude:
      enabled: true
""".lstrip()
            )

        log_path = os.path.join(project_dir, "tail.jsonl")
        complete = (
            '{"type":"assistant","timestamp":"2026-06-08T10:00:00.000Z",'
            '"requestId":"req_1","message":{"id":"msg_1","model":"claude-sonnet-4-6",'
            '"role":"assistant","usage":{"input_tokens":10,"output_tokens":20,'
            '"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}'
        )
        partial = (
            '{"type":"assistant","timestamp":"2026-06-08T10:01:00.000Z",'
            '"requestId":"req_2","message":{"id":"msg_2","model":"claude-sonnet-4-6",'
            '"role":"assistant","usage":{"input_tokens":30'
        )
        with open(log_path, "w", encoding="utf-8") as handle:
            handle.write(complete + "\n" + partial)

        env = isolated_usage_env(tmpdir, home, config_path=config_path)

        first = subprocess.run(
            [BIN, "cost", "--provider", "claude", "--days", "30", "--json"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert first.returncode == 0, first.stderr
        first_payload = json.loads(first.stdout)
        assert first_payload["grand"]["inputTokens"] == 10, first_payload["grand"]
        assert first_payload["grand"]["outputTokens"] == 20, first_payload["grand"]
        assert first_payload["grand"]["requestCount"] == 1, first_payload["grand"]
        cache_path = first_payload["sourceInfo"]["cachePath"]
        with open(cache_path, "r", encoding="utf-8") as handle:
            cache = json.load(handle)
        first_entry = cached_file_entry(cache, log_path)
        assert first_entry["parsedBytes"] < first_entry["stamp"]["size"], first_entry

        with open(log_path, "a", encoding="utf-8") as handle:
            handle.write(',"output_tokens":40,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}\n')
        for name in os.listdir(os.path.dirname(cache_path)):
            if name.startswith("local-report-v") and name.endswith(".json"):
                os.unlink(os.path.join(os.path.dirname(cache_path), name))

        second = subprocess.run(
            [BIN, "cost", "--provider", "claude", "--days", "30", "--json"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert second.returncode == 0, second.stderr
        second_payload = json.loads(second.stdout)
        assert second_payload["grand"]["inputTokens"] == 40, second_payload["grand"]
        assert second_payload["grand"]["outputTokens"] == 60, second_payload["grand"]
        assert second_payload["grand"]["requestCount"] == 2, second_payload["grand"]
        with open(cache_path, "r", encoding="utf-8") as handle:
            cache = json.load(handle)
        second_entry = cached_file_entry(cache, log_path)
        assert second_entry["parsedBytes"] == second_entry["stamp"]["size"], second_entry


def test_cost_cli_refresh_forces_rescan():
    with tempfile.TemporaryDirectory(prefix="conductorctl-cost-refresh-") as tmpdir:
        home = os.path.join(tmpdir, "home")
        project_dir = os.path.join(home, ".claude", "projects", "-Users-refresh")
        os.makedirs(project_dir, exist_ok=True)
        write_fresh_models_dev_cache(home)

        config_path = os.path.join(tmpdir, "config.yaml")
        with open(config_path, "w", encoding="utf-8") as handle:
            handle.write(
                """
usage:
  providers:
    claude:
      enabled: true
""".lstrip()
            )

        log_path = os.path.join(project_dir, "refresh.jsonl")
        first_line = (
            '{"type":"assistant","timestamp":"2026-06-08T11:00:00.000Z",'
            '"requestId":"req_refresh_1","message":{"id":"msg_refresh_1",'
            '"model":"claude-sonnet-4-6","role":"assistant","usage":{'
            '"input_tokens":10,"output_tokens":20,'
            '"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}'
        )
        second_line = (
            '{"type":"assistant","timestamp":"2026-06-08T11:01:00.000Z",'
            '"requestId":"req_refresh_2","message":{"id":"msg_refresh_2",'
            '"model":"claude-sonnet-4-6","role":"assistant","usage":{'
            '"input_tokens":30,"output_tokens":40,'
            '"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}'
        )
        with open(log_path, "w", encoding="utf-8") as handle:
            handle.write(first_line + "\n")

        env = isolated_usage_env(tmpdir, home, config_path=config_path)
        first = subprocess.run(
            [BIN, "cost", "--provider", "claude", "--days", "30", "--json-only"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert first.returncode == 0, first.stderr
        assert first.stderr == "", first.stderr
        first_payload = json.loads(first.stdout)
        assert first_payload["grand"]["inputTokens"] == 10, first_payload["grand"]
        assert first_payload["grand"]["outputTokens"] == 20, first_payload["grand"]
        assert first_payload["grand"]["requestCount"] == 1, first_payload["grand"]

        with open(log_path, "a", encoding="utf-8") as handle:
            handle.write(second_line + "\n")

        cached = subprocess.run(
            [BIN, "cost", "--provider", "claude", "--days", "30", "--json"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert cached.returncode == 0, cached.stderr
        cached_payload = json.loads(cached.stdout)
        assert cached_payload["sourceInfo"]["source"] == "report_cache", cached_payload["sourceInfo"]
        assert cached_payload["grand"]["inputTokens"] == 10, cached_payload["grand"]
        assert cached_payload["grand"]["outputTokens"] == 20, cached_payload["grand"]
        assert cached_payload["grand"]["requestCount"] == 1, cached_payload["grand"]

        refreshed = subprocess.run(
            [BIN, "cost", "--provider", "claude", "--days", "30", "--refresh", "--json"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        assert refreshed.returncode == 0, refreshed.stderr
        refreshed_payload = json.loads(refreshed.stdout)
        assert refreshed_payload["sourceInfo"]["source"] == "file_cache_scan", refreshed_payload["sourceInfo"]
        assert refreshed_payload["grand"]["inputTokens"] == 40, refreshed_payload["grand"]
        assert refreshed_payload["grand"]["outputTokens"] == 60, refreshed_payload["grand"]
        assert refreshed_payload["grand"]["requestCount"] == 2, refreshed_payload["grand"]


def test_cost_scanner_large_claude_corpus_smoke():
    with tempfile.TemporaryDirectory(prefix="conductorctl-cost-large-") as tmpdir:
        home = os.path.join(tmpdir, "home")
        project_dir = os.path.join(home, ".claude", "projects", "-Users-large-corpus")
        os.makedirs(project_dir, exist_ok=True)
        write_fresh_models_dev_cache(home)

        config_path = os.path.join(tmpdir, "config.yaml")
        with open(config_path, "w", encoding="utf-8") as handle:
            handle.write(
                """
usage:
  providers:
    claude:
      enabled: true
""".lstrip()
            )

        large_line = "x" * 620_000
        expected_input = 0
        expected_output = 0
        file_count = 18
        for index in range(file_count):
            input_tokens = 100 + index
            output_tokens = 10 + index
            expected_input += input_tokens
            expected_output += output_tokens
            usage_line = (
                '{"type":"assistant","timestamp":"2026-06-08T10:%02d:00.000Z",'
                '"requestId":"req_large_%02d","message":{"id":"msg_large_%02d",'
                '"model":"claude-sonnet-4-6","role":"assistant","usage":{'
                '"input_tokens":%d,"output_tokens":%d,'
                '"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}'
                % (index, index, index, input_tokens, output_tokens)
            )
            path = os.path.join(project_dir, f"large-{index:02d}.jsonl")
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(large_line + "\n" + usage_line + "\n" + large_line + "\n")

        env = isolated_usage_env(tmpdir, home, config_path=config_path)
        started = time.monotonic()
        proc = subprocess.run(
            [BIN, "cost", "--provider", "claude", "--days", "30", "--json"],
            cwd=ROOT,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        elapsed = time.monotonic() - started
        assert proc.returncode == 0, proc.stderr
        payload = json.loads(proc.stdout)
        assert payload["grand"]["inputTokens"] == expected_input, payload["grand"]
        assert payload["grand"]["outputTokens"] == expected_output, payload["grand"]
        assert payload["grand"]["requestCount"] == file_count, payload["grand"]
        assert payload["sessionsScanned"] == file_count, payload
        assert elapsed < 30, elapsed


def test_usage_configured_probes_do_not_read_browser_state():
    providers = {
        "AbacusUsage.swift": "AbacusUsageFetcher",
        "AlibabaTokenPlanUsage.swift": "AlibabaTokenPlanUsageFetcher",
        "AugmentUsage.swift": "AugmentUsageFetcher",
        "CommandCodeUsage.swift": "CommandCodeUsageFetcher",
        "CursorUsage.swift": "CursorUsageFetcher",
        "DevinUsage.swift": "DevinUsageFetcher",
        "FactoryUsage.swift": "FactoryUsageFetcher",
        "GrokUsage.swift": "GrokUsageFetcher",
        "ManusUsage.swift": "ManusUsageFetcher",
        "MiMoUsage.swift": "MiMoUsageFetcher",
        "MistralUsage.swift": "MistralUsageFetcher",
        "OllamaUsage.swift": "OllamaUsageFetcher",
        "OpenCodeUsage.swift": "OpenCodeUsageFetcher",
        "OpenCodeGoUsage.swift": "OpenCodeGoUsageFetcher",
        "PerplexityUsage.swift": "PerplexityUsageFetcher",
        "T3ChatUsage.swift": "T3ChatUsageFetcher",
        "WindsurfUsage.swift": "WindsurfUsageFetcher",
    }
    forbidden = [
        "BrowserCookieClient",
        "Browser.defaultImportOrder",
        "cookieHeader()",
        "browserCookieHeader()",
        "cookies(env:",
        "session()",
        "cookieToken()",
        "importSession()",
        "resolveSessionCookie(",
    ]

    for filename, symbol in providers.items():
        path = os.path.join(ROOT, "Sources", "ConductorCore", "Usage", filename)
        with open(path, "r", encoding="utf-8") as handle:
            source = handle.read()
        marker = "public static func hasSession"
        start = source.find(marker)
        assert start != -1, f"{filename} missing hasSession"
        brace = source.find("{", start)
        assert brace != -1, f"{filename} hasSession missing body"
        depth = 0
        end = brace
        for index in range(brace, len(source)):
            char = source[index]
            if char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
                if depth == 0:
                    end = index + 1
                    break
        body = source[brace:end]
        for token in forbidden:
            assert token not in body, f"{symbol}.hasSession should not read browser state via {token}"


def test_usage_web_cookie_fetchers_label_actual_source():
    expectations = {
        "AugmentUsage.swift": '.withSourceLabel("web")',
        "AzureOpenAIUsage.swift": '.withSourceLabel("deployment")',
        "CursorUsage.swift": '.withSourceLabel("web")',
        "FactoryUsage.swift": '.withSourceLabel("web")',
        "JetBrainsUsage.swift": '.withSourceLabel("local")',
        "KiroUsage.swift": '.withSourceLabel("cli")',
        "OpenAIUsage.swift": 'sourceLabel: "billing-api"',
        "ZedUsage.swift": 'sourceLabel: "local"',
    }
    for filename, token in expectations.items():
        path = os.path.join(ROOT, "Sources", "ConductorCore", "Usage", filename)
        with open(path, "r", encoding="utf-8") as handle:
            source = handle.read()
        assert token in source, f"{filename} must label browser-cookie fetches as web"


def test_antigravity_serve_reuses_warm_agy_session():
    with tempfile.TemporaryDirectory(prefix="conductorctl-antigravity-warm-") as tmpdir:
        cert_path = os.path.join(tmpdir, "localhost.crt")
        key_path = os.path.join(tmpdir, "localhost.key")
        subprocess.run(
            [
                "openssl",
                "req",
                "-x509",
                "-newkey",
                "rsa:2048",
                "-nodes",
                "-keyout",
                key_path,
                "-out",
                cert_path,
                "-days",
                "1",
                "-subj",
                "/CN=localhost",
            ],
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
        )

        launch_count_path = os.path.join(tmpdir, "agy-launches.txt")
        quota_count_path = os.path.join(tmpdir, "quota-requests.txt")
        agy_path = os.path.join(tmpdir, "agy")
        with open(agy_path, "w", encoding="utf-8") as handle:
            handle.write(
                """#!/usr/bin/env python3
import http.server
import json
import os
import signal
import ssl
import sys

with open(os.environ["ANTIGRAVITY_FAKE_LAUNCH_COUNT"], "a", encoding="utf-8") as handle:
    handle.write("1\\n")

class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        _ = self.rfile.read(int(self.headers.get("Content-Length", "0") or "0"))
        if self.path.endswith("/RetrieveUserQuotaSummary"):
            with open(os.environ["ANTIGRAVITY_FAKE_QUOTA_COUNT"], "a", encoding="utf-8") as handle:
                handle.write("1\\n")
            body = {
                "code": 0,
                "response": {
                    "groups": [
                        {
                            "displayName": "Gemini Models",
                            "buckets": [
                                {
                                    "bucketId": "gemini-5h",
                                    "displayName": "5-hour",
                                    "remainingFraction": 0.5,
                                }
                            ],
                        }
                    ]
                },
            }
        elif self.path.endswith("/GetUserStatus"):
            body = {
                "code": 0,
                "userStatus": {
                    "email": "warm-agy@example.com",
                    "userTier": {"name": "Pro"},
                    "cascadeModelConfigData": {"clientModelConfigs": []},
                },
            }
        else:
            body = {"code": 0, "clientModelConfigs": []}
        payload = json.dumps(body, separators=(",", ":")).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, fmt, *args):
        pass

def stop(_signum, _frame):
    sys.exit(0)

signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)

server = http.server.ThreadingHTTPServer(("127.0.0.1", int(os.environ["ANTIGRAVITY_FAKE_PORT"])), Handler)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(os.environ["ANTIGRAVITY_FAKE_CERT"], os.environ["ANTIGRAVITY_FAKE_KEY"])
server.socket = context.wrap_socket(server.socket, server_side=True)
server.serve_forever()
"""
            )
        os.chmod(agy_path, 0o755)

        serve_port = free_port()
        agy_port = free_port()
        env = os.environ.copy()
        env["HOME"] = tmpdir
        env["ANTIGRAVITY_CLI_PATH"] = agy_path
        env["ANTIGRAVITY_FAKE_PORT"] = str(agy_port)
        env["ANTIGRAVITY_FAKE_CERT"] = cert_path
        env["ANTIGRAVITY_FAKE_KEY"] = key_path
        env["ANTIGRAVITY_FAKE_LAUNCH_COUNT"] = launch_count_path
        env["ANTIGRAVITY_FAKE_QUOTA_COUNT"] = quota_count_path

        server = subprocess.Popen(
            [
                BIN,
                "serve",
                "--port",
                str(serve_port),
                "--refresh-interval",
                "0",
                "--request-timeout",
                "15",
            ],
            cwd=ROOT,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        try:
            wait_port(serve_port)

            def fetch_antigravity():
                conn = http.client.HTTPConnection("127.0.0.1", serve_port, timeout=15)
                conn.request("GET", "/usage?provider=antigravity&source=cli")
                response = conn.getresponse()
                payload = json.loads(response.read().decode())
                conn.close()
                assert response.status == 200, payload
                usage = payload[0]["usage"]
                assert usage["sourceLabel"] == "cli", payload
                assert usage["accountLabel"] == "warm-agy@example.com", payload
                assert usage["windows"][0]["usedPercent"] == 50, payload

            fetch_antigravity()
            fetch_antigravity()

            with open(launch_count_path, "r", encoding="utf-8") as handle:
                launches = [line for line in handle.read().splitlines() if line]
            with open(quota_count_path, "r", encoding="utf-8") as handle:
                quota_requests = [line for line in handle.read().splitlines() if line]
            assert len(launches) == 1, launches
            assert len(quota_requests) >= 2, quota_requests
        finally:
            server.terminate()
            try:
                server.wait(timeout=5)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait(timeout=5)


def test_antigravity_app_local_probe_uses_csrf():
    with tempfile.TemporaryDirectory(prefix="conductorctl-antigravity-app-") as tmpdir:
        cert_path = os.path.join(tmpdir, "localhost.crt")
        key_path = os.path.join(tmpdir, "localhost.key")
        subprocess.run(
            [
                "openssl",
                "req",
                "-x509",
                "-newkey",
                "rsa:2048",
                "-nodes",
                "-keyout",
                key_path,
                "-out",
                cert_path,
                "-days",
                "1",
                "-subj",
                "/CN=localhost",
            ],
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
        )

        app_bin_dir = os.path.join(tmpdir, "antigravity", "bin")
        os.makedirs(app_bin_dir, exist_ok=True)
        language_server = os.path.join(app_bin_dir, "language_server")
        csrf_token = "csrf-local-app-token"
        csrf_seen_path = os.path.join(tmpdir, "csrf-seen.txt")
        with open(language_server, "w", encoding="utf-8") as handle:
            handle.write(
                """#!/usr/bin/env python3
import http.server
import json
import os
import signal
import ssl
import sys

class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        _ = self.rfile.read(int(self.headers.get("Content-Length", "0") or "0"))
        if self.headers.get("X-Codeium-Csrf-Token") != os.environ["ANTIGRAVITY_FAKE_CSRF"]:
            payload = b'{"error":"missing csrf"}'
            self.send_response(403)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return
        with open(os.environ["ANTIGRAVITY_FAKE_CSRF_SEEN"], "a", encoding="utf-8") as handle:
            handle.write(self.path + "\\n")
        if self.path.endswith("/RetrieveUserQuotaSummary"):
            groups = [
                {
                    "displayName": "Gemini Models",
                    "buckets": [
                        {
                            "bucketId": "gemini-5h",
                            "displayName": "5-hour",
                            "remainingFraction": float(os.environ.get("ANTIGRAVITY_FAKE_REMAINING_FRACTION", "0.2")),
                        }
                    ],
                }
            ]
            if os.environ.get("ANTIGRAVITY_FAKE_EXTRA_CLAUDE") == "1":
                groups.append(
                    {
                        "displayName": "Claude and GPT models",
                        "buckets": [
                            {
                                "bucketId": "claude-weekly",
                                "displayName": "Weekly",
                                "remainingFraction": 0.1,
                            }
                        ],
                    }
                )
            body = {
                "code": 0,
                "response": {
                    "groups": groups
                },
            }
        elif self.path.endswith("/GetUserStatus"):
            body = {
                "code": 0,
                "userStatus": {
                    "email": os.environ.get("ANTIGRAVITY_FAKE_EMAIL", "app-local@example.com"),
                    "userTier": {"name": "Pro"},
                    "cascadeModelConfigData": {"clientModelConfigs": []},
                },
            }
        else:
            body = {"code": 0, "clientModelConfigs": []}
        payload = json.dumps(body, separators=(",", ":")).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, fmt, *args):
        pass

def stop(_signum, _frame):
    sys.exit(0)

signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)

server = http.server.HTTPServer(("127.0.0.1", int(os.environ["ANTIGRAVITY_FAKE_PORT"])), Handler)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(os.environ["ANTIGRAVITY_FAKE_CERT"], os.environ["ANTIGRAVITY_FAKE_KEY"])
server.socket = context.wrap_socket(server.socket, server_side=True)
server.serve_forever()
"""
            )
        os.chmod(language_server, 0o755)

        app_port = free_port()
        app_env = os.environ.copy()
        app_env["ANTIGRAVITY_FAKE_PORT"] = str(app_port)
        app_env["ANTIGRAVITY_FAKE_CERT"] = cert_path
        app_env["ANTIGRAVITY_FAKE_KEY"] = key_path
        app_env["ANTIGRAVITY_FAKE_CSRF"] = csrf_token
        app_env["ANTIGRAVITY_FAKE_CSRF_SEEN"] = csrf_seen_path
        wrong_process = None
        app_process = subprocess.Popen(
            [
                language_server,
                "--csrf_token",
                csrf_token,
                "--app_data_dir",
                os.path.join(tmpdir, "antigravity-app-data"),
            ],
            cwd=tmpdir,
            env=app_env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        try:
            def wait_tls_port(port):
                tls_deadline = time.time() + 5
                while True:
                    try:
                        tls_context = ssl._create_unverified_context()
                        with socket.create_connection(("127.0.0.1", port), timeout=0.2) as sock:
                            with tls_context.wrap_socket(sock, server_hostname="localhost"):
                                break
                    except OSError:
                        if time.time() > tls_deadline:
                            raise RuntimeError("antigravity fake app server did not listen in time")
                        time.sleep(0.05)

            wait_tls_port(app_port)
            cli_env = os.environ.copy()
            cli_env["HOME"] = tmpdir
            cli_env.pop("ANTIGRAVITY_CLI_PATH", None)
            proc = subprocess.run(
                [BIN, "usage", "--provider", "antigravity", "--source", "cli", "--json-only"],
                cwd=ROOT,
                env=cli_env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
            )
            assert proc.returncode == 0, proc.stdout + proc.stderr
            assert proc.stderr == "", proc.stderr
            payload = json.loads(proc.stdout)
            usage = payload[0]["usage"]
            assert usage["sourceLabel"] == "app", payload
            assert usage["accountLabel"] == "app-local@example.com", payload
            assert usage["windows"][0]["usedPercent"] == 80, payload
            with open(csrf_seen_path, "r", encoding="utf-8") as handle:
                csrf_paths = handle.read().splitlines()
            assert any(path.endswith("/RetrieveUserQuotaSummary") for path in csrf_paths), csrf_paths

            wrong_port = free_port()
            wrong_csrf_token = "csrf-wrong-account-token"
            wrong_env = os.environ.copy()
            wrong_env["ANTIGRAVITY_FAKE_PORT"] = str(wrong_port)
            wrong_env["ANTIGRAVITY_FAKE_CERT"] = cert_path
            wrong_env["ANTIGRAVITY_FAKE_KEY"] = key_path
            wrong_env["ANTIGRAVITY_FAKE_CSRF"] = wrong_csrf_token
            wrong_env["ANTIGRAVITY_FAKE_CSRF_SEEN"] = os.path.join(tmpdir, "wrong-csrf-seen.txt")
            wrong_env["ANTIGRAVITY_FAKE_EMAIL"] = "wrong-local@example.com"
            wrong_env["ANTIGRAVITY_FAKE_EXTRA_CLAUDE"] = "1"
            wrong_process = subprocess.Popen(
                [
                    language_server,
                    "--csrf_token",
                    wrong_csrf_token,
                    "--app_data_dir",
                    os.path.join(tmpdir, "wrong-antigravity-app-data"),
                ],
                cwd=tmpdir,
                env=wrong_env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            wait_tls_port(wrong_port)

            selected_env = cli_env.copy()
            selected_env["ANTIGRAVITY_OAUTH_CREDENTIALS_JSON"] = json.dumps(
                {"email": "app-local@example.com", "access_token": "token"},
                separators=(",", ":"),
            )
            proc = subprocess.run(
                [BIN, "usage", "--provider", "antigravity", "--source", "cli", "--json-only"],
                cwd=ROOT,
                env=selected_env,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
            )
            assert proc.returncode == 0, proc.stdout + proc.stderr
            assert proc.stderr == "", proc.stderr
            payload = json.loads(proc.stdout)
            usage = payload[0]["usage"]
            assert usage["sourceLabel"] == "app", payload
            assert usage["accountLabel"] == "app-local@example.com", payload
            assert usage["windows"][0]["usedPercent"] == 80, payload
        finally:
            if wrong_process is not None:
                wrong_process.terminate()
                try:
                    wrong_process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    wrong_process.kill()
                    wrong_process.wait(timeout=5)
            app_process.terminate()
            try:
                app_process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                app_process.kill()
                app_process.wait(timeout=5)


def main():
    test_run_wait()
    print("run-wait ok")
    test_stdin_and_batch()
    print("stdin-batch ok")
    test_bridge_http()
    print("bridge-http ok")
    test_usage_server_config_validate()
    print("usage-server-config ok")
    test_resource_commands()
    print("resource-commands ok")
    test_config_validate_cookie_source_semantics()
    print("config-validate ok")
    test_usage_marks_token_account_last_used()
    print("usage-token-last-used ok")
    test_usage_repair_actions_include_config_commands()
    print("usage-repair-actions ok")
    test_usage_cli_help_has_no_side_effects()
    print("usage-cli-help ok")
    test_usage_cli_json_only_alias()
    print("usage-cli-json-only ok")
    test_usage_configured_probes_do_not_read_browser_state()
    print("usage-configured-probes ok")
    test_usage_web_cookie_fetchers_label_actual_source()
    print("usage-web-cookie-source-labels ok")
    test_antigravity_serve_reuses_warm_agy_session()
    print("antigravity-warm-session ok")
    test_antigravity_app_local_probe_uses_csrf()
    print("antigravity-app-local-csrf ok")
    test_cache_cli_provider_scope_errors()
    print("cache-cli-errors ok")
    test_cost_scanner_truncated_codex_context()
    print("cost-scan-truncation ok")
    test_cost_scanner_incomplete_tail_append_cache()
    print("cost-scan-tail-cache ok")
    test_cost_cli_refresh_forces_rescan()
    print("cost-cli-refresh ok")
    test_cost_scanner_large_claude_corpus_smoke()
    print("cost-scan-large-corpus ok")
    test_cli_command_surface()
    print("cli-command-surface ok")


main()
PY
