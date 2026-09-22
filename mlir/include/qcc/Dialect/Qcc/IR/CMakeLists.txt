set(LLVM_TARGET_DEFINITIONS QccDialect.td)
mlir_tablegen(QccDialect.h.inc -gen-dialect-decls -dialect=qcc)
mlir_tablegen(QccDialect.cpp.inc -gen-dialect-defs -dialect=qcc)
add_public_tablegen_target(QCCQccDialectIncGen)

set(LLVM_TARGET_DEFINITIONS QccInterfaces.td)
mlir_tablegen(QccInterfaces.h.inc -gen-attr-interface-decls)
mlir_tablegen(QccInterfaces.cpp.inc -gen-attr-interface-defs)
add_public_tablegen_target(QCCQccInterfacesIncGen)

set(LLVM_TARGET_DEFINITIONS QccAttrs.td)
mlir_tablegen(QccAttrs.h.inc -gen-attrdef-decls -attrdefs-dialect=qcc)
mlir_tablegen(QccAttrs.cpp.inc -gen-attrdef-defs -attrdefs-dialect=qcc)
add_public_tablegen_target(QCCQccAttrsIncGen)

add_qcc_doc(QccAttrs QccDialect Dialects/ -gen-dialect-doc -dialect=qcc)
