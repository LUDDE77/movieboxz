import { describe, it, expect } from 'vitest'
import {
    levenshtein,
    normalizeTitle,
    titleSimilarity,
    detectSeries,
    cleanEpisodeTitle,
    matchEpisode,
    extractEpisodeNumber,
    proposeEpisodeMatch,
    EPISODE_MATCH_THRESHOLD
} from '../src/utils/episodeMatcher.js'

// Realistic fixtures modeled on the kids-cartoon channel this productizes
const HEMAN = {
    tvSeriesId: '6c783b97-5cd1-4e12-a5b2-742b54fb2784',
    title: 'He-Man and the Masters of the Universe',
    episodes: [
        { season: 1, episode: 1, name: 'Diamond Ray of Disappearance', air_date: '1983-09-05' },
        { season: 1, episode: 2, name: 'The Cosmic Comet', air_date: '1983-09-06' },
        { season: 1, episode: 3, name: 'Disappearing Act', air_date: '1983-09-07' },
        { season: 2, episode: 1, name: 'The Cat and the Spider', air_date: '1984-09-03' }
    ]
}
const SHERA = {
    tvSeriesId: '8c0e1b33-cf01-40a3-98eb-628368053070',
    title: 'She-Ra: Princess of Power',
    episodes: [
        { season: 1, episode: 1, name: 'Into Etheria', air_date: '1985-09-09' },
        { season: 1, episode: 2, name: 'Beast Island', air_date: '1985-09-10' }
    ]
}
const HEMAN_NEW = {
    tvSeriesId: '9d5707ee-5663-4dcd-97c1-f29bde1bbac4',
    title: 'The New Adventures of He-Man',
    episodes: [
        { season: 1, episode: 1, name: 'A New Beginning', air_date: '1990-09-10' }
    ]
}
const SERIES = [HEMAN, SHERA, HEMAN_NEW]

describe('normalizeTitle', () => {
    it('lowercases and strips punctuation', () => {
        expect(normalizeTitle('He-Man!')).toBe('heman')
        expect(normalizeTitle('She-Ra: Princess of Power')).toBe('shera princess of power')
    })

    it('collapses whitespace and handles empty input', () => {
        expect(normalizeTitle('  The   Cosmic    Comet ')).toBe('the cosmic comet')
        expect(normalizeTitle(null)).toBe('')
        expect(normalizeTitle('')).toBe('')
    })
})

describe('levenshtein / titleSimilarity', () => {
    it('computes edit distance', () => {
        expect(levenshtein('kitten', 'sitting')).toBe(3)
        expect(levenshtein('abc', 'abc')).toBe(0)
    })

    it('scores identical titles as 1 regardless of punctuation', () => {
        expect(titleSimilarity('Diamond Ray of Disappearance', 'Diamond Ray of Disappearance!')).toBe(1)
    })

    it('scores near-identical titles high and unrelated titles low', () => {
        expect(titleSimilarity('The Diamond Ray of Disappearance', 'Diamond Ray of Disappearance')).toBeGreaterThan(0.8)
        expect(titleSimilarity('Diamond Ray of Disappearance', 'Beast Island')).toBeLessThan(0.3)
    })

    it('returns 0 for empty input', () => {
        expect(titleSimilarity('', 'anything')).toBe(0)
    })
})

describe('detectSeries', () => {
    it('detects a series when its name prefixes the YouTube title', () => {
        const result = detectSeries(
            'He-Man and the Masters of the Universe - Diamond Ray of Disappearance - FULL EPISODE',
            SERIES
        )
        expect(result?.tvSeriesId).toBe(HEMAN.tvSeriesId)
    })

    it('prefers the longest containing series name (New Adventures over original He-Man)', () => {
        const result = detectSeries(
            'The New Adventures of He-Man - A New Beginning - Episode 1',
            SERIES
        )
        expect(result?.tvSeriesId).toBe(HEMAN_NEW.tvSeriesId)
    })

    it('handles punctuation differences in the series name', () => {
        const result = detectSeries(
            'She-Ra Princess of Power | Into Etheria | FULL EPISODE',
            SERIES
        )
        expect(result?.tvSeriesId).toBe(SHERA.tvSeriesId)
    })

    it('returns null when no series matches', () => {
        expect(detectSeries('Best pasta recipe you will ever cook', SERIES)).toBeNull()
        expect(detectSeries('', SERIES)).toBeNull()
    })
})

describe('cleanEpisodeTitle', () => {
    it('strips the series name and filler words', () => {
        const cleaned = cleanEpisodeTitle(
            'He-Man and the Masters of the Universe - Diamond Ray of Disappearance - FULL EPISODE',
            HEMAN.title
        )
        expect(cleaned).toBe('Diamond Ray of Disappearance')
    })

    it('takes only the first pipe segment', () => {
        const cleaned = cleanEpisodeTitle('The Cosmic Comet | He-Man Official | Cartoons for Kids', HEMAN.title)
        expect(cleaned).toBe('The Cosmic Comet')
    })
})

