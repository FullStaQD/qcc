get_property(dialect_libs GLOBAL PROPERTY MLIR_DIALECT_LIBS)
get_property(conversion_libs GLOBAL PROPERTY MLIR_CONVERSION_LIBS)
get_property(extension_libs GLOBAL PROPERTY MLIR_EXTENSION_LIBS)

set(LLVM_LINK_COMPONENTS BitWriter)

set(LIBS
    ${dialect_libs}
    ${conversion_libs}
    ${extension_libs}
    MLIRIR
    MLIRParser
    MLIRPass
    MLIRTransforms
    MLIRSupport
    MLIROptLib
    MLIRRegisterAllDialects
    MLIRRegisterAllExtensions
    MLIRBytecodeWriter
    MLIRTargetLLVMIRExport
    MLIRBuiltinToLLVMIRTranslation
    MLIRLLVMToLLVMIRTranslation
    QCCCompiler
    QCCTarget)

add_llvm_executable(qcc qcc.cpp DEPENDS ${LIBS})

# mqt-core's QCO and QTensor dialects are mutually dependent, and `MLIRQCODialect` does not declare its use of `qtensor`
# ops. Link them as a rescan group so resolution does not depend on the order they happen to appear in `dialect_libs`.
# Keep `LIBS` itself free of the generator expression, since `add_llvm_executable(... DEPENDS)` cannot take one. The
# `RESCAN` feature is only predefined for GNU-ld-like linkers, and using it elsewhere is a hard error at generate time;
# Apple ld and MSVC `link.exe` rescan archives on their own, so plain `LIBS` is enough there. FIXME: simplify this once
# resolved in MQT Core.
if(DEFINED CMAKE_CXX_LINK_GROUP_USING_RESCAN_SUPPORTED)
  set(RESCAN_SUPPORTED ${CMAKE_CXX_LINK_GROUP_USING_RESCAN_SUPPORTED})
else()
  set(RESCAN_SUPPORTED ${CMAKE_LINK_GROUP_USING_RESCAN_SUPPORTED})
endif()

set(LINK_LIBS ${LIBS})
if(RESCAN_SUPPORTED)
  list(REMOVE_ITEM LINK_LIBS MLIRQCODialect MLIRQTensorDialect MLIRQTensorUtils)
  list(APPEND LINK_LIBS "$<LINK_GROUP:RESCAN,MLIRQCODialect,MLIRQTensorDialect,MLIRQTensorUtils>")
endif()

target_link_libraries(qcc PRIVATE ${LINK_LIBS})

llvm_update_compile_flags(qcc)
mlir_check_all_link_libraries(qcc)
