// RUN: qcc-opt %s -convert-qir-to-hisepq-intrinsics --split-input-file --verify-diagnostics

llvm.func @__quantum__qis__x__body(!llvm.ptr) -> ()

llvm.func @non_constant_qubit_ptr(%q: !llvm.ptr) {
  // expected-error @+1 {{cannot extract qubit index from ptr for '__quantum__qis__x__body'}}
  llvm.call @__quantum__qis__x__body(%q) : (!llvm.ptr) -> ()
  llvm.return
}

// -----

llvm.func @__quantum__qis__x__body(!llvm.ptr) -> ()

llvm.func @out_of_range_qubit_index() {
  %c256 = llvm.mlir.constant(256 : i64) : i64
  %q = llvm.inttoptr %c256 : i64 to !llvm.ptr
  // expected-error @+1 {{qubit index 256 out of range for '__quantum__qis__x__body'}}
  llvm.call @__quantum__qis__x__body(%q) : (!llvm.ptr) -> ()
  llvm.return
}

// -----

llvm.func @__quantum__qis__cx__body(!llvm.ptr) -> ()

llvm.func @too_few_qubit_operands() {
  %c0 = llvm.mlir.constant(0 : i64) : i64
  %q = llvm.inttoptr %c0 : i64 to !llvm.ptr
  // expected-error @+1 {{'__quantum__qis__cx__body' expects at least 2 qubit operand(s), got 1}}
  llvm.call @__quantum__qis__cx__body(%q) : (!llvm.ptr) -> ()
  llvm.return
}
