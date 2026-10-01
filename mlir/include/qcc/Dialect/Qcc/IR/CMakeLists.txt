set(LLVM_TARGET_DEFINITIONS QccDialect.td)
mlir_tablegen(QccDialect.h.inc -gen-dialect-decls -dialect=qcc)
mlir_tablegen(QccDialect.cpp.inc -gen-dialect-defs -dialect=qcc)
add_public_tablegen_target(QCCQccDialectIncGen)

set(LLVM_TARGET_DEFINITIONS QccInterfaces.td)
mlir_tablegen(QccInterfaces.h.inc -gen-attr-interface-decls)
mlir_tablegen(QccInterfaces.cpp.inc -gen-attr-interface-defs)
add_public_tablegen_target(QCCQccInterfacesIncGen)

add_qcc_doc(QccDialect QccDialect Dialects/ -gen-dialect-doc -dialect=qcc)
