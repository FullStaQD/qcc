# How to release qcc

A qcc release is a GitHub release with prebuilt archives for Linux on x86_64 and aarch64, a `SHA256SUMS` file, and
build attestations for the archives. Pushing a tag `v<version>` starts the release workflow
`.github/workflows/release.yml`. It builds and tests the archives, smoke-tests them on AlmaLinux 8, and creates a draft
release, which a maintainer then publishes by hand. The comments in `release.yml` explain the technical details.

The release files besides the binaries live in `utils/release/`. Only those allowed to bypass the `release-tags`
ruleset (repository settings, Rules) can create, move, or delete `v*` tags.

## Versions

The version is `VERSION` in `project()` in the top-level `CMakeLists.txt`. The tag is `v<version>` for a release, or
`v<version>-<suffix>` with a SemVer pre-release suffix such as `-alpha.1` for a pre-release. The workflow rejects other
tags before it builds anything, and marks pre-releases as such on GitHub. Runs without a tag use the suffix `-dev`.

TODO: Decide when to bump `VERSION`. Dry runs of main build `<version>-dev`, which SemVer orders before `<version>`,
hence after a final release main should move on to the next version.

## Releasing

1. Update `utils/release/release-notes.md`, and `VERSION` if needed, in a PR and merge it. The workflow reads the notes
   from the tagged commit.
2. Check that CI and QISA CI passed on the commit to tag. The release workflow skips the tests that execute QIR or need
   `lld` or the HiSEP-Q simulator, QISA CI runs them.
3. Optionally, try the archives of a [dry run](#dry-runs) of main. It also makes sure that LLVM is cached: with it a run
   takes about 15 minutes, without it the run first builds LLVM for about 3 hours.
4. Tag the commit and push the tag:

   ```sh
   git tag v<version> <commit>
   git push origin v<version>
   ```

5. Wait for the "Release" workflow to finish, then open the draft on the releases page. Check the files (one archive per
   architecture and `SHA256SUMS`), the text, and the pre-release flag, then publish it.
6. Check the release like a user would, following `utils/release/archive-readme.md`.

### If something goes wrong

Before publishing, delete the draft release and the tag (`git push --delete origin v<version>`), fix the problem, and
tag again. Once published, never move or delete the tag, since users and scripts rely on it. Release a new version
instead, e.g. the next `-alpha.<n>`.

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
