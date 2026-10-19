set(LLVM_TARGET_DEFINITIONS QccDialect.td)
mlir_tablegen(QccDialect.h.inc -gen-dialect-decls -dialect=qcc)
mlir_tablegen(QccDialect.cpp.inc -gen-dialect-defs -dialect=qcc)
add_public_tablegen_target(QCCQccDialectIncGen)

set(LLVM_TARGET_DEFINITIONS QccInterfaces.td)
mlir_tablegen(QccAttrInterfaces.h.inc -gen-attr-interface-decls)
mlir_tablegen(QccAttrInterfaces.cpp.inc -gen-attr-interface-defs)
mlir_tablegen(QccOpInterfaces.h.inc -gen-op-interface-decls)
mlir_tablegen(QccOpInterfaces.cpp.inc -gen-op-interface-defs)
add_public_tablegen_target(QCCQccInterfacesIncGen)

set(LLVM_TARGET_DEFINITIONS QccTypes.td)
mlir_tablegen(QccTypes.h.inc -gen-typedef-decls -typedefs-dialect=qcc)
mlir_tablegen(QccTypes.cpp.inc -gen-typedef-defs -typedefs-dialect=qcc)
add_public_tablegen_target(QCCQccTypesIncGen)

set(LLVM_TARGET_DEFINITIONS QccOps.td)
mlir_tablegen(QccOps.h.inc -gen-op-decls)
mlir_tablegen(QccOps.cpp.inc -gen-op-defs)
add_public_tablegen_target(QCCQccOpsIncGen)

add_qcc_doc(QccOps QccDialect Dialects/ -gen-dialect-doc -dialect=qcc)
