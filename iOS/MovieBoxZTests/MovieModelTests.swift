import XCTest
@testable import MovieBoxZ

// MARK: - Movie test factory

private extension Movie {
    static func make(
        id: String = "test-id",
        youtubeVideoId: String = "dQw4w9WgXcQ",
        title: String = "Test Movie",
        youtubeVideoTitle: String = "YouTube Title",
        channelId: String = "UCtest",
        channelTitle: String = "Test Channel",
        viewCount: Int = 1_000,
        runtimeMinutes: Int? = nil,
        voteAverage: Double? = nil,
        imdbRating: Double? = nil,
        releaseDate: Date? = nil,
        posterPath: String? = nil,
        backdropPath: String? = nil,
        lastRefreshed: Date? = nil,
        featured: Bool = false,
        trending: Bool = false
    ) -> Movie {
        Movie(
            id: id,
            youtubeVideoId: youtubeVideoId,
            title: title,
            originalTitle: nil,
            description: nil,
            releaseDate: releaseDate,
            runtimeMinutes: runtimeMinutes,
            youtubeVideoTitle: youtubeVideoTitle,
            channelId: channelId,
            channelTitle: channelTitle,
            channelThumbnail: nil,
            viewCount: viewCount,
            likeCount: nil,
            commentCount: nil,
            publishedAt: nil,
            lastRefreshed: lastRefreshed,
            tmdbId: nil,
            imdbId: nil,
            posterPath: posterPath,
            backdropPath: backdropPath,
            voteAverage: voteAverage,
            voteCount: nil,
            popularity: nil,
            imdbRating: imdbRating,
            rated: nil,
            category: nil,
            quality: nil,
            featured: featured,
            trending: trending,
            isAvailable: true,
            isEmbeddable: true,
            genres: nil,
            addedAt: Date(),
            lastValidated: nil
        )
    }
}

// MARK: - displayTitle

final class MovieDisplayTitleTests: XCTestCase {

    func testUsesMovieTitle() {
        let movie = Movie.make(title: "Fight Club")
        XCTAssertEqual(movie.displayTitle, "Fight Club")
    }

    func testTrimsWhitespace() {
        let movie = Movie.make(title: "  Fight Club  ")
        XCTAssertEqual(movie.displayTitle, "Fight Club")
    }

    func testFallsBackToYouTubeTitleWhenEmpty() {
        let movie = Movie.make(title: "", youtubeVideoTitle: "Fight Club Full Movie")
        XCTAssertEqual(movie.displayTitle, "Fight Club Full Movie")
    }

    func testFallsBackToYouTubeTitleWhenWhitespaceOnly() {
        let movie = Movie.make(title: "   ", youtubeVideoTitle: "YouTube Title")
        XCTAssertEqual(movie.displayTitle, "YouTube Title")
    }
}

// MARK: - formattedRuntime

final class MovieRuntimeTests: XCTestCase {

    func testHoursAndMinutes() {
        let movie = Movie.make(runtimeMinutes: 148)
        XCTAssertEqual(movie.formattedRuntime, "2h 28m")
    }

    func testExactHour() {
        let movie = Movie.make(runtimeMinutes: 60)
        XCTAssertEqual(movie.formattedRuntime, "1h 0m")
    }

    func testMinutesOnly() {
        let movie = Movie.make(runtimeMinutes: 45)
        XCTAssertEqual(movie.formattedRuntime, "45m")
    }

    func testZeroMinutes() {
        let movie = Movie.make(runtimeMinutes: 0)
        XCTAssertEqual(movie.formattedRuntime, "0m")
    }

    func testNilRuntimeReturnsNA() {
        let movie = Movie.make(runtimeMinutes: nil)
        XCTAssertEqual(movie.formattedRuntime, "N/A")
    }
}

// MARK: - formattedRating

final class MovieRatingTests: XCTestCase {

    func testPrefersVoteAverage() {
        let movie = Movie.make(voteAverage: 8.3, imdbRating: 7.0)
        XCTAssertEqual(movie.formattedRating, "8.3")
    }

    func testFallsBackToIMDBRating() {
        let movie = Movie.make(voteAverage: nil, imdbRating: 7.5)
        XCTAssertEqual(movie.formattedRating, "7.5")
    }

    func testBothNilReturnsNA() {
        let movie = Movie.make(voteAverage: nil, imdbRating: nil)
        XCTAssertEqual(movie.formattedRating, "N/A")
    }

