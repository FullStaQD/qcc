set(LLVM_TARGET_DEFINITIONS ToHiSEPQ.td)
mlir_tablegen(ToHiSEPQ.h.inc -gen-pass-decls -name ToHiSEPQ)
add_public_tablegen_target(QCCToHiSEPQIncGen)

add_mlir_doc(ToHiSEPQ QCCToHiSEPQ Conversions/ -gen-pass-doc)
