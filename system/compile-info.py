#!/usr/bin/env python3
"""Build a JSON summary of the package index.

Reads ``packages.plist`` (OpenStep format) and produces ``packages-info.json``
with two top-level keys:

* ``updateOrder`` — a list of package URLs, most recently updated first. For each
  package a "last updated" timestamp is determined:

  * If the package has an ``archiveURL`` (a Zip), an HTTP HEAD request is made and
    the ``Last-Modified`` response header is used. The emitted URL is the
    ``archiveURL`` itself.
  * Otherwise the ``url`` is a GitHub repository. The date of the latest commit on
    the package's ``branch`` (or the default branch) is used. The emitted URL is
    the ``url``.

  URLs whose timestamp cannot be resolved are dropped. The remaining URLs are
  de-duplicated (keeping the most recent timestamp) and sorted.

* ``screenshots`` — a map from each package's ``screenshot`` image URL to its
  pixel dimensions, ``{"width": W, "height": H}``. Screenshots whose dimensions
  cannot be read are dropped.

Requires the ``openstep-plist`` and ``Pillow`` packages. Reads ``GITHUB_TOKEN``
from the environment for authenticated GitHub API access.
"""

import io
import os
import sys
import time
import json
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime

import openstep_plist
from PIL import Image

PLIST_PATH = "packages.plist"
OUTPUT_PATH = "packages-info.json"
PACKAGE_TYPES = ("plugins", "scripts", "modules")

MAX_WORKERS = 12
REQUEST_TIMEOUT = 30  # seconds
MAX_ATTEMPTS = 3
USER_AGENT = "glyphs-packages-index"

GITHUB_TOKEN = os.environ.get("GITHUB_TOKEN")


def log(message):
    print(message, file=sys.stderr)


def request_with_retries(req):
    """Open *req*, retrying on transient failures. Returns the response body bytes
    and the response object, or raises the last error."""
    last_error = None
    for attempt in range(1, MAX_ATTEMPTS + 1):
        try:
            with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT) as response:
                return response.read(), response
        except (urllib.error.URLError, TimeoutError) as error:
            last_error = error
            # Do not retry a definitive 404.
            if isinstance(error, urllib.error.HTTPError) and error.code == 404:
                break
            if attempt < MAX_ATTEMPTS:
                time.sleep(2 ** (attempt - 1))
    raise last_error


def archive_timestamp(archive_url):
    """Return the ``Last-Modified`` time of *archive_url* as an aware datetime."""
    req = urllib.request.Request(
        archive_url,
        method="HEAD",
        headers={"User-Agent": USER_AGENT},
    )
    _, response = request_with_retries(req)
    last_modified = response.headers.get("Last-Modified")
    if not last_modified:
        raise ValueError("missing Last-Modified header")
    dt = parsedate_to_datetime(last_modified)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt


def github_timestamp(owner, repo, branch):
    """Return the latest commit date for *owner/repo* on *branch* (or default)."""
    query = {"per_page": "1"}
    if branch:
        query["sha"] = branch
    url = "https://api.github.com/repos/{}/{}/commits?{}".format(
        owner, repo, urllib.parse.urlencode(query)
    )
    headers = {
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": USER_AGENT,
    }
    if GITHUB_TOKEN:
        headers["Authorization"] = "Bearer " + GITHUB_TOKEN
    req = urllib.request.Request(url, headers=headers)
    body, _ = request_with_retries(req)
    commits = json.loads(body)
    if not commits:
        raise ValueError("no commits returned")
    date_str = commits[0]["commit"]["committer"]["date"]
    return datetime.fromisoformat(date_str.replace("Z", "+00:00"))


def screenshot_dimensions(screenshot_url):
    """Return ``{"width": W, "height": H}`` for the image at *screenshot_url*."""
    req = urllib.request.Request(
        screenshot_url,
        headers={"User-Agent": USER_AGENT},
    )
    body, _ = request_with_retries(req)
    with Image.open(io.BytesIO(body)) as img:
        width, height = img.size
    return {"width": width, "height": height}


