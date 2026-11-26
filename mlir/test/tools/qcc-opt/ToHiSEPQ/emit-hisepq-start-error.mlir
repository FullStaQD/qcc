// RUN: qcc-opt %s -emit-hisepq-start --split-input-file --verify-diagnostics

// expected-note @+1 {{previous entry point declared here}}
llvm.func @first_entry() attributes { qcc.entry_point } {
  llvm.return
}

// expected-error @+1 {{expected at most one function tagged as the entry point}}
llvm.func @second_entry() attributes { qcc.entry_point } {
  llvm.return
}

// -----

// expected-error @below {{did not find any entry point}}
module {
  llvm.func @not_an_entry_point() {
    llvm.return
  }
}

// -----

// expected-error @+1 {{expected the entry point to take no arguments}}
llvm.func @takes_arguments(%arg0: i64) attributes { qcc.entry_point } {
  llvm.return
}

// -----

// Results returned in memory would need a pointer from the caller, which `_start` does not provide.

// expected-error @+1 {{expected the entry point to return nothing or an integer exit code of at most 64 bits, got '!llvm.struct<(i64, i64)>'}}
llvm.func @returns_results() -> !llvm.struct<(i64, i64)> attributes { qcc.entry_point } {
  %0 = llvm.mlir.poison : !llvm.struct<(i64, i64)>
  llvm.return %0 : !llvm.struct<(i64, i64)>
}
