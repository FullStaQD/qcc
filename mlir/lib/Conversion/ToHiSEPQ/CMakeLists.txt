file(GLOB CONVERSION_SOURCES *.cpp)

add_mlir_conversion_library(
  QCCToHiSEPQ
  ${CONVERSION_SOURCES}
  DEPENDS
  QCCToHiSEPQIncGen
  QCCAuxDialectIncGen
  QCCAuxOpsIncGen
  QCCQVecDialectIncGen
  QCCQVecAttrsIncGen
  QCCQVecOpsIncGen
  LINK_LIBS
  # Dialects
  MLIRQCODialect
  MLIRFuncDialect
  MLIRLLVMDialect
  MLIRVectorDialect
  QCCAuxDialect
  QCCQVecDialect
  QCCQVecMachine
  # Conversion infra
  MLIRLLVMCommonConversion
  MLIRTransforms
  MLIRFuncToLLVM
  # Core MLIR
  MLIRIR
  MLIRPass)
