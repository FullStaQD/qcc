set(LLVM_TARGET_DEFINITIONS Passes.td)
mlir_tablegen(Passes.h.inc -gen-pass-decls -name QCO)
add_public_tablegen_target(QCCQCOTransformsIncGen)

add_mlir_doc(Passes QCCQCOTransforms Dialects/ -gen-pass-doc)
