#!/usr/bin/env python3
"""
Enrich production movies that have an IMDB ID but are missing
description, imdb_rating, director, or actors.
Uses subprocess/curl to avoid Python SSL certificate issues on macOS.
"""

import json
import time
import subprocess
from datetime import datetime

BACKEND_URL = "https://movieboxz-backend-production.up.railway.app"
ADMIN_API_KEY = os.environ["ADMIN_API_KEY"]


def curl_get(url):
    result = subprocess.run(
        ["curl", "-s", "--max-time", "30", url],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        return 0, {"error": result.stderr}
    try:
        return 200, json.loads(result.stdout)
    except json.JSONDecodeError as e:
        return 0, {"error": f"JSON parse error: {e}", "raw": result.stdout[:200]}


def curl_post(url, data, headers=None):
    cmd = ["curl", "-s", "--max-time", "30", "-X", "POST", url,
           "-H", "Content-Type: application/json",
           "-d", json.dumps(data)]
    if headers:
        for k, v in headers.items():
            cmd += ["-H", f"{k}: {v}"]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        return 0, {"error": result.stderr}
    try:
        parsed = json.loads(result.stdout)
        # Determine HTTP status from response body
        if parsed.get("success"):
            return 200, parsed
        else:
            # Try to infer status from known error patterns
            return 400, parsed
    except json.JSONDecodeError as e:
        return 0, {"error": f"JSON parse error: {e}", "raw": result.stdout[:200]}


def curl_post_with_status(url, data, headers=None):
    """Returns actual HTTP status code using -w flag."""
    cmd = ["curl", "-s", "--max-time", "30", "-X", "POST",
           "-w", "\n__HTTP_STATUS__%{http_code}",
           url,
           "-H", "Content-Type: application/json",
           "-d", json.dumps(data)]
    if headers:
        for k, v in headers.items():
            cmd += ["-H", f"{k}: {v}"]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        return 0, {"error": result.stderr}

    output = result.stdout
    # Split out the HTTP status code appended at the end
    if "__HTTP_STATUS__" in output:
        body_part, status_part = output.rsplit("__HTTP_STATUS__", 1)
        http_status = int(status_part.strip())
    else:
        body_part = output
        http_status = 0

    try:
        parsed = json.loads(body_part.strip())
        return http_status, parsed
    except json.JSONDecodeError as e:
        return http_status, {"error": f"JSON parse error: {e}", "raw": body_part[:200]}


def needs_enrichment(movie):
    """Return True if movie has imdb_id but is missing one of the key fields."""
    if not movie.get("imdb_id"):
        return False
    missing_description = not movie.get("description") or str(movie["description"]).strip() == ""
    missing_rating = movie.get("imdb_rating") is None
    missing_director = not movie.get("director") or str(movie["director"]).strip() == ""
    missing_actors = not movie.get("actors") or str(movie["actors"]).strip() == ""
    return missing_description or missing_rating or missing_director or missing_actors


def get_missing_fields(movie):
    fields = []
    if not movie.get("description") or str(movie["description"]).strip() == "":
        fields.append("description")
    if movie.get("imdb_rating") is None:
        fields.append("imdb_rating")
    if not movie.get("director") or str(movie["director"]).strip() == "":
        fields.append("director")
    if not movie.get("actors") or str(movie["actors"]).strip() == "":
        fields.append("actors")
    return fields


def fetch_all_movies():
    """Fetch all movies from the public API, paginated."""
    all_movies = []
    page = 1
    limit = 200
    total_pages = None

    while True:
        url = f"{BACKEND_URL}/api/movies?limit={limit}&page={page}"
        status, data = curl_get(url)
        if status != 200 or "data" not in data:
            print(f"  Error fetching page {page}: status={status}, {data}")
            break
        movies = data["data"]["movies"]
        all_movies.extend(movies)
        pagination = data["data"]["pagination"]
        total_pages = pagination["pages"]
        print(f"  Page {page}/{total_pages}: {len(movies)} movies (total: {len(all_movies)})")
        if page >= total_pages:
            break
        page += 1
        time.sleep(0.1)

    return all_movies


def enrich_movie(movie_id, imdb_id):
    """Call the enrichment endpoint."""
    url = f"{BACKEND_URL}/api/admin/movies/{movie_id}/enrich-manual-imdb"
    headers = {"x-admin-api-key": ADMIN_API_KEY}
    data = {"imdbId": imdb_id, "verifiedBy": "batch-enrich"}
    return curl_post_with_status(url, data, headers)


def main():
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"=== Enrichment Run - {timestamp} ===\n")

    print("Fetching all production movies...")
    all_movies = fetch_all_movies()
    print(f"Total movies fetched: {len(all_movies)}\n")

    # Filter movies needing enrichment
    to_enrich = [m for m in all_movies if needs_enrichment(m)]
    print(f"Movies needing enrichment: {len(to_enrich)}\n")

    succeeded = []
    failed = []

    for i, movie in enumerate(to_enrich, 1):
        movie_id = movie["id"]
        imdb_id = movie["imdb_id"]
        title = movie.get("title", "Unknown")
        missing_fields = get_missing_fields(movie)

        print(f"[{i}/{len(to_enrich)}] {title} ({imdb_id}) - missing: {', '.join(missing_fields)}", end="", flush=True)

        status, resp = enrich_movie(movie_id, imdb_id)

        if status == 200 and resp.get("success"):
            print(f" -> OK")
            succeeded.append({
                "id": movie_id,
                "title": title,
                "imdb_id": imdb_id,
                "missing_fields": missing_fields,
            })
        else:
            error_msg = resp.get("message") or resp.get("error") or str(resp)
            print(f" -> FAILED (HTTP {status}): {error_msg[:80]}")
            failed.append({
                "id": movie_id,
                "title": title,
                "imdb_id": imdb_id,
                "missing_fields": missing_fields,
                "status": status,
                "error": error_msg,
            })

        # Wait 250ms between calls
        time.sleep(0.25)

    # Write results log
    log_path = "/Users/mrahl/movieboxz/backend/enrichment-log.md"
    with open(log_path, "w") as f:
        f.write(f"# Enrichment Run - {timestamp}\n\n")
        f.write(f"## Summary\n\n")
        f.write(f"- **Total Movies in DB**: {len(all_movies)}\n")
        f.write(f"- **Movies Needing Enrichment**: {len(to_enrich)}\n")
        f.write(f"- **Succeeded**: {len(succeeded)}\n")
        f.write(f"- **Failed**: {len(failed)}\n")
        success_rate = round(len(succeeded) / len(to_enrich) * 100, 1) if to_enrich else 0
        f.write(f"- **Success Rate**: {success_rate}%\n\n")

        f.write(f"## Succeeded ({len(succeeded)} movies)\n\n")
        for m in succeeded:
            f.write(f"- **{m['title']}** (`{m['imdb_id']}`) — was missing: {', '.join(m['missing_fields'])}\n")

        f.write(f"\n## Failed ({len(failed)} movies)\n\n")
        if not failed:
            f.write("None.\n")
        for m in failed:
            f.write(f"- **{m['title']}** (`{m['imdb_id']}`)\n")
            f.write(f"  - Missing fields: {', '.join(m['missing_fields'])}\n")
            f.write(f"  - HTTP status: {m['status']}\n")
            f.write(f"  - Error: {m['error']}\n")

    print(f"\n=== FINAL RESULTS ===")
    print(f"Total movies in DB:        {len(all_movies)}")
    print(f"Needing enrichment:        {len(to_enrich)}")
    print(f"Succeeded:                 {len(succeeded)}")
    print(f"Failed:                    {len(failed)}")
    if to_enrich:
        print(f"Success rate:              {round(len(succeeded)/len(to_enrich)*100, 1)}%")
    if failed:
        print(f"\nFailed movies:")
        for m in failed:
            print(f"  [{m['status']}] {m['title']} ({m['imdb_id']}): {m['error'][:80]}")
    print(f"\nLog written to: {log_path}")


if __name__ == "__main__":
    main()
