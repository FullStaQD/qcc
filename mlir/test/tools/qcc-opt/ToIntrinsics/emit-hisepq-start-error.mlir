// RUN: qcc-opt %s -emit-hisepq-start --split-input-file --verify-diagnostics

// The hardware boots at a single address, so at most one function may be tagged
// as the entry point.

llvm.func @first_entry() attributes { passthrough = ["entry_point"] } {
  llvm.return
}

// expected-error @+1 {{expected at most one function tagged as the entry point, but found 'first_entry' and 'second_entry'}}
llvm.func @second_entry() attributes { passthrough = ["entry_point"] } {
  llvm.return
}

// -----

// ... and at least one, as there is nothing to boot into otherwise.

// expected-error @below {{did not find any entry point}}
module {
  llvm.func @not_an_entry_point() {
    llvm.return
  }
}
