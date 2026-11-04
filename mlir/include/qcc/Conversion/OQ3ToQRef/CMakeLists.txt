set(LLVM_TARGET_DEFINITIONS OQ3ToQRef.td)
mlir_tablegen(OQ3ToQRef.h.inc -gen-pass-decls -name OQ3ToQRef)
add_public_tablegen_target(QCCOQ3ToQRefIncGen)

add_qcc_doc(OQ3ToQRef QCCOQ3ToQRef Conversions/ -gen-pass-doc)
