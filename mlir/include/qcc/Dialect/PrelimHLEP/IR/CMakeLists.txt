set(LLVM_TARGET_DEFINITIONS PrelimHLEPDialect.td)
mlir_tablegen(PrelimHLEPDialect.h.inc -gen-dialect-decls)
mlir_tablegen(PrelimHLEPDialect.cpp.inc -gen-dialect-defs)
add_public_tablegen_target(QCCPrelimHLEPDialectIncGen)

set(LLVM_TARGET_DEFINITIONS PrelimHLEPTypes.td)
mlir_tablegen(PrelimHLEPTypes.h.inc -gen-typedef-decls --typedefs-dialect=prelimhlep)
mlir_tablegen(PrelimHLEPTypes.cpp.inc -gen-typedef-defs --typedefs-dialect=prelimhlep)
add_public_tablegen_target(QCCPrelimHLEPTypesIncGen)

set(LLVM_TARGET_DEFINITIONS PrelimHLEPAttrs.td)
mlir_tablegen(PrelimHLEPAttrs.h.inc -gen-attrdef-decls --attrdefs-dialect=prelimhlep)
mlir_tablegen(PrelimHLEPAttrs.cpp.inc -gen-attrdef-defs --attrdefs-dialect=prelimhlep)
add_public_tablegen_target(QCCPrelimHLEPAttrsIncGen)

set(LLVM_TARGET_DEFINITIONS PrelimHLEPOps.td)
mlir_tablegen(PrelimHLEPOps.h.inc -gen-op-decls)
mlir_tablegen(PrelimHLEPOps.cpp.inc -gen-op-defs)
add_public_tablegen_target(QCCPrelimHLEPOpsIncGen)
