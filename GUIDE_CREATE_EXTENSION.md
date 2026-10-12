# Guide: Creating an Animestream JavaScript Extension

This guide explains how to write a custom anime or manga extension for Animestream from scratch.

---

## Step 1: Directory Setup
Create a folder for your extension:
```
my_extension/
├── manifest.json
└── index.js
```

---

## Step 2: Define `manifest.json`

```json
{
  "id": "anime_sample_source",
  "name": "Sample Anime Source",
  "version": "1.0.0",
  "apiVersion": "1.0.0",
  "type": "anime",
  "author": "YourName",
  "description": "Scrapes and streams anime episodes from SampleSource.",
  "iconUrl": "https://example.com/icon.png",
  "lang": "en",
  "entrypoint": "index.js",
  "baseUrl": "https://samplesource.example.com",
  "capabilities": [
    "searchAnime",
    "animeDetails",
    "videoSources"
  ]
}
```

---

## Step 3: Implement `index.js`

Write your scraping logic in vanilla JavaScript (ES5 / ES6 compatible):

```javascript
var extensionInfo = {
  id: "anime_sample_source",
  name: "Sample Anime Source",
  version: "1.0.0"
};

// 1. Search Anime
function searchAnime(query, page) {
  var url = "https://samplesource.example.com/api/search?q=" + encodeURIComponent(query);
  var response = http.get(url, { "Accept": "application/json" });
  var json = JSON.parse(response);

  return json.results.map(function(item) {
    return {
      id: item.slug,
      title: item.title,
      posterUrl: item.thumbnail,
      releaseYear: item.year,
      type: "TV",
      rating: item.score
    };
  });
}

// 2. Anime Details & Episodes
function getAnimeDetails(animeId) {
  var url = "https://samplesource.example.com/api/anime/" + animeId;
  var response = http.get(url, {});
  var data = JSON.parse(response);

  return {
    id: animeId,
    title: data.name,
    posterUrl: data.poster,
    description: data.synopsis,
    genres: data.genres,
    episodes: data.episodes.map(function(ep) {
      return {
        id: ep.id,
        episodeNumber: ep.number,
        title: "Episode " + ep.number + ": " + (ep.title || "")
      };
    })
  };
}

// 3. Playable Video Streams
function getVideoSources(episodeId) {
  var url = "https://samplesource.example.com/api/watch/" + episodeId;
  var response = http.get(url, {});
  var data = JSON.parse(response);

  return data.sources.map(function(src) {
    return {
      url: src.file,
      quality: src.label || "Auto",
      isM3U8: src.file.indexOf(".m3u8") !== -1,
      headers: { "Referer": "https://samplesource.example.com" }
    };
  });
}
```

---

## Step 4: Testing Your Extension
1. Open Animestream.
2. Navigate to **Settings > Manage Extensions**.
3. Select **Add Repository** and enter your GitHub repository URL or test locally.
4. Verify search and video playback work cleanly without network errors.
