set(LLVM_TARGET_DEFINITIONS OQ3Dialect.td)
mlir_tablegen(OQ3Dialect.h.inc -gen-dialect-decls -dialect=oq3)
mlir_tablegen(OQ3Dialect.cpp.inc -gen-dialect-defs -dialect=oq3)
add_public_tablegen_target(QCCOQ3DialectIncGen)

set(LLVM_TARGET_DEFINITIONS OQ3Enums.td)
mlir_tablegen(OQ3Enums.h.inc -gen-enum-decls)
mlir_tablegen(OQ3Enums.cpp.inc -gen-enum-defs)

set(LLVM_TARGET_DEFINITIONS OQ3Attrs.td)
mlir_tablegen(OQ3Attrs.h.inc -gen-attrdef-decls -attrdefs-dialect=oq3)
mlir_tablegen(OQ3Attrs.cpp.inc -gen-attrdef-defs -attrdefs-dialect=oq3)
add_public_tablegen_target(QCCOQ3AttrsIncGen)

set(LLVM_TARGET_DEFINITIONS OQ3Types.td)
mlir_tablegen(OQ3Types.h.inc -gen-typedef-decls -typedefs-dialect=oq3)
mlir_tablegen(OQ3Types.cpp.inc -gen-typedef-defs -typedefs-dialect=oq3)
add_public_tablegen_target(QCCOQ3TypesIncGen)

set(LLVM_TARGET_DEFINITIONS OQ3Ops.td)
mlir_tablegen(OQ3Ops.h.inc -gen-op-decls)
mlir_tablegen(OQ3Ops.cpp.inc -gen-op-defs)
add_public_tablegen_target(QCCOQ3OpsIncGen)

add_qcc_doc(OQ3Ops OQ3Dialect Dialects/ -gen-dialect-doc -dialect=oq3)
