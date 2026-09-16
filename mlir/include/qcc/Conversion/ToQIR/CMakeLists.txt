set(LLVM_TARGET_DEFINITIONS ToQIR.td)
mlir_tablegen(ToQIR.h.inc -gen-pass-decls -name ToQIR)
add_public_tablegen_target(QCCToQIRIncGen)

add_qcc_doc(ToQIR QCCToQIR Conversions/ -gen-pass-doc)
