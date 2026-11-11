include(FetchContent)
set(FETCH_PACKAGES "")

FetchContent_Declare(
  mqt-core
  GIT_REPOSITORY https://github.com/munich-quantum-toolkit/core.git
  GIT_TAG ff81ba313ffc5cb27cff5bd6e2edbebf1d65cc29 # Date:   Fri Sep 4 18:44:59 2026 +0200
)
list(APPEND FETCH_PACKAGES mqt-core)

FetchContent_MakeAvailable(${FETCH_PACKAGES})

# qcc only depends on the aggregate header targets (see top-level CMakeLists.txt), but mqt-core's pass declarations are
# in none of them. Add the ones we include.
add_dependencies(mlir-headers QCToQCOIncGen)
