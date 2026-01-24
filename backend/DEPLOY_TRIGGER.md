# Deployment Trigger

Last deployment trigger: 2026-01-24 21:59 UTC

## Recent Changes

- Implemented YouTube channel video pagination (fetch up to 500 videos)
- Updated movieCurator.js maxResults from 50 to 500
- Allows complete channel imports (all 449 videos from The Midnight Screening)

## Expected Behavior After Deployment

When importing The Midnight Screening channel:
- Should fetch all 449 videos (9 pages of YouTube API results)
- Should identify ~225 movies (50% of videos pass movie filters)
- Should use ~909 YouTube API quota units (9% of daily limit)
- Should take 3-4 minutes to complete

## Version Info

Git commit: 2b349e4798e9f84bae0a9abcb6b11c51677d8dd5
Branch: main
