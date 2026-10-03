set(LLVM_TARGET_DEFINITIONS PrelimHLEPToQCO.td)
mlir_tablegen(PrelimHLEPToQCO.h.inc -gen-pass-decls -name PrelimHLEPToQCO)
add_public_tablegen_target(PrelimHLEPToQCOIncGen)

add_mlir_doc(PrelimHLEPToQCO QCCPrelimHLEPToQCO Conversions/ -gen-pass-doc)
