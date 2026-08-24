#!/usr/bin/env python3
"""Fetch tester-shared TestFlight crash logs without requesting tester identity fields."""

from __future__ import annotations

import argparse
import base64
import json
import pathlib
import time
import urllib.error
import urllib.parse
import urllib.request

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature


API_ROOT = "https://api.appstoreconnect.apple.com"


def base64url(value: bytes) -> str:
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


class AppStoreConnectClient:
    def __init__(self, key_id: str, issuer_id: str, private_key_path: pathlib.Path) -> None:
        self.key_id = key_id
        self.issuer_id = issuer_id
        self.private_key = serialization.load_pem_private_key(
            private_key_path.read_bytes(), password=None
        )

    def token(self) -> str:
        now = int(time.time())
        header = {"alg": "ES256", "kid": self.key_id, "typ": "JWT"}
        payload = {
            "iss": self.issuer_id,
            "iat": now - 5,
            "exp": now + 15 * 60,
            "aud": "appstoreconnect-v1",
        }
        encoded_header = base64url(
            json.dumps(header, separators=(",", ":")).encode("utf-8")
        )
        encoded_payload = base64url(
            json.dumps(payload, separators=(",", ":")).encode("utf-8")
        )
        signing_input = f"{encoded_header}.{encoded_payload}".encode("ascii")
        der_signature = self.private_key.sign(signing_input, ec.ECDSA(hashes.SHA256()))
        r, s = decode_dss_signature(der_signature)
        raw_signature = r.to_bytes(32, "big") + s.to_bytes(32, "big")
        return f"{encoded_header}.{encoded_payload}.{base64url(raw_signature)}"

    def get(self, path: str, query: dict[str, str] | None = None) -> dict:
        url = f"{API_ROOT}{path}"
        if query:
            url = f"{url}?{urllib.parse.urlencode(query)}"
        request = urllib.request.Request(
            url,
            headers={
                "Authorization": f"Bearer {self.token()}",
                "Accept": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(request, timeout=45) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            body = error.read().decode("utf-8", errors="replace")
            raise RuntimeError(
                f"App Store Connect returned HTTP {error.code}: {body[:2000]}"
            ) from error


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--app-id", required=True)
    parser.add_argument("--expected-bundle-id", required=True)
    parser.add_argument("--key-id", required=True)
    parser.add_argument("--issuer-id", required=True)
    parser.add_argument("--private-key", required=True, type=pathlib.Path)
    parser.add_argument("--wait-minutes", type=int, default=20)
    parser.add_argument("--output", required=True, type=pathlib.Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    client = AppStoreConnectClient(args.key_id, args.issuer_id, args.private_key)
    attempts = max(1, args.wait_minutes * 2)
    submissions: list[dict] = []

    for attempt in range(1, attempts + 1):
        response = client.get(
            f"/v1/apps/{args.app_id}/betaFeedbackCrashSubmissions",
            {
                "fields[betaFeedbackCrashSubmissions]": (
                    "createdDate,deviceModel,osVersion,architecture,"
                    "appUptimeInMilliseconds,appPlatform,devicePlatform,"
                    "deviceFamily,buildBundleId,crashLog,build"
                ),
                "sort": "-createdDate",
                "limit": "10",
            },
        )
        submissions = response.get("data", [])
        if submissions:
            break
        print(
            f"Apple has not published the shared crash yet "
            f"(attempt {attempt}/{attempts})."
        )
        if attempt < attempts:
            time.sleep(30)

    if not submissions:
        raise RuntimeError(
            "No tester-shared TestFlight crash submission was available before the polling deadline."
        )

    summaries: list[dict] = []
    for index, submission in enumerate(submissions, start=1):
        submission_id = submission["id"]
        attributes = submission.get("attributes") or {}
        bundle_id = attributes.get("buildBundleId")
        if bundle_id and bundle_id != args.expected_bundle_id:
            continue
        crash = client.get(
            f"/v1/betaFeedbackCrashSubmissions/{submission_id}/crashLog",
            {"fields[betaCrashLogs]": "logText"},
        )
        crash_attributes = (crash.get("data") or {}).get("attributes") or {}
        log_text = crash_attributes.get("logText") or ""
        log_path = args.output / f"crash-{index}-{submission_id}.crash"
        log_path.write_text(log_text, encoding="utf-8")
        summaries.append(
            {
                "submissionId": submission_id,
                "createdDate": attributes.get("createdDate"),
                "deviceModel": attributes.get("deviceModel"),
                "osVersion": attributes.get("osVersion"),
                "architecture": attributes.get("architecture"),
                "appUptimeInMilliseconds": attributes.get(
                    "appUptimeInMilliseconds"
                ),
                "appPlatform": attributes.get("appPlatform"),
                "devicePlatform": attributes.get("devicePlatform"),
                "deviceFamily": attributes.get("deviceFamily"),
                "buildBundleId": bundle_id,
                "crashLogFile": log_path.name,
            }
        )

    if not summaries:
        raise RuntimeError(
            f"Crash submissions existed, but none matched {args.expected_bundle_id}."
        )

    summary_path = args.output / "summary.json"
    summary_path.write_text(json.dumps(summaries, indent=2), encoding="utf-8")
    print(f"Downloaded {len(summaries)} privacy-bounded TestFlight crash diagnostic(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
