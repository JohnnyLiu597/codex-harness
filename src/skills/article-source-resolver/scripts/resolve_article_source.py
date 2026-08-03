#!/usr/bin/env python3
"""Resolve article HTML into an evidence-graded, citation-aware JSON record."""

from __future__ import annotations

import argparse
import codecs
import datetime as dt
import hashlib
import html
import ipaddress
import json
import mimetypes
import re
import socket
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from html.parser import HTMLParser
from pathlib import Path
from typing import Any


CAPTURE_IDS = {
    "activity-name",
    "js_name",
    "js_author_name",
    "js_title_inner",
    "profileBt",
    "publish_time",
}
BLOCK_TAGS = {
    "article",
    "blockquote",
    "br",
    "dd",
    "div",
    "dl",
    "dt",
    "figcaption",
    "figure",
    "h1",
    "h2",
    "h3",
    "h4",
    "h5",
    "h6",
    "li",
    "ol",
    "p",
    "pre",
    "section",
    "table",
    "td",
    "th",
    "tr",
    "ul",
}
GENERIC_CONTENT_CLASSES = {
    "article-body",
    "article-content",
    "article__body",
    "content-body",
    "entry-content",
    "layout__content",
    "main-page-content",
    "markdown-body",
    "mw-parser-output",
    "post-body",
    "post-content",
    "prose",
    "rich-text",
    "story-body",
}
GENERIC_CONTENT_IDS = {
    "article-body",
    "article-content",
    "bodycontent",
    "main-content",
    "mw-content-text",
    "pep-content",
    "post-content",
    "story-body",
}
JSON_LD_ARTICLE_TYPES = {
    "article",
    "blogposting",
    "newsarticle",
    "report",
    "scholarlyarticle",
    "techarticle",
}
ERROR_PHRASES = {
    "deleted": (
        "该内容已被发布者删除",
        "作者已删除",
        "the content has been deleted by the author",
    ),
    "unavailable": (
        "该内容暂时无法查看",
        "内容违规",
        "此内容因违规无法查看",
        "this content is unavailable",
    ),
    "challenge": (
        "环境异常",
        "操作频繁",
        "访问过于频繁",
        "请输入验证码",
        "安全验证",
        "weixin110.qq.com",
        "wappoc_appmsgcaptcha",
    ),
}
JS_STRING = r'("(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\')'
SYNTHETIC_EGRESS = ipaddress.ip_network("198.18.0.0/15")
BROWSER_COMPATIBLE_USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
    "AppleWebKit/537.36 Chrome/126 Safari/537.36"
)
MIN_FULL_CONTENT_CHARS = 120
MOJIBAKE_MARKERS = (
    "锟斤拷",
    "鈥",
    "鍙堟槸",
    "涓€",
    "鐨勫",
    "杩欐",
    "璇ユ",
    "鏂囩",
)
HTML_MEDIA_TYPES = {"text/html", "application/xhtml+xml"}
JSON_MEDIA_TYPES = {"application/json", "application/geo+json", "application/ld+json"}
XML_MEDIA_TYPES = {"application/xml", "text/xml"}
FEED_MEDIA_TYPES = {"application/rss+xml", "application/atom+xml"}
CSV_MEDIA_TYPES = {"text/csv", "application/csv"}
TEXT_APPLICATION_TYPES = {
    "application/javascript",
    "application/sql",
    "application/x-javascript",
    "application/x-ndjson",
    "application/yaml",
}


def clean_text(value: str) -> str:
    value = html.unescape(value or "").replace("\xa0", " ")
    lines = []
    for line in re.split(r"[\r\n]+", value):
        line = re.sub(r"[ \t\f\v]+", " ", line).strip()
        if line:
            lines.append(line)
    return "\n".join(lines)


def normalize_charset(value: str) -> str:
    if not value:
        return ""
    try:
        return codecs.lookup(value.strip().strip('"\'')).name
    except LookupError:
        return ""


def sniff_meta_charset(payload: bytes) -> str:
    head = payload[:16384]
    patterns = (
        rb'<meta[^>]+charset\s*=\s*["\']?\s*([A-Za-z0-9._:-]+)',
        rb'<meta[^>]+content\s*=\s*["\'][^"\']*charset\s*=\s*([A-Za-z0-9._:-]+)',
    )
    for pattern in patterns:
        match = re.search(pattern, head, flags=re.IGNORECASE)
        if match:
            return match.group(1).decode("ascii", errors="ignore")
    return ""


def decode_payload(payload: bytes, declared_charset: str = "") -> tuple[str, str, list[str]]:
    candidates: list[str] = []
    if payload.startswith(codecs.BOM_UTF8):
        candidates.append("utf-8-sig")
    elif payload.startswith((codecs.BOM_UTF32_LE, codecs.BOM_UTF32_BE)):
        candidates.append("utf-32")
    elif payload.startswith((codecs.BOM_UTF16_LE, codecs.BOM_UTF16_BE)):
        candidates.append("utf-16")

    candidates.extend((declared_charset, sniff_meta_charset(payload), "utf-8", "gb18030"))
    normalized_candidates: list[str] = []
    for candidate in candidates:
        normalized = normalize_charset(candidate)
        if normalized and normalized not in normalized_candidates:
            normalized_candidates.append(normalized)

    for candidate in normalized_candidates:
        try:
            return payload.decode(candidate), candidate, []
        except UnicodeDecodeError:
            continue

    fallback = normalized_candidates[0] if normalized_candidates else "utf-8"
    return (
        payload.decode(fallback, errors="replace"),
        fallback,
        [f"Response required replacement decoding with {fallback}."],
    )