def parse_github_owner_repo(url):
    """Return ``(owner, repo)`` for a github.com URL, or ``None``."""
    parsed = urllib.parse.urlparse(url)
    if parsed.netloc.lower() not in ("github.com", "www.github.com"):
        return None
    parts = [p for p in parsed.path.split("/") if p]
    if len(parts) < 2:
        return None
    owner, repo = parts[0], parts[1]
    if repo.endswith(".git"):
        repo = repo[:-4]
    return owner, repo


def collect_tasks(data):
    """Return a list of unique ``(kind, key, detail)`` lookup tasks.

    ``kind`` is one of:

    * ``"archive"`` — ``key`` is the archive URL, ``detail`` is the archive URL.
    * ``"github"`` — ``key`` is the package ``url``, ``detail`` is
      ``(owner, repo, branch)``.
    * ``"screenshot"`` — ``key`` is the screenshot image URL, ``detail`` is the
      same URL.

    Each ``(kind, key)`` is emitted at most once. Timestamp results
    (``archive``/``github``) are de-duplicated again by ``key`` after resolution,
    since the same URL may be reached via different branches.
    """
    tasks = []
    seen = set()

    def add(kind, key, detail):
        identity = (kind, key)
        if identity not in seen:
            seen.add(identity)
            tasks.append((kind, key, detail))

    packages = data.get("packages", {})
    for package_type in PACKAGE_TYPES:
        for entry in packages.get(package_type, []):
            # Screenshot dimensions — independent of the timestamp source.
            screenshot = entry.get("screenshot")
            if screenshot:
                add("screenshot", screenshot, screenshot)

            # Timestamp source: archive URL takes precedence over the repo URL.
            archive_url = entry.get("archiveURL")
            if archive_url:
                add("archive", archive_url, archive_url)
                continue
            url = entry.get("url")
            if not url:
                continue
            owner_repo = parse_github_owner_repo(url)
            if not owner_repo:
                log("skipping non-GitHub, non-archive url: {}".format(url))
                continue
            owner, repo = owner_repo
            branch = entry.get("branch")
            # Reach the same URL via different branches only once.
            dedup_key = ("github", owner.lower(), repo.lower(), branch)
            if dedup_key in seen:
                continue
            seen.add(dedup_key)
            add("github", url, (owner, repo, branch))
    return tasks


def resolve(task):
    """Resolve a task to ``(kind, key, value)`` or ``(kind, key, None)``."""
    kind, key, detail = task
    try:
        if kind == "archive":
            return kind, key, archive_timestamp(detail)
        if kind == "github":
            owner, repo, branch = detail
            return kind, key, github_timestamp(owner, repo, branch)
        if kind == "screenshot":
            return kind, key, screenshot_dimensions(detail)
        raise ValueError("unknown task kind: {}".format(kind))
    except Exception as error:  # noqa: BLE001 - tolerate any per-URL failure
        log("dropping {}: {}".format(key, error))
        return kind, key, None


def main():
    with open(PLIST_PATH, "r", encoding="utf-8") as f:
        data = openstep_plist.load(f)

    tasks = collect_tasks(data)
    log("resolving {} unique lookups...".format(len(tasks)))

    latest = {}  # emitted URL -> most recent datetime
    screenshots = {}  # screenshot URL -> {"width", "height"}
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        for kind, key, value in executor.map(resolve, tasks):
            if value is None:
                continue
            if kind == "screenshot":
                screenshots[key] = value
            else:
                current = latest.get(key)
                if current is None or value > current:
                    latest[key] = value

    # Most recent first; break ties on the URL for reproducible output.
    ordered = sorted(latest.items(), key=lambda item: (item[1], item[0]), reverse=True)

    if not ordered:
        # A wholly empty update order almost always means a systemic failure (lost
        # auth, network outage). Fail loudly so the previously published asset is
        # left untouched rather than overwritten with nothing.
        log("error: no URLs resolved to a timestamp; refusing to write an empty list")
        sys.exit(1)

    output = {
        "updateOrder": [url for url, _ in ordered],
        # Sorted by URL so the file is byte-stable across runs.
        "screenshots": dict(sorted(screenshots.items())),
    }

    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        json.dump(output, f, ensure_ascii=False, indent=2)
        f.write("\n")

    log(
        "wrote {} URLs and {} screenshot sizes to {}".format(
            len(ordered), len(screenshots), OUTPUT_PATH
        )
    )


if __name__ == "__main__":
    main()
