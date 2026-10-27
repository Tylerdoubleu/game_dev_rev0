#!/usr/bin/env python3
"""
Edgegap Arbitrium Deployment Automation for 2000s Pro Paintball (game-dev-rev0)
Creates/updates the Edgegap application, creates/updates version v0.2.2 pointing to
ghcr.io/tylerdoubleu/game_dev_rev0:latest on port 8080 (WS/HTTP with TLS upgrade),
and launches a live deployment (`POST /v1/deploy`).
"""
import os
import sys
import time
import json
import urllib.request
import urllib.error

API_BASE = "https://api.edgegap.com"
APP_NAME = os.environ.get("EDGEGAP_APP_NAME", "game-dev-rev0")
VERSION_NAME = os.environ.get("EDGEGAP_VERSION_NAME", "v0.2.2")
IMAGE_REPO = os.environ.get("EDGEGAP_IMAGE_REPO", "docker.io")
IMAGE_NAME = os.environ.get("EDGEGAP_IMAGE_NAME", "library/node")
IMAGE_TAG = os.environ.get("EDGEGAP_IMAGE_TAG", "20-bookworm")


def get_auth_header() -> str:
    raw = os.environ.get("EDGEGAP_API_TOKEN", "").strip()
    if not raw:
        raise RuntimeError("EDGEGAP_API_TOKEN environment variable is not set")
    return raw if raw.lower().startswith("token ") else f"token {raw}"


def api_request(method: str, path: str, payload=None):
    url = f"{API_BASE}{path}"
    headers = {
        "Authorization": get_auth_header(),
        "Accept": "application/json",
    }
    data = None
    if payload is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read().decode("utf-8")
            return resp.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8", errors="replace")
        return e.code, {"error": err_body}


def get_public_ip() -> str:
    for url in ["https://api.ipify.org", "https://ifconfig.me/ip"]:
        try:
            with urllib.request.urlopen(url, timeout=5) as r:
                ip = r.read().decode("utf-8").strip()
                if ip:
                    return ip
        except Exception:
            pass
    return "8.8.8.8"


def main():
    print(f"[Edgegap] Ensuring application '{APP_NAME}' exists...")
    status, app_resp = api_request("GET", f"/v1/app/{APP_NAME}")
    if status == 404:
        # 1x1 transparent PNG base64 for Edgegap app icon
        icon_b64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        status, app_resp = api_request(
            "POST",
            "/v1/apps",
            {"name": APP_NAME, "is_active": True, "image": icon_b64},
        )
        print(f"[Edgegap] Created app '{APP_NAME}' (HTTP {status})")
    else:
        print(f"[Edgegap] Found existing app '{APP_NAME}' (HTTP {status})")

    version_payload = {
        "name": VERSION_NAME,
        "docker_repository": IMAGE_REPO,
        "docker_image": IMAGE_NAME,
        "docker_tag": IMAGE_TAG,
        "req_cpu": 128,
        "req_memory": 256,
        "req_video": 0,
        "max_duration": 60,
        "use_telemetry": False,
        "inject_context_env": True,
        "force_cache": False,
        "ports": [
            {
                "port": 8080,
                "protocol": "WS",
                "to_check": True,
                "tls_upgrade": True,
                "name": "gameport",
            }
        ],
        "envs": [
            {"key": "PORT", "value": "8080", "is_secret": False},
            {"key": "WS_PORT", "value": "9080", "is_secret": False},
            {"key": "AUTO_START_GODOT", "value": "1", "is_secret": False},
            {"key": "DEDICATED_SERVER", "value": "1", "is_secret": False},
        ],
    }

    print(f"[Edgegap] Creating/updating version '{VERSION_NAME}' -> {IMAGE_REPO}/{IMAGE_NAME}:{IMAGE_TAG}...")
    v_status, v_resp = api_request("POST", f"/v1/app/{APP_NAME}/version", version_payload)
    if v_status in (400, 409):
        v_status, v_resp = api_request("PATCH", f"/v1/app/{APP_NAME}/version/{VERSION_NAME}", version_payload)
        print(f"[Edgegap] Updated version '{VERSION_NAME}' (HTTP {v_status})")
    else:
        print(f"[Edgegap] Created version '{VERSION_NAME}' (HTTP {v_status})")

    if v_status >= 400:
        print(f"[Edgegap] Version error response: {v_resp}")

    client_ip = get_public_ip()
    print(f"[Edgegap] Launching live deployment for {APP_NAME}:{VERSION_NAME} (client IP: {client_ip})...")
    d_status, d_resp = api_request(
        "POST",
        "/v1/deploy",
        {
            "app_name": APP_NAME,
            "version_name": VERSION_NAME,
            "ip_list": [client_ip],
        },
    )
    print(f"[Edgegap] POST /v1/deploy -> HTTP {d_status}: {json.dumps(d_resp)}")
    req_id = d_resp.get("request_id")
    if not req_id:
        return

    print(f"[Edgegap] Polling status for request_id={req_id}...")
    for _ in range(30):
        time.sleep(4)
        s_code, s_body = api_request("GET", f"/v1/status/{req_id}")
        cur = s_body.get("current_status", "UNKNOWN")
        print(f"  status={cur} (HTTP {s_code})")
        if "READY" in cur.upper():
            print("\n=== EDGEGAP LIVE DEPLOYMENT READY ===")
            print(json.dumps(s_body, indent=2))
            break
        if "ERROR" in cur.upper() or "TERMINATED" in cur.upper():
            print("\n=== EDGEGAP DEPLOYMENT STOPPED/ERROR ===")
            print(json.dumps(s_body, indent=2))
            break


if __name__ == "__main__":
    main()
