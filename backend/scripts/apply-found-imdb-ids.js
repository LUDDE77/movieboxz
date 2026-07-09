#!/usr/bin/env node
/**
 * apply-found-imdb-ids.js
 *
 * Applies manually-found IMDB IDs to production movies that had none,
 * then calls enrich-manual-imdb to fill in poster/description/rating/cast.
 */

import axios from 'axios'

const BACKEND_URL = 'https://movieboxz-backend-production.up.railway.app'
const ADMIN_KEY = process.env.ADMIN_API_KEY
const headers = { 'x-admin-api-key': ADMIN_KEY, 'Content-Type': 'application/json' }

async function sleep(ms) { return new Promise(r => setTimeout(r, ms)) }

// Manually found IMDB IDs for production movies that had none
const IMDB_MAPPINGS = [
    { titleSearch: "'c' man",        imdb_id: 'tt0041218', note: "'C' Man (1950)" },
    { titleSearch: "danger ahead",   imdb_id: 'tt0032379', note: "Danger Ahead (1940)" },
    { titleSearch: "detour",         imdb_id: 'tt0037638', note: "Detour (1946)" },
    { titleSearch: "ghost crazy",    imdb_id: 'tt0036728', note: "Ghost Crazy / Crazy Knights (1944)" },
    { titleSearch: "gung ho",        imdb_id: 'tt0035958', note: "Gung Ho! (1943)" },
    { titleSearch: "lethal justice", imdb_id: 'tt0331281', note: "Lethal Justice" },
    { titleSearch: "misty",          imdb_id: 'tt0055186', note: "Misty (1961)" },
    { titleSearch: "the card",       imdb_id: 'tt0045056', note: "The Card (1952)" },
    { titleSearch: "the korean",     imdb_id: 'tt1261889', note: "The Korean (2008)" },
    { titleSearch: "the psyborgs",   imdb_id: 'tt7816868', note: "The PsyBorgs (2019)" },
    { titleSearch: "three of a kind",imdb_id: 'tt4998708', note: "Three of a Kind (1941)" },
    { titleSearch: "the crusader",   imdb_id: 'tt0022794', note: "The Crusader (1932)" },
    { titleSearch: "convict 99",     imdb_id: 'tt0031178', note: "Convict 99 (1938)" },
    { titleSearch: "crusoe",         imdb_id: 'tt1117552', note: "Crusoe (TV series)" },
    { titleSearch: "deadly lessons", imdb_id: 'tt0758763', note: "Deadly Lessons / The Legend of Simon Conjurer (2014)" },
]

// Production movies with manually-found IMDB IDs (from Supabase query)
const MOVIES_TO_ENRICH = [
    { id: '55af70ad-26dc-456f-a4ae-b52fa81afe32', title: "'C' Man",              imdb_id: 'tt0041218' },
    { id: '7fa21c08-9c86-42b2-bf61-bd381f3bbbe3', title: 'CRUSOE Part 10',       imdb_id: 'tt1117552' },
    { id: 'd9d5725c-70b4-4934-8856-1d68d5e0ca76', title: 'Danger Ahead',         imdb_id: 'tt0032379' },
    { id: '98ad51ac-682e-4ffa-a22f-b5356c828769', title: 'Deadly Lessons',       imdb_id: 'tt0758763' },
    { id: '694a5fbe-12e3-407c-9635-347abe834759', title: 'Detour',               imdb_id: 'tt0037638' },
    { id: 'b3c59b31-5098-4a31-8501-47dab18d1b0d', title: 'Ghost Crazy (1)',      imdb_id: 'tt0036728' },
    { id: '7bb00f9d-55f3-4f06-8219-3b4a61c9e917', title: 'Ghost Crazy (2)',      imdb_id: 'tt0036728' },
    { id: '2ecc1d65-d4ea-48ca-9d39-9399f13fb9b5', title: 'Gung Ho! (1)',         imdb_id: 'tt0035958' },
    { id: 'ed726c28-c381-4825-8ba3-cc0b32bc46ba', title: 'Gung Ho! (2)',         imdb_id: 'tt0035958' },
    { id: '35af3176-8587-40d7-b1af-8fe6a43dd215', title: 'LETHAL JUSTICE',       imdb_id: 'tt0331281' },
    { id: '166d830f-772d-4aec-900c-53f031e9e900', title: 'Misty',                imdb_id: 'tt0055186' },
    { id: '27fd6959-cfcd-4640-8126-04b7ae497c68', title: 'The Card',             imdb_id: 'tt0045056' },
    { id: '315fc286-16ee-4787-822d-8ba93d09a794', title: 'The Crusader (1)',     imdb_id: 'tt0022794' },
    { id: '75b3452c-4b30-461b-ad0c-e3bae1970794', title: 'The Crusader (2)',     imdb_id: 'tt0022794' },
    { id: '81bc0fbb-68a6-46b6-ba8c-c97453230bba', title: 'The Korean',           imdb_id: 'tt1261889' },
    { id: 'b4173241-e29a-42bb-ade0-e58a8ecb687e', title: 'The PsyBorgs',        imdb_id: 'tt7816868' },
    { id: '9b4e9ad9-d8b1-4c1b-8c63-ac76964bb4f9', title: 'Three of a kind (1)', imdb_id: 'tt4998708' },
    { id: '4f66b41b-a0eb-4900-8ef3-952e04078e00', title: 'Three of a kind (2)', imdb_id: 'tt4998708' },
    { id: '6604ba8c-dfe6-4d3f-80ea-7e9416043d04', title: 'Will Hays Convict 99', imdb_id: 'tt0031178' },
]

async function enrichMovie(movieId, imdbId) {
    try {
        await axios.post(
            `${BACKEND_URL}/api/admin/movies/${movieId}/enrich-manual-imdb`,
            { imdbId, verifiedBy: 'apply-found-imdb-ids' },
            { headers }
        )
        return 'ok'
    } catch (err) {
        const status = err.response?.status
        if (status === 404 || status === 500) return `omdb-miss(${status})`
        throw err
    }
}

async function main() {
    console.log('🎬 Enriching production movies with found IMDB IDs\n')

    for (const movie of MOVIES_TO_ENRICH) {
        const result = await enrichMovie(movie.id, movie.imdb_id)
        if (result === 'ok') {
            console.log(`✅ ${movie.title} (${movie.imdb_id})`)
        } else {
            console.log(`⚠️  ${movie.title} (${movie.imdb_id}) → ${result}`)
        }
        await sleep(400)
    }

    console.log('\nDone.')
}

main().catch(console.error)
