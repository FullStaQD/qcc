set(LLVM_TARGET_DEFINITIONS Passes.td)
mlir_tablegen(Passes.h.inc -gen-pass-decls -name Qcc)
add_mlir_dialect_tablegen_target(QCCQccTransformsIncGen)

add_qcc_doc(Passes QCCQccTransforms Dialects/ -gen-pass-doc)
