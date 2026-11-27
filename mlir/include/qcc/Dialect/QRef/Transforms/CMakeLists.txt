set(LLVM_TARGET_DEFINITIONS Passes.td)
mlir_tablegen(Passes.h.inc -gen-pass-decls -name QRef)
add_mlir_dialect_tablegen_target(QCCQRefTransformsIncGen)

add_qcc_doc(Passes QCCQRefTransforms Dialects/ -gen-pass-doc)
