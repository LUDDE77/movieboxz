#!/usr/bin/env node
/**
 * review-cartoon-episodes.js
 *
 * Local review server for cartoon episode matching.
 * Shows staged episodes that are missing episode_number and lets you
 * assign season/episode + approve them, one by one.
 *
 * Usage:
 *   node scripts/review-cartoon-episodes.js
 *   node scripts/review-cartoon-episodes.js --channel "Masters of the Universe: He-Man & She-Ra"
 *
 * Opens http://localhost:7789
 */

import express from 'express'
import axios from 'axios'
import { readFileSync } from 'fs'
import { createServer } from 'http'
import { exec } from 'child_process'

const BACKEND_URL = 'https://movieboxz-backend-production.up.railway.app'
const ADMIN_KEY = process.env.ADMIN_API_KEY
const headers = { 'x-admin-api-key': ADMIN_KEY, 'Content-Type': 'application/json' }
const PORT = 7789

const args = process.argv.slice(2)
const CHANNEL_ARG = args.find((_, i) => args[i - 1] === '--channel') || 'Masters of the Universe: He-Man & She-Ra'

// Load episode guides
const EPISODE_GUIDES = {}
const GUIDE_FILES = {
    'He-Man and the Masters of the Universe': '/tmp/episodes-tt0126158-clean.json',
    'She-Ra: Princess of Power': '/tmp/episodes-tt0126171-clean.json',
    'The New Adventures of He-Man': '/tmp/episodes-tt0100546-clean.json',
}
for (const [name, path] of Object.entries(GUIDE_FILES)) {
    try {
        const data = JSON.parse(readFileSync(path, 'utf8'))
        EPISODE_GUIDES[name] = data.episodes || []
    } catch {
        EPISODE_GUIDES[name] = []
    }
}

// TV series UUIDs
const SERIES_UUID_TO_NAME = {
    '6c783b97-5cd1-4e12-a5b2-742b54fb2784': 'He-Man and the Masters of the Universe',
    '8c0e1b33-cf01-40a3-98eb-628368053070': 'She-Ra: Princess of Power',
    '9d5707ee-5663-4dcd-97c1-f29bde1bbac4': 'The New Adventures of He-Man',
}

async function fetchEpisodesNeedingReview() {
    let all = [], page = 1
    while (true) {
        const res = await axios.get(`${BACKEND_URL}/api/admin/staging/movies`, {
            params: { channel: CHANNEL_ARG, status: 'pending', limit: 100, page },
            headers
        })
        const movies = res.data.data?.movies || res.data.movies || []
        all = all.concat(movies)
        if (movies.length < 100) break
        page++
    }
    // Only keep those with tv_series_id set but no episode_number
    return all.filter(m => m.tv_series_id && !m.episode_number)
}

