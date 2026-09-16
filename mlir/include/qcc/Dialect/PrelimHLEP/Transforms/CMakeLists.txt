set(LLVM_TARGET_DEFINITIONS Passes.td)
mlir_tablegen(Passes.h.inc -gen-pass-decls -name PrelimHLEP)
add_public_tablegen_target(QCCPrelimHLEPTransformsIncGen)

add_mlir_doc(Passes QCCPrelimHLEPTransforms Dialects/ -gen-pass-doc)
