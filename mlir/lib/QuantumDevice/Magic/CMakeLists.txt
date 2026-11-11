add_mlir_library(
  QCCQuantumDeviceMagic
  MagicPipeline.cpp
  LINK_LIBS
  MLIRPass
  MLIRTransforms
  # Dialects
  MLIRFuncDialect
  # Passes
  QCCAuxOutputRecording
  QCCMagicTransforms
  QCCQCToQRef
  QCCQCircToQVec
  QCCQRefToQCirc
  QCCQVecToMagic
  QCCQVecTransforms)
