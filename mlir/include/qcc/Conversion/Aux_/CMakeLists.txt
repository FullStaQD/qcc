set(LLVM_TARGET_DEFINITIONS AuxOutputRecording.td)
mlir_tablegen(AuxOutputRecording.h.inc -gen-pass-decls -name AuxOutputRecording)
add_public_tablegen_target(AuxOutputRecordingIncGen)

add_qcc_doc(AuxOutputRecording QCCAuxOutputRecording Conversions/ -gen-pass-doc)

set(LLVM_TARGET_DEFINITIONS AuxUnpackRecordInt.td)
mlir_tablegen(AuxUnpackRecordInt.h.inc -gen-pass-decls -name AuxUnpackRecordInt)
add_public_tablegen_target(AuxUnpackRecordIntIncGen)

add_qcc_doc(AuxUnpackRecordInt QCCAuxUnpackRecordInt Conversions/ -gen-pass-doc)
