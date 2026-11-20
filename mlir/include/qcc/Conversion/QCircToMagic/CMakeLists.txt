set(LLVM_TARGET_DEFINITIONS QCircToMagic.td)
mlir_tablegen(QCircToMagic.h.inc -gen-pass-decls -name QCircToMagic)
add_mlir_generic_tablegen_target(QCCQCircToMagicIncGen)

add_qcc_doc(QCircToMagic QCCQCircToMagic Conversions/ -gen-pass-doc)
