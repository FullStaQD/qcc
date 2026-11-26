file(GLOB CONVERSION_SOURCES *.cpp)

add_mlir_conversion_library(QCCAuxOutputRecording ${CONVERSION_SOURCES} LINK_LIBS MLIRArithDialect QCCAuxDialect)
