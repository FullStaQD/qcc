// RUN: qcc-opt %s --magic-shuttle-inter-trap-zz --verify-diagnostics

#trap = #magic.trap<capacity = 2, couplings = [
  dense<0.0> : tensor<1x1xf64>,
  dense<[[0.0, 1.0], [1.0, 0.0]]> : tensor<2x2xf64>]>

// Both traps are full: no ion can move.
module attributes {qcc.device = #magic.device<name = "two-trap-full", time_unit_ns = 1000, initial_occupancies = [2, 2], traps = [#trap, #trap]>} {
  func.func @no_free_slot() {
    %a0, %b0 = magic.init : !magic.ion_chain<0, [0:1, 1:1]>, !magic.ion_chain<1, [2:1, 3:1]>
    // expected-error @+1 {{cannot bring ions 0 and 2 together: both traps are full, shuttling needs a free slot}}
    %a1, %b1 = magic.inter_trap_zz %a0, %b0 ions [0, 2] {angle = 0.5} : !magic.ion_chain<0, [0:1, 1:1]>, !magic.ion_chain<1, [2:1, 3:1]>
    %m0, %m1 = magic.mzd %a1 : !magic.ion_chain<0, [0:1, 1:1]> -> i1, i1
    %m2, %m3 = magic.mzd %b1 : !magic.ion_chain<1, [2:1, 3:1]> -> i1, i1
    return
  }
}
