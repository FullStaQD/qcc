# Like upstream's test dialect, this one has no headers under `mlir/include`: sources and generated files sit here.
include_directories(${CMAKE_CURRENT_SOURCE_DIR} ${CMAKE_CURRENT_BINARY_DIR})

set(LLVM_TARGET_DEFINITIONS TestDialect.td)
mlir_tablegen(TestDialect.h.inc -gen-dialect-decls)
mlir_tablegen(TestDialect.cpp.inc -gen-dialect-defs)
add_public_tablegen_target(QCCTestDialectIncGen)

set(LLVM_TARGET_DEFINITIONS TestOps.td)
mlir_tablegen(TestOps.h.inc -gen-op-decls)
mlir_tablegen(TestOps.cpp.inc -gen-op-defs)
add_public_tablegen_target(QCCTestOpsIncGen)

# Not `add_mlir_dialect_library`: that would list it in MLIR_DIALECT_LIBS, which `qcc` links in full.
add_mlir_library(
  QCCTestDialect
  TestDialect.cpp
  DEPENDS
  QCCTestDialectIncGen
  QCCTestOpsIncGen
  LINK_LIBS
  PUBLIC
  MLIRIR
  MLIRSupport)
