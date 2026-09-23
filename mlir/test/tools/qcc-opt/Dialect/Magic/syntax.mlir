// RUN: qcc-opt %s | FileCheck %s
// RUN: qcc-opt %s --mlir-print-op-generic | qcc-opt | FileCheck %s

// Every op once, in custom form, and once more after a round trip through the generic form. Chain types are printed
// as aliases `!chain`, `!chain1`, ... (numbered by the printer), so we match them loosely.

!t0  = !magic.ion_chain<0, [0:1, 1:1]>
!t1  = !magic.ion_chain<1, [2:1]>
!t1i = !magic.ion_chain<1, [2:0]>
!t0s = !magic.ion_chain<0, [1:1]>
!t1s = !magic.ion_chain<1, [0:1, 2:1]>
!t0i = !magic.ion_chain<0, [1:0]>

// Type aliases come first, then the attribute aliases of the device used by @main below.
// CHECK: !magic.ion_chain<0, [0:1, 1:1]>
// CHECK: !magic.ion_chain<1, [2:1]>
// CHECK: #magic_trap = #qcc.magic_trap<capacity = 3, couplings = [dense<0.000000e+00> : tensor<1x1xf64>, dense<{{.*}}> : tensor<2x2xf64>, dense<{{.*}}> : tensor<3x3xf64>]>
// CHECK: #magic_device = #qcc.magic_device<name = "two-trap", time_unit_ns = 1000, initial_occupancies = [2, 1], traps = [#magic_trap, #magic_trap]>

// CHECK-LABEL: func.func @native_ops
func.func @native_ops() {
  // CHECK: %[[INIT:.*]]:2 = magic.init : !chain{{[0-9]*}}, !chain{{[0-9]*}}
  %a0, %b0 = magic.init : !t0, !t1

  // CHECK: %[[A1:.*]] = magic.sym_zxz %[[INIT]]#0 ions [0] {x = [1.570800e+00], z = [1.570800e+00]} : !chain{{[0-9]*}}
  %a1 = magic.sym_zxz %a0 ions [0] {z = [1.5708], x = [1.5708]} : !t0
  // CHECK: %[[A2:.*]] = magic.delay %[[A1]] {ticks = 2491 : i64} : !chain{{[0-9]*}}
  %a2 = magic.delay %a1 {ticks = 2491} : !t0
  // CHECK: %[[A3:.*]] = magic.rz %[[A2]] ions [0, 1] {angles = [-1.570800e+00, -1.570800e+00]} : !chain{{[0-9]*}}
  %a3 = magic.rz %a2 ions [0, 1] {angles = [-1.5708, -1.5708]} : !t0

  // CHECK: %[[B1:.*]] = magic.recode %[[INIT]]#1 : !chain{{[0-9]*}} -> !chain{{[0-9]*}}
  %b1 = magic.recode %b0 : !t1 -> !t1i
  // CHECK: %[[B2:.*]] = magic.delay %[[B1]] {ticks = 2491 : i64}
  %b2 = magic.delay %b1 {ticks = 2491} : !t1i
  // CHECK: %[[B3:.*]] = magic.recode %[[B2]]
  %b3 = magic.recode %b2 : !t1i -> !t1

  // CHECK: %[[FROM:.*]], %[[TO:.*]] = magic.shuttle %[[A3]], %[[B3]] : !chain{{[0-9]*}}, !chain{{[0-9]*}} -> !chain{{[0-9]*}}, !chain{{[0-9]*}}
  %a4, %b4 = magic.shuttle %a3, %b3 : !t0, !t1 -> !t0s, !t1s

  // CHECK: %[[M0:.*]] = magic.mzd %[[FROM]] : !chain{{[0-9]*}} -> i1
  %m0 = magic.mzd %a4 : !t0s -> i1
  // CHECK: %[[M12:.*]]:2 = magic.mzd %[[TO]] : !chain{{[0-9]*}} -> i1, i1
  %m1, %m2 = magic.mzd %b4 : !t1s -> i1, i1
  // CHECK: aux.record_int %[[M0]] : i1
  aux.record_int %m0 : i1
  // CHECK: aux.record_int %[[M12]]#0 : i1
  aux.record_int %m1 : i1
  // CHECK: aux.record_int %[[M12]]#1 : i1
  aux.record_int %m2 : i1
  return
}

