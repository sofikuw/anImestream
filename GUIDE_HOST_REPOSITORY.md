# Guide: Hosting an Animestream Extension Repository on GitHub

Animestream repositories are static HTTPS directories containing an `index.json` catalog and extension assets. You can host them for free on **GitHub Pages** or direct **Raw GitHub URLs**.

---

## 1. Repository Directory Structure

Create a Git repository (e.g. `animestream-community-extensions`):

```
animestream-community-extensions/
├── index.json
├── icons/
│   ├── gogoanime.png
│   └── mangadex.png
└── extensions/
    ├── gogoanime/
    │   ├── manifest.json
    │   └── index.js
    └── mangadex/
        ├── manifest.json
        └── index.js
```

---

## 2. Formatting `index.json`

The root catalog file `index.json` indexes all extensions in your repository:

```json
{
  "name": "My Custom Community Extensions",
  "formatVersion": "1.0.0",
  "description": "Custom verified anime & manga dynamic extensions",
  "extensions": [
    {
      "id": "my_anime_ext",
      "name": "My Anime Provider",
      "version": "1.0.0",
      "apiVersion": "1.0.0",
      "type": "anime",
      "description": "Fast anime streams.",
      "author": "GitHubUsername",
      "iconUrl": "icons/my_anime_ext.png",
      "lang": "en",
      "manifestUrl": "extensions/my_anime_ext/manifest.json",
      "codeUrl": "extensions/my_anime_ext/index.js",
      "capabilities": ["searchAnime", "videoSources"]
    }
  ]
}
```

*Note: Relative paths (`manifestUrl`, `codeUrl`, `iconUrl`) are automatically resolved by Animestream against your repository base URL.*

---

## 3. GitHub Hosting Steps
1. Push your repository to GitHub:
   ```bash
   git init
   git add .
   git commit -m "Initial extensions commit"
   git branch -M main
   git remote add origin https://github.com/<USERNAME>/<REPO_NAME>.git
   git push -u origin main
   ```
2. Your repository URL to enter in Animestream is:
   ```
   https://raw.githubusercontent.com/<USERNAME>/<REPO_NAME>/main
   ```
   Or enable **GitHub Pages** in Repository Settings > Pages > Deploy from branch `main` / `root`, giving you:
   ```
   https://<USERNAME>.github.io/<REPO_NAME>
   ```
