add_custom_target(QCCUnitTests)

function(add_qcc_unittest test_name)
  add_unittest(QCCUnitTests ${test_name} ${ARGN})
endfunction()

add_subdirectory(Dialect)