def parse_content_type(value: str) -> tuple[str, str]:
    parts = [part.strip() for part in (value or "").split(";") if part.strip()]
    media_type = parts[0].lower() if parts else ""
    charset = ""
    for part in parts[1:]:
        key, separator, raw_value = part.partition("=")
        if separator and key.strip().lower() == "charset":
            charset = normalize_charset(raw_value)
            break
    return media_type, charset


def kind_from_media_type(media_type: str) -> str:
    media_type = (media_type or "").lower()
    if media_type in HTML_MEDIA_TYPES or media_type.endswith("+html"):
        return "html"
    if media_type in FEED_MEDIA_TYPES:
        return "feed"
    if media_type in JSON_MEDIA_TYPES or media_type.endswith("+json"):
        return "json"
    if media_type in XML_MEDIA_TYPES or media_type.endswith("+xml"):
        return "xml"
    if media_type in CSV_MEDIA_TYPES:
        return "csv"
    if media_type == "application/pdf":
        return "pdf"
    if media_type.startswith("image/"):
        return "image"
    if media_type.startswith("audio/"):
        return "audio"
    if media_type.startswith("video/"):
        return "video"
    if media_type.startswith("text/") or media_type in TEXT_APPLICATION_TYPES:
        return "text"
    if media_type in {
        "application/gzip",
        "application/vnd.rar",
        "application/x-7z-compressed",
        "application/x-tar",
        "application/zip",
    }:
        return "archive"
    return ""


def sniff_resource(payload: bytes, declared_media_type: str, locator: str) -> dict[str, Any]:
    declared_media_type = (declared_media_type or "").lower()
    extension_media_type, _ = mimetypes.guess_type(urllib.parse.urlsplit(locator).path if locator else "")
    extension_media_type = (extension_media_type or "").lower()
    stripped = payload.lstrip()
    sample = stripped[:4096]
    sample_lower = sample.lower()
    detected_kind = ""
    detected_media_type = ""
    detection_source = ""

    magic_signatures = (
        (b"%PDF-", "pdf", "application/pdf"),
        (b"\x89PNG\r\n\x1a\n", "image", "image/png"),
        (b"\xff\xd8\xff", "image", "image/jpeg"),
        (b"GIF87a", "image", "image/gif"),
        (b"GIF89a", "image", "image/gif"),
        (b"PK\x03\x04", "archive", "application/zip"),
    )
    for signature, kind, media_type in magic_signatures:
        if payload.startswith(signature):
            detected_kind = kind
            detected_media_type = media_type
            detection_source = "magic"
            break
    if not detected_kind and len(payload) >= 12 and payload[:4] == b"RIFF" and payload[8:12] == b"WEBP":
        detected_kind = "image"
        detected_media_type = "image/webp"
        detection_source = "magic"
    if not detected_kind and (
        b"<!doctype html" in sample_lower
        or b"<html" in sample_lower
        or b"<head" in sample_lower
        or b"<body" in sample_lower
    ):
        detected_kind = "html"
        detected_media_type = "text/html"
        detection_source = "content"
    if not detected_kind and sample_lower.startswith(b"<svg"):
        detected_kind = "image"
        detected_media_type = "image/svg+xml"
        detection_source = "content"
    if not detected_kind and sample[:1] in {b"{", b"["}:
        detected_kind = "json"
        detected_media_type = declared_media_type if kind_from_media_type(declared_media_type) == "json" else "application/json"
        detection_source = "content"
    if not detected_kind and sample.startswith(b"<"):
        if re.search(br"<(?:rss|feed)(?:\s|>)", sample, flags=re.IGNORECASE):
            detected_kind = "feed"
            detected_media_type = (
                "application/rss+xml" if re.search(br"<rss(?:\s|>)", sample, flags=re.IGNORECASE) else "application/atom+xml"
            )
        else:
            detected_kind = "xml"
            detected_media_type = "application/xml"
        detection_source = "content"
    if not detected_kind:
        declared_kind = kind_from_media_type(declared_media_type)
        if declared_kind:
            detected_kind = declared_kind
            detected_media_type = declared_media_type
            detection_source = "content-type"
    if not detected_kind:
        extension_kind = kind_from_media_type(extension_media_type)
        if extension_kind:
            detected_kind = extension_kind
            detected_media_type = extension_media_type
            detection_source = "extension"
    if not detected_kind:
        control_bytes = sum(byte < 9 or 13 < byte < 32 for byte in payload[:4096])
        sample_size = max(1, len(payload[:4096]))
        if control_bytes / sample_size <= 0.02:
            detected_kind = "text"
            detected_media_type = declared_media_type or extension_media_type or "text/plain"
            detection_source = "content"
        else:
            detected_kind = "binary"
            detected_media_type = declared_media_type or extension_media_type or "application/octet-stream"
            detection_source = "fallback"

    return {
        "kind": detected_kind,
        "media_type": detected_media_type,
        "declared_media_type": declared_media_type,
        "extension_media_type": extension_media_type,
        "detection_source": detection_source,
        "textual": detected_kind in {"html", "json", "xml", "feed", "csv", "text"},
    }


def text_quality(value: str) -> dict[str, Any]:
    replacement_chars = value.count("\ufffd")
    mojibake_marker_hits = sum(value.count(marker) for marker in MOJIBAKE_MARKERS)
    return {
        "replacement_chars": replacement_chars,
        "mojibake_marker_hits": mojibake_marker_hits,
        "mojibake_suspected": replacement_chars > 0 or mojibake_marker_hits >= 2,
    }


def normalized_match_key(value: str) -> str:
    return re.sub(r"[^\w]+", "", (value or "").casefold(), flags=re.UNICODE)


