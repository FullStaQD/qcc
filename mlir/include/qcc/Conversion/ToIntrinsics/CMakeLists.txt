set(LLVM_TARGET_DEFINITIONS ToIntrinsics.td)
mlir_tablegen(ToIntrinsics.h.inc -gen-pass-decls -name ToIntrinsics)
add_public_tablegen_target(QCCToIntrinsicsIncGen)

add_mlir_doc(ToIntrinsics QCCToIntrinsics Conversions/ -gen-pass-doc)
