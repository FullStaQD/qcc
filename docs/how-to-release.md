# How to release qcc

## Overview

A qcc release is a GitHub release with prebuilt archives for supported platforms, a `SHA256SUMS` file, and build
attestations for the archives. Pushing a tag `v<version>` starts the release workflow `.github/workflows/release.yml`.
It creates a draft release, which a maintainer then publishes by hand.

Release tags are protected by a ruleset. Only maintainers can create, move, or delete `v*` tags.

## Versioning

The version of QCC is given by `VERSION` in `project()` in the top-level `CMakeLists.txt`. It is of the form `X.Y.Z`.
Each release commit should be tagged with `v<VERSION>`. For pre-releases use `v<VERSION>-<suffix>` (which SemVer orders
before `v<VERSION>`). The release workflow rejects any other tags of the form `v*`. In this file, `<version>` is
`VERSION` plus the suffix, if any.

After releasing `X.Y.Z`, bump `VERSION` on `main` to `X.Y.(Z+1)`, so that dev builds report `X.Y.(Z+1)-dev`, which
SemVer orders after the release. Decide on the actual version when preparing the next release: keep `X.Y.(Z+1)` if only
fixes have landed, or raise it to `X.(Y+1).0` for notable or breaking changes.

TODO: Remove this TODO once `0.1.0` is released. Until then we are in the alpha phase: we want people to try qcc while
the release process and the archive layout are still settling. In this phase the rules above are overridden: releases
are pre-releases `0.1.0-alpha.<n>`, `VERSION` stays at `0.1.0`, and there is no bump after a release. The alpha phase
ends with the release of `0.1.0`, after which `main` moves on to `0.1.1` as described above. For `0.1.0`, also remove
the alpha wording from `utils/release/archive-readme.md` and `utils/release/release-notes.md`.

## Releasing

0. Read this file and the [release files README](../utils/release/README.md) completely.
1. In a PR, decide on `VERSION` (see [Versioning](#versioning)) and update the release files under `utils/release/` if
   necessary.
2. Check that CI passed on the commit you want to release.
3. Optionally, do a [dry run](#dry-runs). It also warms the LLVM cache for the release.
4. Tag the commit and push the tag:

   ```sh
   # Possible versions: 0.1.0 (release), 0.1.0-alpha.1 (pre-release)
   git tag v<version> <commit>
   git push origin v<version>
   ```

5. Wait for the "Release" workflow to finish, then check the draft release: its files (one archive per architecture and
   `SHA256SUMS`) and release notes. Try the archives like a user would, following the README inside them.
6. Publish it in the GitHub UI or with `gh release edit v<version> --draft=false`.
7. Bump `VERSION` on `main` in a PR, see [Versioning](#versioning).

### If something goes wrong

Before publishing, delete the draft release and the tag (`git push --delete origin v<version>`), fix the problem, and
tag again. Once published, never move or delete the tag, since users and scripts rely on it. Release the next version
instead, see [Versioning](#versioning).

## Dry runs

The release workflow also runs without a tag (but doesn't create a draft release): manually (`gh workflow run
release.yml --ref main`, or "Run workflow" on the Actions page), on pushes to `main` that change `third-party/llvm/` or
`release.yml`, and twice a week on a schedule. The scheduled runs keep the LLVM cache of `main` from being evicted.
