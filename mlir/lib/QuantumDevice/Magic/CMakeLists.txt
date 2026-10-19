add_mlir_library(
  QCCQuantumDeviceMagic
  MagicPipeline.cpp
  DEPENDS
  AuxOutputRecordingIncGen
  AuxUnpackRecordIntIncGen
  QCCMagicTransformsIncGen
  QCCQCOToQVecIncGen
  QCCQVecToMagicIncGen
  QCCQVecTransformsIncGen
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
