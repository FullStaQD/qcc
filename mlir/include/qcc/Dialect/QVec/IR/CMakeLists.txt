set(LLVM_TARGET_DEFINITIONS QVecDialect.td)
mlir_tablegen(QVecDialect.h.inc -gen-dialect-decls -dialect=qvec)
mlir_tablegen(QVecDialect.cpp.inc -gen-dialect-defs -dialect=qvec)
add_mlir_dialect_tablegen_target(QCCQVecDialectIncGen)

set(LLVM_TARGET_DEFINITIONS QVecEnums.td)
mlir_tablegen(QVecEnums.h.inc -gen-enum-decls)
mlir_tablegen(QVecEnums.cpp.inc -gen-enum-defs)

set(LLVM_TARGET_DEFINITIONS QVecAttrs.td)
mlir_tablegen(QVecAttrs.h.inc -gen-attrdef-decls -attrdefs-dialect=qvec)
mlir_tablegen(QVecAttrs.cpp.inc -gen-attrdef-defs -attrdefs-dialect=qvec)
add_mlir_dialect_tablegen_target(QCCQVecAttrsIncGen)

set(LLVM_TARGET_DEFINITIONS QVecOps.td)
mlir_tablegen(QVecOps.h.inc -gen-op-decls)
mlir_tablegen(QVecOps.cpp.inc -gen-op-defs)
add_mlir_dialect_tablegen_target(QCCQVecOpsIncGen)

add_qcc_doc(QVecOps QVecDialect Dialects/ -gen-dialect-doc -dialect=qvec)
