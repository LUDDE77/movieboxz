#!/usr/bin/env node

/**
 * Apply Database Migrations
 *
 * This script applies SQL migrations from the database/migrations directory
 * to the Supabase production database.
 *
 * Usage:
 *   node scripts/apply-migrations.js [migration-number]
 *
 * Examples:
 *   node scripts/apply-migrations.js              # Apply all pending migrations
 *   node scripts/apply-migrations.js 002          # Apply specific migration
 */

import { createClient } from '@supabase/supabase-js'
import { readFileSync, readdirSync } from 'fs'
import { join, dirname } from 'path'
import { fileURLToPath } from 'url'
import dotenv from 'dotenv'

// Load environment variables
dotenv.config()

const __filename = fileURLToPath(import.meta.url)
const __dirname = dirname(__filename)

// Supabase connection
const supabaseUrl = process.env.SUPABASE_URL
const supabaseServiceKey = process.env.SUPABASE_SERVICE_KEY

if (!supabaseUrl || !supabaseServiceKey) {
    console.error('❌ Missing SUPABASE_URL or SUPABASE_SERVICE_KEY environment variables')
    process.exit(1)
}

const supabase = createClient(supabaseUrl, supabaseServiceKey)

// Get migrations directory
const migrationsDir = join(__dirname, '../database/migrations')

/**
 * Get list of migration files
 */
function getMigrationFiles() {
    try {
        const files = readdirSync(migrationsDir)
            .filter(file => file.endsWith('.sql'))
            .sort()

        return files
    } catch (error) {
        console.error(`❌ Failed to read migrations directory: ${error.message}`)
        process.exit(1)
    }
}

/**
 * Read migration file
 */
function readMigration(filename) {
    const filepath = join(migrationsDir, filename)
    try {
        return readFileSync(filepath, 'utf8')
    } catch (error) {
        console.error(`❌ Failed to read migration ${filename}: ${error.message}`)
        process.exit(1)
    }
}

/**
 * Apply migration to database
 * NOTE: This uses direct SQL execution via postgrest
 */
async function applyMigration(filename, sql) {
    console.log(`\n📄 Applying migration: ${filename}`)
    console.log(`📝 SQL Preview (first 200 chars):\n   ${sql.substring(0, 200)}...`)

    try {
        // Remove BEGIN/COMMIT as Supabase handles transactions
        const cleanSql = sql
            .replace(/^\s*BEGIN\s*;/im, '')
            .replace(/\s*COMMIT\s*;?\s*$/im, '')
            .trim()

        // Split into individual statements (simple split on semicolons)
        const statements = cleanSql
            .split(';')
            .map(s => s.trim())
            .filter(s => s && !s.startsWith('--'))

        console.log(`   Executing ${statements.length} statement(s)...`)

        // Execute each statement
        for (let i = 0; i < statements.length; i++) {
            const stmt = statements[i]
            if (!stmt) continue

            // Use Supabase's from().select() to execute raw SQL via RPC
            const { error } = await supabase.from('_migrations').select('*').limit(0)

            // For now, we'll use the rest API endpoint directly
            const response = await fetch(`${supabaseUrl}/rest/v1/rpc/exec`, {
                method: 'POST',
                headers: {
                    'apikey': supabaseServiceKey,
                    'Authorization': `Bearer ${supabaseServiceKey}`,
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({ query: stmt })
            })

            if (!response.ok) {
                const errorText = await response.text()
                throw new Error(`Statement ${i + 1} failed: ${errorText}`)
            }
        }

        console.log(`✅ Migration ${filename} applied successfully`)
        return true
    } catch (error) {
        console.error(`❌ Failed to apply migration ${filename}:`)
        console.error(error.message)
        console.log(`\n💡 Alternative: Apply manually via Supabase SQL Editor`)
        console.log(`   1. Go to: ${supabaseUrl.replace('supabase.co', 'supabase.com')}/project/_/sql`)
        console.log(`   2. Paste contents of: ${join(migrationsDir, filename)}`)
        console.log(`   3. Click "Run"`)
        return false
    }
}

/**
 * Main function
 */
async function main() {
    const args = process.argv.slice(2)
    const specificMigration = args[0]

    console.log('🚀 MovieBoxZ Migration Tool')
    console.log('=' .repeat(50))

    // Get all migration files
    const migrationFiles = getMigrationFiles()

    if (migrationFiles.length === 0) {
        console.log('ℹ️  No migrations found')
        return
    }

    // Filter migrations if specific one requested
    let migrationsToApply = migrationFiles
    if (specificMigration) {
        migrationsToApply = migrationFiles.filter(f => f.startsWith(specificMigration))

        if (migrationsToApply.length === 0) {
            console.error(`❌ Migration ${specificMigration} not found`)
            process.exit(1)
        }
    }

    console.log(`\nℹ️  Found ${migrationsToApply.length} migration(s) to apply:\n`)
    migrationsToApply.forEach(f => console.log(`   - ${f}`))

    // Apply migrations
    let successCount = 0
    let failCount = 0

    for (const filename of migrationsToApply) {
        const sql = readMigration(filename)
        const success = await applyMigration(filename, sql)

        if (success) {
            successCount++
        } else {
            failCount++
            break // Stop on first failure
        }
    }

    // Summary
    console.log('\n' + '='.repeat(50))
    console.log(`\n📊 Migration Summary:`)
    console.log(`   ✅ Successful: ${successCount}`)
    console.log(`   ❌ Failed: ${failCount}`)

    if (failCount > 0) {
        console.log(`\n⚠️  Migrations stopped due to error`)
        process.exit(1)
    } else {
        console.log(`\n🎉 All migrations applied successfully!`)
    }
}

// Run
main().catch(error => {
    console.error('❌ Unexpected error:', error)
    process.exit(1)
})
