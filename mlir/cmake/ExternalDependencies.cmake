include(FetchContent)
set(FETCH_PACKAGES "")

FetchContent_Declare(
  mqt-core
  GIT_REPOSITORY https://github.com/munich-quantum-toolkit/core.git
  GIT_TAG efbba8902710cebae60e865ef031df146a5868bf # Date:   Fri Sep 4 12:42:26 2026 +0200
)
list(APPEND FETCH_PACKAGES mqt-core)

FetchContent_MakeAvailable(${FETCH_PACKAGES})
