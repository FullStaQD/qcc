add_mlir_library(
  QCCQuantumDeviceMagic
  MagicPipeline.cpp
  DEPENDS
  AuxOutputRecordingIncGen
  AuxUnpackRecordIntIncGen
  QCCMagicTransformsIncGen
  QCCQCToQRefIncGen
  QCCQCircToQVecIncGen
  QCCQRefToQCircIncGen
  QCCQVecToMagicIncGen
  QCCQVecTransformsIncGen
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
