add_mlir_conversion_library(
  QCCQCircToQRef
  ConvertQCircToQRef.cpp
  LINK_LIBS
  PRIVATE
  # Dialects
  MLIRFuncDialect
  MLIRSCFDialect
  QCCQccDialect
  QCCQCFDialect
  QCCQCircDialect
  QCCQRefDialect
  # Conversion infra
  MLIRTransforms
  # Core MLIR
  MLIRIR
  MLIRPass
  MLIRSupport)
