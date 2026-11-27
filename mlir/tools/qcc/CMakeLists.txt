set(LLVM_LINK_COMPONENTS BitWriter Core Support)

set(LIBS
    MLIRBytecodeWriter
    MLIRIR
    MLIRParser
    MLIRPass
    MLIRSupport
    # LLVM IR translation
    MLIRBuiltinToLLVMIRTranslation
    MLIRLLVMToLLVMIRTranslation
    MLIRTargetLLVMIRExport
    # QCC
    QCCCompiler
    QCCQccDialect
    QCCQuantumDevice
    QCCRegisterAllDialects
    QCCSupport
    QCCTarget)

add_llvm_executable(qcc qcc.cpp DEPENDS ${LIBS})

target_link_libraries(qcc PRIVATE ${LIBS})

llvm_update_compile_flags(qcc)
mlir_check_all_link_libraries(qcc)

# The archive README (utils/release/archive-readme.md) promises that the path of bin/qcc in the archive stays stable.
install(TARGETS qcc RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR} COMPONENT qcc)
