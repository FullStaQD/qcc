set(LLVM_TARGET_DEFINITIONS Passes.td)
mlir_tablegen(Passes.h.inc -gen-pass-decls -name QVec)
add_public_tablegen_target(QCCQVecTransformsIncGen)

add_mlir_doc(Passes QCCQVecTransforms Dialects/ -gen-pass-doc)
