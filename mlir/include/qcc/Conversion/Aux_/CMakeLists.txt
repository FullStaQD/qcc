set(LLVM_TARGET_DEFINITIONS AuxOutputRecording.td)
mlir_tablegen(AuxOutputRecording.h.inc -gen-pass-decls -name AuxOutputRecording)
add_public_tablegen_target(AuxOutputRecordingIncGen)

add_qcc_doc(AuxOutputRecording QCCAuxOutputRecording Conversions/ -gen-pass-doc)
