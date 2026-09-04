# `QVecTypes.td` includes mqt-core's `QCOTypes.td`, which is not on TableGen's default search path.
list(APPEND LLVM_TABLEGEN_FLAGS -I ${mqt-core_SOURCE_DIR}/mlir/include)

set(LLVM_TARGET_DEFINITIONS QVecDialect.td)
mlir_tablegen(QVecDialect.h.inc -gen-dialect-decls -dialect=qvec)
mlir_tablegen(QVecDialect.cpp.inc -gen-dialect-defs -dialect=qvec)
add_public_tablegen_target(QCCQVecDialectIncGen)

set(LLVM_TARGET_DEFINITIONS QVecAttrs.td)
mlir_tablegen(QVecEnums.h.inc -gen-enum-decls)
mlir_tablegen(QVecEnums.cpp.inc -gen-enum-defs)
mlir_tablegen(QVecAttrs.h.inc -gen-attrdef-decls -attrdefs-dialect=qvec)
mlir_tablegen(QVecAttrs.cpp.inc -gen-attrdef-defs -attrdefs-dialect=qvec)
add_public_tablegen_target(QCCQVecAttrsIncGen)

set(LLVM_TARGET_DEFINITIONS QVecInterfaces.td)
mlir_tablegen(QVecInterfaces.h.inc -gen-op-interface-decls)
mlir_tablegen(QVecInterfaces.cpp.inc -gen-op-interface-defs)
add_public_tablegen_target(QCCQVecInterfacesIncGen)

set(LLVM_TARGET_DEFINITIONS QVecOps.td)
mlir_tablegen(QVecOps.h.inc -gen-op-decls)
mlir_tablegen(QVecOps.cpp.inc -gen-op-defs)
add_public_tablegen_target(QCCQVecOpsIncGen)
