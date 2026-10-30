set(LLVM_TARGET_DEFINITIONS QCircToQRef.td)
mlir_tablegen(QCircToQRef.h.inc -gen-pass-decls -name QCircToQRef)
add_public_tablegen_target(QCCQCircToQRefIncGen)

add_qcc_doc(QCircToQRef QCCQCircToQRef Conversions/ -gen-pass-doc)
