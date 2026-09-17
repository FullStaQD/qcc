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

# Optional: path to a checkout of the Mojo fork carrying the synced copy of the PrelimHLEP dialect (see
# mojo/dialect-sync/). When set, two extra lit tests run -- the dialect sync check and the generic-form round trip
# between qcc-opt and the fork's kgen-opt. Unset, both are reported unsupported, so CI without a fork checkout stays
# green.
set(QCC_MOJO_FORK
    ""
    CACHE PATH "Path to a Mojo fork checkout to cross-check the PrelimHLEP dialect against")

if(QCC_MOJO_FORK)
  find_program(
    QCC_MOJO_KGEN_OPT
    NAMES kgen-opt
    HINTS "${QCC_MOJO_FORK}/bazel-bin/Mojo/tools/kgen-opt"
    DOC "Path to the Mojo fork's 'kgen-opt', used for the PrelimHLEP round-trip test"
    NO_DEFAULT_PATH)
  if(NOT QCC_MOJO_KGEN_OPT)
    message(WARNING "QCC_MOJO_FORK is set but 'kgen-opt' was not found under it; build it with "
                    "'./bazelw build --config=build-mojo //Mojo/tools/kgen-opt'. The round-trip test will be skipped.")
  endif()

  # The end-to-end tests additionally need the compiler itself and a built standard library, since a kernel is ordinary
  # Mojo and imports it.
  find_program(
    QCC_MOJO_KGEN
    NAMES kgen
    HINTS "${QCC_MOJO_FORK}/bazel-bin/Mojo/tools/kgen"
    DOC "Path to the Mojo fork's 'kgen', used for the end-to-end Mojo kernel tests"
    NO_DEFAULT_PATH)
  set(QCC_MOJO_STDLIB "${QCC_MOJO_FORK}/bazel-bin/Mojo/stdlib/std")
  if(NOT QCC_MOJO_KGEN OR NOT IS_DIRECTORY "${QCC_MOJO_STDLIB}")
    message(WARNING "QCC_MOJO_FORK is set but 'kgen' or the built standard library was not found under it; build them "
                    "with './bazelw build --config=build-mojo //Mojo/tools/kgen:kgen //Mojo/stdlib/std'. The "
                    "end-to-end Mojo kernel tests will be skipped.")
  endif()
endif()

configure_lit_site_cfg(${CMAKE_CURRENT_SOURCE_DIR}/lit.site.cfg.py.in ${CMAKE_CURRENT_BINARY_DIR}/lit.site.cfg.py
                       MAIN_CONFIG ${CMAKE_CURRENT_SOURCE_DIR}/lit.cfg.py)

add_lit_testsuite(check-qcc "Run the QCC project tests" ${CMAKE_CURRENT_BINARY_DIR} DEPENDS
                  ${MLIR_COMPILER_TEST_DEPENDS})

add_test(NAME check-qcc COMMAND ${CMAKE_COMMAND} --build ${CMAKE_BINARY_DIR} --config $<CONFIG> --target check-qcc)
