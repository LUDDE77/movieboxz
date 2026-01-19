#!/usr/bin/env node

import { createClient } from '@supabase/supabase-js'
import dotenv from 'dotenv'
import { logger } from '../src/utils/logger.js'

// Load environment variables
dotenv.config()

const supabaseUrl = process.env.SUPABASE_URL
const supabaseServiceKey = process.env.SUPABASE_SERVICE_KEY

if (!supabaseUrl || !supabaseServiceKey) {
    console.error('Missing Supabase credentials in environment variables')
    process.exit(1)
}

// Initialize Supabase client
const supabase = createClient(supabaseUrl, supabaseServiceKey, {
    auth: {
        autoRefreshToken: false,
        persistSession: false
    }
})

// Sample channels data
const sampleChannels = [
    {
        id: 'UCCGqTWHalrn3g4rNgAa_8-A',
        title: 'Classic Horror Films',
        description: 'A curated collection of classic horror films in the public domain',
        thumbnail_url: 'https://yt3.ggpht.com/example1',
        subscriber_count: 125000,
        video_count: 450,
        view_count: 25000000,
        is_verified: true,
        is_curated: true,
        country: 'US',
        language: 'en'
    },
    {
        id: 'UCRetroFilms',
        title: 'Retro Films Collection',
        description: 'B-movies and cult classics from the golden age of cinema',
        thumbnail_url: 'https://yt3.ggpht.com/example2',
        subscriber_count: 87000,
        video_count: 320,
        view_count: 18000000,
        is_verified: false,
        is_curated: true,
        country: 'US',
        language: 'en'
    },
    {
        id: 'UCClassicSilentFilms',
        title: 'Classic Silent Films',
        description: 'Restored silent films and early cinema masterpieces',
        thumbnail_url: 'https://yt3.ggpht.com/example3',
        subscriber_count: 203000,
        video_count: 180,
        view_count: 45000000,
        is_verified: true,
        is_curated: true,
        country: 'US',
        language: 'en'
    }
]

// Sample movies data (classic public domain films available on YouTube)
const sampleMovies = [
    {
        youtube_video_id: 'dQw4w9WgXcQ', // Sample video ID
        title: 'Night of the Living Dead',
        original_title: 'Night of the Living Dead',
        description: 'A disparate group of individuals take shelter in an abandoned house when corpses begin leaving the graveyard in search of fresh human bodies to devour.',
        release_date: '1968-10-01',
        runtime_minutes: 96,
        channel_id: 'UCCGqTWHalrn3g4rNgAa_8-A',
        view_count: 1500000,
        like_count: 45000,
        published_at: '2020-01-15T10:00:00Z',
        tmdb_id: 1585,
        imdb_id: 'tt0063350',
        poster_path: '/inNUOa9WZGdyRXQlt7eqmHtCttl.jpg',
        backdrop_path: '/f7I8x8HZ7N9V4LMhLfZH4YZJKkr.jpg',
        vote_average: 7.1,
        vote_count: 1234,
        category: 'horror',
        language: 'en',
        is_embeddable: true,
        is_available: true,
        featured: true,
        trending: true
    },
    {
        youtube_video_id: 'j8068F_aUnM',
        title: 'The Cabinet of Dr. Caligari',
        original_title: 'Das Cabinet des Dr. Caligari',
        description: 'Francis, a young man, recalls in his memory the horrible experiences he and his fiancée Jane recently went through.',
        release_date: '1920-02-27',
        runtime_minutes: 77,
        channel_id: 'UCCGqTWHalrn3g4rNgAa_8-A',
        view_count: 850000,
        like_count: 32000,
        published_at: '2019-10-31T14:30:00Z',
        tmdb_id: 253,
        imdb_id: 'tt0010323',
        poster_path: '/ucM2X3eLOsVgSyPd3z0JW7xKLJa.jpg',
        backdrop_path: '/vCT6BqWv2Vj8Xha4gZtZKs8fFqm.jpg',
        vote_average: 8.1,
        vote_count: 987,
        category: 'horror',
        language: 'de',
        is_embeddable: true,
        is_available: true,
        featured: false,
        trending: true
    },
    {
        youtube_video_id: 'k7J0VJAjJZM',
        title: 'Plan 9 from Outer Space',
        original_title: 'Plan 9 from Outer Space',
        description: 'Evil aliens attack Earth and set their terrible "Plan 9" in action.',
        release_date: '1959-07-22',
        runtime_minutes: 79,
        channel_id: 'UCRetroFilms',
        view_count: 2100000,
        like_count: 67000,
        published_at: '2018-12-08T09:15:00Z',
        tmdb_id: 18979,
        imdb_id: 'tt0052077',
        poster_path: '/9UkmAGhOKNJQ1H0kLAQLZJH4cG.jpg',
        backdrop_path: '/yQgK8q1QG0FSKF8TRYnO5jqZEfh.jpg',
        vote_average: 4.2,
        vote_count: 543,
        category: 'science_fiction',
        language: 'en',
        is_embeddable: true,
        is_available: true,
        featured: false,
        trending: false
    },
    {
        youtube_video_id: 'H8jqvNa9_Dg',
        title: 'Nosferatu',
        original_title: 'Nosferatu, eine Symphonie des Grauens',
        description: 'Vampire Count Orlok expresses interest in a new residence and real estate agent Hutter\'s wife.',
        release_date: '1922-03-04',
        runtime_minutes: 94,
        channel_id: 'UCClassicSilentFilms',
        view_count: 1800000,
        like_count: 78000,
        published_at: '2019-03-22T16:45:00Z',
        tmdb_id: 696,
        imdb_id: 'tt0013442',
        poster_path: '/rqe6aKSzs97vlIG1FcaJZS6edSN.jpg',
        backdrop_path: '/xAL78MaogDKXWVGSI6jz88vQ3e9.jpg',
        vote_average: 7.9,
        vote_count: 1876,
        category: 'horror',
        language: 'de',
        is_embeddable: true,
        is_available: true,
        featured: true,
        trending: false
    },
    {
        youtube_video_id: 'PtGV5gPKJlA',
        title: 'Metropolis',
        original_title: 'Metropolis',
        description: 'In a futuristic city sharply divided between the working class and the city planners, the son of the city\'s mastermind falls in love with a working class prophet.',
        release_date: '1927-01-10',
        runtime_minutes: 149,
        channel_id: 'UCClassicSilentFilms',
        view_count: 3200000,
        like_count: 125000,
        published_at: '2018-08-17T12:20:00Z',
        tmdb_id: 676,
        imdb_id: 'tt0017136',
        poster_path: '/cEKgQfLQFjGCHOg5mC0pnYScY6v.jpg',
        backdrop_path: '/n67ky5ZIlndjGi5Xk2qO7uJwCUE.jpg',
        vote_average: 8.3,
        vote_count: 2543,
        category: 'science_fiction',
        language: 'de',
        is_embeddable: true,
        is_available: true,
        featured: true,
        trending: true
    }
]

