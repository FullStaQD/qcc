set(LLVM_TARGET_DEFINITIONS Passes.td)
mlir_tablegen(Passes.h.inc -gen-pass-decls -name HiSEPQ)
add_public_tablegen_target(QCCHiSEPQTransformsIncGen)

add_mlir_doc(Passes QCCHiSEPQTransforms Dialects/ -gen-pass-doc)
