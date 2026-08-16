---
name: github-release
description: Cut a versioned GitHub release (e.g. v1.2.0) for this mod — build a changelog from the previous tag, push the version tag so CI builds and publishes the assets, then replace the generated notes with the curated changelog and mark it Latest. Use when the user wants to "make a release", "cut vX.Y.Z", or "publish a release".
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
`gh release view vX.Y.Z -R "$REPO" --json assets --jq '.assets[].name'` once the release exists.

## Background: how CI releases work

Pushing a **`v*` tag** is the only thing that publishes. `.github/workflows/build.yml` builds every
archive on that tag and creates the GitHub Release with `--generate-notes`, attaching each `.7z`.

Pushes to `main` build as a smoke test but publish nothing, and PRs attach their archives as
throwaway Actions artifacts. So a release is: **tag → wait for CI → curate the notes.**

## Steps

### 1. Establish the version and the previous tag

- Confirm the new version with the user (e.g. `v1.2.0`) if not given. Follow semver off the last
  version tag: `gh release list -R "$REPO" --limit 100`.
- The previous version tag (`PREV`) is the newest `vX.Y.Z` release — this is the changelog base.

### 2. Sync and inspect the changes

```bash
git fetch --all --tags
git pull --ff-only          # get main to origin tip
git log --oneline --no-merges PREV..HEAD
```

Read the meaningful commits and group them for the changelog (plugin/record changes, scripts,
FOMOD/installer, CI). **Call out which plugins actually changed** — for a multi-plugin repo, users
care whether the main mod moved or whether this is a patches-only release.

### 3. Check the commit you are about to tag is green

The tag build is the release build, so a red `main` means a failed release, not a bad asset:

```bash
gh run list -R "$REPO" --workflow build.yml --branch main --limit 3
```

If the newest `main` run failed, fix that before tagging.

### 4. Write the changelog notes

Write a `notes.md` in a scratch dir. Structure it with `##` sections, lead with a one-line framing
of what the release is mainly about, and end with:

```
**Full Changelog**: https://github.com/<REPO>/compare/PREV...vX.Y.Z
```

### 5. Tag it — this publishes

Confirm the version and the expected asset list with the user first: pushing the tag is what makes
the release public.

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
```

Then watch the build that cuts the release:

```bash
gh run list -R "$REPO" --workflow build.yml --limit 3          # find the run for the tag
gh run watch <runId> -R "$REPO" --exit-status
```

### 6. Replace the generated notes and mark it Latest

CI creates the release with auto-generated notes. Overwrite them with the curated changelog:

```bash
gh release edit vX.Y.Z -R "$REPO" --notes-file notes.md --latest
```

### 7. Verify

```bash
gh release view vX.Y.Z -R "$REPO" --json assets,isLatest,isDraft \
  --jq '{latest:.isLatest, draft:.isDraft, assets:[.assets[].name]}'
```

Confirm the release is `Latest`, not a draft, and that every archive from `build/manifest.json` is
attached. Report the release URL to the user.

## Notes / gotchas

- **A failed tag build leaves the tag but no release.** Delete the tag before retrying, or the
  re-push is a no-op: `git push origin :refs/tags/vX.Y.Z && git tag -d vX.Y.Z`.
- **Don't build locally and upload by hand.** Let the tag build produce the assets; a local Spriggit
  deserialize can drift from what CI ships. Only fall back to a manual build if the user explicitly
  asks.
- Keep asset filenames exactly as CI produced them — that's what users and any install instructions
  expect.
- Publishing a release is **outward-facing and hard to reverse**. Confirm the version number and the
  asset list with the user before pushing the tag in step 5.
