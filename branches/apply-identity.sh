#!/usr/bin/env bash
#
# Applies a branch's identity (branches/<name>/identity.env) to this working tree.
#
# Run by .github/workflows/build-ios.yml and build-android.yml after they check
# the branch out, and safe to run by hand. It only rewrites files, so
# `git checkout -- .` undoes all of it, and it is idempotent: running it twice
# leaves the tree in the same state and reports that nothing changed.
#
#   bash branches/apply-identity.sh divergent
#
# What a branch's identity can change:
#   pubspec.yaml                      description only
#   ios/**/project.pbxproj            PRODUCT_BUNDLE_IDENTIFIER
#   ios/**/Info.plist                 CFBundleDisplayName / CFBundleName
#   android/app/build.gradle.kts      applicationId
#   android/app/src/main/AndroidManifest.xml    android:label
#   lib/assets/icons/*.png            any PNG in branches/<name>/icon/
#
# What it deliberately does not change:
#   pubspec.yaml `name:`  -- the Dart package id lib/ imports. Dots and capitals
#                            are illegal there, so a bundle id can never be one.
#   ios CFBundleURLSchemes -- OAuth redirect schemes. Changing a scheme would
#                            break AniList login until the provider's registered
#                            redirect URI is updated too.
#   android `namespace`   -- the compile-time Kotlin package, which is where
#                            MainActivity.kt lives. An applicationId is an
#                            install identity, not a package rename; moving the
#                            namespace means moving source files.
#
# DISPLAY_NAME serves both platforms: it is the iOS CFBundleDisplayName and the
# Android android:label. One branch, one name.
set -euo pipefail

