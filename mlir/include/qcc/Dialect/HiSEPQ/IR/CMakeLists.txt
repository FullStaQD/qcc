# `HiSEPQTypes.td` includes mqt-core's `QCOTypes.td`, which is not on TableGen's default search path.
list(APPEND LLVM_TABLEGEN_FLAGS -I ${mqt-core_SOURCE_DIR}/mlir/include)

set(LLVM_TARGET_DEFINITIONS HiSEPQDialect.td)
mlir_tablegen(HiSEPQDialect.h.inc -gen-dialect-decls -dialect=hisepq)
mlir_tablegen(HiSEPQDialect.cpp.inc -gen-dialect-defs -dialect=hisepq)
add_public_tablegen_target(QCCHiSEPQDialectIncGen)

set(LLVM_TARGET_DEFINITIONS HiSEPQAttrs.td)
mlir_tablegen(HiSEPQEnums.h.inc -gen-enum-decls)
mlir_tablegen(HiSEPQEnums.cpp.inc -gen-enum-defs)
mlir_tablegen(HiSEPQAttrs.h.inc -gen-attrdef-decls -attrdefs-dialect=hisepq)
mlir_tablegen(HiSEPQAttrs.cpp.inc -gen-attrdef-defs -attrdefs-dialect=hisepq)
add_public_tablegen_target(QCCHiSEPQAttrsIncGen)

set(LLVM_TARGET_DEFINITIONS HiSEPQOps.td)
mlir_tablegen(HiSEPQOps.h.inc -gen-op-decls)
mlir_tablegen(HiSEPQOps.cpp.inc -gen-op-defs)
add_public_tablegen_target(QCCHiSEPQOpsIncGen)
