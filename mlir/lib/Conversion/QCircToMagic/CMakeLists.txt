add_mlir_conversion_library(
  QCCQCircToMagic
  ConvertQCircToMagic.cpp
  LINK_LIBS
  PRIVATE
  # Dialects
  MLIRArithDialect
  MLIRFuncDialect
  QCCAuxDialect
  QCCMagicDevice
  QCCMagicDialect
  QCCQccDialect
  QCCQCircDialect
  QCCQCircTransforms
  # Core MLIR
  MLIRIR
  MLIRPass
  MLIRSupport)
