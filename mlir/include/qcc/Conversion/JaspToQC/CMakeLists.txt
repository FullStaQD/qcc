set(LLVM_TARGET_DEFINITIONS JaspToQC.td)
mlir_tablegen(JaspToQC.h.inc -gen-pass-decls -name JaspToQC)
add_public_tablegen_target(JaspToQCIncGen)

add_qcc_doc(JaspToQC QCCJaspToQC Conversions/ -gen-pass-doc)