def timestamp_to_iso(value: str) -> str:
    if re.fullmatch(r"\d{10}|\d{13}", value or ""):
        seconds = int(value)
        if len(value) == 13:
            seconds /= 1000
        try:
            parsed = dt.datetime.fromtimestamp(seconds, tz=dt.timezone.utc)
        except (OverflowError, OSError, ValueError):
            return ""
        return parsed.isoformat().replace("+00:00", "Z")
    try:
        parsed = dt.datetime.fromisoformat((value or "").replace("Z", "+00:00"))
    except ValueError:
        return ""
    return parsed.isoformat().replace("+00:00", "Z")


def iter_json_nodes(value: Any):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from iter_json_nodes(child)
    elif isinstance(value, list):
        for child in value:
            yield from iter_json_nodes(child)


def json_ld_author(value: Any) -> str:
    if isinstance(value, str):
        return clean_text(value)
    if isinstance(value, list):
        names = [json_ld_author(item) for item in value]
        return ", ".join(dict.fromkeys(name for name in names if name))
    if isinstance(value, dict):
        name = value.get("name")
        if isinstance(name, str):
            return clean_text(name)
        parts = [value.get("givenName"), value.get("familyName")]
        return clean_text(" ".join(str(part) for part in parts if part))
    return ""


def extract_json_ld_article(raw_html: str) -> dict[str, str]:
    pattern = re.compile(
        r'<script\b(?=[^>]*\btype\s*=\s*["\']application/ld\+json["\'])[^>]*>(.*?)</script>',
        flags=re.IGNORECASE | re.DOTALL,
    )
    candidates: list[dict[str, str]] = []
    for match in pattern.finditer(raw_html):
        payload = match.group(1).strip()
        payload = re.sub(r"^\s*<!--|-->\s*$", "", payload).strip()
        try:
            data = json.loads(payload)
        except (json.JSONDecodeError, TypeError):
            continue
        for node in iter_json_nodes(data):
            raw_types = node.get("@type", [])
            if isinstance(raw_types, str):
                raw_types = [raw_types]
            types = {str(item).lower() for item in raw_types}
            if not types.intersection(JSON_LD_ARTICLE_TYPES):
                continue
            title = node.get("headline") or node.get("name") or ""
            body = node.get("articleBody") or node.get("text") or ""
            published_at = node.get("datePublished") or node.get("dateCreated") or ""
            candidates.append(
                {
                    "title": clean_text(str(title)) if title else "",
                    "author": json_ld_author(node.get("author")),
                    "published_at": clean_text(str(published_at)) if published_at else "",
                    "body": str(body) if body else "",
                }
            )
    if not candidates:
        return {}
    return max(candidates, key=lambda item: (len(item["body"]), len(item["title"])))


def decode_js_literal(literal: str) -> str:
    if not literal or literal[0] not in {"'", '"'}:
        return literal
    if literal[0] == '"':
        try:
            return json.loads(literal)
        except json.JSONDecodeError:
            pass

    body = literal[1:-1]

    def replace_escape(match: re.Match[str]) -> str:
        token = match.group(1)
        simple = {
            "n": "\n",
            "r": "\r",
            "t": "\t",
            "b": "\b",
            "f": "\f",
            "\\": "\\",
            "'": "'",
            '"': '"',
            "/": "/",
        }
        if token in simple:
            return simple[token]
        if token.startswith("u") and len(token) == 5:
            return chr(int(token[1:], 16))
        if token.startswith("x") and len(token) == 3:
            return chr(int(token[1:], 16))
        return token

    return re.sub(r"\\(u[0-9a-fA-F]{4}|x[0-9a-fA-F]{2}|.)", replace_escape, body)


def extract_js_value(script_text: str, keys: tuple[str, ...]) -> str:
    for key in keys:
        escaped = re.escape(key)
        patterns = (
            rf"(?:var\s+)?{escaped}\s*[:=]\s*({JS_STRING})",
            rf"(?:var\s+)?{escaped}\s*[:=]\s*JsDecode\(\s*({JS_STRING})\s*\)",
            rf"(?:var\s+)?{escaped}\s*[:=]\s*([0-9]{{4,}})",
        )
        for pattern in patterns:
            match = re.search(pattern, script_text, flags=re.IGNORECASE | re.DOTALL)
            if not match:
                continue
            value = match.group(1)
            if value[:1] in {"'", '"'}:
                return decode_js_literal(value)
            return value
    return ""


class FragmentParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.stack: list[str] = []
        self.text_parts: list[str] = []
        self.references: list[dict[str, Any]] = []
        self.images: list[str] = []
        self.anchor_stack: list[int | None] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        tag = tag.lower()
        attrs_map = {key.lower(): value or "" for key, value in attrs}
        self.stack.append(tag)
        anchor_index: int | None = None
        if tag == "a" and attrs_map.get("href"):
            anchor_index = len(self.references)
            self.references.append({"url": attrs_map["href"], "text_parts": []})
        self.anchor_stack.append(anchor_index)
        if tag == "img":
            src = attrs_map.get("data-src") or attrs_map.get("src")
            if src:
                self.images.append(src)
        if tag in BLOCK_TAGS:
            self.text_parts.append("\n")

    def handle_startendtag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        self.handle_starttag(tag, attrs)
        self.handle_endtag(tag)

    def handle_endtag(self, tag: str) -> None:
        if tag.lower() in BLOCK_TAGS:
            self.text_parts.append("\n")
        if self.stack:
            self.stack.pop()
        if self.anchor_stack:
            self.anchor_stack.pop()

    def handle_data(self, data: str) -> None:
        if not self.stack or self.stack[-1] not in {"script", "style", "noscript"}:
            self.text_parts.append(data)
            for index in self.anchor_stack:
                if index is not None:
                    self.references[index]["text_parts"].append(data)


