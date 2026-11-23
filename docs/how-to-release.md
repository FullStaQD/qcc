# How to release qcc

## Overview

A qcc release is a GitHub release with prebuilt archives for supported platforms, a `SHA256SUMS` file, and build
attestations for the archives. Pushing a tag `v<version>` starts the release workflow `.github/workflows/release.yml`.
It creates a draft release, which a maintainer then publishes by hand.

Release tags are protected by a ruleset. Only maintainers can create, move, or delete `v*` tags.

## Versioning

The version of QCC is given by `VERSION` in `project()` in the top-level `CMakeLists.txt`. It is of the form `X.Y.Z`.
Each release commit should be tagged with `v<VERSION>`. For pre-releases use `v<VERSION>-<suffix>` (which are sorted
before `v<VERSION>`). The release workflow rejects any other tags of the form `v*`.

After releasing `X.Y.Z`, bump `VERSION` on main to `X.Y.(Z+1)`, so that dev builds report `X.Y.(Z+1)-dev`, which SemVer
orders after the release. Decide on the actual version when preparing the next release: keep `X.Y.(Z+1)` if only fixes
have landed, or raise it to `X.(Y+1).0` for notable or breaking changes.

TODO: Remove this TODO once `0.1.0` is released. Until then we are in the alpha phase: we want people to try qcc while
the release process and the archive layout are still settling. In this phase the rules above are overridden: releases
are pre-releases `0.1.0-alpha.<n>`, `VERSION` stays at `0.1.0`, and there is no bump after a release. The alpha phase
ends with the release of `0.1.0`, after which main moves on to `0.1.1` as described above.

## Releasing

0. Read this file and the [release files README](../utils/release/README.md) completely.
1. In a PR, decide on `VERSION` (see [Versioning](#versioning)) and update the release files under `utils/release/` if
   necessary.
2. Check that CI passed on the commit you want to release.
3. Optionally, do a [dry run](#dry-runs). This also ensures the cache is warm for the real release.
4. Tag the commit and push the tag:

   ```sh
   # Possible versions: 0.1.0 (release), 0.1.0-alpha.1 (pre-release)
   git tag v<version> <commit>
   git push origin v<version>
   ```

5. Wait for the "Release" workflow to finish, then inspect the draft release (either via UI or `gh` CLI): Check the
   files (one archive per architecture and `SHA256SUMS`) and the release notes. Check the release like a user would,
   following the README inside each archive.
6. Publish it either via GitHub UI or via `gh release edit v<version> --draft=false`.
7. Bump `VERSION` on main in a PR, see [Versioning](#versioning).

### If something goes wrong

Before publishing, delete the draft release and the tag (`git push --delete origin v<version>`), fix the problem, and
tag again. Once published, never move or delete the tag, since users and scripts rely on it. Release the next version
instead, see [Versioning](#versioning).

## Dry runs

The workflow also runs without a tag: manually (`gh workflow run release.yml --ref main`, or "Run workflow" on the
Actions page), on pushes to main that change `third-party/llvm/` or `release.yml`, and twice a week on a schedule. Dry
runs create no release, the archives become workflow artifacts. The scheduled runs keep the LLVM cache of main from
being evicted. This matters because a tag run can only use the caches of main and of its own tag.

## Maintenance

- The archives contain everything installed with `COMPONENT qcc`, among it `utils/release/archive-readme.md` as
  `README.md`. That README promises that the download URL and the path of `bin/qcc` in the archive stay stable, hence
  announce changes to them.
- Bump `LLVM_CACHE_VERSION` in `release.yml` when the LLVM CMake flags there change. The cache key only tracks the LLVM
  revision, the patches, and the manylinux image.
