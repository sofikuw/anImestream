# JavaScript provider repository format (v1)

Manage Providers accepts JavaScript **anime and manga** providers, plus MangaYomi JavaScript extensions. A repository URL must be HTTPS and return a JSON object shaped like this:

```json
{
  "schemaVersion": 1,
  "providers": [
    {
      "manifestVersion": 1,
      "name": "Example Anime",
      "identifier": "example-anime",
      "version": "1.0.0",
      "scriptType": "javascript",
      "contentTypes": ["anime"],
      "entrypoint": "providers/example-anime.js",
      "entrypointSha256": "replace-with-the-lowercase-sha256-of-the-file",
      "allowedHosts": ["api.example.org"],
      "supportDownloads": false
    }
  ]
}
```

`entrypoint` is resolved relative to the catalog URL and must stay on the same HTTPS hostname. The SHA-256 is calculated over the exact downloaded JavaScript bytes. Provider identifiers are unique within a catalog; versions use `major.minor.patch` numeric format. `allowedHosts` is an explicit list of exact DNS hostnames—wildcards, IP literals, and local hostnames are rejected. At connection time, every DNS answer must be a globally routable IP, and the HTTP client pins the socket to a checked address while still validating the HTTPS certificate against the hostname.

Provider code exports an object with `search`, `getAnimeEpisodeLink`, and `getStreams` functions, plus `getDownloadSources` when `supportDownloads` is true. Each function receives `(input, api)` and may be async. The only network capability is `api.request({url, method?, headers?, body?})`; it is HTTPS-only and limited to the manifest's exact `allowedHosts`. Direct `fetch`, XHR, timers, filesystem access, native APIs, credentials, and app cookies are not exposed. See the adapter documentation in `lib/core/anime/providers/javascriptAnimeProvider.dart` for the result fields.

Catalog responses are capped at 1 MiB, provider source files at 256 KiB, and provider HTTP responses at 1 MiB. Each repository transfer has a 15-second total deadline; a provider's async invocation has a 30-second outer deadline.

New installs start disabled. Enabling a provider is a separate user action. The runtime limits synchronous JavaScript to five seconds per evaluation and 64 MiB of JavaScript heap; awaited provider work and each HTTP request also have deadlines and size limits.

These controls are defense-in-depth, not OS-process isolation: QuickJS runs in the app process, and a native runtime vulnerability is outside the JavaScript API restrictions. The digest detects code/catalog mismatches; it is **not** a publisher signature. HTTPS and a hash do not prove that a repository is trustworthy. Only add repositories whose publisher you trust. Updates are accepted only from the repository the provider was installed from, and older/equal versions are not applied.


## MangaYomi catalogs

A repository URL may also point at a MangaYomi `index.json`. That file is a flat
JSON array rather than the object above, for example:

```json
[
  {
    "name": "Example Manga",
    "id": 123456789,
    "baseUrl": "https://example.org",
    "apiUrl": "",
    "lang": "en",
    "iconUrl": "https://raw.githubusercontent.com/owner/repo/main/icon/example.png",
    "typeSource": "single",
    "isManga": true,
    "version": "0.1.3",
    "sourceCodeUrl": "https://raw.githubusercontent.com/owner/repo/main/javascript/manga/src/en/example.js",
    "sourceCodeLanguage": 1
  }
]
```

How entries are mapped:

- `isManga` selects `contentTypes: ["manga"]` or `["anime"]`.
- `baseUrl` and `apiUrl` become `allowedHosts`. MangaYomi bridges additionally
  accept subdomains of those hosts and follow redirects, revalidating every hop.
- `pkgPath` (or the entry index) becomes the identifier, prefixed with `mg-`.
- `version` is normalized to `major.minor.patch`; non-numeric versions fall back
  to `0.0.N`.
- `sourceCodeUrl` is fetched over public HTTPS. Because the index carries no
  digest, the SHA-256 is computed at install time and stored for change
  detection; it is not a publisher signature.
- Entries whose code URL ends in `.dart` are skipped, as are entries that fail
  validation. The rest of the catalog still installs.
- `sourceCodeLanguage: 1` marks JavaScript. Other values are not required for
  parsing but a Dart source is rejected by its `.dart` URL.

The MangaYomi shim implements `MProvider`, `Client` (HEAD/GET/POST/PUT/DELETE/
PATCH), `Document`/`Element`, `SharedPreferences`, and the `String` helpers.
Not implemented: XPath queries, the native AES/JS-unpacker helpers
(`cryptoHandler`, `encryptAESCryptoJS`, `decryptAESCryptoJS`, `decryptAESGCM`,
`deobfuscateJsPassword`), and epub parsing. Sources that require them fail with
a named error instead of silently returning wrong data.

Tachiyomi, Aniyomi, and Mihon extensions are Kotlin APKs and are not supported.
They require the Android `DexClassLoader` plus the Tachiyomi extension API
classes, which the current JavaScript-only runtime cannot provide.
