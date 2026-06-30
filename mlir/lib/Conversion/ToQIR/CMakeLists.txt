file(GLOB CONVERSION_SOURCES *.cpp)

add_mlir_conversion_library(
  QCCToQIR
  ${CONVERSION_SOURCES}
  DEPENDS
  QCCToQIRIncGen
  QCCAuxDialectIncGen
  QCCAuxOpsIncGen
  LINK_LIBS
  # Dialects
  MLIRQCDialect
  MLIRFuncDialect
  MLIRLLVMDialect
  QCCAuxDialect
  # Conversion infra
  MLIRLLVMCommonConversion
  MLIRTransforms
  MLIRFuncToLLVM
  MLIRSCFToControlFlow
  # Core MLIR
  MLIRIR
  MLIRPass)
