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
  MLIRQCODialect
  MLIRVectorDialect
  QCCAuxDialect
  QCCMagicDevice
  QCCMagicDialect
  QCCQVecDialect
  QCCQVecTransforms
  # Core MLIR
  MLIRIR
  MLIRPass
  MLIRSupport)