// CHECK-LABEL: func.func @intermediate_ops
func.func @intermediate_ops() {
  // CHECK: %[[INIT:.*]]:2 = magic.init
  %a0, %b0 = magic.init : !t0, !t1
  // CHECK: %[[A1:.*]] = magic.zxz %[[INIT]]#0 ions [0, 1] {x = [3.141600e+00, 1.570800e+00], z1 = [0.000000e+00, 1.570800e+00], z2 = [0.000000e+00, -1.570800e+00]} : !chain{{[0-9]*}}
  %a1 = magic.zxz %a0 ions [0, 1] {z1 = [0.0, 1.5708], x = [3.1416, 1.5708], z2 = [0.0, -1.5708]} : !t0
  // CHECK: %[[A2:.*]] = magic.active_zz %[[A1]] {angles = dense<{{\[\[}}0.000000e+00, 1.570800e+00], [1.570800e+00, 0.000000e+00]]> : tensor<2x2xf64>} : !chain{{[0-9]*}}
  %a2 = magic.active_zz %a1 {angles = dense<[[0.0, 1.5708], [1.5708, 0.0]]> : tensor<2x2xf64>} : !t0
  // CHECK: %[[A3:.*]], %[[B1:.*]] = magic.inter_trap_zz %[[A2]], %[[INIT]]#1 ions [1, 2] {angle = 7.854000e-01 : f64} : !chain{{[0-9]*}}, !chain{{[0-9]*}}
  %a3, %b1 = magic.inter_trap_zz %a2, %b0 ions [1, 2] {angle = 0.7854} : !t0, !t1
  // CHECK: magic.swap %[[A3]] ions [1, 0] : !chain{{[0-9]*}}
  %a4 = magic.swap %a3 ions [1, 0] : !t0
  return
}

// Ion ids are not positions: the chain lists ions front to back, ops refer to ids.
// CHECK-LABEL: func.func @ids_not_positions
func.func @ids_not_positions() {
  // CHECK: magic.init : !chain{{[0-9]*}}
  // CHECK: magic.rz %{{.*}} ions [7] {angles = [1.000000e+00]}
  %c0 = magic.init : !magic.ion_chain<0, [5:1, 7:1, 3:1]>
  %c1 = magic.rz %c0 ions [7] {angles = [1.0]} : !magic.ion_chain<0, [5:1, 7:1, 3:1]>
  // Only two ions are active, so the ZZ matrix is 2x2.
  // CHECK: magic.recode
  %c2 = magic.recode %c1 : !magic.ion_chain<0, [5:1, 7:1, 3:1]> -> !magic.ion_chain<0, [5:1, 7:0, 3:1]>
  // CHECK: magic.active_zz %{{.*}} {angles = dense<{{\[\[}}0.000000e+00, 5.000000e-01], [5.000000e-01, 0.000000e+00]]> : tensor<2x2xf64>}
  %c3 = magic.active_zz %c2 {angles = dense<[[0.0, 0.5], [0.5, 0.0]]> : tensor<2x2xf64>} : !magic.ion_chain<0, [5:1, 7:0, 3:1]>
  // Shuttling an ion into an empty trap.
  // CHECK: magic.shuttle
  %d0 = magic.init : !magic.ion_chain<1, []>
  %c4, %d1 = magic.shuttle %c3, %d0 : !magic.ion_chain<0, [5:1, 7:0, 3:1]>, !magic.ion_chain<1, []>
                                    -> !magic.ion_chain<0, [7:0, 3:1]>, !magic.ion_chain<1, [5:1]>
  return
}

// A whole program: a two-trap device, padding on the idle trap, one shuttle.
#trap = #qcc.magic_trap<capacity = 3, couplings = [
  dense<0.0> : tensor<1x1xf64>,
  dense<[[0.0, 297.4], [297.4, 0.0]]> : tensor<2x2xf64>,
  dense<[[0.0, 297.4, 150.0], [297.4, 0.0, 297.4], [150.0, 297.4, 0.0]]> : tensor<3x3xf64>]>

// CHECK: module attributes {qcc.device = #magic_device}
module attributes {qcc.device = #qcc.magic_device<name = "two-trap", time_unit_ns = 1000, initial_occupancies = [2, 1], traps = [#trap, #trap]>} {
  // CHECK: func.func @main() attributes {qcc.entry_point}
  func.func @main() attributes {qcc.entry_point} {
    %a0, %b0 = magic.init : !t0, !t1

    // segment 1: trap 0 works, trap 1 idles (padding)
    %a1 = magic.sym_zxz %a0 ions [0] {z = [1.5708], x = [1.5708]} : !t0
    %a2 = magic.delay %a1 {ticks = 2491} : !t0
    %a3 = magic.rz %a2 ions [0, 1] {angles = [-1.5708, -1.5708]} : !t0
    %b1 = magic.recode %b0 : !t1 -> !t1i
    %b2 = magic.delay %b1 {ticks = 2491} : !t1i
    %b3 = magic.recode %b2 : !t1i -> !t1

    // sync point
    %a4, %b4 = magic.shuttle %a3, %b3 : !t0, !t1 -> !t0s, !t1s

    // segment 2: trap 1 works, trap 0 pads
    %b5 = magic.sym_zxz %b4 ions [0] {z = [0.0], x = [3.1416]} : !t1s
    %b6 = magic.delay %b5 {ticks = 4982} : !t1s
    %a5 = magic.recode %a4 : !t0s -> !t0i
    %a6 = magic.delay %a5 {ticks = 4982} : !t0i
    %a7 = magic.recode %a6 : !t0i -> !t0s

    %m0 = magic.mzd %a7 : !t0s -> i1
    %m1, %m2 = magic.mzd %b6 : !t1s -> i1, i1
    aux.record_int %m0 : i1
    aux.record_int %m1 : i1
    aux.record_int %m2 : i1
    return
  }
}
