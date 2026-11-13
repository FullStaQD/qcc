add_executable(qcc-translate qcc-translate.cpp)
target_link_libraries(
  qcc-translate
  PRIVATE MLIRIR
          MLIRSupport
          MLIRTranslateLib
          MLIRFuncDialect
          QCCMagicExport
          QCCOQ3Dialect
          QCCOQ3Export
          QCCOQ3Import
          QCCQccDialect)
