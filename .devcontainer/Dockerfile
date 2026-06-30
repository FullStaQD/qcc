FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# Installs the basic underlying framework
RUN apt-get -y update && \
  apt-get install -y --no-install-recommends clang clang-tools clangd lld curl ca-certificates zstd git gcc g++

# Copy uv and uvx binaries from the official image and make them accessible to all users
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

# Store tool binaries and environments in system-wide locations
ENV UV_TOOL_BIN_DIR=/usr/local/bin
ENV UV_TOOL_DIR=/opt/uv/tools

# Install the latest versions of cmake, ninja, lit, and prek as tools
RUN uv tool install cmake && \
  uv tool install ninja && \
  uv tool install lit && \
  uv tool install prek && \
  uv tool install qirrunner

# Downloads and installs a prebuilt LLVM/MLIR toolchain for the current OS and architecture. Uses `zstd`.
RUN curl -LsSf https://github.com/munich-quantum-software/setup-mlir/releases/latest/download/setup-mlir.sh \
  | bash -s -- -v 22.1.7 -p /opt/llvm
