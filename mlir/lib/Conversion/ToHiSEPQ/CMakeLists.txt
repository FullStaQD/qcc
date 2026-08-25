file(GLOB CONVERSION_SOURCES *.cpp)

add_mlir_conversion_library(
  QCCToHiSEPQ
  ${CONVERSION_SOURCES}
  DEPENDS
  QCCToHiSEPQIncGen
  QCCAuxDialectIncGen
  QCCAuxOpsIncGen
  QCCHiSEPQDialectIncGen
  QCCHiSEPQAttrsIncGen
  QCCHiSEPQOpsIncGen
  LINK_LIBS
  # Dialects
  MLIRQCDialect
  MLIRFuncDialect
  MLIRLLVMDialect
  MLIRVectorDialect
  QCCAuxDialect
  QCCHiSEPQDialect
  QCCHiSEPQHardware
  # Conversion infra
  MLIRLLVMCommonConversion
  MLIRTransforms
  MLIRFuncToLLVM
  # Core MLIR
  MLIRIR
  MLIRPass)
