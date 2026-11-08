# AGENTS.md

## Android builds (fork: divergent)

- `.github/workflows/build-android.yml` only runs on `workflow_dispatch` (or `android-v*` / `divergent-android-v*` tags). Pushing a branch does not build.
- Always dispatch with `release_channel: beta`. These builds are prereleases; `stable` creates a full GitHub release that then has to be flipped to prerelease by hand.
- Dispatch, expect HTTP 204, then poll the run:

  ```bash
  curl -s -o /dev/null -w "%{http_code}\n" -X POST \
    -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
    https://api.github.com/repos/sofikuw/anImestream/actions/workflows/build-android.yml/dispatches \
    -d '{"ref":"divergent","inputs":{"branch":"divergent","release_channel":"beta","tag_name":"","create_release":true,"regenerate_icons":false}}'
  ```

  Beta tags look like `divergent-android-v<version>-beta.<hash>` and are published as prereleases.

## Project rules

1. **Version bumps require at least 5 changes.** Do not bump `version:` unless the same release adds, removes or changes at least 5 user-facing things.
2. **Write the smallest code that works.** Prefer ~10 lines over ~50; no speculative abstraction.
3. **Delete failed ideas entirely.** If an approach does not work, remove its code completely instead of leaving it disabled, commented out, or unwired.

## Versioning

- Bump `version: X.Y.Z+N` in `pubspec.yaml`; the workflow derives tag, APK name and build number from it.

## Environment

- No Dart/Flutter SDK in this workspace. Verify Dart edits with `tree-sitter` + `tree_sitter_dart` (0 `ERROR` / `is_missing` nodes); a real build is the only full check.
