set(LLVM_TARGET_DEFINITIONS QRefToOQ3.td)
mlir_tablegen(QRefToOQ3.h.inc -gen-pass-decls -name QRefToOQ3)
add_public_tablegen_target(QCCQRefToOQ3IncGen)

add_qcc_doc(QRefToOQ3 QCCQRefToOQ3 Conversions/ -gen-pass-doc)
