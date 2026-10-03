// RUN: qcc-opt %s --magic-compact-ion-ids --verify-diagnostics

// The ions are numbered by the program's `magic.init`, so there has to be exactly one.
func.func @two_inits() {
  %a0 = magic.init : !magic.ion_chain<0, [3:1]>
  // expected-error @+1 {{'magic.init' op is the second 'magic.init' of the program: expected at most one to number the ions by}}
  %b0 = magic.init : !magic.ion_chain<1, [5:1]>
  return
}
