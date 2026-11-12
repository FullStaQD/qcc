cmake_minimum_required(VERSION 3.24...4.2)

project(
  qcc
  VERSION 0.1.0
  DESCRIPTION "Quantum Compiler Collection, part of FullStaQD"
  LANGUAGES C CXX)

# Pre-releases append a SemVer pre-release suffix to the version, e.g. 0.1.0-alpha.1.
set(QCC_VERSION_SUFFIX
    ""
    CACHE STRING "Suffix appended to the version, e.g. -alpha.1 (empty for a release)")
if(NOT QCC_VERSION_SUFFIX MATCHES "^(-[0-9A-Za-z-]+(\\.[0-9A-Za-z-]+)*)?$")
  message(FATAL_ERROR "QCC_VERSION_SUFFIX must be empty or a pre-release suffix like -alpha.1, "
                      "got '${QCC_VERSION_SUFFIX}'")
endif()
set(QCC_VERSION "${PROJECT_VERSION}${QCC_VERSION_SUFFIX}")

# Off by default: with the commit in --version, every new commit relinks the tools. Release builds should turn it on.
option(QCC_APPEND_VC_REV "Append the git commit to the --version output" OFF)

if(NOT DEFINED CMAKE_CXX_STANDARD OR CMAKE_CXX_STANDARD LESS 20)
  set(CMAKE_CXX_STANDARD
      20
      CACHE STRING "C++ standard to conform to")
endif()

# Generate compile_commands.json to make it easier to work with clang based tools
set(CMAKE_EXPORT_COMPILE_COMMANDS
    ON
    CACHE BOOL "Export compile commands" FORCE)

include(GNUInstallDirs)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/${CMAKE_INSTALL_BINDIR})
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/${CMAKE_INSTALL_LIBDIR})
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/${CMAKE_INSTALL_LIBDIR})

option(QCC_ENABLE_HISEPQ "Build the HiSEP-Q target" OFF)

# ExternalDependencies MUST be included before SetupMLIR. `mqt-core` calls find_package(MLIR) internally. Setting up
# MLIR here before they are done with the build would create conflicts.
include(mlir/cmake/ExternalDependencies.cmake)
include(mlir/cmake/SetupMLIR.cmake)

# The unit tests use LLVM's gtest (`llvm_gtest`). LLVM build trees provide it, LLVM installs only if LLVM was configured
# with LLVM_INSTALL_GTEST=ON.
if(TARGET llvm_gtest)
  set(QCC_INCLUDE_UNITTESTS_DEFAULT ON)
else()
  set(QCC_INCLUDE_UNITTESTS_DEFAULT OFF)
endif()
option(QCC_INCLUDE_UNITTESTS "Generate build targets for the unit tests (requires llvm_gtest)"
       ${QCC_INCLUDE_UNITTESTS_DEFAULT})
if(QCC_INCLUDE_UNITTESTS AND NOT TARGET llvm_gtest)
  message(FATAL_ERROR "QCC_INCLUDE_UNITTESTS requires llvm_gtest, which this LLVM does not provide. "
                      "Use an LLVM configured with -DLLVM_INSTALL_GTEST=ON or set -DQCC_INCLUDE_UNITTESTS=OFF.")
elseif(NOT TARGET llvm_gtest)
  message(WARNING "gtest not found, unittests will not be available")
endif()

add_subdirectory(mlir/include)

# All targets below may depend on all tablegen'd files (like clang does). Must come after mlir/include: the tablegen
# targets themselves would otherwise depend on these aggregates, which contain them.
list(APPEND LLVM_COMMON_DEPENDS mlir-headers mlir-generic-headers)

add_subdirectory(mlir/lib)
add_subdirectory(mlir/tools)

if(QCC_INCLUDE_UNITTESTS)
  add_subdirectory(mlir/unittests)
endif()

enable_testing()
add_subdirectory(mlir/test)

# To enable `cmake --install <build> --component qcc --strip --prefix <dir>`.
install(
  FILES LICENSE.txt NOTICE.txt docs/release/README.md
  DESTINATION .
  COMPONENT qcc)
install(
  FILES third-party/llvm/LICENSE.TXT
  DESTINATION third-party/llvm
  COMPONENT qcc)
# All of it, so the source of the EPL-2.0 licensed dialect definition travels with the binaries.
install(
  DIRECTORY third-party/qrisp
  DESTINATION third-party
  COMPONENT qcc)
