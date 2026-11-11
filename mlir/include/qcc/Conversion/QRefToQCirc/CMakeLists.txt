set(LLVM_TARGET_DEFINITIONS QRefToQCirc.td)
mlir_tablegen(QRefToQCirc.h.inc -gen-pass-decls -name QRefToQCirc)
add_mlir_generic_tablegen_target(QCCQRefToQCircIncGen)

add_qcc_doc(QRefToQCirc QCCQRefToQCirc Conversions/ -gen-pass-doc)
