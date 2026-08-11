file(GLOB CONVERSION_SOURCES *.cpp)

add_mlir_conversion_library(
  QCCToIntrinsics
  ${CONVERSION_SOURCES}
  DEPENDS
  QCCToIntrinsicsIncGen
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
