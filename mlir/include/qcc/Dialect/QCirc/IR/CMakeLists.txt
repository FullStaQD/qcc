set(LLVM_TARGET_DEFINITIONS QCircDialect.td)
mlir_tablegen(QCircDialect.h.inc -gen-dialect-decls -dialect=qcirc)
mlir_tablegen(QCircDialect.cpp.inc -gen-dialect-defs -dialect=qcirc)
add_public_tablegen_target(QCCQCircDialectIncGen)

set(LLVM_TARGET_DEFINITIONS QCircOps.td)
mlir_tablegen(QCircOps.h.inc -gen-op-decls)
mlir_tablegen(QCircOps.cpp.inc -gen-op-defs)
add_public_tablegen_target(QCCQCircOpsIncGen)

add_qcc_doc(QCircOps QCircDialect Dialects/ -gen-dialect-doc -dialect=qcirc)
