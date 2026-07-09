#!/usr/bin/env node
/**
 * Cleanup Artflix - Movie Classics duplicate staged movies.
 * - Keeps one copy per title (published > approved > pending, oldest first)
 * - Rejects all extras
 * - Publishes all approved movies
 */

import axios from 'axios'

const BACKEND_URL = 'https://movieboxz-backend-production.up.railway.app'
const ADMIN_KEY = process.env.ADMIN_API_KEY
const headers = { 'x-admin-api-key': ADMIN_KEY, 'Content-Type': 'application/json' }

async function sleep(ms) { return new Promise(r => setTimeout(r, ms)) }

async function getAllStagedMovies() {
  let all = []
  let page = 1
  const limit = 100
  while (true) {
    const res = await axios.get(`${BACKEND_URL}/api/admin/staging/movies`, {
      params: { channel: 'Artflix - Movie Classics', limit, page },
      headers
    })
    const movies = res.data.data?.movies || res.data.movies || []
    all = all.concat(movies)
    if (movies.length < limit) break
    page++
  }
  return all
}

async function rejectMovie(id, reason) {
  await axios.post(`${BACKEND_URL}/api/admin/staging/movies/${id}/reject`, { reason }, { headers })
}

async function publishMovies(ids) {
  const res = await axios.post(`${BACKEND_URL}/api/admin/staging/publish`, { ids }, { headers })
  return res.data
}

const STATUS_PRIORITY = { published: 0, approved: 1, enriched: 2, pending: 3, rejected: 99 }

async function main() {
  console.log('Fetching all Artflix staged movies...')
  const movies = await getAllStagedMovies()
  console.log(`  Found ${movies.length} total staged movies\n`)

  // Group by title (case-insensitive)
  const groups = {}
  for (const m of movies) {
    const key = m.title?.toLowerCase().trim() || m.id
    if (!groups[key]) groups[key] = []
    groups[key].push(m)
  }

  const toReject = []
  const toPublish = []

  for (const [, group] of Object.entries(groups)) {
    if (group.length === 1) {
      // Single copy - just publish if approved
      if (group[0].approval_status === 'approved') toPublish.push(group[0].id)
      continue
    }

    // Sort: best status first, then oldest first
    group.sort((a, b) => {
      const sp = (STATUS_PRIORITY[a.approval_status] ?? 99) - (STATUS_PRIORITY[b.approval_status] ?? 99)
      if (sp !== 0) return sp
      return new Date(a.created_at) - new Date(b.created_at)
    })

    const [keeper, ...extras] = group

    // Skip if already rejected
    if (keeper.approval_status === 'rejected') continue

    console.log(`📽  "${keeper.title}" — keeping ${keeper.approval_status} (${keeper.youtube_video_id}), rejecting ${extras.length} extra(s)`)

    for (const extra of extras) {
      if (extra.approval_status !== 'rejected' && extra.approval_status !== 'published') {
        toReject.push(extra.id)
      }
    }

    if (keeper.approval_status === 'approved') toPublish.push(keeper.id)
  }

  console.log(`\n🗑  Rejecting ${toReject.length} duplicates...`)
  let rejected = 0
  for (const id of toReject) {
    try {
      await rejectMovie(id, 'Duplicate upload')
      rejected++
      if (rejected % 10 === 0) console.log(`  ${rejected}/${toReject.length}...`)
    } catch (err) {
      console.log(`  ⚠️  Failed to reject ${id}: ${err.message}`)
    }
    await sleep(200)
  }
  console.log(`  ✅ Rejected ${rejected} duplicates`)

  if (toPublish.length > 0) {
    console.log(`\n🚀 Publishing ${toPublish.length} approved movies...`)
    try {
      // Publish in batches of 50
      for (let i = 0; i < toPublish.length; i += 50) {
        const batch = toPublish.slice(i, i + 50)
        const result = await publishMovies(batch)
        const published = result.data?.published || result.published || batch.length
        console.log(`  ✅ Batch ${Math.floor(i/50)+1}: published ${published} movies`)
        await sleep(1000)
      }
    } catch (err) {
      console.log(`  ⚠️  Publish error: ${err.response?.data?.error || err.message}`)
    }
  }

  console.log('\nDone!')
}

main().catch(console.error)
