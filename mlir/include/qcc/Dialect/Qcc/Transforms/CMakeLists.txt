set(LLVM_TARGET_DEFINITIONS Passes.td)
mlir_tablegen(Passes.h.inc -gen-pass-decls -name Qcc)
add_public_tablegen_target(QCCQccTransformsIncGen)

add_qcc_doc(Passes QCCQccTransforms Dialects/ -gen-pass-doc)
