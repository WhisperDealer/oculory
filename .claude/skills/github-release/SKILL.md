---
name: github-release
description: Cut a versioned GitHub release (e.g. v1.2.0) for this mod — build a changelog from the previous tag, attach the latest CI-built .7z assets, mark it Latest, and clean up the throwaway build-timestamp pre-releases/tags. Use when the user wants to "make a release", "cut vX.Y.Z", "publish a release", or tidy up the build-* tags.
---

# Cut a GitHub release

## Resolve the repo and asset names first — never hardcode them

```bash
REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
```

Pass `-R "$REPO"` to every `gh` call so it works regardless of the local remote name.

The release assets are whatever `build/build.ps1` produces — one `.7z` per release in
`build/manifest.json`. Read the names from the manifest rather than assuming:

```bash
python -c "import json;print('\n'.join(r['archiveName']+'.7z' for r in json.load(open('build/manifest.json'))['releases']))"
```

GitHub replaces spaces with dots in uploaded asset filenames, so a manifest `archiveName` of
`Example Mod` arrives as `Example.Mod.7z`. Confirm the actual names with
`gh release view <buildTag> -R "$REPO" --json assets --jq '.assets[].name'` before referencing them.

## Background: how CI releases work

Every push to `main` triggers a GitHub Actions build that publishes a **pre-release** tagged
`build-<UTCtimestamp>` (e.g. `build-20260724-202103`) carrying every release archive as an asset.

A versioned release (`vX.Y.Z`) is a curated, permanent **Latest** release that reuses the assets
from the most recent matching `build-*` pre-release. Those `build-*` pre-releases are throwaway —
delete them once their assets are promoted into a version.

## Steps

### 1. Establish the version and the previous tag

- Confirm the new version with the user (e.g. `v1.2.0`) if not given. Follow semver off the last
  version tag: `gh release list -R "$REPO" --limit 100`.
- The previous version tag (`PREV`) is the newest `vX.Y.Z` release — this is the changelog base.

### 2. Sync and inspect the changes

```bash
git fetch --all --tags
git pull --ff-only          # get main to origin tip
git log --oneline --no-merges PREV..HEAD | grep -v 'ci: update build report'
```

Read the meaningful commits and group them for the changelog (plugin/record changes, scripts,
FOMOD/installer, CI). **Call out which plugins actually changed** — for a multi-plugin repo, users
care whether the main mod moved or whether this is a patches-only release.

### 3. Pick the build whose assets you'll promote

- Find the newest `build-*` pre-release and resolve its commit:
  `gh api "repos/$REPO/git/refs/tags/<buildTag>" --jq '.object.sha'`
- Confirm that commit's **tree** matches what you're releasing. `main` may sit one or two docs-only
  commits ahead (e.g. `ci: update build report [skip ci]` touching `arch-docs/build-report.md`) —
  that's fine; the payload is identical. If real source changed after the last build, tell the user
  the assets are stale and offer to wait for / trigger a fresh CI build rather than shipping old
  binaries.
- Download the assets to a scratch dir:
  `gh release download <buildTag> -R "$REPO" --clobber`

### 4. Write the changelog notes

Write a `notes.md` in the scratch dir. Structure it with `##` sections, lead with a one-line framing
of what the release is mainly about, and end with:

```
**Full Changelog**: https://github.com/<REPO>/compare/PREV...vX.Y.Z
```

### 5. Create the release

```bash
gh release create vX.Y.Z \
  -R "$REPO" \
  --target main \
  --title "vX.Y.Z" \
  --notes-file notes.md \
  --latest \
  <each downloaded .7z>
```

Use `--target main` (a branch name), **not** a short SHA — `gh` rejects short SHAs with
`target_commitish is invalid`.

### 6. Delete the throwaway build-* pre-releases and tags

```bash
for t in $(gh release list -R "$REPO" --limit 100 \
             --json tagName --jq '.[] | select(.tagName|startswith("build-")) | .tagName'); do
  gh release delete "$t" -R "$REPO" --yes --cleanup-tag
done
git tag -l 'build-*' | xargs -r git tag -d   # clean up any locally-fetched build tags
```

`--cleanup-tag` removes the git tag along with the release. Leave the `vX.Y.Z` version tags alone.

### 7. Verify

```bash
gh release list -R "$REPO" --limit 20
git ls-remote --tags origin 'build-*'   # should print nothing
```

Confirm the new version is `Latest`, every expected asset is attached, and no `build-*` tags remain.
Report the release URL to the user.

## Notes / gotchas

- **Short SHA as `--target` fails** — use `main` or a full 40-char SHA.
- **Don't rebuild locally.** Promote the CI-built assets; a local Spriggit deserialize can drift
  from what CI ships. Only fall back to a manual build if the user explicitly asks.
- Keep asset filenames exactly as CI produced them — that's what users and any install instructions
  expect.
- Deleting a `build-*` release also deletes its assets; only do it after the version release exists
  and is confirmed.
- Publishing a release is **outward-facing and hard to reverse**. Confirm the version number and the
  asset list with the user before running step 5.
