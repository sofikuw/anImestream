/**
 * Animestream Dynamic Extension: GogoAnime (JavaScript)
 * API Version: 1.0.0
 * Content Type: Anime
 */

var extensionInfo = {
  id: "animestream_gogoanime",
  name: "GogoAnime",
  version: "1.2.0",
  apiVersion: "1.0.0",
  type: "anime",
  baseUrl: "https://anitaku.to"
};

/**
 * Searches anime by query keyword and page index.
 */
function searchAnime(query, page) {
  var p = page || 1;
  // Real implementation can query endpoint using http.get()
  // e.g.: var html = http.get(extensionInfo.baseUrl + "/search.html?keyword=" + encodeURIComponent(query) + "&page=" + p);
  return [
    {
      id: "jujutsu-kaisen-2nd-season",
      title: "Jujutsu Kaisen 2nd Season",
      posterUrl: "https://images.unsplash.com/photo-1578632767115-351597cf2477?w=500",
      releaseYear: "2023",
      type: "TV",
      rating: 8.8
    },
    {
      id: "frieren-beyond-journeys-end",
      title: "Frieren: Beyond Journey's End",
      posterUrl: "https://images.unsplash.com/photo-1534447677768-be436bb09401?w=500",
      releaseYear: "2023",
      type: "TV",
      rating: 9.3
    },
    {
      id: "solo-leveling",
      title: "Solo Leveling",
      posterUrl: "https://images.unsplash.com/photo-1607604276583-eef5d076aa5f?w=500",
      releaseYear: "2024",
      type: "TV",
      rating: 8.5
    }
  ];
}

/**
 * Returns popular / trending anime.
 */
function getPopularAnime(page) {
  return searchAnime("Popular", page);
}

/**
 * Returns latest released episodes.
 */
function getLatestAnime(page) {
  return searchAnime("Latest", page);
}

/**
 * Retrieves anime details and all available episodes.
 */
function getAnimeDetails(animeId) {
  return {
    id: animeId,
    title: animeId.replace(/-/g, ' ').replace(/\b\w/g, function(l){ return l.toUpperCase(); }),
    posterUrl: "https://images.unsplash.com/photo-1578632767115-351597cf2477?w=500",
    description: "Follow the epic adventure with high quality video streaming and subtitles.",
    genres: ["Action", "Fantasy", "Adventure"],
    status: "Ongoing",
    episodes: [
      { id: animeId + "-episode-1", episodeNumber: 1, title: "Episode 1: The Departure" },
      { id: animeId + "-episode-2", episodeNumber: 2, title: "Episode 2: Meeting the Unknown" },
      { id: animeId + "-episode-3", episodeNumber: 3, title: "Episode 3: The Gathering" },
      { id: animeId + "-episode-4", episodeNumber: 4, title: "Episode 4: Turning Point" }
    ]
  };
}

/**
 * Resolves playable video URLs (HLS m3u8 or MP4) for an episode.
 */
function getVideoSources(episodeId) {
  return [
    {
      url: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
      quality: "1080p FHD",
      isM3U8: false,
      headers: { "Referer": "https://anitaku.to" }
    },
    {
      url: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4",
      quality: "720p HD",
      isM3U8: false
    }
  ];
}

/**
 * Optional subtitle track discovery.
 */
function getSubtitles(episodeId) {
  return [
    {
      url: "https://raw.githubusercontent.com/animestream/sample-subs/main/english.vtt",
      language: "English",
      format: "vtt"
    }
  ];
}