const HTML = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Episode Review</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0 }
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: #111; color: #eee; min-height: 100vh }
  .layout { display: grid; grid-template-columns: 1fr 360px; gap: 0; height: 100vh }
  .main { padding: 28px 32px; overflow-y: auto; border-right: 1px solid #222 }
  .sidebar { padding: 20px; overflow-y: auto; background: #0d0d0d }

  h1 { font-size: 14px; color: #888; font-weight: 500; margin-bottom: 20px; text-transform: uppercase; letter-spacing: .08em }
  .progress-bar { height: 3px; background: #222; border-radius: 2px; margin-bottom: 28px }
  .progress-fill { height: 100%; background: #e50914; border-radius: 2px; transition: width .3s }

  .card { background: #1a1a1a; border-radius: 12px; padding: 20px; margin-bottom: 16px }
  .series-badge { display: inline-block; background: #222; color: #aaa; font-size: 11px; padding: 3px 10px; border-radius: 20px; margin-bottom: 10px }
  .yt-title { font-size: 20px; font-weight: 600; line-height: 1.3; margin-bottom: 6px }
  .sub { font-size: 13px; color: #666 }

  .thumb { width: 100%; aspect-ratio: 16/9; background: #111; border-radius: 8px; object-fit: cover; margin: 16px 0 }

  .form-row { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; margin-bottom: 12px }
  .form-group { display: flex; flex-direction: column; gap: 6px }
  label { font-size: 11px; color: #888; text-transform: uppercase; letter-spacing: .06em; font-weight: 600 }
  input { background: #252525; border: 1px solid #333; color: #eee; padding: 10px 12px; border-radius: 8px; font-size: 15px; width: 100% }
  input:focus { outline: none; border-color: #e50914 }
  input.full { grid-column: 1/-1 }

  .actions { display: flex; gap: 10px; margin-top: 20px }
  button { padding: 12px 24px; border-radius: 8px; border: none; font-size: 14px; font-weight: 600; cursor: pointer; transition: opacity .15s }
  .btn-save { background: #e50914; color: #fff; flex: 1 }
  .btn-approve { background: #2ea44f; color: #fff; flex: 1 }
  .btn-skip { background: #2a2a2a; color: #aaa }
  button:hover { opacity: .85 }
  button:disabled { opacity: .4; cursor: default }

  .sidebar h2 { font-size: 12px; color: #666; text-transform: uppercase; letter-spacing: .08em; margin-bottom: 12px }
  .search-box { width: 100%; background: #1a1a1a; border: 1px solid #333; color: #eee; padding: 8px 12px; border-radius: 8px; font-size: 13px; margin-bottom: 12px }
  .search-box:focus { outline: none; border-color: #555 }
  .ep-list { list-style: none }
  .ep-item { padding: 8px 10px; border-radius: 6px; cursor: pointer; margin-bottom: 2px; font-size: 13px; display: flex; align-items: baseline; gap: 8px }
  .ep-item:hover { background: #1e1e1e }
  .ep-item.active { background: #1e3a1e }
  .ep-num { font-size: 11px; color: #666; white-space: nowrap; font-variant-numeric: tabular-nums }
  .ep-name { color: #ccc }
  .series-section { margin-bottom: 20px }
  .series-title { font-size: 12px; color: #888; margin-bottom: 8px; padding-bottom: 6px; border-bottom: 1px solid #222 }

  .toast { position: fixed; bottom: 24px; left: 50%; transform: translateX(-50%); background: #2ea44f; color: #fff; padding: 10px 20px; border-radius: 8px; font-size: 14px; font-weight: 600; opacity: 0; transition: opacity .3s; pointer-events: none; z-index: 100 }
  .toast.show { opacity: 1 }
  .toast.error { background: #e50914 }

  .done-screen { display: flex; align-items: center; justify-content: center; height: 100vh; flex-direction: column; gap: 16px }
  .done-screen h1 { font-size: 32px; color: #2ea44f }
</style>
</head>
<body>
<div id="app"></div>
<div class="toast" id="toast"></div>

<script>
const guides = __GUIDES__
let episodes = __EPISODES__
let idx = 0

function seriesName(tvSeriesId) {
  const m = {
    '6c783b97-5cd1-4e12-a5b2-742b54fb2784': 'He-Man and the Masters of the Universe',
    '8c0e1b33-cf01-40a3-98eb-628368053070': 'She-Ra: Princess of Power',
    '9d5707ee-5663-4dcd-97c1-f29bde1bbac4': 'The New Adventures of He-Man',
  }
  return m[tvSeriesId] || 'Unknown Series'
}

function showToast(msg, error=false) {
  const t = document.getElementById('toast')
  t.textContent = msg
  t.className = 'toast show' + (error ? ' error' : '')
  setTimeout(() => t.className = 'toast', 2000)
}

function setEpFields(season, episode, name) {
  document.getElementById('season').value = season || ''
  document.getElementById('episode').value = episode || ''
  document.getElementById('ep_name').value = name || ''
}

function render() {
  const app = document.getElementById('app')
  if (idx >= episodes.length) {
    app.innerHTML = '<div class="done-screen"><h1>✅ All Done!</h1><p style="color:#888">All episodes reviewed. You can close this window.</p></div>'
    return
  }
  const ep = episodes[idx]
  const series = seriesName(ep.tv_series_id)
  const guide = guides[series] || []
  const pct = Math.round((idx / episodes.length) * 100)
  const thumb = ep.youtube_video_id ? \`https://img.youtube.com/vi/\${ep.youtube_video_id}/mqdefault.jpg\` : ''

  // Build episode guide sidebar
  let guideHtml = ''
  const grouped = {}
  for (const e of guide) {
    if (!grouped[series]) grouped[series] = []
    grouped[series].push(e)
  }
  for (const [s, eps] of Object.entries(grouped)) {
    guideHtml += \`<div class="series-section">
      <div class="series-title">\${s}</div>
      <ul class="ep-list" id="eplist">
        \${eps.map(e => \`<li class="ep-item" onclick="pickEp(\${e.season},\${e.episode},\${JSON.stringify(e.title)})">
          <span class="ep-num">S\${e.season}E\${String(e.episode).padStart(2,'0')}</span>
          <span class="ep-name">\${e.title}</span>
        </li>\`).join('')}
      </ul>
    </div>\`
  }

  app.innerHTML = \`
    <div class="layout">
      <div class="main">
        <h1>Episode Review — \${idx+1} of \${episodes.length}</h1>
        <div class="progress-bar"><div class="progress-fill" style="width:\${pct}%"></div></div>

        <div class="card">
          <div class="series-badge">\${series}</div>
          <div class="yt-title">\${ep.youtube_video_title || ep.title}</div>
          <div class="sub">YouTube ID: \${ep.youtube_video_id}</div>
          \${thumb ? \`<img class="thumb" src="\${thumb}" onerror="this.style.display='none'">\` : ''}
        </div>

        <div class="card">
          <div class="form-row">
            <div class="form-group">
              <label>Season #</label>
              <input type="number" id="season" value="\${ep.season_number||''}" min="1">
            </div>
            <div class="form-group">
              <label>Episode #</label>
              <input type="number" id="episode" value="\${ep.episode_number||''}" min="1">
            </div>
          </div>
          <div class="form-group" style="margin-bottom:0">
            <label>Episode Name (optional)</label>
            <input type="text" id="ep_name" value="\${ep.episode_name||''}" placeholder="Leave blank if unknown">
          </div>
          <div class="actions">
            <button class="btn-save" onclick="save(false)">Save</button>
            <button class="btn-approve" onclick="save(true)">Save + Approve</button>
            <button class="btn-skip" onclick="skip()">Skip</button>
          </div>
        </div>
      </div>

      <div class="sidebar">
        <h2>Episode Guide</h2>
        <input class="search-box" id="epSearch" placeholder="Search episodes..." oninput="filterEps(this.value)">
        <div id="guideContainer">\${guideHtml}</div>
      </div>
    </div>
  \`

  // Auto-focus season field
  document.getElementById('season').focus()
}

function pickEp(season, episode, name) {
  setEpFields(season, episode, name)
  // Highlight active
  document.querySelectorAll('.ep-item').forEach(el => el.classList.remove('active'))
  event.currentTarget.classList.add('active')
}

function filterEps(q) {
  const lower = q.toLowerCase()
  document.querySelectorAll('.ep-item').forEach(el => {
    const text = el.textContent.toLowerCase()
    el.style.display = text.includes(lower) ? '' : 'none'
  })
}

async function save(andApprove) {
  const ep = episodes[idx]
  const season = parseInt(document.getElementById('season').value) || null
  const episode = parseInt(document.getElementById('episode').value) || null
  const ep_name = document.getElementById('ep_name').value.trim() || null

  const btn = document.querySelector(andApprove ? '.btn-approve' : '.btn-save')
  btn.disabled = true
  btn.textContent = 'Saving...'

  try {
    const res = await fetch('/save', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id: ep.id, season, episode, ep_name, approve: andApprove })
    })
    const data = await res.json()
    if (!data.success) throw new Error(data.error)
    showToast(andApprove ? '✅ Saved + Approved' : '✅ Saved')
    idx++
    setTimeout(render, 300)
  } catch (e) {
    showToast(e.message, true)
    btn.disabled = false
    btn.textContent = andApprove ? 'Save + Approve' : 'Save'
  }
}

function skip() {
  idx++
  render()
}

// Keyboard shortcuts
document.addEventListener('keydown', e => {
  if (e.target.tagName === 'INPUT') return
  if (e.key === 'Enter') save(false)
  if (e.key === 'a' || e.key === 'A') save(true)
  if (e.key === 's' || e.key === 'S') skip()
})

render()
</script>
</body>
</html>`

async function main() {
    console.log(`🎬 Cartoon Episode Review Server`)
    console.log(`   Channel: ${CHANNEL_ARG}\n`)

    console.log('📥 Fetching episodes needing review...')
    const episodes = await fetchEpisodesNeedingReview()
    console.log(`   Found ${episodes.length} episodes without episode numbers\n`)

    if (!episodes.length) {
        console.log('Nothing to review!')
        process.exit(0)
    }

    const app = express()
    app.use(express.json())

    // Inject data into HTML template
    const buildHtml = () => HTML
        .replace('__GUIDES__', JSON.stringify(EPISODE_GUIDES))
        .replace('__EPISODES__', JSON.stringify(episodes))

    app.get('/', (req, res) => res.send(buildHtml()))

    app.post('/save', async (req, res) => {
        const { id, season, episode, ep_name, approve } = req.body

        try {
            // Patch the episode metadata
            const patchData = {}
            if (season) patchData.season_number = season
            if (episode) patchData.episode_number = episode
            if (ep_name) patchData.episode_name = ep_name

            if (Object.keys(patchData).length) {
                await axios.patch(`${BACKEND_URL}/api/admin/staging/movies/${id}`, patchData, { headers })
            }

            // Approve if requested
            if (approve) {
                await axios.post(`${BACKEND_URL}/api/admin/staging/movies/${id}/approve`, {}, { headers })
            }

            const ep = episodes.find(m => m.id === id)
            const label = ep ? (ep.youtube_video_title || ep.title).slice(0, 50) : id
            console.log(`   ${approve ? '✅ Saved+Approved' : '💾 Saved'}: ${label}${season ? ` S${season}E${episode}` : ''}`)

            res.json({ success: true })
        } catch (err) {
            console.error(`   ❌ Error for ${id}:`, err.response?.data?.error || err.message)
            res.status(500).json({ error: err.response?.data?.error || err.message })
        }
    })

    const server = createServer(app)
    server.listen(PORT, async () => {
        const url = `http://localhost:${PORT}`
        console.log(`🌐 Review server ready at ${url}`)
        console.log(`   Keyboard: Enter=Save  A=Save+Approve  S=Skip\n`)
        exec(`open "${url}"`) // macOS
    })
}

main().catch(console.error)
