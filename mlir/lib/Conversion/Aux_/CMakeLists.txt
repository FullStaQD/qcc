file(GLOB CONVERSION_SOURCES *.cpp)

add_mlir_conversion_library(
  QCCAuxOutputRecording
  ${CONVERSION_SOURCES}
  DEPENDS
  AuxOutputRecordingIncGen
  QCCAuxDialectIncGen
  QCCAuxOpsIncGen
  LINK_LIBS
  QCCAuxDialect)

mqt_mlir_target_use_project_options(QCCAuxOutputRecording)
