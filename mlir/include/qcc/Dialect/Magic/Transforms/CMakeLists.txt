set(LLVM_TARGET_DEFINITIONS Passes.td)
mlir_tablegen(Passes.h.inc -gen-pass-decls -name Magic)
add_public_tablegen_target(QCCMagicTransformsIncGen)

add_qcc_doc(Passes QCCMagicTransforms Dialects/ -gen-pass-doc)
