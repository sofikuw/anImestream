# divergent icon

Drop the branch's icon PNGs here, named after the assets they replace in
`lib/assets/icons/`. `branches/apply-identity.sh divergent` copies each one over
its same-named counterpart before the build:

```
branches/divergent/icon/logo.png             -> lib/assets/icons/logo.png             (iOS/Android app icon)
branches/divergent/icon/logo_foreground.png  -> lib/assets/icons/logo_foreground.png  (adaptive foreground)
branches/divergent/icon/logo_background.png  -> lib/assets/icons/logo_background.png  (adaptive background)
branches/divergent/icon/logo_monochrome.png  -> lib/assets/icons/logo_monochrome.png  (Themed/Monochrome)
branches/divergent/icon/logo_foreground_splash.png -> …splash image
```

A file with no counterpart in `lib/assets/icons/` is reported and skipped, not
guessed at.

**This directory is intentionally empty of PNGs in the archive.** The icon is not
authored byte-by-byte — it is the original artwork with a crack overlay drawn
over it, so the staging val renders it instead:

    https://animestream-manga.val.run/icon/divergent-logo.png

Download that PNG to `branches/divergent/icon/logo.png` and commit it. The legible
version — what the route does and what it refuses to do — is in the val's
`crackedIcon.ts`.

After replacing an icon, regenerate the sizes Xcode needs:

```bash
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```
