# qcc

qcc compiles quantum programs from [Qrisp](https://qrisp.eu) to [QIR](https://www.qir-alliance.org) and to native code
for [HiSEP-Q](https://github.com/caps-tum/HiSEP-Q-2.0). It is part of the FullStaQD project. Source code and issues:
<https://github.com/FullStaQD/qcc>.

**This is an alpha release.** The command line and archive layout is not stable and may change in any release. Pin the
exact version and the SHA-256 of the archive.

## Requirements

- Linux with glibc 2.28 or newer (RHEL/AlmaLinux/Rocky 8+, Debian 10+, Ubuntu 20.04+, Fedora 29+) on x86_64 or aarch64.
- For HiSEP-Q only: a RISC-V capable linker such as `ld.lld`. The archive does not include one.

On Windows, use WSL2. On other platforms, build qcc from source.

## Install

Download the archive for your architecture and `SHA256SUMS` from the release page, check the archive, and unpack it
anywhere:

```sh
sha256sum -c SHA256SUMS --ignore-missing
tar -xzf qcc-<version>-linux-<arch>.tar.gz
```

Optionally check that GitHub Actions built the archive from the qcc repository (needs the GitHub CLI):

```sh
gh attestation verify qcc-<version>-linux-<arch>.tar.gz --repo FullStaQD/qcc
```

The download URL `https://github.com/FullStaQD/qcc/releases/download/v<version>/qcc-<version>-linux-<arch>.tar.gz` and
the path `qcc-<version>-linux-<arch>/bin/qcc` inside the archive stay stable (or we announce changes), so scripts can
rely on them. Use exact versions: `releases/latest` skips pre-releases.

## Usage

Compile Qrisp's `jasp` MLIR to QIR:

```sh
qcc input.mlir -o output.ll
```

See `qcc --help` for all options.

## Reporting problems

Open an issue at <https://github.com/FullStaQD/qcc/issues> with the output of `qcc --version`, the full command, and
the input file.

## License

qcc is licensed under the Apache License v2.0 with LLVM Exceptions, see `LICENSE.txt` and `NOTICE.txt`. The binaries
contain third-party code under its own license, see `third-party/`:

- LLVM and MLIR: Apache License v2.0 with LLVM Exceptions
- MQT Core: MIT License
- The Qrisp `jasp` dialect definition: Eclipse Public License 2.0, source included
