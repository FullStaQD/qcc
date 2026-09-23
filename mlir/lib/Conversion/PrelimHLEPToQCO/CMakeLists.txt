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
  LINK_LIBS
  MLIRQCODialect
  QCCPrelimHLEPDialect
  MLIRArithDialect
  MLIRComplexDialect
  MLIRSCFDialect
  MLIRFuncDialect
  MLIRFuncTransforms
  MLIRTransforms)

mqt_mlir_target_use_project_options(QCCPrelimHLEPToQCO)