async function seedSampleMovies() {
    try {
        logger.info('Starting sample movie seeding...')

        // Clear existing data
        const { error: deleteMoviesError } = await supabase
            .from('movies')
            .delete()
            .neq('id', 'non-existent') // Delete all rows

        if (deleteMoviesError) {
            logger.warn('Warning clearing existing movies:', deleteMoviesError.message)
        }

        const { error: deleteChannelsError } = await supabase
            .from('channels')
            .delete()
            .neq('id', 'non-existent') // Delete all rows

        if (deleteChannelsError) {
            logger.warn('Warning clearing existing channels:', deleteChannelsError.message)
        }

        // Insert sample channels first
        const { data: channelsData, error: channelsError } = await supabase
            .from('channels')
            .insert(sampleChannels)
            .select()

        if (channelsError) {
            logger.error('Error inserting sample channels:', channelsError)
            throw channelsError
        }

        logger.info(`Successfully inserted ${channelsData.length} sample channels`)

        // Insert sample movies
        const { data, error } = await supabase
            .from('movies')
            .insert(sampleMovies)
            .select()

        if (error) {
            logger.error('Error inserting sample movies:', error)
            throw error
        }

        logger.info(`Successfully inserted ${data.length} sample movies`)
        logger.info('Sample movie seeding completed successfully!')

        // Test the seeded data
        const { data: testData, error: testError } = await supabase
            .from('movies')
            .select('id, title, featured, trending')
            .limit(10)

        if (testError) {
            logger.error('Error testing seeded data:', testError)
        } else {
            logger.info('Seeded movies preview:')
            testData.forEach(movie => {
                logger.info(`  - ${movie.title} (ID: ${movie.id}) [Featured: ${movie.featured}, Trending: ${movie.trending}]`)
            })
        }

    } catch (error) {
        logger.error('Failed to seed sample movies:', error)
        process.exit(1)
    }
}

// Run the seeding
seedSampleMovies()
    .then(() => {
        logger.info('Movie seeding completed')
        process.exit(0)
    })
    .catch((error) => {
        logger.error('Movie seeding failed:', error)
        process.exit(1)
    })