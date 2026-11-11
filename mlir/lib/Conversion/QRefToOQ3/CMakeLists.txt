add_mlir_conversion_library(
  QCCQRefToOQ3
  ConvertQRefToOQ3.cpp
  LINK_LIBS
  PRIVATE
  # Dialects
  MLIRArithDialect
  MLIRFuncDialect
  MLIRMemRefDialect
  MLIRTensorDialect
  QCCOQ3Dialect
  QCCQccDialect
  QCCQRefDialect
  # Core MLIR
  MLIRDataLayoutInterfaces
  MLIRIR
  MLIRPass
  MLIRSupport)
