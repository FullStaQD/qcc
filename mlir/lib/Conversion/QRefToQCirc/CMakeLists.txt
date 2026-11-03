add_mlir_conversion_library(
  QCCQRefToQCirc
  ConvertQRefToQCirc.cpp
  DEPENDS
  QCCQRefToQCircIncGen
  LINK_LIBS
  PRIVATE
  # Dialects
  MLIRFuncDialect
  MLIRSCFDialect
  QCCQccDialect
  QCCQCFDialect
  QCCQCircDialect
  QCCQRefDialect
  # Core MLIR
  MLIRCallInterfaces
  MLIRIR
  MLIRPass
  MLIRSupport)
