set(LLVM_TARGET_DEFINITIONS JaspToQRef.td)
mlir_tablegen(JaspToQRef.h.inc -gen-pass-decls -name JaspToQRef)
add_mlir_generic_tablegen_target(QCCJaspToQRefIncGen)

add_qcc_doc(JaspToQRef QCCJaspToQRef Conversions/ -gen-pass-doc)
