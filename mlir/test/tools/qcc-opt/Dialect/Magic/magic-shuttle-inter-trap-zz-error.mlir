// RUN: qcc-opt %s --magic-shuttle-inter-trap-zz --split-input-file --verify-diagnostics

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

// -----

#trap = #magic.trap<capacity = 2, couplings = [
  dense<0.0> : tensor<1x1xf64>,
  dense<[[0.0, 1.0], [1.0, 0.0]]> : tensor<2x2xf64>]>

// The coupling acts between active ions only.
module attributes {qcc.device = #magic.device<name = "two-trap", time_unit_ns = 1000, initial_occupancies = [1, 1], traps = [#trap, #trap]>} {
  func.func @inactive_ion() {
    %a0, %b0 = magic.init : !magic.ion_chain<0, [0:1]>, !magic.ion_chain<1, [1:1]>
    %a1 = magic.recode %a0 : !magic.ion_chain<0, [0:1]> -> !magic.ion_chain<0, [0:0]>
    // expected-error @+1 {{expects both ions to be active}}
    %a2, %b1 = magic.inter_trap_zz %a1, %b0 ions [0, 1] {angle = 0.5} : !magic.ion_chain<0, [0:0]>, !magic.ion_chain<1, [1:1]>
    %m0 = magic.mzd %a2 : !magic.ion_chain<0, [0:0]> -> i1
    %m1 = magic.mzd %b1 : !magic.ion_chain<1, [1:1]> -> i1
    return
  }
}

// -----

#trap = #magic.trap<capacity = 3, couplings = [
  dense<0.0> : tensor<1x1xf64>,
  dense<[[0.0, 1.0], [1.0, 0.0]]> : tensor<2x2xf64>,
  dense<[[0.0, 1.0, 1.0], [1.0, 0.0, 1.0], [1.0, 1.0, 0.0]]> : tensor<3x3xf64>]>

// One free slot each, neither ion at the front, and both front ions inactive: no front ion can carry the coupling.
module attributes {qcc.device = #magic.device<name = "two-trap", time_unit_ns = 1000, initial_occupancies = [2, 2], traps = [#trap, #trap]>} {
  func.func @inactive_fronts() {
    %a0, %b0 = magic.init : !magic.ion_chain<0, [0:1, 1:1]>, !magic.ion_chain<1, [2:1, 3:1]>
    %a1 = magic.recode %a0 : !magic.ion_chain<0, [0:1, 1:1]> -> !magic.ion_chain<0, [0:0, 1:1]>
    %b1 = magic.recode %b0 : !magic.ion_chain<1, [2:1, 3:1]> -> !magic.ion_chain<1, [2:0, 3:1]>
    // expected-error @+1 {{cannot bring ions 1 and 3 together: the swap fallback needs an active front ion}}
    %a2, %b2 = magic.inter_trap_zz %a1, %b1 ions [1, 3] {angle = 0.5} : !magic.ion_chain<0, [0:0, 1:1]>, !magic.ion_chain<1, [2:0, 3:1]>
    return
  }
}
