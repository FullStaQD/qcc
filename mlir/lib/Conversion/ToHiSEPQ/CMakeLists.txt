file(GLOB CONVERSION_SOURCES *.cpp)

add_mlir_conversion_library(
  QCCToHiSEPQ
  ${CONVERSION_SOURCES}
  LINK_LIBS
  # Dialects
  MLIRFuncDialect
  MLIRLLVMDialect
  MLIRSCFDialect
  MLIRVectorDialect
  QCCAuxDialect
  QCCQccDialect
  QCCQVecDialect
  # Conversion infra
  MLIRLLVMCommonConversion
  MLIRTransforms
  MLIRFuncToLLVM
  # Core MLIR
  MLIRIR
  MLIRPass)
