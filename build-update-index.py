#!/usr/bin/env python3
"""Build a plain-text list of package URLs ordered by most recent update.

Reads ``packages.plist`` (OpenStep format) and, for every package, determines a
"last updated" timestamp:

* If the package has an ``archiveURL`` (a Zip), an HTTP HEAD request is made and
  the ``Last-Modified`` response header is used. The emitted URL is the
  ``archiveURL`` itself.
* Otherwise the ``url`` is a GitHub repository. The date of the latest commit on
  the package's ``branch`` (or the default branch) is used. The emitted URL is the
  ``url``.

URLs whose timestamp cannot be resolved are dropped. The remaining URLs are
de-duplicated (keeping the most recent timestamp) and written to
``packages-by-update``, one URL per line, most recently updated first.

Requires the ``openstep-plist`` package. Reads ``GITHUB_TOKEN`` from the
environment for authenticated GitHub API access.
"""

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

PLIST_PATH = "packages.plist"
OUTPUT_PATH = "packages-by-update"
PACKAGE_TYPES = ("plugins", "scripts", "modules")

MAX_WORKERS = 12
REQUEST_TIMEOUT = 30  # seconds
MAX_ATTEMPTS = 3

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
        headers={"User-Agent": "glyphs-packages-index"},
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
        "User-Agent": "glyphs-packages-index",
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
    """Return a list of unique ``(emitted_url, kind, detail)`` lookup tasks.

    ``kind`` is ``"archive"`` (detail is the archive URL) or ``"github"`` (detail
    is ``(owner, repo, branch)``). Duplicate emitted URLs are kept (the same URL
    may resolve via different branches); de-duplication happens after resolution.
    """
    tasks = []
    seen = set()
    packages = data.get("packages", {})
    for package_type in PACKAGE_TYPES:
        for entry in packages.get(package_type, []):
            archive_url = entry.get("archiveURL")
            if archive_url:
                key = ("archive", archive_url)
                if key not in seen:
                    seen.add(key)
                    tasks.append((archive_url, "archive", archive_url))
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
            key = ("github", owner.lower(), repo.lower(), branch)
            if key not in seen:
                seen.add(key)
                tasks.append((url, "github", (owner, repo, branch)))
    return tasks


def resolve(task):
    """Resolve a task to ``(emitted_url, datetime)`` or ``(emitted_url, None)``."""
    emitted_url, kind, detail = task
    try:
        if kind == "archive":
            return emitted_url, archive_timestamp(detail)
        owner, repo, branch = detail
        return emitted_url, github_timestamp(owner, repo, branch)
    except Exception as error:  # noqa: BLE001 - tolerate any per-URL failure
        log("dropping {}: {}".format(emitted_url, error))
        return emitted_url, None


def main():
    with open(PLIST_PATH, "r", encoding="utf-8") as f:
        data = openstep_plist.load(f)

    tasks = collect_tasks(data)
    log("resolving {} unique lookups...".format(len(tasks)))

    # De-duplicate by emitted URL, keeping the most recent timestamp.
    latest = {}
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        for emitted_url, dt in executor.map(resolve, tasks):
            if dt is None:
                continue
            current = latest.get(emitted_url)
            if current is None or dt > current:
                latest[emitted_url] = dt

    # Most recent first; break ties on the URL for reproducible output.
    ordered = sorted(latest.items(), key=lambda item: (item[1], item[0]), reverse=True)

    if not ordered:
        # A wholly empty result almost always means a systemic failure (lost
        # auth, network outage). Fail loudly so the previously published asset
        # is left untouched rather than overwritten with nothing.
        log("error: no URLs resolved to a timestamp; refusing to write an empty list")
        sys.exit(1)

    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        for url, _ in ordered:
            f.write(url + "\n")

    log("wrote {} URLs to {}".format(len(ordered), OUTPUT_PATH))


if __name__ == "__main__":
    main()
