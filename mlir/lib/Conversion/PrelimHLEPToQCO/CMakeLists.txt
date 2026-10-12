file(GLOB CONVERSION_SOURCES *.cpp)

add_mlir_conversion_library(
  QCCPrelimHLEPToQCO
  ${CONVERSION_SOURCES}
  DEPENDS
  PrelimHLEPToQCOIncGen
  QCCPrelimHLEPDialectIncGen
  QCCPrelimHLEPTypesIncGen
  QCCPrelimHLEPAttrsIncGen
  QCCPrelimHLEPOpsIncGen
  QCCHLEPGateOpsIncGen
  LINK_LIBS
  MLIRQCODialect
  QCCPrelimHLEPDialect
  QCCHLEPGateDialect
  MLIRArithDialect
  MLIRComplexDialect
  MLIRSCFDialect
  MLIRFuncDialect
  MLIRFuncTransforms
  MLIRTransforms)

mqt_mlir_target_use_project_options(QCCPrelimHLEPToQCO)