class ArticleParser(HTMLParser):
    def __init__(self, capture_body: bool = False) -> None:
        super().__init__(convert_charrefs=True)
        self.capture_body = capture_body
        self.stack: list[dict[str, Any]] = []
        self.ids: set[str] = set()
        self.classes: set[str] = set()
        self.meta: dict[str, str] = {}
        self.captured: dict[str, list[str]] = {item: [] for item in CAPTURE_IDS}
        self.content_parts: list[str] = []
        self.references: list[dict[str, Any]] = []
        self.images: list[str] = []
        self.script_parts: list[str] = []
        self.error_parts: list[str] = []
        self.title_parts: list[str] = []
        self.content_heading_parts: list[str] = []
        self.content_roots: set[str] = set()
        self.headings: list[dict[str, Any]] = []
        self.paragraph_count = 0
        self.canonical_url = ""
        self.document_language = ""

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        tag = tag.lower()
        attrs_map = {key.lower(): value or "" for key, value in attrs}
        element_id = attrs_map.get("id", "")
        classes = {item.lower() for item in attrs_map.get("class", "").split() if item}
        itemprops = {item.lower() for item in attrs_map.get("itemprop", "").split() if item}
        parent_content = bool(self.stack and self.stack[-1]["inside_content"])
        is_rfc_document = any(
            entry["tag"] == "html" and "rfc" in entry["classes"] for entry in self.stack
        )
        content_root = ""
        if tag == "html" and attrs_map.get("lang"):
            self.document_language = attrs_map["lang"]
        if tag == "link" and "canonical" in attrs_map.get("rel", "").lower().split():
            self.canonical_url = attrs_map.get("href", "")
        if element_id == "js_content":
            content_root = "#js_content"
        elif tag == "article":
            content_root = "tag:article"
        elif "articlebody" in itemprops:
            content_root = "itemprop:articleBody"
        elif element_id.lower() in GENERIC_CONTENT_IDS:
            content_root = "id:" + element_id
        elif classes.intersection(GENERIC_CONTENT_CLASSES):
            content_root = "class:" + sorted(classes.intersection(GENERIC_CONTENT_CLASSES))[0]
        elif tag == "main" or attrs_map.get("role", "").lower() == "main":
            content_root = "tag:main" if tag == "main" else "role:main"
        elif tag == "body" and (is_rfc_document or self.capture_body):
            content_root = "document:rfc" if is_rfc_document else "tag:body"
        if content_root:
            self.content_roots.add(content_root)
        inside_content = parent_content or bool(content_root)
        anchor_index: int | None = None

        if element_id:
            self.ids.add(element_id)
        self.classes.update(classes)
        if tag == "meta":
            key = (attrs_map.get("property") or attrs_map.get("name") or "").lower()
            if key and attrs_map.get("content"):
                self.meta[key] = attrs_map["content"]
        if inside_content and tag == "a" and attrs_map.get("href"):
            anchor_index = len(self.references)
            self.references.append({"url": attrs_map["href"], "text_parts": []})
        if inside_content and tag == "img":
            src = attrs_map.get("data-src") or attrs_map.get("src")
            if src:
                self.images.append(src)
        heading_index: int | None = None
        if inside_content and tag in {"h1", "h2", "h3", "h4", "h5", "h6"}:
            heading_index = len(self.headings)
            self.headings.append({"level": int(tag[1]), "text_parts": []})
        if inside_content and tag == "p":
            self.paragraph_count += 1
        if inside_content and tag in BLOCK_TAGS:
            self.content_parts.append("\n")

        self.stack.append(
            {
                "tag": tag,
                "id": element_id,
                "classes": classes,
                "inside_content": inside_content,
                "anchor_index": anchor_index,
                "heading_index": heading_index,
            }
        )

    def handle_startendtag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        self.handle_starttag(tag, attrs)
        self.handle_endtag(tag)

    def handle_endtag(self, tag: str) -> None:
        if self.stack and self.stack[-1]["inside_content"] and tag.lower() in BLOCK_TAGS:
            self.content_parts.append("\n")
        if self.stack:
            self.stack.pop()

    def handle_data(self, data: str) -> None:
        if not self.stack:
            return
        current = self.stack[-1]
        if current["tag"] == "script":
            self.script_parts.append(data)
            return
        if current["tag"] in {"style", "noscript"}:
            return
        if current["tag"] == "title":
            self.title_parts.append(data)
        if current["tag"] == "h1" and current["inside_content"]:
            self.content_heading_parts.append(data)
        for entry in self.stack:
            if entry["id"] in self.captured:
                self.captured[entry["id"]].append(data)
            if "weui-msg__title" in entry["classes"] or "mesg-block" in entry["classes"]:
                self.error_parts.append(data)
            if entry["anchor_index"] is not None:
                self.references[entry["anchor_index"]]["text_parts"].append(data)
            if entry["heading_index"] is not None:
                self.headings[entry["heading_index"]]["text_parts"].append(data)
        if current["inside_content"]:
            self.content_parts.append(data)


def normalize_url(candidate: str, source_url: str) -> str:
    candidate = html.unescape(candidate or "").strip()
    if not candidate or candidate.startswith(("javascript:", "data:", "mailto:")):
        return ""
    absolute = urllib.parse.urljoin(source_url or "", candidate)
    try:
        parsed = urllib.parse.urlsplit(absolute)
    except ValueError:
        return ""
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        return ""
    query = urllib.parse.parse_qs(parsed.query)
    if "url" in query and any(token in parsed.path.lower() for token in ("redirect", "wapredirect", "checkurl")):
        nested = urllib.parse.unquote(query["url"][0])
        return normalize_url(nested, source_url)
    return urllib.parse.urlunsplit((parsed.scheme, parsed.netloc, parsed.path, parsed.query, ""))


