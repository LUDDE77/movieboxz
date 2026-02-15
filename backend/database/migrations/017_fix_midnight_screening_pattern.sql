-- Migration 017: Fix The Midnight Screening Pattern - Swap Actor/Genre Groups
-- Description: The YouTube titles have actors BEFORE genre, but pattern had them backwards
-- Date: 2026-02-15
--
-- PROBLEM:
-- YouTube title format: "Reapers FULL MOVIE | Danny Trejo | Action Movies | The Midnight Screening"
-- Current pattern expected: Title | Genre Movies | Actors | Channel
-- Actual format is:  Title | Actors | Genre Movies | Channel
--
-- This caused actors="War Movies" and genre="Nick Stahl" (swapped!)
-- Fix: Swap the parameter mappings for groups 2 and 3 in pattern 1

-- Pattern 1: OLD regex expected "Genre Movies" in position 2, but titles have Actors there
-- Pattern 1: NEW regex expects Actors in position 2, "Genre Movies" in position 3
--
-- Pattern 2: Also swapped - actors come before genre

UPDATE channel_patterns
SET patterns = $$[
    {
        "regex": "^(.+?)\\s*FULL MOVIE\\s*\\|\\s*(.+?)\\s*\\|\\s*(.+?)\\s*Movies?\\s*\\|\\s*The Midnight Screening$",
        "parameters": {
            "title": 1,
            "actors": 2,
            "genre": 3,
            "channel": "The Midnight Screening"
        }
    },
    {
        "regex": "^(.+?)\\s*\\((\\d{4})\\)\\s*\\|\\s*(.+?)\\s*\\|\\s*(.+?)\\s*\\|\\s*The Midnight Screening$",
        "parameters": {
            "title": 1,
            "year": 2,
            "actors": 3,
            "genre": 4,
            "channel": "The Midnight Screening"
        }
    }
]$$::jsonb,
updated_at = NOW()
WHERE channel_id = 'UC6A_LC-A5NVJ2vw9A0OjCug';

-- Verify the update
DO $$
BEGIN
    RAISE NOTICE 'Pattern updated for The Midnight Screening channel';
    RAISE NOTICE 'Pattern 1: Title FULL MOVIE | Actors | Genre Movies | Channel';
    RAISE NOTICE 'Pattern 2: Title (Year) | Actors | Genre | Channel';
END $$;
