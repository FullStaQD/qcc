set(LLVM_TARGET_DEFINITIONS QCToQRef.td)
mlir_tablegen(QCToQRef.h.inc -gen-pass-decls -name QCToQRef)
add_public_tablegen_target(QCCQCToQRefIncGen)

add_qcc_doc(QCToQRef QCCQCToQRef Conversions/ -gen-pass-doc)
