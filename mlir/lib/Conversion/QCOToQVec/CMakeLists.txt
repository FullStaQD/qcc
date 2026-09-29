file(GLOB CONVERSION_SOURCES *.cpp)

add_mlir_conversion_library(
  QCCQCOToQVec
  ${CONVERSION_SOURCES}
  DEPENDS
  QCCQCOToQVecIncGen
  QCCQVecDialectIncGen
  QCCQVecAttrsIncGen
  QCCQVecOpsIncGen
  LINK_LIBS
  # Dialects
  MLIRQCODialect
  MLIRSCFDialect
  MLIRQTensorDialect
  MLIRFuncDialect
  MLIRVectorDialect
  QCCQVecDialect
  # Conversion infra
  MLIRTransforms
  # Core MLIR
  MLIRIR
  MLIRPass)
