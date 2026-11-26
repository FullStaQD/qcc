add_mlir_conversion_library(
  QCCJaspToQRef
  ConvertJaspToQRef.cpp
  LINK_LIBS
  PRIVATE
  # Dialects
  MLIRArithDialect
  MLIRFuncDialect
  MLIRSCFDialect
  MLIRTensorDialect
  QCCJaspDialect
  QCCQccDialect
  QCCQRefDialect
  # Conversion infra
  MLIRFuncTransforms
  MLIRSCFTransforms
  MLIRTransforms
  # Core MLIR
  MLIRIR
  MLIRPass
  MLIRSupport)
