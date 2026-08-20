// RUN: qcc-opt %s -emit-hisepq-start --split-input-file --verify-diagnostics

// expected-note @+1 {{previous entry point declared here}}
llvm.func @first_entry() attributes { passthrough = ["entry_point"] } {
  llvm.return
}

// expected-error @+1 {{expected at most one function tagged as the entry point}}
llvm.func @second_entry() attributes { passthrough = ["entry_point"] } {
  llvm.return
}

// -----

// expected-error @below {{did not find any entry point}}
module {
  llvm.func @not_an_entry_point() {
    llvm.return
  }
}
