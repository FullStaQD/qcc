file(GLOB CONVERSION_SOURCES *.cpp)

add_mlir_conversion_library(
  QCCToQIR
  ${CONVERSION_SOURCES}
  LINK_LIBS
  # Dialects
  MLIRFuncDialect
  MLIRLLVMDialect
  QCCAuxDialect
  QCCQccDialect
  QCCQRefDialect
  # Conversion infra
  MLIRLLVMCommonConversion
  MLIRTransforms
  MLIRFuncToLLVM
  MLIRMemRefToLLVM
  MLIRSCFToControlFlow
  # Core MLIR
  MLIRIR
  MLIRPass)
