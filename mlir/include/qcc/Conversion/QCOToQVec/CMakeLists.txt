set(LLVM_TARGET_DEFINITIONS QCOToQVec.td)
mlir_tablegen(QCOToQVec.h.inc -gen-pass-decls -name QCOToQVec)
add_mlir_generic_tablegen_target(QCCQCOToQVecIncGen)

add_qcc_doc(QCOToQVec QCCQCOToQVec Conversions/ -gen-pass-doc)
