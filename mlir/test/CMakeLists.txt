configure_lit_site_cfg(${CMAKE_CURRENT_SOURCE_DIR}/lit.site.cfg.py.in ${CMAKE_CURRENT_BINARY_DIR}/lit.site.cfg.py
                       MAIN_CONFIG ${CMAKE_CURRENT_SOURCE_DIR}/lit.cfg.py)

set(MLIR_COMPILER_TEST_DEPENDS FileCheck count not qcc-opt qcc qcc-lsp-server)

add_lit_testsuite(check-qcc "Run the QCC project tests" ${CMAKE_CURRENT_BINARY_DIR} DEPENDS
                  ${MLIR_COMPILER_TEST_DEPENDS})

add_test(NAME check-qcc COMMAND ${CMAKE_COMMAND} --build ${CMAKE_BINARY_DIR} --config $<CONFIG> --target check-qcc)
