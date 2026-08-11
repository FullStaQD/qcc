<div align="center">
  <img src="https://img.shields.io/badge/Status-Early_Development-red?style=for-the-badge" alt="Early Development">
</div>

---

### **⚠️ Notice: Early Development Phase**

This project is currently in its **infant stages**, so we are keeping things "in-house" for now while we find our footing.

- **No External PRs:** We aren't accepting outside contributions just yet.
- **Coming Soon:** We plan to open the gates to the community once the foundation is solid.

**Stay tuned—we'd love your help later!**

---

# Compiler

The structure of the project follows that of standard MLIR compilers.
The root directory is `mlir`, which contains all the source code.
The tool that is generated is called `qcc-opt`.

---

## Getting Started

### Option 1: Dev Container (Recommended)

The easiest way to get started is via the provided [devcontainer](https://containers.dev), which automatically installs all dependencies including LLVM/MLIR.
This requires [docker](https://www.docker.com/) to be installed on the host.
Various IDEs support support the standard, e.g.:

- vscode: via [Dev Containers](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers) extension.
- jetbrains IDEs: See e.g. [here](https://www.jetbrains.com/help/idea/connect-to-devcontainer.html).

There is also a [dev container cli](https://github.com/devcontainers/cli) which can be used alongside IDE integrations.

For advanced users: put your own local `devcontainer.json` under `.devcontainer/local/` (gitignored).
IDEs and the cli should provide you with a way to choose which config you want to use.
For advanced users: put your own local `devcontainer.json` under `.devcontainer/local/` (gitignored).
IDEs and the cli should provide you with a way to choose which config you want to use.

### Option 2: Manual Setup

If you prefer to build outside the container, you need LLVM/MLIR version >= [VERSION_USED_BY_DEVCONTAINER_IMAGE](.devcontainer/Dockerfile) installed. If you have no previous installation, check the guide [here](https://mqt.readthedocs.io/projects/core/en/latest/installation.html#setting-up-mlir).

We also recommend to [install](https://docs.astral.sh/uv/getting-started/installation/) `uv`.

---

## Coding agents

Project-wide guidance for AI coding agents lives in [AGENTS.md](AGENTS.md).
See [agents.md](https://agents.md).
Developers may keep their own personal, tool-specific customization files
(e.g. `CLAUDE.md`); these are gitignored and not part of the project.

We try to keep the file lean and focussed on the essentials.
Some studies suggest that too much context degrades agent performance.

---

## Building

If you are using a devcontainer, configure the project like so:

```shell
 cmake --preset dev
 # You can also override variables, here an example for the case if the lit tool (testing) is not found:
 cmake --preset dev -DLLVM_EXTERNAL_LIT=$(which lit)
```

This uses [cmake presets](https://cmake.org/cmake/help/latest/manual/cmake-presets.7.html).
You might want to create your own `CMakeUserPresets.json` (it is under gitignore).
On the other hand, if you manually installed LLVM and MLIR, run:

```shell
cmake -S . -B build/dev -G Ninja \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DMLIR_DIR=path/to/mlir/installation/dir \
  -DLLVM_DIR=/path/to/llvm/installation/dir \
  -DLLVM_EXTERNAL_LIT=$(which lit)
```

Then build the project like so:

```shell
# With presets:
cmake --build --preset dev
# Or if you do not like presets:
cmake --build build/dev
```

> [!NOTE]
>
> If you are not using a single-config generator (such as when using MSVC on Windows), you need to specify the build configuration explicitly for the build command:

### Post build verification

To make sure that the build procedure worked correctly, run the following:

```shell
./build/dev/bin/qcc-opt mlir/test/tools/qcc-opt/mqt-core-integration-test.mlir
```

and it should output some plain MLIR source.

### Support for Quantum ISAs

By default `qcc` is build with support for QIR _only_. Support for a proper
Quantum ISA (QISA) as `--target` can be accomplished by setting the cmake option
`QCC_ENABLE_HISEPQ=ON` (for HiSEP-Q in this case). This however needs a patched
LLVM. So in order to work with that you should be willing to build LLVM from
source. Details on what to do exactly can be found in
[third-party/llvm/](./third-party/llvm/README.md).

---

## Testing

Run the tests like so:

```shell
# Rebuilds and runs all tests:
cmake --build build/dev --target check-qcc

# Run specific tests (filters by filename):
lit build/dev/mlir/test/ -v --filter "convert"
```

---

## Language server

If you use VSCode and would like to enable the custom MLIR LSP server including quantum dialects, add this line to your
settings:

```
"mlir.server_path": "build/dev/bin/qcc-lsp-server"
```

---

## License

QCC is licensed under the Apache License v2.0 with LLVM Exceptions; see
[`LICENSE.txt`](LICENSE.txt).

Third-party components live under `third-party/`, and each subdirectory's
`README.md` records its provenance and license if relevant. When a component is
distributed under a different license, its full text is shipped alongside it —
for example [`third-party/qrisp/`](third-party/qrisp/) (EPL-2.0).

### License headers

The license headers in this repository are managed using the [`license-eye`](https://github.com/apache/skywalking-eyes) tool.

```shell
# Install (for the right version see the CI):
apt-get install golang-go # on ubuntu
GOPATH=/usr/local go install github.com/apache/skywalking-eyes/cmd/license-eye@v0.8.0

# Basic usage:
license-eye header check
license-eye header fix
```

The license headers are checked by a GitHub Actions workflow.
If the workflow fails in a PR, run the command above.
Alternatively, copy the license header from another file.
