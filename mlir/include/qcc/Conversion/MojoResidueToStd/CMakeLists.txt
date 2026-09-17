set(LLVM_TARGET_DEFINITIONS MojoResidueToStd.td)
mlir_tablegen(MojoResidueToStd.h.inc -gen-pass-decls -name MojoResidueToStd)
add_public_tablegen_target(MojoResidueToStdIncGen)

add_mlir_doc(MojoResidueToStd QCCMojoResidueToStd Conversions/ -gen-pass-doc)
