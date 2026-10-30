set(LLVM_TARGET_DEFINITIONS QRefDialect.td)
mlir_tablegen(QRefDialect.h.inc -gen-dialect-decls -dialect=qref)
mlir_tablegen(QRefDialect.cpp.inc -gen-dialect-defs -dialect=qref)
add_public_tablegen_target(QCCQRefDialectIncGen)

set(LLVM_TARGET_DEFINITIONS QRefOps.td)
mlir_tablegen(QRefOps.h.inc -gen-op-decls)
mlir_tablegen(QRefOps.cpp.inc -gen-op-defs)
add_public_tablegen_target(QCCQRefOpsIncGen)

add_qcc_doc(QRefOps QRefDialect Dialects/ -gen-dialect-doc -dialect=qref)
