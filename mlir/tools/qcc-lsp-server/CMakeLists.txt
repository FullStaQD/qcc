add_mlir_tool(qcc-lsp-server qcc-lsp-server.cpp)

target_link_libraries(
  qcc-lsp-server
  PRIVATE MLIRLspServerLib
          MLIRRegisterAllDialects
          MLIRRegisterAllExtensions
          MLIRRegisterAllPasses
          # Dialect libraries used by our project
          QCCJaspDialect
          QCCAuxDialect
          MLIRQCDialect
          QCCPrelimHLEPDialect)

llvm_update_compile_flags(qcc-lsp-server)
mlir_check_all_link_libraries(qcc-lsp-server)
