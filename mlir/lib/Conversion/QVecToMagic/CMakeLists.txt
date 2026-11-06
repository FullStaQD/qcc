add_mlir_conversion_library(
  QCCQVecToMagic
  ConvertQVecToMagic.cpp
  DEPENDS
  QCCQVecToMagicIncGen
  LINK_LIBS
  PRIVATE
  # Dialects
  MLIRArithDialect
  MLIRFuncDialect
  MLIRVectorDialect
  QCCAuxDialect
  QCCMagicDevice
  QCCMagicDialect
  QCCQccDialect
  QCCQVecDialect
  QCCQVecTransforms
  # Core MLIR
  MLIRIR
  MLIRPass
  MLIRSupport)
