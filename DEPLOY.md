# MovieBoxZ Deployment Guide

**Purpose:** Complete deployment workflow using MCP tools for GitHub, Railway, and Supabase.

---

## 🚨 CRITICAL: Repository Information

- **GitHub Owner:** `LUDDE77` (NOT `mrahl`)
- **Repository:** `movieboxz`
- **Full Path:** `LUDDE77/movieboxz`
- **Main Branch:** `main`

**⚠️ ALWAYS use `LUDDE77` as the owner in GitHub MCP calls.**

---

## 📋 Pre-Deployment Checklist

Before deploying, verify:

1. ✅ All code changes are tested locally
2. ✅ Database migrations are sequentially numbered
3. ✅ Environment variables are documented
4. ✅ API endpoints are tested with curl/Postman
5. ✅ Version number incremented in `iOS/MovieBoxZ/AppVersion.swift` (for iOS changes)

---

## 🔧 Available MCP Tools

### GitHub MCP (`mcp__github__*`)
- `mcp__github__get_me` - Get authenticated user info
- `mcp__github__push_files` - Push multiple files in one commit
- `mcp__github__create_or_update_file` - Push single file
- `mcp__github__get_file_contents` - Read file from GitHub
- `mcp__github__list_commits` - View commit history
- `mcp__github__create_pull_request` - Create PR (optional)

### Railway MCP (`mcp__railway__*`)
- `mcp__railway__project_list` - List all projects
- `mcp__railway__service_list` - List services in project
- `mcp__railway__service_info` - Get service details
- `mcp__railway__deployment_list` - List recent deployments
- `mcp__railway__deployment_status` - Check deployment status
- `mcp__railway__deployment_logs` - View deployment logs
- `mcp__railway__deployment_trigger` - Trigger new deployment (usually auto)
- `mcp__railway__variable_set` - Set environment variable
- `mcp__railway__variable_list` - List environment variables
- `mcp__railway__service_restart` - Restart service

### Supabase MCP (`mcp__supabase__*`)
- `mcp__supabase__list_projects` - List Supabase projects
- `mcp__supabase__get_project` - Get project details
- `mcp__supabase__list_tables` - List database tables
- `mcp__supabase__execute_sql` - Run SQL queries
- `mcp__supabase__apply_migration` - Apply migration file
- `mcp__supabase__get_logs` - View service logs
- `mcp__supabase__get_advisors` - Check security/performance advisories

---

## 🚀 Complete Deployment Workflow

### Step 1: Prepare Files

**Check git status:**
```bash
git status
```

**Stage changes:**
```bash
git add <files>
```

**Commit locally (optional but recommended):**
```bash
git commit -m "Your commit message"
```

---

### Step 2: Push to GitHub Using MCP

**⚠️ DO NOT use `git push` via Bash - it will fail due to authentication issues.**

#### Option A: Push Multiple Files (Recommended)

Use `mcp__github__push_files` for pushing multiple files in one commit:

```typescript
mcp__github__push_files({
  owner: "LUDDE77",
  repo: "movieboxz",
  branch: "main",
  message: "Descriptive commit message with details",
  files: [
    {
      path: "backend/src/routes/browse.js",
      content: "<file contents>"
    },
    {
      path: "backend/src/config/database.js",
      content: "<file contents>"
    },
    {
      path: "backend/src/middleware/auth.js",
      content: "<file contents>"
    }
  ]
})
```

**Steps:**
1. Read each file using `Read` tool
2. Collect file contents
3. Call `mcp__github__push_files` with all files
4. Verify response includes commit SHA

#### Option B: Push Single File

Use `mcp__github__create_or_update_file` for single file updates:

```typescript
mcp__github__create_or_update_file({
  owner: "LUDDE77",
  repo: "movieboxz",
  path: "backend/src/routes/movies.js",
  content: "<file contents>",
  message: "Update movies.js with YouTube TOS compliance",
  branch: "main",
  sha: "<sha if updating existing file>"
})
```

