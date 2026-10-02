// RUN: qcc-opt %s --qcc-attach-device=file=%S/../Qcc/Inputs/device-2x3.mlir --magic-verify --split-input-file --verify-diagnostics

// The device: two traps of capacity 3.

//===----------------------------------------------------------------------===//
// Valid programs
//===----------------------------------------------------------------------===//

!t0 = !magic.ion_chain<0, [0:1, 1:1]>
!t1 = !magic.ion_chain<1, [2:1, 3:1]>
!t1i = !magic.ion_chain<1, [2:0, 3:0]>
!t0s = !magic.ion_chain<0, [1:1]>
!t1s = !magic.ion_chain<1, [0:1, 2:1, 3:1]>

// The example program of the dialect on this device: padding on the idle trap, one shuttle, everything measured
// and recorded.
func.func @main() attributes {qcc.entry_point} {
  %a0, %b0 = magic.init : !t0, !t1
  %a1 = magic.sym_zxz %a0 ions [0] {z = [1.5708], x = [1.5708]} : !t0
  %a2 = magic.delay %a1 {ticks = 2491} : !t0
  %a3 = magic.rz %a2 ions [0, 1] {angles = [-1.5708, -1.5708]} : !t0
  %b1 = magic.recode %b0 : !t1 -> !t1i
  %b2 = magic.delay %b1 {ticks = 2491} : !t1i
  %b3 = magic.recode %b2 : !t1i -> !t1
  %a4, %b4 = magic.shuttle %a3, %b3 : !t0, !t1 -> !t0s, !t1s
  %b5 = magic.sym_zxz %b4 ions [0] {z = [0.0], x = [3.1416]} : !t1s
  %b6 = magic.delay %b5 {ticks = 4982} : !t1s
  %m1 = magic.mzd %a4 : !t0s -> i1
  %m0, %m2, %m3 = magic.mzd %b6 : !t1s -> i1, i1, i1
  aux.record_int %m0 : i1
  aux.record_int %m1 : i1
  aux.record_int %m2 : i1
  aux.record_int %m3 : i1
  return
}

// -----

!t0 = !magic.ion_chain<0, [0:1]>
!t1 = !magic.ion_chain<1, [1:1]>

// The measurement is no sync point: the traps may have spent different times when they are measured.
func.func @measurement_need_no_syncing() {
  %a0, %b0 = magic.init : !t0, !t1
  %a1 = magic.delay %a0 {ticks = 10} : !t0
  %m0 = magic.mzd %a1 : !t0 -> i1
  %m1 = magic.mzd %b0 : !t1 -> i1
  aux.record_int %m0 : i1
  aux.record_int %m1 : i1
  return
}

// -----

!t0 = !magic.ion_chain<0, [0:1, 1:1]>
!t1 = !magic.ion_chain<1, [2:1]>

// Measuring and recording are optional: trap 1 is not measured, the result of ion 1 is not recorded.
func.func @partly_observed() {
  %a0, %b0 = magic.init : !t0, !t1
  %m0, %m1 = magic.mzd %a0 : !t0 -> i1, i1
  aux.record_int %m0 : i1
  return
}

// -----

// A module without magic code.
func.func @no_magic() {
  return
}

// -----

//===----------------------------------------------------------------------===//
// Violations
//===----------------------------------------------------------------------===//

!t0 = !magic.ion_chain<0, [0:1]>

func.func @two_inits() {
  // expected-note @+1 {{the program's 'magic.init' is here}}
  %a0 = magic.init : !t0
  // expected-error @+1 {{a program has at most one 'magic.init': one op creates the chains of all traps}}
  %b0 = magic.init : !magic.ion_chain<1, []>
  %m0 = magic.mzd %a0 : !t0 -> i1
  aux.record_int %m0 : i1
  return
}

// -----

!t0 = !magic.ion_chain<0, [1:1, 0:1]>

func.func @wrong_ions() {
  // expected-error @+1 {{expected trap 0 to start with the ions [0, 1], got '!magic.ion_chain<0, [1:1, 0:1]>': ion ids are assigned trap by trap}}
  %a0 = magic.init : !t0
  %m1, %m0 = magic.mzd %a0 : !t0 -> i1, i1
  aux.record_int %m0 : i1
  aux.record_int %m1 : i1
  return
}

// -----

func.func @unknown_trap() {
  // expected-error @+1 {{'magic.init' op produces a chain of trap 2, but the device has 2 traps}}
  %a0 = magic.init : !magic.ion_chain<2, [0:1]>
  %m0 = magic.mzd %a0 : !magic.ion_chain<2, [0:1]> -> i1
  aux.record_int %m0 : i1
  return
}

// -----

!t0 = !magic.ion_chain<0, [0:1, 1:1, 2:1, 3:1]>

func.func @over_capacity() {
  // expected-error @+1 {{'magic.init' op puts 4 ions into trap 0, which holds at most 3}}
  %a0 = magic.init : !t0
  %m0, %m1, %m2, %m3 = magic.mzd %a0 : !t0 -> i1, i1, i1, i1
  aux.record_int %m0 : i1
  aux.record_int %m1 : i1
  aux.record_int %m2 : i1
  aux.record_int %m3 : i1
  return
}

// -----

!t0 = !magic.ion_chain<0, [0:1]>

func.func @not_native() {
  %a0 = magic.init : !t0
  // expected-error @+1 {{'magic.zxz' op is not native to the device and must be lowered before export}}
  %a1 = magic.zxz %a0 ions [0] {z1 = [0.1], x = [0.2], z2 = [0.3]} : !t0
  %m0 = magic.mzd %a1 : !t0 -> i1
  aux.record_int %m0 : i1
  return
}

// -----

!t0 = !magic.ion_chain<0, [0:1]>
!t1 = !magic.ion_chain<1, [1:1]>
!t0s = !magic.ion_chain<0, []>
!t1s = !magic.ion_chain<1, [0:1, 1:1]>

func.func @unbalanced() {
  %a0, %b0 = magic.init : !t0, !t1
  %a1 = magic.delay %a0 {ticks = 10} : !t0
  // expected-error @+1 {{'magic.shuttle' op has unbalanced timing: trap 0 has spent 10 ticks, but trap 1 0; the two traps of a shuttle must have spent the same time}}
  %a2, %b1 = magic.shuttle %a1, %b0 : !t0, !t1 -> !t0s, !t1s
  %m0, %m1 = magic.mzd %b1 : !t1s -> i1, i1
  aux.record_int %m0 : i1
  aux.record_int %m1 : i1
  return
}

// -----

!t0 = !magic.ion_chain<0, [0:1]>

func.func @recorded_twice() {
  %a0 = magic.init : !t0
  // expected-error @+1 {{'magic.mzd' op must have its result for ion 0 recorded by at most one 'aux.record_int' and used nowhere else}}
  %m0 = magic.mzd %a0 : !t0 -> i1
  aux.record_int %m0 : i1
  aux.record_int %m0 : i1
  return
}

// -----

!t0 = !magic.ion_chain<0, [0:1]>

func.func @other_record() {
  %a0 = magic.init : !t0
  %m0 = magic.mzd %a0 : !t0 -> i1
  aux.record_int %m0 : i1
  %c = arith.constant 7 : i64
  // expected-error @+1 {{records a value that is not a 'magic.mzd' result; a program records its measurements}}
  aux.record_int %c : i64
  return
}
