set(LLVM_TARGET_DEFINITIONS Passes.td)
mlir_tablegen(Passes.h.inc -gen-pass-decls -name QCirc)
add_mlir_dialect_tablegen_target(QCCQCircTransformsIncGen)

add_qcc_doc(Passes QCCQCircTransforms Dialects/ -gen-pass-doc)