**Get SHA before updating:**
```bash
git ls-tree HEAD backend/src/routes/movies.js
```

---

### Step 3: Verify GitHub Push

**Check latest commits:**
```typescript
mcp__github__list_commits({
  owner: "LUDDE77",
  repo: "movieboxz",
  perPage: 5
})
```

**Verify file contents:**
```typescript
mcp__github__get_file_contents({
  owner: "LUDDE77",
  repo: "movieboxz",
  path: "backend/src/routes/browse.js"
})
```

---

### Step 4: Monitor Railway Deployment

**Railway auto-deploys from GitHub pushes. Monitor the deployment:**

#### 4.1: List Projects
```typescript
mcp__railway__project_list()
```

Find project ID (usually has "movieboxz" in name).

#### 4.2: List Services
```typescript
mcp__railway__service_list({
  projectId: "<project-id>"
})
```

Find backend service ID and environment ID.

#### 4.3: Check Recent Deployments
```typescript
mcp__railway__deployment_list({
  projectId: "<project-id>",
  serviceId: "<service-id>",
  environmentId: "<environment-id>",
  limit: 5
})
```

#### 4.4: Check Deployment Status
```typescript
mcp__railway__deployment_status({
  deploymentId: "<deployment-id>"
})
```

**Status values:**
- `BUILDING` - Deployment in progress
- `DEPLOYING` - Deployment starting
- `SUCCESS` - Deployment succeeded ✅
- `FAILED` - Deployment failed ❌
- `CRASHED` - Service crashed after deployment ❌

#### 4.5: View Deployment Logs (if failed)
```typescript
mcp__railway__deployment_logs({
  deploymentId: "<deployment-id>",
  limit: 100
})
```

---

### Step 5: Apply Database Migrations (if needed)

**⚠️ Only needed if you created new migration files.**

#### 5.1: List Supabase Projects
```typescript
mcp__supabase__list_projects()
```

Find project ID (usually `oltlikatlvbwavfxqazn` for production).

#### 5.2: Check Current Migrations
```typescript
mcp__supabase__execute_sql({
  project_id: "oltlikatlvbwavfxqazn",
  query: "SELECT * FROM supabase_migrations.schema_migrations ORDER BY version DESC LIMIT 5;"
})
```

#### 5.3: Apply Migration

**Option A: Via Supabase MCP (Recommended)**
```typescript
mcp__supabase__apply_migration({
  project_id: "oltlikatlvbwavfxqazn",
  name: "006_add_new_feature",
  query: `
    -- Migration SQL here
    ALTER TABLE movies ADD COLUMN new_field TEXT;
  `
})
```

**Option B: Via Direct SQL**
```typescript
mcp__supabase__execute_sql({
  project_id: "oltlikatlvbwavfxqazn",
  query: `
    -- Your SQL here
  `
})
```

#### 5.4: Verify Migration
```typescript
mcp__supabase__list_tables({
  project_id: "oltlikatlvbwavfxqazn",
  schemas: ["public"]
})
```

---

### Step 6: Test Production Endpoints

**Test with curl:**

```bash
# Health check
curl https://movieboxz-backend-production.up.railway.app/api/health

# Test new endpoints
curl https://movieboxz-backend-production.up.railway.app/api/browse/genres

# Test with filters
curl "https://movieboxz-backend-production.up.railway.app/api/movies?genre=28&limit=5"

# Verify data integrity
curl "https://movieboxz-backend-production.up.railway.app/api/movies?limit=3" | jq '.data.movies[] | {title, youtube_video_title}'
```

---

### Step 7: Restart Service (if needed)

**If deployment succeeded but service isn't responding:**

```typescript
mcp__railway__service_restart({
  serviceId: "<service-id>",
  environmentId: "<environment-id>"
})
```

---

## 🔍 Common Deployment Scenarios

### Scenario 1: Backend Code Changes Only

