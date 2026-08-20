file(GLOB CONVERSION_SOURCES *.cpp)

add_mlir_conversion_library(
  QCCToHiSEPQ
  ${CONVERSION_SOURCES}
  DEPENDS
  QCCToHiSEPQIncGen
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
  # Core MLIR
  MLIRIR
  MLIRPass)
