set(MLIR_COMPILER_TEST_DEPENDS FileCheck count not qcc-opt qcc qcc-lsp-server)

if(QCC_ENABLE_HISEPQ)
  set(QCC_ENABLE_HISEPQ_PY True) # for lit config
  find_program(
    QCC_SIM_HISEPQ_EXECUTABLE
    NAMES sim_hisepq
    HINTS "$ENV{HOME}/.local/bin"
    DOC "Path to the prebuilt HiSEP-Q Verilator testbench (sim_hisepq)")
  list(APPEND MLIR_COMPILER_TEST_DEPENDS hisepq-elf2mem)
else()
  set(QCC_ENABLE_HISEPQ_PY False)
endif()

configure_lit_site_cfg(${CMAKE_CURRENT_SOURCE_DIR}/lit.site.cfg.py.in ${CMAKE_CURRENT_BINARY_DIR}/lit.site.cfg.py
                       MAIN_CONFIG ${CMAKE_CURRENT_SOURCE_DIR}/lit.cfg.py)

add_lit_testsuite(check-qcc "Run the QCC project tests" ${CMAKE_CURRENT_BINARY_DIR} DEPENDS
                  ${MLIR_COMPILER_TEST_DEPENDS})

add_test(NAME check-qcc COMMAND ${CMAKE_COMMAND} --build ${CMAKE_BINARY_DIR} --config $<CONFIG> --target check-qcc)
