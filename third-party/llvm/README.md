# LLVM Dependency

## QISA Support

The file `base.rev` pins the exact revision of llvm we depend on.

Conceptually backends for QISA support (like HiSEP-Q) belong into this repo.
Unfortunately developing an LLVM backend requires us to do it inside the LLVM
repository. We do this in [our own llvm
fork](https://github.com/FullStaQD/llvm-project). From there we generate patches
for LLVM which are hosted in the sub-directory `patches/qisa/`.

The simplest way to get a patched version of LLVM is to use the provided script:

```shell
# Make sure you understand what the script is doing:
cd <repo-root>
./utils/provision-llvm --help

# clone and patch LLVM
./utils/provision-llvm /path/where/to/put/llvm-project-patched
```

Now build LLVM like so:

```shell
cd /path/to/llvm-fork

# Configure. Note that HiSEP-Q is a subtarget of RISCV.
cmake -G Ninja -S llvm -B build/dev \
  -DLLVM_ENABLE_RTTI=ON \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
  -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON \
  -DCMAKE_C_COMPILER=clang \
  -DCMAKE_CXX_COMPILER=clang++ \
  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
  -DLLVM_BUILD_EXAMPLES=OFF \
  -DLLVM_ENABLE_LLD=ON \
  -DLLVM_ENABLE_PROJECTS="mlir;llvm;clang;clang-tools-extra" \
  -DLLVM_ENABLE_ASSERTIONS=ON \
  -DLLVM_INSTALL_UTILS=ON \
  -DLLVM_OPTIMIZED_TABLEGEN=ON \
  -DLLVM_TARGETS_TO_BUILD="Native;RISCV" \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo

# Build. Takes a while.
cmake --build build/dev
```

Finally make sure to use this build when building `qcc` (set `LLVM_DIR` and
`MLIR_DIR` appropriately).

## Developing QISA backends

As already pointed out development happens in our dedicated fork of LLVM. Once
you are done over there you have to update the patches over here like so:

```shell
# Open a PR, then do:
rm third-party/llvm/patches/qisa/*.patch # always remove the old ones
BASE_REV=$(cat third-party/llvm/base.rev)
git -C /path/to/llvm-fork format-patch $BASE_REV..fullstaqd-qisa \
  -o /path/to/qcc/third-party/llvm/patches/qisa
```
