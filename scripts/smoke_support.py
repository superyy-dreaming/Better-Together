#!/usr/bin/env python3
"""Safe synthetic-account HTTP helpers; never proxy or store AI credentials."""
from __future__ import annotations

import argparse
from datetime import datetime
import hashlib
import io
import json
from pathlib import Path
import random
import re
import stat
import sys
import time
from typing import Any
import urllib.error
import urllib.parse
import urllib.request
import uuid
from zoneinfo import ZoneInfo


class SmokeError(Exception):
    """Safe, fixed diagnostic code; never stores response bodies or URLs."""

    def __init__(self, code: str):
        super().__init__(code)
        self.code = code


def require(condition: bool, code: str) -> None:
    if not condition:
        raise SmokeError(code)


def private_text(path: Path) -> str:
    try:
        metadata = path.lstat()
        require(stat.S_ISREG(metadata.st_mode), "CONFIG_NOT_REGULAR")
        require(stat.S_IMODE(metadata.st_mode) == 0o600, "CONFIG_PERMISSIONS")
        return path.read_text(encoding="utf-8")
    except OSError:
        raise SmokeError("CONFIG_UNREADABLE") from None


def env_file(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for line in private_text(path).splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        require("=" in line, "CONFIG_FORMAT")
        key, value = line.split("=", 1)
        key, value = key.strip(), value.strip()
        require(bool(re.fullmatch(r"[A-Z][A-Z0-9_]*", key)), "CONFIG_FORMAT")
        require(key not in values, "CONFIG_DUPLICATE")
        if value.startswith(("'", '"')):
            require(len(value) >= 2 and value[-1] == value[0], "CONFIG_QUOTES")
            value = value[1:-1]
        values[key] = value
    return values


def required(config: dict[str, Any], key: str) -> str:
    value = config.get(key)
    require(isinstance(value, str) and bool(value.strip()), "CONFIG_MISSING")
    return value.strip()


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # Never forward account or service credentials to a redirect target.
        raise SmokeError("REDIRECT_REJECTED")


class Client:
    def __init__(self, base_url: str, anon: str, service: str, job_secret: str):
        parsed = urllib.parse.urlsplit(base_url)
        require(parsed.scheme == "https" and parsed.hostname is not None and
                parsed.hostname.endswith(".supabase.co") and not parsed.username and
                not parsed.password and not parsed.query and not parsed.fragment and
                parsed.path in ("", "/"), "PROJECT_URL_INVALID")
        self.base_url = base_url.rstrip("/")
        self.anon = anon
        self.service = service
        self.job_secret = job_secret
        self.token = ""
        self.owner = ""
        self.opener = urllib.request.build_opener(NoRedirect())

    def call(self, path: str, payload: Any = None, *, method: str = "POST",
             admin: bool = False, worker: bool = False,
             raw: bytes | None = None, content_type: str = "application/json") -> Any:
        require(path.startswith("/") and not path.startswith("//"), "REQUEST_PATH_INVALID")
        key = self.service if admin else self.anon
        headers = {"apikey": key, "Content-Type": content_type}
        if admin:
            headers["Authorization"] = "Bearer " + self.service
        elif self.token:
            headers["Authorization"] = "Bearer " + self.token
        if worker:
            headers["x-job-secret"] = self.job_secret
        body = raw if raw is not None else json.dumps(payload).encode() if payload is not None else None
        request = urllib.request.Request(self.base_url + path, data=body, headers=headers, method=method)
        try:
            with self.opener.open(request, timeout=110) as response:
                value = response.read(12 * 1024 * 1024 + 1)
                require(len(value) <= 12 * 1024 * 1024, "RESPONSE_TOO_LARGE")
                return json.loads(value) if value else None
        except urllib.error.HTTPError as error:
            # Error bodies can contain tokens/provider echoes. Do not read them.
            code = int(error.code)
            error.close()
            raise SmokeError(f"HTTP_{code}") from None
        except (urllib.error.URLError, TimeoutError, OSError):
            raise SmokeError("NETWORK_UNAVAILABLE") from None
        except (json.JSONDecodeError, UnicodeError):
            raise SmokeError("RESPONSE_INVALID") from None

    def login(self, config: dict[str, Any]) -> None:
        result = self.call("/auth/v1/token?grant_type=password", {
            "email": required(config, "TEST_EMAIL"),
            "password": required(config, "TEST_PASSWORD"),
        })
        self.token = required(result, "access_token")
        self.owner = required(result.get("user", {}), "id")
        require(bool(re.fullmatch(r"[0-9a-f-]{36}", self.owner)), "ACCOUNT_ID_INVALID")

    def action(self, name: str, **args: Any) -> Any:
        response = self.call("/functions/v1/api", {"action": name, **args})
        require(isinstance(response, dict) and "data" in response, "API_RESPONSE_INVALID")
        return response["data"]

    def rows(self, table: str, select: str, filters: dict[str, str]) -> list[dict[str, Any]]:
        query = urllib.parse.urlencode({"select": select, **filters})
        result = self.call(f"/rest/v1/{table}?{query}", method="GET", admin=True)
        require(isinstance(result, list), "DATABASE_RESPONSE_INVALID")
        return result

    def timezone(self) -> str:
        members = self.rows("team_members", "team_id", {"user_id": "eq." + self.owner,
                                                        "left_at": "is.null"})
        require(len(members) <= 1, "MULTIPLE_TEAMS")
        if members:
            teams = self.rows("teams", "timezone", {"id": "eq." + members[0]["team_id"]})
            require(len(teams) == 1, "TEAM_MISSING")
            return required(teams[0], "timezone")
        profiles = self.rows("profiles", "timezone", {"id": "eq." + self.owner})
        require(len(profiles) == 1, "PROFILE_MISSING")
        return required(profiles[0], "timezone")

    def exact_counts(self, batch: str, photo: str) -> dict[str, int]:
        media = self.rows("media", "id", {"user_id": "eq." + self.owner, "batch_id": "eq." + batch})
        checkins = self.rows("checkins", "id", {"user_id": "eq." + self.owner, "batch_id": "eq." + batch})
        analysis = self.rows("media_analysis", "media_id", {"user_id": "eq." + self.owner,
                                                              "media_id": "eq." + photo})
        objects = self.call("/storage/v1/object/list/evidence", {
            "prefix": f"{self.owner}/{batch}/", "limit": 100, "offset": 0,
        }, admin=True)
        require(isinstance(objects, list), "STORAGE_LIST_INVALID")
        return {"media": len(media), "checkins": len(checkins), "analysis": len(analysis), "objects": len(objects)}

    def multipart(self, name: str, fields: dict[str, str], files: dict[str, bytes]) -> dict[str, Any]:
        boundary = "BetterTogetherSmoke" + uuid.uuid4().hex
        content = bytearray()
        for key, value in fields.items():
            content.extend(f'--{boundary}\r\nContent-Disposition: form-data; name="{key}"\r\n\r\n{value}\r\n'.encode())
        for key, value in files.items():
            content.extend(f'--{boundary}\r\nContent-Disposition: form-data; name="{key}"; filename="{key}.jpg"\r\nContent-Type: image/jpeg\r\n\r\n'.encode())
            content.extend(value)
            content.extend(b"\r\n")
        content.extend(f"--{boundary}--\r\n".encode())
        result = self.call("/functions/v1/" + name, raw=bytes(content),
                           content_type="multipart/form-data; boundary=" + boundary)
        require(isinstance(result, dict) and isinstance(result.get("data"), dict), "UPLOAD_RESPONSE_INVALID")
        return result["data"]

def synthetic_photo(timezone: str) -> tuple[bytes, bytes, dict[str, int], str]:
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError:
        raise SmokeError("PIL_REQUIRED") from None
    now = datetime.now(ZoneInfo(timezone))
    image = Image.new("RGB", (2100, 1400), "#f6f3ea")
    draw = ImageDraw.Draw(image)
    rng = random.Random(uuid.uuid4().int)
    # Large random blocks ensure distinct perceptual structure across reruns;
    # the picture is explicitly synthetic and contains no user information.
    for x in range(0, 2100, 300):
        for y in range(760, 1400, 160):
            color = tuple(rng.randrange(30, 230) for _ in range(3))
            draw.rectangle((x, y, x + rng.randrange(100, 295), y + 140), fill=color)
    font = None
    for candidate in ("/System/Library/Fonts/Supplemental/Courier New.ttf",
                      "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"):
        try:
            font = ImageFont.truetype(candidate, 56)
            break
        except OSError:
            pass
    if font is None:
        font = ImageFont.load_default()
    lines = ["SYNTHETIC FAILURE RECOVERY TEST", "BIOLOGY STUDY NOTES",
             "Plants use sunlight to create chemical energy.",
             "Water + carbon dioxide -> glucose + oxygen.",
             now.strftime("%Y-%m-%d %H:%M:%S %z")]
    for index, line in enumerate(lines):
        draw.text((70, 90 + index * 125), line, fill="#173e2e", font=font)
    exif = Image.Exif()
    exif[34665] = {36867: now.strftime("%Y:%m:%d %H:%M:%S")}
    offset = now.strftime("%z")
    exif[34665][36881] = offset[:3] + ":" + offset[3:]
    original = io.BytesIO()
    image.save(original, format="JPEG", quality=94, exif=exif)
    image.thumbnail((1600, 1600))
    analysis = io.BytesIO()
    image.save(analysis, format="JPEG", quality=82)
    require(max(image.size) <= 1600 and len(analysis.getvalue()) <= 2 * 1024 * 1024,
            "SYNTHETIC_IMAGE_LIMIT")
    return original.getvalue(), analysis.getvalue(), {
        "original_width": 2100, "original_height": 1400,
        "analysis_width": image.width, "analysis_height": image.height,
    }, now.strftime("%Y-%m-%d")


