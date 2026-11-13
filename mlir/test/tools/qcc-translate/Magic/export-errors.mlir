// RUN: qcc-translate --export-custom-magic --split-input-file --verify-diagnostics %s

// What the exporter rejects although it is valid, verified magic IR.

// expected-error @below {{cannot be exported: the entry point holds no 'magic.init'}}
func.func @main() attributes {qcc.entry_point} {
  return
}

// -----

!a = !magic.ion_chain<0, [0:1]>

// expected-note @below {{the first entry point is here}}
func.func @main() attributes {qcc.entry_point} {
  %a0 = magic.init : !a
  %m0 = magic.mzd %a0 : !a -> i1
  aux.record_int %m0 : i1
  return
}

// expected-error @below {{is a second entry point: only a module with a single entry point can be exported}}
func.func @other() attributes {qcc.entry_point} {
  %a0 = magic.init : !a
  %m0 = magic.mzd %a0 : !a -> i1
  aux.record_int %m0 : i1
  return
}

// -----

!a = !magic.ion_chain<0, [0:1]>

module attributes {qcc.device = #magic.device<name = "one-ion", time_unit_ns = 1000, traps = [
    #magic.trap<capacity = 1, couplings = [dense<0.0> : tensor<1x1xf64>]>]>} {
  func.func private @classical()

  func.func @main() attributes {qcc.entry_point} {
    %a0 = magic.init : !a
    // expected-error @below {{cannot be exported: the format has native magic ops and records only}}
    call @classical() : () -> ()
    %m0 = magic.mzd %a0 : !a -> i1
    aux.record_int %m0 : i1
    return
  }
}
