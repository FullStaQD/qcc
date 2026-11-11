add_mlir_conversion_library(
  QCCQCircToQVec
  ConvertQCircToQVec.cpp
  LINK_LIBS
  PRIVATE
  # Dialects
  MLIRFuncDialect
  MLIRSCFDialect
  MLIRVectorDialect
  QCCQccDialect
  QCCQCFDialect
  QCCQCircDialect
  QCCQVecDialect
  # Conversion infra
  MLIRTransforms
  # Core MLIR
  MLIRIR
  MLIRPass
  MLIRSupport)
