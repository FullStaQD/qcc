set(LLVM_TARGET_DEFINITIONS QVecToMagic.td)
mlir_tablegen(QVecToMagic.h.inc -gen-pass-decls -name QVecToMagic)
add_public_tablegen_target(QCCQVecToMagicIncGen)

add_qcc_doc(QVecToMagic QCCQVecToMagic Conversions/ -gen-pass-doc)