def validate_public_url(url: str) -> None:
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme not in {"http", "https"} or not parsed.hostname:
        raise ValueError("Only public HTTP(S) URLs are supported.")
    if parsed.username or parsed.password:
        raise ValueError("URLs with embedded credentials are not supported.")
    try:
        literal_ip = ipaddress.ip_address(parsed.hostname)
    except ValueError:
        literal_ip = None
    if literal_ip is not None and not literal_ip.is_global:
        raise ValueError(f"Private or non-global network destination is blocked: {literal_ip}")
    addresses = socket.getaddrinfo(parsed.hostname, parsed.port or (443 if parsed.scheme == "https" else 80))
    for address in addresses:
        ip = ipaddress.ip_address(address[4][0])
        synthetic_domain_egress = literal_ip is None and ip.version == 4 and ip in SYNTHETIC_EGRESS
        if not ip.is_global and not synthetic_domain_egress:
            raise ValueError(f"Private or non-global network destination is blocked: {ip}")


class SafeRedirectHandler(urllib.request.HTTPRedirectHandler):
    max_redirections = 5

    def __init__(self) -> None:
        super().__init__()
        self.redirect_count = 0

    def redirect_request(self, req: Any, fp: Any, code: int, msg: str, headers: Any, newurl: str) -> Any:
        validate_public_url(newurl)
        self.redirect_count += 1
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def fetch_url(url: str, timeout: int, retries: int, max_bytes: int) -> tuple[bytes, dict[str, Any]]:
    validate_public_url(url)
    retry_codes = {429, 500, 502, 503, 504}
    last_error: Exception | None = None
    proxy_schemes = sorted(
        key
        for key, value in urllib.request.getproxies().items()
        if value and key.lower() in {"http", "https", "all"}
    )
    for attempt in range(retries + 1):
        redirect_handler = SafeRedirectHandler()
        opener = urllib.request.build_opener(redirect_handler)
        request = urllib.request.Request(
            url,
            headers={
                "User-Agent": BROWSER_COMPATIBLE_USER_AGENT,
                "Accept": "text/html,application/xhtml+xml,application/json,application/xml,text/plain,*/*;q=0.5",
                "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
            },
        )
        try:
            with opener.open(request, timeout=timeout) as response:
                final_url = response.geturl()
                validate_public_url(final_url)
                payload = response.read(max_bytes + 1)
                if len(payload) > max_bytes:
                    raise ValueError(f"Response exceeds max size of {max_bytes} bytes.")
                declared_charset = response.headers.get_content_charset() or ""
                return payload, {
                    "requested_url": url,
                    "final_url": final_url,
                    "status_code": response.status,
                    "content_type": response.headers.get_content_type(),
                    "content_type_header": response.headers.get("Content-Type", ""),
                    "reported_content_length": response.headers.get("Content-Length"),
                    "declared_charset": normalize_charset(declared_charset),
                    "charset": "",
                    "bytes": len(payload),
                    "redirect_count": redirect_handler.redirect_count,
                    "engine": "python-urllib",
                    "request_profile": "browser-compatible-public",
                    "user_agent": BROWSER_COMPATIBLE_USER_AGENT,
                    "environment_proxy_present": bool(proxy_schemes),
                    "environment_proxy_schemes": proxy_schemes,
                    "decode_warnings": [],
                }
        except urllib.error.HTTPError as exc:
            last_error = exc
            if exc.code not in retry_codes or attempt >= retries:
                raise
        except (urllib.error.URLError, TimeoutError, OSError) as exc:
            last_error = exc
            if attempt >= retries:
                raise
        time.sleep((1, 3)[min(attempt, 1)])
    raise RuntimeError(f"Network acquisition failed: {last_error}")


def parse_fragment(value: str) -> tuple[str, list[dict[str, Any]], list[str]]:
    parser = FragmentParser()
    parser.feed(value)
    return clean_text("".join(parser.text_parts)), parser.references, parser.images


def classify_error(raw_html: str, parser: ArticleParser) -> tuple[str, str]:
    error_text = clean_text(" ".join(parser.error_parts))
    haystack = f"{error_text}\n{raw_html}".lower()
    for reason, phrases in ERROR_PHRASES.items():
        if any(phrase.lower() in haystack for phrase in phrases):
            return reason, error_text or reason
    if "weui-msg" in parser.classes or "mesg-block" in parser.classes:
        return "unavailable", error_text or "recognized error page"
    return "", ""


def route_for_resource(kind: str) -> dict[str, str]:
    routes = {
        "json": (
            "structured-data",
            "json-parser",
            "Parse as structured JSON and apply the user's requested extraction, comparison, or analysis.",
        ),
        "feed": (
            "feed-analysis",
            "xml-feed-parser",
            "Parse feed entries and metadata with an XML-aware feed workflow.",
        ),
        "xml": (
            "structured-data",
            "xml-parser",
            "Parse the XML tree and namespaces before extracting requested fields.",
        ),
        "csv": (
            "tabular-data",
            "table-parser",
            "Use a table-aware parser for rows, columns, types, and comparisons.",
        ),
        "text": (
            "text-analysis",
            "text-parser",
            "Analyze the decoded text according to the user's task rather than applying article assumptions.",
        ),
        "pdf": (
            "document-analysis",
            "pdf",
            "Use the PDF workflow for text extraction, rendering, page structure, or form inspection.",
        ),
        "image": (
            "visual-inspection",
            "image-inspection",
            "Use visual inspection or image tooling based on whether the user wants reading, analysis, or editing.",
        ),
        "audio": (
            "media-inspection",
            "audio-inspection",
            "Use an audio-capable workflow for playback, transcription, or analysis.",
        ),
        "video": (
            "media-inspection",
            "video-inspection",
            "Use a video-capable workflow for playback, frame inspection, transcription, or analysis.",
        ),
        "archive": (
            "archive-inspection",
            "archive-tool",
            "Inspect archive contents safely before choosing format-specific downstream tools.",
        ),
        "binary": (
            "binary-resource",
            "download-or-format-tool",
            "Preserve the acquired bytes and identify the format before attempting interpretation.",
        ),
    }
    route_id, handler, reason = routes.get(kind, routes["binary"])
    return {"route": route_id, "handler": handler, "reason": reason}


