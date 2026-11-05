set(LLVM_TARGET_DEFINITIONS HLEPDialect.td)
mlir_tablegen(HLEPDialect.h.inc -gen-dialect-decls)
mlir_tablegen(HLEPDialect.cpp.inc -gen-dialect-defs)
add_public_tablegen_target(QCCHLEPDialectIncGen)

set(LLVM_TARGET_DEFINITIONS HLEPTypes.td)
mlir_tablegen(HLEPTypes.h.inc -gen-typedef-decls --typedefs-dialect=hlep)
mlir_tablegen(HLEPTypes.cpp.inc -gen-typedef-defs --typedefs-dialect=hlep)
add_public_tablegen_target(QCCHLEPTypesIncGen)

set(LLVM_TARGET_DEFINITIONS HLEPAttrs.td)
mlir_tablegen(HLEPAttrs.h.inc -gen-attrdef-decls --attrdefs-dialect=hlep)
mlir_tablegen(HLEPAttrs.cpp.inc -gen-attrdef-defs --attrdefs-dialect=hlep)
add_public_tablegen_target(QCCHLEPAttrsIncGen)

set(LLVM_TARGET_DEFINITIONS HLEPInterfaces.td)
mlir_tablegen(HLEPInterfaces.h.inc -gen-op-interface-decls)
mlir_tablegen(HLEPInterfaces.cpp.inc -gen-op-interface-defs)
add_public_tablegen_target(QCCHLEPInterfacesIncGen)

set(LLVM_TARGET_DEFINITIONS HLEPOps.td)
mlir_tablegen(HLEPOps.h.inc -gen-op-decls)
mlir_tablegen(HLEPOps.cpp.inc -gen-op-defs)
add_public_tablegen_target(QCCHLEPOpsIncGen)
