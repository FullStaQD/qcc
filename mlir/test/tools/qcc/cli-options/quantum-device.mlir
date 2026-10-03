// A quantum device has no QISA so far: it implies --target=none, which stops after the device lowering.
// RUN: qcc --quantum-device=magic --device-description=%S/Inputs/device.mlir --compile-to=mlir %s | FileCheck %s --check-prefix=CHECK-MAGIC
// RUN: qcc --quantum-device=magic --target=none --device-description=%S/Inputs/device.mlir --compile-to=mlir %s | FileCheck %s --check-prefix=CHECK-MAGIC
// RUN: qcc --quantum-device=magic --device-description=%S/Inputs/device.mlir --compile-to=custom-magic %s | FileCheck %s --check-prefix=CHECK-TXT

// --target=none without a quantum device: the module after the frontend lowering.
// RUN: qcc --target=none --compile-to=mlir %s | FileCheck %s --check-prefix=CHECK-NONE
// RUN: qcc --target=none --quantum-device=none --compile-to=mlir %s | FileCheck %s --check-prefix=CHECK-NONE

// RUN: qcc --list-quantum-devices | FileCheck %s --check-prefix=CHECK-LIST

// RUN: not qcc --quantum-device=does-not-exist %s 2>&1 | FileCheck %s --check-prefix=CHECK-ERR-UNKNOWN
// A quantum device and a QISA target do not go together yet:
// RUN: not qcc --quantum-device=magic --target=qir --compile-to=mlir %s 2>&1 | FileCheck %s --check-prefix=CHECK-ERR-TARGET
// There is no LLVM IR and no native code without a QISA. LLVM IR is the default stage, so the stage must be named:
// RUN: not qcc --quantum-device=magic --device-description=%S/Inputs/device.mlir %s 2>&1 | FileCheck %s --check-prefix=CHECK-ERR-LLVMIR-MAGIC
// RUN: not qcc --target=none %s 2>&1 | FileCheck %s --check-prefix=CHECK-ERR-LLVMIR
// RUN: not qcc --target=none --compile-to=native %s 2>&1 | FileCheck %s --check-prefix=CHECK-ERR-NATIVE
// The text format belongs to the MAGIC device and is not implied by it, nor does it imply the device:
// RUN: not qcc --compile-to=custom-magic %s 2>&1 | FileCheck %s --check-prefix=CHECK-ERR-CUSTOM
// RUN: not qcc --target=none --compile-to=custom-magic %s 2>&1 | FileCheck %s --check-prefix=CHECK-ERR-CUSTOM
// RUN: not qcc --quantum-device=magic --device-description=%S/Inputs/device.mlir --compile-to=custom-magic --binary %s 2>&1 | FileCheck %s --check-prefix=CHECK-ERR-BINARY
// A device description needs a quantum device:
// RUN: not qcc --device-description=%S/Inputs/device.mlir --compile-to=mlir %s 2>&1 | FileCheck %s --check-prefix=CHECK-ERR-DESCRIPTION
// RUN: not qcc --quantum-device=magic --device-description=%S/Inputs/does-not-exist.mlir --compile-to=mlir %s 2>&1 | FileCheck %s --check-prefix=CHECK-ERR-FILE
// Without a description the module has to carry the device:
// RUN: not qcc --quantum-device=magic --compile-to=mlir %s 2>&1 | FileCheck %s --check-prefix=CHECK-ERR-NO-DEVICE

func.func @main() attributes { qcc.entry_point } {
    %q = qc.static 0 : !qc.qubit
    qc.x %q : !qc.qubit
    %m = qc.measure %q : !qc.qubit -> i1
    aux.record_int %m : i1
    return
}

// CHECK-MAGIC: module attributes {qcc.device = #magic_device}
// CHECK-MAGIC: magic.init
// CHECK-MAGIC: magic.sym_zxz
// CHECK-MAGIC: magic.mzd

// CHECK-TXT: OPENQASM 3.0;
// CHECK-TXT: c[0] = measure q[0];

// CHECK-NONE: func.func @main()
// CHECK-NONE: qc.x
// CHECK-NONE: aux.record_int

// CHECK-LIST: none
// CHECK-LIST: magic

// CHECK-ERR-UNKNOWN: error: unknown quantum device 'does-not-exist' (see --list-quantum-devices)
// CHECK-ERR-TARGET: error: --quantum-device=magic and --target=qir are not supported together (use --target=none)
// CHECK-ERR-LLVMIR-MAGIC: error: LLVM IR output (--compile-to=llvmir, the default) is not supported for --target=none; choose the stage explicitly: --compile-to=mlir or --compile-to=custom-magic
// CHECK-ERR-LLVMIR: error: LLVM IR output (--compile-to=llvmir, the default) is not supported for --target=none; choose the stage explicitly: --compile-to=mlir{{$}}
// CHECK-ERR-NATIVE: error: native output is not supported for --target=none
// CHECK-ERR-CUSTOM: error: --compile-to=custom-magic requires --quantum-device=magic
// CHECK-ERR-BINARY: error: --binary is not supported for --compile-to=custom-magic
// CHECK-ERR-DESCRIPTION: error: --device-description requires a quantum device (see --quantum-device)
// CHECK-ERR-FILE: error: cannot read device file '{{.*}}does-not-exist.mlir'
// CHECK-ERR-NO-DEVICE: error: module carries no 'qcc.device' attribute