1. Read modified files using `Read` tool
2. Push to GitHub using `mcp__github__push_files`
3. Wait 2-3 minutes for Railway auto-deploy
4. Check `mcp__railway__deployment_list` for status
5. Test production endpoints with curl
6. ✅ Done

**No database migration needed.**

---

### Scenario 2: Database Schema Changes

1. Create migration file: `backend/supabase/migrations/00X_description.sql`
2. Test migration locally (optional)
3. Push migration file to GitHub using `mcp__github__push_files`
4. Apply migration using `mcp__supabase__apply_migration`
5. Verify schema using `mcp__supabase__list_tables`
6. Wait for Railway auto-deploy
7. Test production endpoints
8. ✅ Done

**Migration → GitHub → Railway (automatic).**

---

### Scenario 3: New API Endpoints

1. Create/modify route files
2. Update `server.js` to register routes
3. Add database operations to `database.js` (if needed)
4. Push all files to GitHub using `mcp__github__push_files`
5. Wait for Railway auto-deploy
6. Test new endpoints with curl
7. ✅ Done

**No migration needed unless schema changes.**

---

### Scenario 4: Environment Variable Changes

1. List current variables:
   ```typescript
   mcp__railway__variable_list({
     projectId: "<project-id>",
     environmentId: "<environment-id>",
     serviceId: "<service-id>"
   })
   ```

2. Set new variable:
   ```typescript
   mcp__railway__variable_set({
     projectId: "<project-id>",
     environmentId: "<environment-id>",
     serviceId: "<service-id>",
     name: "NEW_API_KEY",
     value: "secret-value"
   })
   ```

3. Restart service (required for env vars):
   ```typescript
   mcp__railway__service_restart({
     serviceId: "<service-id>",
     environmentId: "<environment-id>"
   })
   ```

4. ✅ Done

**Railway auto-redeploys when env vars change.**

---

### Scenario 5: iOS App Changes

1. Update `iOS/MovieBoxZ/AppVersion.swift` - increment build number
2. Make iOS code changes
3. Test in Xcode simulator
4. Build for device:
   ```bash
   cd iOS
   xcodebuild -scheme MovieBoxZ -destination 'generic/platform=tvOS' build
   ```
5. Push changes to GitHub (for backup):
   ```typescript
   mcp__github__push_files({
     owner: "LUDDE77",
     repo: "movieboxz",
     branch: "main",
     message: "iOS: Increment build to 23 - Fix layout issue",
     files: [/* iOS files */]
   })
   ```
6. ✅ Done

**iOS deployment is manual via Xcode → Device/TestFlight.**

---

## 🚨 Troubleshooting

### Problem: GitHub Push Fails with 404

**Cause:** Using wrong owner (mrahl instead of LUDDE77)

**Fix:**
```typescript
// ❌ WRONG
mcp__github__push_files({ owner: "mrahl", repo: "movieboxz", ... })

// ✅ CORRECT
mcp__github__push_files({ owner: "LUDDE77", repo: "movieboxz", ... })
```

**Verify owner:**
```typescript
mcp__github__get_me()
// This returns your user, but repo owner is LUDDE77
```

---

### Problem: Railway Deployment Stuck in BUILDING

**Cause:** Build error or long dependency install

**Check logs:**
```typescript
mcp__railway__deployment_logs({
  deploymentId: "<deployment-id>",
  limit: 100
})
```

**Common causes:**
- Missing `package.json` dependencies
- Syntax error in JavaScript
- Missing environment variables
- Out of memory during build

---

### Problem: Railway Deployment CRASHED

**Cause:** Runtime error after successful build

**Check service logs:**
```typescript
mcp__railway__deployment_logs({
  deploymentId: "<deployment-id>",
  limit: 50
})
```

**Common causes:**
- Missing environment variable (SUPABASE_URL, etc)
- Database connection failed
- Port binding issue
- Uncaught exception in code

---

### Problem: Migration Already Applied

**Error:** `duplicate key value violates unique constraint`

