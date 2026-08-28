include(FetchContent)
set(FETCH_PACKAGES "")

FetchContent_Declare(
  mqt-core
  GIT_REPOSITORY https://github.com/munich-quantum-toolkit/core.git
  GIT_TAG 25b7eb8ef50db57abe0de94044821a160f384b89 # Date:   Fri Aug 28 00:41:57 2026 +0200
)
list(APPEND FETCH_PACKAGES mqt-core)

FetchContent_MakeAvailable(${FETCH_PACKAGES})
