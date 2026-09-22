set(LLVM_TARGET_DEFINITIONS MagicDialect.td)
mlir_tablegen(MagicDialect.h.inc -gen-dialect-decls -dialect=magic)
mlir_tablegen(MagicDialect.cpp.inc -gen-dialect-defs -dialect=magic)
add_public_tablegen_target(QCCMagicDialectIncGen)

set(LLVM_TARGET_DEFINITIONS MagicTypes.td)
mlir_tablegen(MagicTypes.h.inc -gen-typedef-decls -typedefs-dialect=magic)
mlir_tablegen(MagicTypes.cpp.inc -gen-typedef-defs -typedefs-dialect=magic)
add_public_tablegen_target(QCCMagicTypesIncGen)

set(LLVM_TARGET_DEFINITIONS MagicOps.td)
mlir_tablegen(MagicOps.h.inc -gen-op-decls)
mlir_tablegen(MagicOps.cpp.inc -gen-op-defs)
add_public_tablegen_target(QCCMagicOpsIncGen)

add_qcc_doc(MagicOps MagicDialect Dialects/ -gen-dialect-doc -dialect=magic)
