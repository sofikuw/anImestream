# Animestream JavaScript Extension API Specification (v1.0.0)

## Overview
Animestream's dynamic extension system is inspired by Mangayomi. It allows third-party developers and community contributors to distribute lightweight JavaScript sources that scrape, query, or stream anime and manga content directly on client devices without requiring iOS IPA rebuilds or native re-compilations.

---

## 1. Runtime Environment & Host APIs

All extensions run within an isolated JavaScript execution context (Apple's **JavaScriptCore** on iOS, **QuickJS** on Android/Desktop).

### Available Global Objects & Host APIs
1. `console.log(msg)`, `console.warn(msg)`, `console.error(msg)`
   - Safe sandbox logging directed to native log streams.
2. `http.get(url, headers)`
   - Performs a sandboxed synchronous/asynchronous HTTP GET request.
   - Default User-Agent is automatically populated.
   - Returns response body string.
3. `http.post(url, body, headers)`
   - Performs an HTTP POST request. Returns response body string.
4. `atob(base64String)` & `btoa(asciiString)`
   - Standard Base64 decode and encode utilities.
5. `JSON.parse(str)` & `JSON.stringify(obj)`
   - Standard ECMAScript JSON serialization.

### Security Guarantees
- No unrestricted local filesystem access (`fs`, `dart:io` are blocked).
- No access to Keychain, user accounts, AniList OAuth tokens, or private app storage.
- Strict 15-second execution timeout per method invocation.

---

## 2. Extension Manifest Schema (`manifest.json`)

Each extension directory must declare its metadata in `manifest.json`:

```json
{
  "id": "animestream_gogoanime",
  "name": "GogoAnime",
  "version": "1.2.0",
  "apiVersion": "1.0.0",
  "type": "anime",
  "author": "Animestream Community",
  "description": "Stream anime with multiple video servers and subtitle mirrors.",
  "iconUrl": "https://example.com/icon.png",
  "lang": "en",
  "entrypoint": "index.js",
  "baseUrl": "https://anitaku.to",
  "capabilities": [
    "searchAnime",
    "popularAnime",
    "latestAnime",
    "animeDetails",
    "episodes",
    "videoSources",
    "subtitles"
  ]
}
```

### Supported `type` Values:
- `"anime"`: Provides anime search, episode lists, and video sources.
- `"manga"`: Provides manga search, chapter lists, and image page URLs.
- `"both"`: Provides both anime and manga capabilities.

---

## 3. Anime Provider Methods

Extensions declaring `"type": "anime"` or `"both"` can implement:

### `searchAnime(query: string, page: number): AnimeItem[]`
Returns search results matching `query`.
```javascript
function searchAnime(query, page) {
  return [
    {
      id: "jujutsu-kaisen",
      title: "Jujutsu Kaisen",
      posterUrl: "https://...",
      releaseYear: "2023",
      type: "TV",
      rating: 8.8
    }
  ];
}
```

### `getPopularAnime(page: number): AnimeItem[]`
Returns trending/popular anime on the source.

### `getAnimeDetails(animeId: string): AnimeDetails`
Returns metadata and list of episodes.
```javascript
function getAnimeDetails(animeId) {
  return {
    id: animeId,
    title: "Jujutsu Kaisen",
    posterUrl: "https://...",
    description: "Series synopsis...",
    genres: ["Action", "Supernatural"],
    status: "Ongoing",
    episodes: [
      { id: "jjk-ep-1", episodeNumber: 1, title: "Episode 1: Ryomen Sukuna" },
      { id: "jjk-ep-2", episodeNumber: 2, title: "Episode 2: For Myself" }
    ]
  };
}
```

### `getVideoSources(episodeId: string): VideoSource[]`
Resolves playable video stream URLs.
```javascript
function getVideoSources(episodeId) {
  return [
    {
      url: "https://cdn.example.com/stream.m3u8",
      quality: "1080p FHD",
      isM3U8: true,
      headers: { "Referer": "https://source.com" }
    }
  ];
}
```

---

## 4. Manga Provider Methods

Extensions declaring `"type": "manga"` or `"both"` can implement:

### `searchManga(query: string, page: number): MangaItem[]`
```javascript
function searchManga(query, page) {
  return [
    {
      id: "berserk",
      title: "Berserk",
      coverUrl: "https://...",
      description: "Dark fantasy manga...",
      author: "Kentaro Miura",
      status: "Ongoing",
      totalChapters: 374,
      genres: ["Action", "Dark Fantasy"]
    }
  ];
}
```

### `getPopularManga(page: number): MangaItem[]`
Returns popular titles on the source.

### `getMangaDetails(mangaId: string): MangaDetails`
Returns full details and list of chapters.
```javascript
function getMangaDetails(mangaId) {
  return {
    id: mangaId,
    title: "Berserk",
    coverUrl: "https://...",
    description: "Synopsis...",
    author: "Kentaro Miura",
    status: "Ongoing",
    chapters: [
      { id: "b-c1", number: 1, title: "Chapter 1: The Black Swordsman", date: "1989-08-25" },
      { id: "b-c2", number: 2, title: "Chapter 2: The Brand", date: "1989-09-25" }
    ]
  };
}
```

### `getChapterPages(chapterId: string): (MangaPage | string)[]`
Returns image URLs for all pages in a chapter.
```javascript
function getChapterPages(chapterId) {
  return [
    { index: 0, url: "https://cdn.example.com/page01.jpg" },
    { index: 1, url: "https://cdn.example.com/page02.jpg" }
  ];
}
```

---

## 5. Error Handling & Stability Contract
- Extensions must return structured objects or throw standard JavaScript `Error` objects (`throw new Error("Captcha required")`).
- If an extension throws, Animestream intercepts the exception cleanly without crashing Flutter or the video/manga viewer.
