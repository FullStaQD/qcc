set(LLVM_TARGET_DEFINITIONS AffineRaise.td)
mlir_tablegen(AffineRaise.h.inc -gen-pass-decls -name AffineRaise)
add_public_tablegen_target(QCCAffineRaiseIncGen)

add_mlir_doc(AffineRaise QCCAffineRaise Conversions/ -gen-pass-doc)
