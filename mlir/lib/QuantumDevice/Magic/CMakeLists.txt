add_mlir_library(
  QCCQuantumDeviceMagic
  MagicPipeline.cpp
  LINK_LIBS
  MLIRPass
  MLIRTransforms
  # Dialects
  MLIRFuncDialect
  # Passes
  MLIRQCToQCO
  QCCAuxOutputRecording
  QCCMagicTransforms
  QCCQCOToQVec
  QCCQVecToMagic
  QCCQVecTransforms)
