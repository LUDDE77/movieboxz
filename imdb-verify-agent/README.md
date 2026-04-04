# MovieBoxZ IMDB Verification Agent

Standalone CLI tool that uses Playwright to verify and fix IMDB IDs for all production movies.

## Setup

```bash
cd imdb-verify-agent
npm install
npx playwright install chromium
cp .env.example .env
# Edit .env — set BACKEND_URL and ADMIN_API_KEY
```

## Usage

```bash
# Full run: auto-fix confident matches + open browser review for uncertain ones
node verify.js

# Test with 20 movies first
node verify.js --limit 20

# Auto-fix only (no browser review server)
node verify.js --auto-only

# Open browser review for already-queued items (after a previous run)
node verify.js --review-only

# Resume an interrupted run
node verify.js --resume

# Skip movies already manually verified
node verify.js --skip-verified
```

## How it works

1. **Fetch** — loads all production movies from the backend API
2. **Search** — Playwright searches IMDB for each movie
3. **Score** — confidence scoring (0–100) compares title, year, director, actors, type
4. **Route by confidence:**
   - ≥ 85% → auto-fix (calls `enrich-manual-imdb` API)
   - 50–84% → queued for manual review
   - < 50% → skipped
5. **Review** — opens `http://localhost:7788` with side-by-side comparison UI

## Review page

- **C** = Confirm match (stored ID is correct)
- **U** = Use candidate (apply the IMDB search result)
- **S** = Skip
- **O** = Open IMDB in browser
- **1/2/3** = Switch between candidates

Progress is saved to `queue.json` after every decision. Use `--resume` to continue later.
