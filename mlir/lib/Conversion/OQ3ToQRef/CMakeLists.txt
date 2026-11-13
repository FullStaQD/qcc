add_mlir_conversion_library(
  QCCOQ3ToQRef
  ConvertOQ3ToQRef.cpp
  LINK_LIBS
  PRIVATE
  # Dialects
  MLIRArithDialect
  MLIRFuncDialect
  MLIRMemRefDialect
  MLIRSCFDialect
  MLIRTensorDialect
  QCCOQ3Dialect
  QCCQccDialect
  QCCQRefDialect
  # Conversion infra
  MLIRTransforms
  # Core MLIR
  MLIRDataLayoutInterfaces
  MLIRIR
  MLIRPass
  MLIRSupport)