describe('matchEpisode', () => {
    it('matches the classic "Series - Episode - FULL EPISODE" format with high confidence', () => {
        const match = matchEpisode(
            'He-Man and the Masters of the Universe - Diamond Ray of Disappearance - FULL EPISODE',
            HEMAN.episodes,
            HEMAN.title
        )
        expect(match).not.toBeNull()
        expect(match.season).toBe(1)
        expect(match.episode).toBe(1)
        expect(match.name).toBe('Diamond Ray of Disappearance')
        expect(match.confidence).toBeGreaterThanOrEqual(90)
        expect(match.confidence).toBeLessThanOrEqual(100)
    })

    it('matches pipe-separated titles', () => {
        const match = matchEpisode(
            'The Cosmic Comet | He-Man Official | Full Episode HD',
            HEMAN.episodes,
            HEMAN.title
        )
        expect(match?.season).toBe(1)
        expect(match?.episode).toBe(2)
    })

    it('supports guides that use "title" instead of "name"', () => {
        const guide = [{ season: 3, episode: 7, title: 'Beast Island' }]
        const match = matchEpisode('She-Ra - Beast Island - FULL EPISODE', guide, SHERA.title)
        expect(match?.season).toBe(3)
        expect(match?.episode).toBe(7)
        expect(match?.name).toBe('Beast Island')
    })

    it('returns null below the confidence threshold', () => {
        const match = matchEpisode(
            'He-Man Compilation - 3 Hours of Non-Stop Battles Marathon Special',
            HEMAN.episodes,
            HEMAN.title
        )
        expect(match).toBeNull()
        expect(EPISODE_MATCH_THRESHOLD).toBe(0.45)
    })

    it('returns null for empty guides', () => {
        expect(matchEpisode('Anything', [], HEMAN.title)).toBeNull()
        expect(matchEpisode('Anything', null, HEMAN.title)).toBeNull()
    })
})

describe('extractEpisodeNumber', () => {
    it('extracts common episode markers', () => {
        expect(extractEpisodeNumber('He-Man Episode 12 - Something')).toBe(12)
        expect(extractEpisodeNumber('She-Ra Ep. 5')).toBe(5)
        expect(extractEpisodeNumber('He-Man #7 Full Episode')).toBe(7)
        expect(extractEpisodeNumber('Part 3 of 65')).toBe(3)
    })

    it('returns null when no marker exists', () => {
        expect(extractEpisodeNumber('Diamond Ray of Disappearance')).toBeNull()
        expect(extractEpisodeNumber(null)).toBeNull()
    })
})

describe('proposeEpisodeMatch (end-to-end)', () => {
    it('produces a full proposal for a matchable title', () => {
        const result = proposeEpisodeMatch(
            'He-Man and the Masters of the Universe - Diamond Ray of Disappearance - FULL EPISODE',
            SERIES
        )
        expect(result.matched).toBe(true)
        expect(result.tvSeriesId).toBe(HEMAN.tvSeriesId)
        expect(result.season).toBe(1)
        expect(result.episode).toBe(1)
        expect(result.episodeName).toBe('Diamond Ray of Disappearance')
        expect(result.confidence).toBeGreaterThanOrEqual(0)
        expect(result.confidence).toBeLessThanOrEqual(100)
    })

    it('routes She-Ra uploads to the She-Ra guide, not He-Man', () => {
        const result = proposeEpisodeMatch(
            'She-Ra: Princess of Power - Into Etheria - FULL EPISODE',
            SERIES
        )
        expect(result.matched).toBe(true)
        expect(result.tvSeriesId).toBe(SHERA.tvSeriesId)
        expect(result.episodeName).toBe('Into Etheria')
    })

    it('reports no_series_match for unrelated titles', () => {
        const result = proposeEpisodeMatch('Lo-fi beats to study to', SERIES)
        expect(result).toEqual({ matched: false, reason: 'no_series_match' })
    })

    it('reports no_episode_guide when the detected series has no guide', () => {
        const noGuide = [{ ...HEMAN, episodes: [] }]
        const result = proposeEpisodeMatch(
            'He-Man and the Masters of the Universe - Diamond Ray of Disappearance',
            noGuide
        )
        expect(result.matched).toBe(false)
        expect(result.reason).toBe('no_episode_guide')
        expect(result.tvSeriesId).toBe(HEMAN.tvSeriesId)
    })

    it('reports no_episode_match when the title matches no episode', () => {
        const result = proposeEpisodeMatch(
            'He-Man and the Masters of the Universe - 3 Hour Mega Marathon Compilation Special',
            SERIES
        )
        expect(result.matched).toBe(false)
        expect(result.reason).toBe('no_episode_match')
        expect(result.tvSeriesId).toBe(HEMAN.tvSeriesId)
    })
})
