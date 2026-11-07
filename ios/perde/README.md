# Perde

An iPhone app for choosing what to watch on Turkcell TV+. The interface is in Turkish.

- **Discover:** the current TV+ catalog, films and series, with IMDb scores and vote counts.
- **Sorting by fit:** mood shelves, genre, year, origin, a minimum IMDb score with a minimum
  vote count, and an IMDb order that does not reward high scores from few votes. "Bana uygun"
  orders by the genres of the user's own list and scores.
- **Lists:** priority (reorderable), list and watched, with a personal score. Stored on the
  phone with SwiftData.
- **Live scan:** VisionKit reads titles from the camera, and the IMDb score appears over the
  title. Tap a score to open the title.

## Data sources

| Source | Provides | Key |
|---|---|---|
| TMDB (availability from JustWatch) | Catalog, overviews, genres, keywords, cast, reviews | Free, https://www.themoviedb.org/settings/api |
| OMDb | IMDb score and votes, Rotten Tomatoes, Metacritic | Free, 1,000 requests a day, https://www.omdbapi.com/apikey.aspx |

The user enters both keys in the app (Keşfet › Ayarlar). They stay in the Keychain. Ratings are
cached for 7 days to protect the OMDb quota.

The TV+ provider is found by name in TMDB's Turkish provider list, because the id belongs to TMDB.
To add a platform, add a value to `StreamingPlatform.all` and a picker in Discover.

## Known limits

- The catalog is as complete as JustWatch's TV+ data, not TV+'s own list.
- TMDB provides the reviews. IMDb user reviews have no public API, and Turkish reviews are rare.
- The IMDb minimum score and IMDb order work on the pages fetched so far. TMDB does not know IMDb scores.
- The scanner reads text. A poster with no readable title is not recognised.

## Build

```bash
cd ios && xcodegen generate
```

```bash
zsh install-on-iphone.sh
```

Debug builds accept `TMDB_API_KEY`, `OMDB_API_KEY`, `TMDB_BASE_URL`, `OMDB_BASE_URL` and
`TMDB_IMAGE_BASE_URL` as environment variables, to run against a local fixture server.
Live scanning needs a real iPhone; the simulator shows an explanation instead.
