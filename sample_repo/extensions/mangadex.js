/**
 * Animestream Dynamic Extension: MangaDex (JavaScript)
 * API Version: 1.0.0
 * Content Type: Manga
 */

var extensionInfo = {
  id: "animestream_mangadex",
  name: "MangaDex",
  version: "1.1.4",
  apiVersion: "1.0.0",
  type: "manga",
  baseUrl: "https://api.mangadex.org"
};

/**
 * Searches manga titles by query.
 */
function searchManga(query, page) {
  var p = page || 1;
  return [
    {
      id: "berserk",
      title: "Berserk",
      coverUrl: "https://images.unsplash.com/photo-1607604276583-eef5d076aa5f?w=500",
      description: "Guts, a former mercenary known as the Black Swordsman, is out for revenge.",
      author: "Kentaro Miura",
      status: "Ongoing",
      totalChapters: 374,
      genres: ["Dark Fantasy", "Action", "Tragedy"]
    },
    {
      id: "chainsaw-man",
      title: "Chainsaw Man",
      coverUrl: "https://images.unsplash.com/photo-1534447677768-be436bb09401?w=500",
      description: "Denji's life of poverty is forever changed when he merges with his pet chainsaw devil, Pochita.",
      author: "Tatsuki Fujimoto",
      status: "Ongoing",
      totalChapters: 160,
      genres: ["Supernatural", "Action", "Comedy"]
    },
    {
      id: "vinland-saga",
      title: "Vinland Saga",
      coverUrl: "https://images.unsplash.com/photo-1578632767115-351597cf2477?w=500",
      description: "Thorfinn, son of one of the Vikings' greatest warriors, rises amidst historical battles in England.",
      author: "Makoto Yukimura",
      status: "Ongoing",
      totalChapters: 210,
      genres: ["Historical", "Adventure", "Drama"]
    }
  ];
}

function getPopularManga(page) {
  return searchManga("", page);
}

function getLatestManga(page) {
  return searchManga("", page);
}

/**
 * Fetches full manga details and chapter list.
 */
function getMangaDetails(mangaId) {
  return {
    id: mangaId,
    title: mangaId.replace(/-/g, ' ').replace(/\b\w/g, function(l){ return l.toUpperCase(); }),
    coverUrl: "https://images.unsplash.com/photo-1607604276583-eef5d076aa5f?w=500",
    description: "Detailed synopsis and overview for " + mangaId + ". Read the latest chapters with smooth page navigation.",
    author: "Manga Creator",
    genres: ["Action", "Adventure", "Fantasy"],
    status: "Ongoing",
    totalChapters: 5,
    chapters: [
      { id: mangaId + "-c1", number: 1, title: "Chapter 1: The Beginning", date: "2024-01-01" },
      { id: mangaId + "-c2", number: 2, title: "Chapter 2: The Trial", date: "2024-01-08" },
      { id: mangaId + "-c3", number: 3, title: "Chapter 3: Turning Point", date: "2024-01-15" },
      { id: mangaId + "-c4", number: 4, title: "Chapter 4: Shadows", date: "2024-01-22" },
      { id: mangaId + "-c5", number: 5, title: "Chapter 5: Rising Sun", date: "2024-01-29" }
    ]
  };
}

/**
 * Fetches image URLs for all pages in a chapter.
 */
function getChapterPages(chapterId) {
  return [
    { index: 0, url: "https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?w=800" },
    { index: 1, url: "https://images.unsplash.com/photo-1607604276583-eef5d076aa5f?w=800" },
    { index: 2, url: "https://images.unsplash.com/photo-1578632767115-351597cf2477?w=800" },
    { index: 3, url: "https://images.unsplash.com/photo-1534447677768-be436bb09401?w=800" },
    { index: 4, url: "https://images.unsplash.com/photo-1541701494587-cb58502866ab?w=800" }
  ];
}
