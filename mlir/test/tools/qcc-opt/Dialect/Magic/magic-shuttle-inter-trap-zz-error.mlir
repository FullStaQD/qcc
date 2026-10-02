// RUN: qcc-opt %s --qcc-attach-device=file=%S/../Qcc/Inputs/device-2x3.mlir --magic-shuttle-inter-trap-zz --verify-diagnostics

!a = !magic.ion_chain<0, [0:1, 1:1, 2:1]>
!b = !magic.ion_chain<1, [3:1, 4:1, 5:1]>

// Each trap takes three ions, so both are full: no ion can move.
func.func @no_free_slot() {
  %a0, %b0 = magic.init : !a, !b
  // expected-error @+1 {{cannot bring ions 0 and 3 together: both traps are full, shuttling needs a free slot}}
  %a1, %b1 = magic.inter_trap_zz %a0, %b0 ions [0, 3] {angle = 0.5} : !a, !b
  %m0, %m1, %m2 = magic.mzd %a1 : !a -> i1, i1, i1
  %m3, %m4, %m5 = magic.mzd %b1 : !b -> i1, i1, i1
  return
}