**Fix:** Check if migration already exists:
```typescript
mcp__supabase__execute_sql({
  project_id: "oltlikatlvbwavfxqazn",
  query: "SELECT version FROM supabase_migrations.schema_migrations ORDER BY version;"
})
```

**Skip if version exists, or use `IF NOT EXISTS` in migration SQL.**

---

### Problem: Empty youtube_video_title Field

**Cause:** Migration backfill failed or default value "" overrode data

**Fix:**
```typescript
mcp__supabase__execute_sql({
  project_id: "oltlikatlvbwavfxqazn",
  query: `
    UPDATE movies
    SET youtube_video_title = COALESCE(original_title, title)
    WHERE youtube_video_title = '' OR youtube_video_title IS NULL;
  `
})
```

**Verify:**
```bash
curl "https://movieboxz-backend-production.up.railway.app/api/movies?limit=3" | jq '.data.movies[] | {title, youtube_video_title}'
```

---

## 📚 Reference: Railway Project IDs

**Quick lookup (use `mcp__railway__project_list` to verify):**

- **Project Name:** movieboxz-backend-production
- **Project ID:** Use `project_list` to find current ID
- **Service Name:** movieboxz-backend
- **Environment:** production

---

## 📚 Reference: Supabase Project IDs

**Quick lookup:**

- **Project Name:** movieboxz-production
- **Project ID:** `oltlikatlvbwavfxqazn`
- **Region:** eu-west-1
- **Database:** PostgreSQL 17.6.1

---

## ✅ Deployment Success Checklist

After deployment, verify:

- [ ] GitHub shows latest commit
- [ ] Railway deployment status = SUCCESS
- [ ] Health endpoint responds: `curl https://movieboxz-backend-production.up.railway.app/api/health`
- [ ] New endpoints return data (not 404)
- [ ] Database migrations applied successfully
- [ ] No errors in Railway logs
- [ ] Production data integrity verified
- [ ] iOS app shows new build number (if iOS changes)

---

## 📝 Example: Complete Deployment Session

```typescript
// 1. Read files to deploy
const browseJs = await Read("backend/src/routes/browse.js")
const databaseJs = await Read("backend/src/config/database.js")
const authJs = await Read("backend/src/middleware/auth.js")

// 2. Push to GitHub
await mcp__github__push_files({
  owner: "LUDDE77",
  repo: "movieboxz",
  branch: "main",
  message: "Add genre browsing API and user authentication\n\nImplemented:\n- Genre browsing endpoints\n- JWT authentication middleware\n- Database operations for genres",
  files: [
    { path: "backend/src/routes/browse.js", content: browseJs },
    { path: "backend/src/config/database.js", content: databaseJs },
    { path: "backend/src/middleware/auth.js", content: authJs }
  ]
})

// 3. List Railway projects
const projects = await mcp__railway__project_list()
const projectId = projects[0].id

// 4. List services
const services = await mcp__railway__service_list({ projectId })
const service = services.find(s => s.name.includes("backend"))

// 5. Check deployment
const deployments = await mcp__railway__deployment_list({
  projectId,
  serviceId: service.id,
  environmentId: service.environments[0].id,
  limit: 1
})

// 6. Monitor status
const status = await mcp__railway__deployment_status({
  deploymentId: deployments[0].id
})

// 7. Test production
await Bash(`curl "https://movieboxz-backend-production.up.railway.app/api/browse/genres"`)

// ✅ Deployment complete
```

---

## 🎯 Key Takeaways

1. **Always use `LUDDE77` as GitHub owner**
2. **Use GitHub MCP tools, not `git push` via Bash**
3. **Railway auto-deploys from GitHub commits**
4. **Apply Supabase migrations separately using MCP**
5. **Test production endpoints after every deployment**
6. **Check Railway logs if deployment fails**
7. **Increment iOS build number for every iOS change**

---

**Last Updated:** 2026-01-24
**Author:** Claude Code
**Project:** MovieBoxZ
