set(LLVM_TARGET_DEFINITIONS QCircToQVec.td)
mlir_tablegen(QCircToQVec.h.inc -gen-pass-decls -name QCircToQVec)
add_public_tablegen_target(QCCQCircToQVecIncGen)

add_qcc_doc(QCircToQVec QCCQCircToQVec Conversions/ -gen-pass-doc)
