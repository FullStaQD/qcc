if(DEFINED ENV{LLVM_EXTERNAL_LIT} AND NOT DEFINED LLVM_EXTERNAL_LIT)
  set(LLVM_EXTERNAL_LIT
      $ENV{LLVM_EXTERNAL_LIT}
      CACHE STRING "")
endif()

find_package(MLIR REQUIRED CONFIG)

message(STATUS "Using MLIRConfig.cmake in: ${MLIR_DIR}")
message(STATUS "Using LLVMConfig.cmake in: ${LLVM_DIR}")

list(APPEND CMAKE_MODULE_PATH "${MLIR_CMAKE_DIR}")
list(APPEND CMAKE_MODULE_PATH "${LLVM_CMAKE_DIR}")

include(TableGen)
include(AddLLVM)
include(AddMLIR)
include(${CMAKE_CURRENT_LIST_DIR}/AddQCCDoc.cmake)

include_directories(SYSTEM ${LLVM_INCLUDE_DIRS} ${MLIR_INCLUDE_DIRS})
include_directories(${PROJECT_SOURCE_DIR}/mlir/include)
include_directories(${PROJECT_BINARY_DIR}/mlir/include)