usage() {
  local available
  available=$(ls branches/*/identity.env 2>/dev/null \
    | sed -e 's|^branches/||' -e 's|/identity\.env$||' | tr '\n' ' ')
  echo "usage: $(basename "$0") <branch>   (available: ${available:-none})" >&2
}

BRANCH="${1:-}"
if [ -z "$BRANCH" ]; then
  usage
  exit 2
fi

DESCRIPTOR="branches/${BRANCH}/identity.env"
if [ ! -f "$DESCRIPTOR" ]; then
  echo "no identity for branch: $DESCRIPTOR" >&2
  usage
  exit 2
fi

# shellcheck source=/dev/null
. "$DESCRIPTOR"

echo "branch:       ${BRANCH_NAME:-$BRANCH}"
echo "display name: ${DISPLAY_NAME:-<unchanged>}"
echo "bundle id:    ${BUNDLE_ID:-<unchanged>}"
echo "application:  ${APPLICATION_ID:-<unchanged>}"

if [ "${APPLY_IDENTITY:-false}" != "true" ]; then
  echo
  echo "$BRANCH keeps the identity the branch already carries; nothing to write."
  exit 0
fi

echo

# ---------------------------------------------------------------- pubspec.yaml
#
# Description only. See the header for why `name:` is not touched.
if [ -n "${PUBSPEC_DESCRIPTION:-}" ]; then
  if grep -q '^description:' pubspec.yaml; then
    # `-i.bak` is the one in-place form GNU sed and BSD sed agree on.
    sed -i.bak "s|^description:.*|description: \"${PUBSPEC_DESCRIPTION}\"|" pubspec.yaml
    rm -f pubspec.yaml.bak
    echo "pubspec.yaml                     description -> ${PUBSPEC_DESCRIPTION}"
  else
    echo "pubspec.yaml has no description: line" >&2
    exit 1
  fi
fi

# ------------------------------------------------------------------ bundle id
#
# PRODUCT_BUNDLE_IDENTIFIER appears once per build configuration per target.
# RunnerTests' identifier is the app's with `.RunnerTests` appended, so the
# rewrite preserves that suffix instead of flattening both targets onto one id.
if [ -n "${BUNDLE_ID:-}" ]; then
  python3 - "$BUNDLE_ID" <<'PY'
import pathlib, re, sys

bundle_id = sys.argv[1]
line_re = re.compile(r"^(\s*PRODUCT_BUNDLE_IDENTIFIER = )([^;]+);(\s*)$")

projects = sorted(pathlib.Path("ios").rglob("project.pbxproj"))
if not projects:
    sys.exit("no ios/**/project.pbxproj found")

matched = 0
changed = 0
for path in projects:
    out = []
    for line in path.read_text().splitlines(keepends=True):
        body = line.rstrip("\n")
        m = line_re.match(body)
        if m:
            matched += 1
            old = m.group(2).strip().strip('"')
            if old.endswith(".RunnerTests"):
                new = f"{bundle_id}.RunnerTests"
            else:
                new = bundle_id
            if old != new:
                changed += 1
                line = f"{m.group(1)}{new};" + ("\n" if line.endswith("\n") else "")
        out.append(line)
    if changed:
        path.write_text("".join(out))
    print(f"{path}                    {len(out)} lines scanned")

# Loud on nothing-to-do, because "no bundle id found" and "already correct"
# are the same diff and only one of them is a success.
if matched == 0:
    sys.exit("PRODUCT_BUNDLE_IDENTIFIER not found; refusing to report success")
print(f"                                  {matched} bundle id line(s), {changed} changed -> {bundle_id}")
PY
fi

# --------------------------------------------------------------- display name
#
# What the home screen shows. Flutter writes CFBundleDisplayName as
# $(PRODUCT_NAME) by default, so replacing the value with a literal is what makes
# two branch builds distinguishable on a device.
if [ -n "${DISPLAY_NAME:-}" ]; then
  python3 - "$DISPLAY_NAME" <<'PY'
import pathlib, plistlib, sys

display_name = sys.argv[1]
plists = sorted(pathlib.Path("ios").rglob("Info.plist"))
if not plists:
    sys.exit("no ios/**/Info.plist found")

touched = 0
for path in plists:
    try:
        with path.open("rb") as fh:
            data = plistlib.load(fh)
    except Exception as exc:  # a binary or unusual plist is not our business
        print(f"{path}  skipped ({exc})")
        continue
    changed = False
    for key in ("CFBundleDisplayName", "CFBundleName"):
        if key in data and data[key] != display_name:
            data[key] = display_name
            changed = True
    if changed:
        with path.open("wb") as fh:
            plistlib.dump(data, fh)
        touched += 1
        print(f"{path}                    display name -> {display_name}")

if touched == 0:
    print("                                  display name already correct in every Info.plist")
PY
fi

# --------------------------------------------------------------- android id
#
# Android splits the two identifiers iOS fuses into one, and that split is the
# whole reason this section needs explaining.
#
#   * `namespace` is the *compile-time* package. It decides where
#     `MainActivity.kt` lives, what `.MainActivity` in the manifest resolves
#     against, and therefore which source files the build compiles. Changing it
#     means moving Kotlin files, so a branch does not get to change it.
#   * `applicationId` is the *install* identity: what the device, the launcher
#     and any future store use to tell two builds apart.
#
# Only the second is a branch's. That is why `divergent.sofikuw.anImestream` can
# be an applicationId while every Kotlin file stays under `app.animestream` --
# and why the namespace is asserted here rather than rewritten.
#
# Failing loudly rather than skipping: the archive always carries android/, so a
# missing file means the tree is not what this is being run against, and "found
# nothing to change" and "changed it" produce the same output otherwise.
if [ -n "${APPLICATION_ID:-}" ]; then
  if [ ! -f android/app/build.gradle.kts ]; then
    echo "android/app/build.gradle.kts     is missing; refusing to report success" >&2
    exit 1
  fi

  python3 - "$APPLICATION_ID" <<'PY'
import pathlib, re, sys

application_id = sys.argv[1]
path = pathlib.Path("android/app/build.gradle.kts")
text = path.read_text()

# Anchored to the assignment, and to the end of its own line, so the
# `namespace =` line directly above it cannot match. `[^\n]*` rather than `.*$`
# for the tail: it cannot be confused by a stray carriage return.
pattern = re.compile(r'^(\s*applicationId\s*=\s*)"([^"]*)"([^\n]*)', re.M)
matches = list(pattern.finditer(text))

if len(matches) != 1:
    sys.exit(
        f"expected exactly one applicationId assignment in {path}, found "
        f"{len(matches)}; refusing to guess which build configuration is the app's"
    )

old = matches[0].group(2)
if old == application_id:
    print(f"{path}   applicationId already {application_id}")
else:
    text = pattern.sub(lambda m: f'{m.group(1)}"{application_id}"{m.group(3)}', text)
    path.write_text(text)
    print(f"{path}   applicationId {old} -> {application_id}")

# The namespace is deliberately left alone, and its presence is asserted here so
# that a future edit which "tidies" the two together fails instead of moving
# every Kotlin file out from under the build.
if 'namespace = "app.animestream"' not in text:
    sys.exit(
        'android/app/build.gradle.kts no longer sets namespace = "app.animestream". '
        "That is the compile-time package MainActivity.kt lives in; if it really "
        "moved, this script has to move source files too."
    )
print(f"{path}   namespace left alone (app.animestream)")
PY
fi

# ---------------------------------------------------------- android label
#
# What the launcher shows. Read from DISPLAY_NAME, the same key the iOS section
# above uses, so a branch has one name rather than one per platform.
#
# The manifest holds *two* android:label values -- the <application>'s, and one
# on the OAuth callback activity's intent-filter ("Open in animestream"). Only
# the first is the app's name, so the rewrite is scoped to the <application>
# element's own tag rather than to the first match in the file, which would be
# right by accident and wrong the moment the manifest is reordered.
if [ -n "${DISPLAY_NAME:-}" ]; then
  if [ ! -f android/app/src/main/AndroidManifest.xml ]; then
    echo "android/app/src/main/AndroidManifest.xml is missing; refusing to report success" >&2
    exit 1
  fi

  python3 - "$DISPLAY_NAME" <<'PY'
import pathlib, re, sys

display_name = sys.argv[1]
path = pathlib.Path("android/app/src/main/AndroidManifest.xml")
text = path.read_text()

element = re.search(r'<application\b[^>]*>', text, re.S)
if not element:
    sys.exit(f"no <application> element in {path}")

tag = element.group(0)
new_tag, count = re.subn(
    r'android:label="[^"]*"', f'android:label="{display_name}"', tag, count=1
)
if count != 1:
    sys.exit(f"the <application> element in {path} has no android:label to rewrite")

if new_tag == tag:
    print(f"{path}     label already {display_name}")
else:
    old = re.search(r'android:label="([^"]*)"', tag).group(1)
    path.write_text(text[:element.start()] + new_tag + text[element.end():])
    print(f"{path}     label {old} -> {display_name}")
PY
fi

# ------------------------------------------------------------------- icon set
#
# Any PNG in the branch's icon directory replaces the same-named asset in
# lib/assets/icons/, so a branch ships its own icon without the other branch's
# icon changing. Missing files are reported, not faked: flutter_launcher_icons
# reads lib/assets/icons/logo*.png out of pubspec.yaml, so a silent no-op here
# would mean building with the wrong icon and no signal.
#
# Note that this only replaces the *source* images. The generated icon sets --
# ios/Runner/Assets.xcassets/AppIcon.appiconset and android/app/src/main/res/
# mipmap-* -- are what the build actually ships, and they are not regenerated
# here. `dart run flutter_launcher_icons` does both, and the Android workflow
# will run it for you when the regenerate_icons input is set.
ICON_DIR="branches/${BRANCH}/icon"
if [ -d "$ICON_DIR" ]; then
  shopt -s nullglob
  icons=("$ICON_DIR"/*.png)
  shopt -u nullglob

  if [ "${#icons[@]}" -eq 0 ]; then
    echo "$ICON_DIR                    no PNGs in it; icons left as they are"
  else
    for icon in "${icons[@]}"; do
      name="$(basename "$icon")"
      dest="lib/assets/icons/$name"
      if [ -f "$dest" ]; then
        cp "$icon" "$dest"
        echo "lib/assets/icons/$name$(printf '%*s' $((19 - ${#name})) '')<- $icon"
      else
        echo "no lib/assets/icons/$name to replace; skipping $icon" >&2
      fi
    done
    echo
    echo "Regenerate both icon sets from these with:"
    echo "  dart run flutter_launcher_icons    # iOS AppIcon + Android mipmaps"
    echo "  dart run flutter_native_splash:create"
  fi
fi

echo
echo "applied identity: ${BRANCH_NAME:-$BRANCH}"
