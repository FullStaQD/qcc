set(LLVM_TARGET_DEFINITIONS QCircDialect.td)
mlir_tablegen(QCircDialect.h.inc -gen-dialect-decls -dialect=qcirc)
mlir_tablegen(QCircDialect.cpp.inc -gen-dialect-defs -dialect=qcirc)
add_public_tablegen_target(QCCQCircDialectIncGen)

set(LLVM_TARGET_DEFINITIONS QCircEnums.td)
mlir_tablegen(QCircEnums.h.inc -gen-enum-decls)
mlir_tablegen(QCircEnums.cpp.inc -gen-enum-defs)

set(LLVM_TARGET_DEFINITIONS QCircAttrs.td)
mlir_tablegen(QCircAttrs.h.inc -gen-attrdef-decls -attrdefs-dialect=qcirc)
mlir_tablegen(QCircAttrs.cpp.inc -gen-attrdef-defs -attrdefs-dialect=qcirc)
add_public_tablegen_target(QCCQCircAttrsIncGen)

set(LLVM_TARGET_DEFINITIONS QCircOps.td)
mlir_tablegen(QCircOps.h.inc -gen-op-decls)
mlir_tablegen(QCircOps.cpp.inc -gen-op-defs)
add_public_tablegen_target(QCCQCircOpsIncGen)

add_qcc_doc(QCircOps QCircDialect Dialects/ -gen-dialect-doc -dialect=qcirc)
