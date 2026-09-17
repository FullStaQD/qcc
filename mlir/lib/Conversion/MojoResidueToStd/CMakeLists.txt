file(GLOB CONVERSION_SOURCES *.cpp)

add_mlir_conversion_library(
  QCCMojoResidueToStd
  ${CONVERSION_SOURCES}
  DEPENDS
  MojoResidueToStdIncGen
  QCCPrelimHLEPDialectIncGen
  QCCPrelimHLEPTypesIncGen
  QCCPrelimHLEPAttrsIncGen
  QCCPrelimHLEPOpsIncGen
  LINK_LIBS
  QCCPrelimHLEPDialect
  MLIRArithDialect
  MLIRFuncDialect
  MLIRSCFDialect
  MLIRTransforms)

mqt_mlir_target_use_project_options(QCCMojoResidueToStd)
