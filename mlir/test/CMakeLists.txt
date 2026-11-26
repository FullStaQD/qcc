add_subdirectory(lib)

set(MLIR_COMPILER_TEST_DEPENDS
    FileCheck
    count
    not
    split-file
    qcc-opt
    qcc-translate
    qcc
    qcc-lsp-server)

if(QCC_ENABLE_HISEPQ)
  set(QCC_ENABLE_HISEPQ_PY True) # for lit config
  # Testing HiSEP-Q links with `ld.lld` and runs the program on the RTL testbench `sim_hisepq`. Only a build that cannot
  # provide them (the release build) opts out, which skips the tests that need them.
  option(QCC_HISEPQ_SIM_TESTS "Run the HiSEP-Q tests that need ld.lld and sim_hisepq (then both are required)" ON)
  if(QCC_HISEPQ_SIM_TESTS)
    set(QCC_HISEPQ_SIM_TESTS_PY True) # for lit config
  else()
    set(QCC_HISEPQ_SIM_TESTS_PY False)
  endif()
  find_program(
    QCC_SIM_HISEPQ_EXECUTABLE
    NAMES sim_hisepq
    HINTS "$ENV{HOME}/.local/bin"
    DOC "Path to the prebuilt HiSEP-Q Verilator testbench (sim_hisepq)")
  list(APPEND MLIR_COMPILER_TEST_DEPENDS hisepq-elf2mem)
else()
  set(QCC_ENABLE_HISEPQ_PY False)
  set(QCC_HISEPQ_SIM_TESTS_PY False)
endif()

if(QCC_INCLUDE_UNITTESTS)
  set(QCC_INCLUDE_UNITTESTS_PY True) # for lit config
  configure_lit_site_cfg(
    ${CMAKE_CURRENT_SOURCE_DIR}/Unit/lit.site.cfg.py.in ${CMAKE_CURRENT_BINARY_DIR}/Unit/lit.site.cfg.py MAIN_CONFIG
    ${CMAKE_CURRENT_SOURCE_DIR}/Unit/lit.cfg.py)
  list(APPEND MLIR_COMPILER_TEST_DEPENDS QCCUnitTests)
else()
  set(QCC_INCLUDE_UNITTESTS_PY False)
endif()

configure_lit_site_cfg(${CMAKE_CURRENT_SOURCE_DIR}/lit.site.cfg.py.in ${CMAKE_CURRENT_BINARY_DIR}/lit.site.cfg.py
                       MAIN_CONFIG ${CMAKE_CURRENT_SOURCE_DIR}/lit.cfg.py)

add_lit_testsuite(check-qcc "Run the QCC project tests" ${CMAKE_CURRENT_BINARY_DIR} DEPENDS
                  ${MLIR_COMPILER_TEST_DEPENDS})

add_test(NAME check-qcc COMMAND ${CMAKE_COMMAND} --build ${CMAKE_BINARY_DIR} --config $<CONFIG> --target check-qcc)