    func testOneDecimalPlace() {
        let movie = Movie.make(voteAverage: 7.0)
        XCTAssertEqual(movie.formattedRating, "7.0")
    }
}

// MARK: - formattedViewCount

final class MovieViewCountTests: XCTestCase {

    func testMillions() {
        let movie = Movie.make(viewCount: 2_500_000)
        XCTAssertEqual(movie.formattedViewCount, "2.5M views")
    }

    func testThousands() {
        let movie = Movie.make(viewCount: 1_000)
        XCTAssertEqual(movie.formattedViewCount, "1.0K views")
    }

    func testUnderThousand() {
        let movie = Movie.make(viewCount: 500)
        XCTAssertEqual(movie.formattedViewCount, "500 views")
    }

    func testExactMillion() {
        let movie = Movie.make(viewCount: 1_000_000)
        XCTAssertEqual(movie.formattedViewCount, "1.0M views")
    }
}

// MARK: - URLs

final class MovieURLTests: XCTestCase {

    func testYouTubeURL() {
        let movie = Movie.make(youtubeVideoId: "abc123")
        XCTAssertEqual(movie.youtubeURL?.absoluteString,
                       "https://www.youtube.com/watch?v=abc123")
    }

    func testYouTubeAppURL() {
        let movie = Movie.make(youtubeVideoId: "abc123")
        XCTAssertEqual(movie.youtubeAppURL?.absoluteString,
                       "youtube://www.youtube.com/watch?v=abc123")
    }

    func testYouTubeThumbURL() {
        let movie = Movie.make(youtubeVideoId: "abc123")
        XCTAssertEqual(movie.youtubeThumbURL.absoluteString,
                       "https://img.youtube.com/vi/abc123/hqdefault.jpg")
    }

    func testPosterURLFallsBackToYouTubeThumbnail() {
        let movie = Movie.make(youtubeVideoId: "abc123", posterPath: nil)
        XCTAssertEqual(movie.posterURL?.absoluteString,
                       "https://img.youtube.com/vi/abc123/hqdefault.jpg")
    }

    func testPosterURLFromFullHTTPPath() {
        let movie = Movie.make(posterPath: "https://example.com/poster.jpg")
        XCTAssertEqual(movie.posterURL?.absoluteString, "https://example.com/poster.jpg")
    }

    func testPosterURLFromTMDBRelativePath() {
        let movie = Movie.make(posterPath: "/abc123.jpg")
        XCTAssertEqual(movie.posterURL?.absoluteString,
                       "https://image.tmdb.org/t/p/w500/abc123.jpg")
    }

    func testBackdropURLFallsBackToMaxResYouTubeThumbnail() {
        let movie = Movie.make(youtubeVideoId: "abc123", backdropPath: nil)
        XCTAssertEqual(movie.backdropURL?.absoluteString,
                       "https://img.youtube.com/vi/abc123/maxresdefault.jpg")
    }

    func testChannelURL() {
        let movie = Movie.make(channelId: "UC1234")
        XCTAssertEqual(movie.channelURL?.absoluteString,
                       "https://www.youtube.com/channel/UC1234")
    }
}

// MARK: - needsRefresh

final class MovieCacheTests: XCTestCase {

    func testNeedsRefreshWhenNilLastRefreshed() {
        let movie = Movie.make(lastRefreshed: nil)
        XCTAssertTrue(movie.needsRefresh)
    }

    func testDoesNotNeedRefreshWhenRecentlyRefreshed() {
        let movie = Movie.make(lastRefreshed: Date())
        XCTAssertFalse(movie.needsRefresh)
    }

    func testNeedsRefreshAfter24Hours() {
        let yesterday = Date(timeIntervalSinceNow: -25 * 3600)
        let movie = Movie.make(lastRefreshed: yesterday)
        XCTAssertTrue(movie.needsRefresh)
    }
}

// MARK: - formattedReleaseYear

final class MovieReleaseDateTests: XCTestCase {

    func testExtractsYear() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: 1999, month: 9, day: 10))!
        let movie = Movie.make(releaseDate: date)
        XCTAssertEqual(movie.formattedReleaseYear, "1999")
    }

    func testNilDateReturnsNil() {
        let movie = Movie.make(releaseDate: nil)
        XCTAssertNil(movie.formattedReleaseYear)
    }
}