def resolve_non_html(
    payload: bytes,
    decoded_text: str,
    include_content: bool,
    resource: dict[str, Any],
) -> dict[str, Any]:
    kind = resource["kind"]
    warnings: list[str] = []
    structured: dict[str, Any] = {}
    parse_valid = True

    if kind == "json":
        try:
            value = json.loads(decoded_text)
            structured["top_level_type"] = (
                "object"
                if isinstance(value, dict)
                else "array"
                if isinstance(value, list)
                else "null"
                if value is None
                else "boolean"
                if isinstance(value, bool)
                else "number"
                if isinstance(value, (int, float))
                else "string"
            )
            if isinstance(value, dict):
                structured["top_level_keys"] = list(value.keys())[:100]
                structured["top_level_key_count"] = len(value)
            elif isinstance(value, list):
                structured["item_count"] = len(value)
        except json.JSONDecodeError as exc:
            parse_valid = False
            structured["parse_error"] = str(exc)
            warnings.append("The response was classified as JSON but did not parse as valid JSON.")
    elif kind in {"xml", "feed"}:
        try:
            root = ET.fromstring(decoded_text)
            root_name = root.tag.rsplit("}", 1)[-1]
            structured["root_element"] = root_name
            structured["element_count"] = sum(1 for _ in root.iter())
            if root_name.lower() in {"rss", "feed"}:
                resource["kind"] = "feed"
                kind = "feed"
        except ET.ParseError as exc:
            parse_valid = False
            structured["parse_error"] = str(exc)
            warnings.append("The response was classified as XML but did not parse as valid XML.")
    elif kind == "csv":
        rows = [line for line in decoded_text.splitlines() if line.strip()]
        structured["row_count_estimate"] = len(rows)
        if rows:
            structured["header_preview"] = rows[0][:500]

    text_chars = len(decoded_text) if resource["textual"] else 0
    text_hash = hashlib.sha256(decoded_text.encode("utf-8")).hexdigest() if decoded_text else ""
    grade = "A-full-resource" if parse_valid else "B-partial-resource"
    document = {
        "text_chars": text_chars,
        "text_sha256": text_hash,
        "line_count": len(decoded_text.splitlines()) if decoded_text else 0,
        "preview": decoded_text[:2000] if decoded_text else "",
        "content_included": bool(include_content and decoded_text),
        "structured": structured,
    }
    if include_content and decoded_text:
        document["text"] = decoded_text

    return {
        "evidence": {
            "grade": grade,
            "page_type": kind,
            "body_complete": parse_valid,
            "markers": [],
            "block_kind": "",
            "block_reason": "",
            "render_state": "static-resource",
            "coverage": {
                "content_chars": text_chars,
                "line_count": document["line_count"],
                "parse_valid": parse_valid,
            },
        },
        "resource": resource,
        "document": document,
        "routing": route_for_resource(kind),
        "references": [],
        "images": [],
        "warnings": warnings,
    }


