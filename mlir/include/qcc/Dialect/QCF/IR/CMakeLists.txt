set(LLVM_TARGET_DEFINITIONS QCFDialect.td)
mlir_tablegen(QCFDialect.h.inc -gen-dialect-decls -dialect=qcf)
mlir_tablegen(QCFDialect.cpp.inc -gen-dialect-defs -dialect=qcf)
add_public_tablegen_target(QCCQCFDialectIncGen)

set(LLVM_TARGET_DEFINITIONS QCFOps.td)
mlir_tablegen(QCFOps.h.inc -gen-op-decls)
mlir_tablegen(QCFOps.cpp.inc -gen-op-defs)
add_public_tablegen_target(QCCQCFOpsIncGen)

add_qcc_doc(QCFOps QCFDialect Dialects/ -gen-dialect-doc -dialect=qcf)
