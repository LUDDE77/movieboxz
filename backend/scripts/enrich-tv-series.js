#!/usr/bin/env node
/**
 * Enrich TV series and mini-series movies with IMDB metadata.
 */

import axios from 'axios'

const BACKEND_URL = 'https://movieboxz-backend-production.up.railway.app'
const ADMIN_KEY = process.env.ADMIN_API_KEY
const headers = { 'x-admin-api-key': ADMIN_KEY, 'Content-Type': 'application/json' }

async function sleep(ms) { return new Promise(r => setTimeout(r, ms)) }

const MOVIES = [
  // The Corner episodes — missing poster (same series IMDB ID)
  { id: '55efb88f-1ec4-4247-8fbc-45f5e0517595', title: 'The Corner — Episode 1', imdb_id: 'tt0224853' },
  { id: '502568a8-9447-4ec7-892b-6aa456a8e976', title: 'The Corner — Episode 2', imdb_id: 'tt0224853' },
  { id: '40eb35ed-f94a-4418-a1b4-49e8ec22a6b2', title: 'The Corner — Episode 4', imdb_id: 'tt0224853' },
  { id: '1a5113de-67fa-45d7-8fa5-34928a423489', title: 'The Corner — Episode 5', imdb_id: 'tt0224853' },
  { id: '6c6bc7ef-ea8d-46f4-b367-8393b785524d', title: 'The Corner — Episode 6', imdb_id: 'tt0224853' },
  // Crusoe parts — missing imdb_id and poster
  { id: '7f1d71cb-5eb3-49a5-bd4e-40adcb9a6be2', title: 'Crusoe — Part 5',  imdb_id: 'tt1117552' },
  { id: 'de2b5a81-9b11-4585-8243-317595e0a854', title: 'Crusoe — Part 6',  imdb_id: 'tt1117552' },
  { id: '38e4c626-ab48-48e6-a870-fa9e8d966bb2', title: 'Crusoe — Part 8',  imdb_id: 'tt1117552' },
  { id: '23d66853-f253-498a-bd7d-376b22e5e96f', title: 'Crusoe — Part 9',  imdb_id: 'tt1117552' },
  { id: 'ddd9af1c-f98e-4e16-9494-4d701efe7e5e', title: 'Crusoe — Part 13', imdb_id: 'tt1117552' },
  // Separate But Equal — missing poster (2 of 3)
  { id: '61ff1b77-5363-4dba-91e1-da02109484d8', title: 'Separate But Equal (1)', imdb_id: 'tt0102879' },
  { id: '2290a386-fbd2-468e-8291-8ae4ad62fb64', title: 'Separate But Equal (2)', imdb_id: 'tt0102879' },
  // Queen — missing poster (1 of 2)
  { id: 'a3913f46-4265-43f6-8e55-a88b1986e025', title: 'Queen (2)', imdb_id: 'tt0105937' },
  // Go Down, Moses — missing poster and bad runtime
  { id: 'e532fd79-4c2d-4c81-a9bf-0db9868a9556', title: 'Go Down, Moses', imdb_id: 'tt0592443' },
  // Ice — Part 1 — missing imdb_id and poster
  { id: '6a80790c-4502-4656-a870-234bf14c10c0', title: 'Ice — Part 1', imdb_id: 'tt1510984' },
]

async function enrichMovie(movie) {
  try {
    const res = await axios.post(
      `${BACKEND_URL}/api/admin/movies/${movie.id}/enrich-manual-imdb`,
      { imdbId: movie.imdb_id },
      { headers }
    )
    const data = res.data
    const poster = data.movie?.poster_path ? 'has poster' : 'no poster'
    const runtime = data.movie?.runtime_minutes
    console.log(`✓ ${movie.title} → ${poster}, ${runtime}min`)
  } catch (err) {
    const msg = err.response?.data?.error || err.message
    console.log(`✗ ${movie.title} → ${msg}`)
  }
}

async function main() {
  console.log(`Enriching ${MOVIES.length} TV/mini-series movies...\n`)
  for (const movie of MOVIES) {
    await enrichMovie(movie)
    await sleep(800)
  }
  console.log('\nDone.')
}

main()
