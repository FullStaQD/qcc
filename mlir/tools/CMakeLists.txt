add_subdirectory(qcc)
add_subdirectory(qcc-opt)
add_subdirectory(qcc-lsp-server)

if(QCC_ENABLE_HISEPQ)
  add_subdirectory(hisepq-elf2mem)
endif()
