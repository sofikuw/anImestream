# Build branches

`master` is the branch this repository already had. **`divergent` is the new
one**: the standalone build, shipped under its own iOS display name and bundle
id, so it installs next to a `master` build on the same device.

The branch is the unit of both *what is built* and *what identity it carries*.
Selecting `divergent` in the workflow checks that ref out, then applies the
identity from `branches/divergent/identity.env`. Tag and artifact names are
derived from the branch name, so there is no second list to keep in step: a
build of `divergent` tags `divergent-v1.0.6-4f2ab9` and uploads
`anImestream-divergent-ios-unsigned`.

## Creating the branch

Stage-p lands on `master` first, then the branch is cut from it:

```bash
# after unzipping the archive on master and committing
git checkout -b divergent
git push -u origin divergent
```

Cutting the branch *before* `branches/` exists on master fails the build loudly
(`No identity for branch 'divergent'`), which is the right failure: there would
be no identity to apply.

## The two branches

| | `divergent` | `master` |
| --- | --- | --- |
| File | `branches/divergent/identity.env` | `branches/master/identity.env` |
| Display name | `anImestream-divergent` | `anImestream` |
| Bundle id | `divergent.sofikuw.anImestream` | unchanged |
| Tag prefix | `divergent-` | *(none)* |
| Artifact | `anImestream-divergent-ios-unsigned` | `anImestream-ios-unsigned` |
| Icon | `branches/divergent/icon/` | unchanged |

`master` writes nothing: it carries the identity already, and it is spelled out
as a file so that `divergent` is a peer of `master` rather than "the absence of
one". A build with no branch selected falls back to it.

Tag prefix and artifact name are **not** in the descriptor — the workflow derives
them from the branch name, precisely so the two cannot drift.

## Applying one by hand

```bash
bash branches/apply-identity.sh divergent
git diff --stat          # what the identity costs, before you build
git checkout -- .        # undo
```

The script is idempotent — running it twice reports no changes — and it fails
loudly rather than reporting success when it finds nothing to rewrite, because
"there was no `PRODUCT_BUNDLE_IDENTIFIER` to change" and "it was already correct"
are the same diff.

### Why the identity is applied rather than committed

The alternative is committing the bundle id into the `divergent` branch. That
would put `ios/Runner.xcodeproj/project.pbxproj` — ~90KB of generated Xcode
plist, with the identifier repeated once per build configuration — into the
branch's diff, and every upstream merge would conflict inside it. Applying the
identity at build time keeps the branch thin; the cost is that the working tree
is mutated during the build, so a local `flutter build` needs the script run
first.

## The descriptor schema

| Key | Meaning |
| --- | --- |
| `BRANCH_NAME` | The branch's name. Should match the directory. |
| `BRANCH_DESCRIPTION` | One line, for workflow logs. |
| `DISPLAY_NAME` | `CFBundleDisplayName` / `CFBundleName`. |
| `BUNDLE_ID` | `PRODUCT_BUNDLE_IDENTIFIER`. Empty means "leave it alone". |
| `PUBSPEC_DESCRIPTION` | `pubspec.yaml`'s description. Empty means "leave it alone". |
| `APPLY_IDENTITY` | `false` writes nothing at all. |

## What a branch's identity deliberately cannot change

- **`pubspec.yaml`'s `name:`** — the Dart package id that every
  `package:animestream/...` import in `lib/` depends on. Dart package ids cannot
  contain dots or capitals, so an iOS bundle id can never be one. Changing it
  would be a source-wide refactor with no effect on the build.
- **`ios` OAuth redirect schemes** (`CFBundleURLSchemes`) — changing a scheme
  breaks AniList login until the provider's registered redirect URI is updated to
  match. A bundle-id change does not touch the schemes, so login keeps working
  when a branch changes.
- **The `.app` bundle name** — `Runner.app` comes from Xcode's `PRODUCT_NAME`,
  which the packaging step moves into `Payload/`. Only the bundle id and the
  display name identify the build.

## Adding another branch

1. `mkdir -p branches/<name>` and copy the closest `identity.env`.
2. Set `BRANCH_NAME`, `BRANCH_DESCRIPTION`, `DISPLAY_NAME`, `BUNDLE_ID`,
   `PUBSPEC_DESCRIPTION`, and `APPLY_IDENTITY="true"`.
3. Add it to the `options:` list of the `branch` input in
   `.github/workflows/build-ios.yml`.
4. If it ships its own icon, put PNGs in `branches/<name>/icon/` named after the
   assets they replace (`logo.png`, `logo_foreground.png`, …) and run
   `dart run flutter_launcher_icons` afterwards.
5. Land it on `master` *before* cutting the branch from it.
