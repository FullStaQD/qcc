add_subdirectory(QIR)

set(QCC_TARGET_LINK_LIBS MLIRPass QCCTargetQIR)

if(QCC_ENABLE_HISEP_Q)
  add_subdirectory(HiSEPQ)
  list(APPEND QCC_TARGET_LINK_LIBS QCCTargetHiSEPQ)
endif()

add_mlir_library(QCCTarget TargetRegistry.cpp LINK_LIBS ${QCC_TARGET_LINK_LIBS})