def resolve_html(raw_html: str, source_url: str, include_content: bool, mode: str = "article") -> dict[str, Any]:
    json_ld = extract_json_ld_article(raw_html)
    parser = ArticleParser()
    parser.feed(raw_html)
    if mode == "web" and not parser.content_roots and not json_ld:
        parser = ArticleParser(capture_body=True)
        parser.feed(raw_html)
    scripts = "\n".join(parser.script_parts)
    markers = sorted(parser.ids)
    has_classic = "js_content" in parser.ids
    has_generic = bool(parser.content_roots.difference({"#js_content"}))
    has_cgi = "window.cgiDataNew" in raw_html
    has_qmtpl = "window.__QMTPL_SSR_DATA__" in raw_html
    if has_cgi:
        markers.append("window.cgiDataNew")
    if has_qmtpl:
        markers.append("window.__QMTPL_SSR_DATA__")
    if json_ld:
        markers.append("json-ld:Article")
    markers.extend(parser.content_roots)

    title = clean_text(" ".join(parser.captured["activity-name"]))
    title = title or clean_text(" ".join(parser.captured["js_title_inner"]))
    title = title or clean_text(parser.meta.get("og:title", ""))
    title = title or clean_text(parser.meta.get("twitter:title", ""))
    title = title or clean_text(extract_js_value(scripts, ("title", "msg_title")))
    title = title or json_ld.get("title", "")
    title = title or clean_text(" ".join(parser.content_heading_parts))
    title = title or clean_text(" ".join(parser.title_parts))

    author = clean_text(" ".join(parser.captured["js_author_name"]))
    author = author or clean_text(" ".join(parser.captured["js_name"]))
    author = author or clean_text(" ".join(parser.captured["profileBt"]))
    author = author or clean_text(extract_js_value(scripts, ("nick_name", "nickname", "author")))
    for meta_key in ("author", "article:author", "parsely-author", "dc.creator", "byl"):
        author = author or clean_text(parser.meta.get(meta_key, ""))
    author = author or json_ld.get("author", "")

    published_at = clean_text(" ".join(parser.captured["publish_time"]))
    published_at = published_at or clean_text(
        extract_js_value(scripts, ("createTime", "create_time", "ori_send_time", "ct"))
    )
    for meta_key in ("article:published_time", "date", "datepublished", "parsely-pub-date"):
        published_at = published_at or clean_text(parser.meta.get(meta_key, ""))
    published_at = published_at or json_ld.get("published_at", "")
    published_at_iso = timestamp_to_iso(published_at)

    content = clean_text("".join(parser.content_parts))
    references = list(parser.references)
    images = list(parser.images)
    if not content and (has_cgi or has_qmtpl):
        structured_content = extract_js_value(scripts, ("content_noencode", "desc"))
        if structured_content:
            content, fragment_refs, fragment_images = parse_fragment(structured_content)
            references.extend(fragment_refs)
            images.extend(fragment_images)
    if not content and json_ld.get("body"):
        structured_content = json_ld["body"]
        if "<" in structured_content and ">" in structured_content:
            content, fragment_refs, fragment_images = parse_fragment(structured_content)
            references.extend(fragment_refs)
            images.extend(fragment_images)
        else:
            content = clean_text(structured_content)

    error_kind, error_reason = classify_error(raw_html, parser)
    content_chars = len(content)
    quality = text_quality(content)
    body_fallback = "tag:body" in parser.content_roots
    client_shell_marker = bool(
        re.search(
            r'(?:id|class)=["\'][^"\']*(?:\bapp\b|\broot\b|__next|hydration|loading)[^"\']*["\']',
            raw_html,
            flags=re.IGNORECASE,
        )
    )
    client_shell = mode == "web" and body_fallback and content_chars < MIN_FULL_CONTENT_CHARS and client_shell_marker
    normalized_headings = []
    for item in parser.headings:
        heading_text = clean_text(" ".join(item.get("text_parts", [])))
        if heading_text:
            normalized_headings.append({"level": item["level"], "text": heading_text})
    title_key = normalized_match_key(title)
    title_heading_match = any(
        len(heading_key := normalized_match_key(item["text"])) >= 4
        and (heading_key in title_key or title_key in heading_key)
        for item in normalized_headings
    )
    strong_article_signal = bool(
        has_classic
        or has_cgi
        or has_qmtpl
        or json_ld
        or "tag:article" in parser.content_roots
        or "itemprop:articleBody" in parser.content_roots
    )
    documentation_markers = {
        "class:main-page-content",
        "class:markdown-body",
        "class:mw-parser-output",
        "document:rfc",
        "id:pep-content",
    }
    documentation_like = bool(parser.content_roots.intersection(documentation_markers))
    article_like = strong_article_signal or bool(
        published_at and parser.paragraph_count >= 2 and not documentation_like
    )

    if error_kind and not (title and content_chars >= MIN_FULL_CONTENT_CHARS):
        grade = "D-blocked"
        page_type = "error"
        complete = False
    elif (
        title
        and content_chars >= MIN_FULL_CONTENT_CHARS
        and (has_classic or has_cgi or has_qmtpl or has_generic or bool(json_ld))
        and not quality["mojibake_suspected"]
    ):
        grade = "A-full-page"
        page_type = (
            "classic"
            if has_classic
            else "ssr"
            if (has_cgi or has_qmtpl)
            else "web"
            if mode == "web" and body_fallback
            else "generic"
        )
        complete = True
    elif title or content_chars:
        grade = "B-partial-page"
        page_type = (
            "classic"
            if has_classic
            else "ssr"
            if (has_cgi or has_qmtpl)
            else "web"
            if mode == "web" and body_fallback
            else "generic"
            if has_generic
            else "unknown"
        )
        complete = False
    else:
        grade = "E-unknown"
        page_type = "unknown"
        complete = False

    normalized_references = []
    seen_refs: set[str] = set()
    for item in references:
        url = normalize_url(item.get("url", ""), source_url)
        if not url or url == source_url or url in seen_refs:
            continue
        seen_refs.add(url)
        label = clean_text(" ".join(item.get("text_parts", [])))
        normalized_references.append({"url": url, "label": label})

    normalized_images = []
    seen_images: set[str] = set()
    for item in images:
        url = normalize_url(item, source_url)
        if not url or url in seen_images:
            continue
        seen_images.add(url)
        normalized_images.append({"url": url})

    article = {
        "title": title,
        "author": author,
        "published_at": published_at,
        "published_at_iso": published_at_iso,
        "content_chars": content_chars,
        "content_sha256": hashlib.sha256(content.encode("utf-8")).hexdigest() if content else "",
        "headings": normalized_headings[:200],
    }
    if include_content:
        article["content"] = content

    canonical_url = normalize_url(parser.canonical_url, source_url)
    description = clean_text(parser.meta.get("description", ""))
    description = description or clean_text(parser.meta.get("og:description", ""))
    page = {
        "title": title,
        "description": description,
        "canonical_url": canonical_url,
        "language": parser.document_language,
        "category": "documentation" if documentation_like else "article" if article_like else "web",
        "text_chars": content_chars,
        "text_sha256": article["content_sha256"],
        "headings": normalized_headings[:200],
        "link_count": len(normalized_references),
        "image_count": len(normalized_images),
    }
    if include_content and mode == "web":
        page["text"] = content

    warnings = []
    if grade != "A-full-page":
        warnings.append(
            "Do not treat this result as a complete rendered web page."
            if mode == "web"
            else "Do not treat this result as a complete article body."
        )
    if grade == "D-blocked":
        warnings.append("Use a user-exported HTML or PDF instead of changing identities or access paths.")
    if quality["mojibake_suspected"]:
        warnings.append("Decoded text may contain replacement characters or mojibake.")
    if client_shell:
        warnings.append("The static response looks like a client-rendered shell; use the browser route for rendered content.")

    render_state = (
        "blocked"
        if grade == "D-blocked"
        else "client-shell"
        if client_shell
        else "static-html"
        if grade == "A-full-page"
        else "partial-html"
    )
    if grade == "D-blocked":
        routing = {
            "route": "blocked",
            "handler": "user-provided-artifact",
            "reason": "Report the access blocker and request a user-owned saved HTML or PDF when appropriate.",
        }
    elif client_shell:
        routing = {
            "route": "browser-render",
            "handler": "browser",
            "reason": "The static response is a client shell; use rendered DOM or interaction evidence.",
        }
    elif documentation_like:
        routing = {
            "route": "documentation-analysis",
            "handler": "web-source-resolver",
            "reason": "Use the extracted document structure and headings without imposing article assumptions.",
        }
    elif article_like:
        routing = {
            "route": "article-analysis",
            "handler": "article-source-resolver",
            "reason": "Article signals are present, so use article-specific completeness, metadata, and citation checks.",
        }
    else:
        routing = {
            "route": "web-page-analysis",
            "handler": "web-source-resolver",
            "reason": "Use the visible page record and choose extraction, comparison, inspection, or browser work from the user's intent.",
        }

    return {
        "evidence": {
            "grade": grade,
            "page_type": page_type,
            "body_complete": complete,
            "markers": sorted(set(markers)),
            "block_kind": error_kind,
            "block_reason": error_reason,
            "render_state": render_state,
            "coverage": {
                "content_chars": content_chars,
                "paragraph_count": parser.paragraph_count,
                "heading_count": len(normalized_headings),
                "headings_truncated_in_article": len(normalized_headings) > 200,
                "first_heading": normalized_headings[0]["text"] if normalized_headings else "",
                "last_heading": normalized_headings[-1]["text"] if normalized_headings else "",
                "title_heading_match": title_heading_match,
                "content_roots": sorted(parser.content_roots),
                **quality,
            },
        },
        "resource": {
            "kind": "html",
            "resolution_mode": mode,
        },
        "page": page,
        "article": article,
        "routing": routing,
        "references": normalized_references,
        "images": normalized_images,
        "warnings": warnings,
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--url")
    source.add_argument("--input-file")
    parser.add_argument("--source-url", default="")
    parser.add_argument("--allow-network", action="store_true")
    parser.add_argument("--include-content", action="store_true")
    parser.add_argument("--mode", choices=("article", "web"), default="article")
    parser.add_argument("--content-type-hint", default="")
    parser.add_argument("--save-html")
    parser.add_argument("--output")
    parser.add_argument("--timeout", type=int, default=25)
    parser.add_argument("--retries", type=int, choices=range(0, 3), default=1)
    parser.add_argument("--max-bytes", type=int, default=5 * 1024 * 1024)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    acquired_at = dt.datetime.now(dt.timezone.utc).isoformat()

    if args.url:
        if not args.allow_network:
            raise ValueError("URL acquisition requires --allow-network.")
        payload, acquisition = fetch_url(args.url, args.timeout, args.retries, args.max_bytes)
        method = "network"
        source_url = acquisition["final_url"]
        if args.save_html:
            saved_html = Path(args.save_html).expanduser().resolve()
            saved_html.parent.mkdir(parents=True, exist_ok=True)
            saved_html.write_bytes(payload)
            acquisition["saved_response"] = str(saved_html)
            if args.mode == "article":
                acquisition["saved_html"] = str(saved_html)
    else:
        if args.save_html:
            raise ValueError("--save-html is only valid with --url.")
        input_path = Path(args.input_file).resolve()
        payload = input_path.read_bytes()
        if len(payload) > args.max_bytes:
            raise ValueError(f"Input file exceeds max size of {args.max_bytes} bytes.")
        source_url = args.source_url
        method = "file"
        hinted_media_type, hinted_charset = parse_content_type(args.content_type_hint)
        acquisition = {
            "requested_url": args.source_url,
            "final_url": args.source_url,
            "status_code": None,
            "content_type": hinted_media_type,
            "content_type_header": args.content_type_hint,
            "reported_content_length": None,
            "declared_charset": hinted_charset,
            "charset": "",
            "bytes": len(payload),
            "redirect_count": 0,
            "engine": "local-file",
            "request_profile": "saved-file",
            "environment_proxy_present": False,
            "environment_proxy_schemes": [],
            "decode_warnings": [],
            "input_file": str(input_path),
        }

    resource_locator = source_url or (str(input_path) if method == "file" else "")
    resource = sniff_resource(payload, acquisition.get("content_type", ""), resource_locator)
    resource["resolution_mode"] = args.mode
    acquisition["detected_content_type"] = resource["media_type"]
    acquisition["content_type_detection"] = resource["detection_source"]

    decoded_text = ""
    if resource["textual"]:
        decoded_text, charset, decode_warnings = decode_payload(
            payload,
            acquisition.get("declared_charset", ""),
        )
        acquisition["charset"] = charset
        acquisition["decode_warnings"] = decode_warnings

    if args.mode == "article" and resource["kind"] != "html":
        raise ValueError(
            f"Article mode requires HTML, but the resource was classified as {resource['kind']}. "
            "Use web-source-resolver for general URL intake."
        )
    if resource["kind"] == "html":
        resolution = resolve_html(decoded_text, source_url, args.include_content, args.mode)
        resolution["resource"] = {**resource, **resolution["resource"]}
    else:
        resolution = resolve_non_html(payload, decoded_text, args.include_content, resource)
    resolution["warnings"] = [*acquisition.get("decode_warnings", []), *resolution["warnings"]]
    result = {
        "schema": "codex-web-source-v1" if args.mode == "web" else "codex-article-source-v1",
        "acquired_at": acquired_at,
        "acquisition": {
            "method": method,
            **acquisition,
            "sha256": hashlib.sha256(payload).hexdigest(),
        },
        **resolution,
    }
    output = json.dumps(result, ensure_ascii=True, indent=2)
    if args.output:
        output_path = Path(args.output).expanduser().resolve()
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(output + "\n", encoding="utf-8")
    else:
        sys.stdout.write(output + "\n")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        sys.stderr.write(json.dumps({"status": "error", "error": str(exc)}, ensure_ascii=True) + "\n")
        raise SystemExit(2)
