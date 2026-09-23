// RUN: qcc-opt %s --split-input-file --verify-diagnostics

// expected-error @+1 {{ion id must be non-negative, got -1}}
func.func @negative_ion(%c: !magic.ion_chain<0, [-1:1]>) {
  return
}

// -----

// expected-error @+1 {{ion 3 appears more than once}}
func.func @duplicate_ion(%c: !magic.ion_chain<0, [3:1, 3:0]>) {
  return
}

// -----

// expected-error @+1 {{expected activation 0 or 1, got 2}}
func.func @bad_activation(%c: !magic.ion_chain<0, [3:2]>) {
  return
}

// -----

func.func @fork() {
  %c0 = magic.init : !magic.ion_chain<0, [0:1]>
  %c1 = magic.rz %c0 ions [0] {angles = [1.0]} : !magic.ion_chain<0, [0:1]>
  // expected-error @+1 {{'magic.rz' op chain operand #0 is used more than once, but chain values are affine}}
  %c2 = magic.rz %c0 ions [0] {angles = [2.0]} : !magic.ion_chain<0, [0:1]>
  return
}

// -----

func.func @init_duplicate_ion() {
  // expected-error @+1 {{'magic.init' op ion 1 is placed in more than one trap}}
  %a, %b = magic.init : !magic.ion_chain<0, [0:1, 1:1]>, !magic.ion_chain<1, [1:1]>
  return
}

// -----

func.func @init_duplicate_trap() {
  // expected-error @+1 {{'magic.init' op trap 0 is initialized more than once}}
  %a, %b = magic.init : !magic.ion_chain<0, [0:1]>, !magic.ion_chain<0, [1:1]>
  return
}

// -----

func.func @init_inactive() {
  // expected-error @+1 {{'magic.init' op ion 0 must be active initially}}
  %a = magic.init : !magic.ion_chain<0, [0:0]>
  return
}

// -----

func.func @ion_not_in_chain() {
  %c0 = magic.init : !magic.ion_chain<0, [0:1, 1:1]>
  // expected-error @+1 {{'magic.sym_zxz' op ion 2 is not in the chain '!magic.ion_chain<0, [0:1, 1:1]>'}}
  %c1 = magic.sym_zxz %c0 ions [2] {z = [0.0], x = [0.0]} : !magic.ion_chain<0, [0:1, 1:1]>
  return
}

// -----

func.func @ion_listed_twice() {
  %c0 = magic.init : !magic.ion_chain<0, [0:1, 1:1]>
  // expected-error @+1 {{'magic.rz' op ion 1 is listed more than once}}
  %c1 = magic.rz %c0 ions [1, 1] {angles = [0.0, 0.0]} : !magic.ion_chain<0, [0:1, 1:1]>
  return
}

// -----

func.func @angle_count() {
  %c0 = magic.init : !magic.ion_chain<0, [0:1, 1:1]>
  // expected-error @+1 {{'magic.zxz' op expected one 'x' angle per ion, got 1 for 2 ions}}
  %c1 = magic.zxz %c0 ions [0, 1] {z1 = [0.0, 0.0], x = [0.0], z2 = [0.0, 0.0]} : !magic.ion_chain<0, [0:1, 1:1]>
  return
}

// -----

func.func @active_zz_size() {
  %c0 = magic.init : !magic.ion_chain<0, [0:1, 1:1, 2:1]>
  %c1 = magic.recode %c0 : !magic.ion_chain<0, [0:1, 1:1, 2:1]> -> !magic.ion_chain<0, [0:1, 1:0, 2:1]>
  // expected-error @+1 {{'magic.active_zz' op expected angles of type tensor<2x2xf64> for 2 active ions, got 'tensor<3x3xf64>'}}
  %c2 = magic.active_zz %c1 {angles = dense<0.0> : tensor<3x3xf64>} : !magic.ion_chain<0, [0:1, 1:0, 2:1]>
  return
}

// -----

func.func @active_zz_asymmetric() {
  %c0 = magic.init : !magic.ion_chain<0, [0:1, 1:1]>
  // expected-error @+1 {{'magic.active_zz' op angles must be symmetric}}
  %c1 = magic.active_zz %c0 {angles = dense<[[0.0, 1.0], [2.0, 0.0]]> : tensor<2x2xf64>} : !magic.ion_chain<0, [0:1, 1:1]>
  return
}

// -----

func.func @active_zz_diagonal() {
  %c0 = magic.init : !magic.ion_chain<0, [0:1, 1:1]>
  // expected-error @+1 {{'magic.active_zz' op angles must have a zero diagonal}}
  %c1 = magic.active_zz %c0 {angles = dense<[[1.0, 0.0], [0.0, 1.0]]> : tensor<2x2xf64>} : !magic.ion_chain<0, [0:1, 1:1]>
  return
}

// -----

func.func @negative_delay() {
  %c0 = magic.init : !magic.ion_chain<0, [0:1]>
  // expected-error @+1 {{'magic.delay' op attribute 'ticks' failed to satisfy constraint: 64-bit signless integer attribute whose value is non-negative}}
  %c1 = magic.delay %c0 {ticks = -1} : !magic.ion_chain<0, [0:1]>
  return
}

// -----

func.func @recode_changes_ions() {
  %c0 = magic.init : !magic.ion_chain<0, [0:1, 1:1]>
  // expected-error @+1 {{'magic.recode' op operand and result must hold the same ions in the same order}}
  %c1 = magic.recode %c0 : !magic.ion_chain<0, [0:1, 1:1]> -> !magic.ion_chain<0, [1:1, 0:0]>
  return
}

// -----

func.func @recode_changes_nothing() {
  %c0 = magic.init : !magic.ion_chain<0, [0:1, 1:1]>
  // expected-error @+1 {{'magic.recode' op expected at least one activation to change}}
  %c1 = magic.recode %c0 : !magic.ion_chain<0, [0:1, 1:1]> -> !magic.ion_chain<0, [0:1, 1:1]>
  return
}

// -----

func.func @recode_changes_trap() {
  %c0 = magic.init : !magic.ion_chain<0, [0:1]>
  // expected-error @+1 {{'magic.recode' op operand and result must belong to the same trap}}
  %c1 = magic.recode %c0 : !magic.ion_chain<0, [0:1]> -> !magic.ion_chain<1, [0:0]>
  return
}

// -----

func.func @shuttle_same_trap() {
  %a = magic.init : !magic.ion_chain<0, [0:1]>
  // expected-error @+1 {{'magic.shuttle' op cannot shuttle within trap 0}}
  %a1, %a2 = magic.shuttle %a, %a : !magic.ion_chain<0, [0:1]>, !magic.ion_chain<0, [0:1]> -> !magic.ion_chain<0, []>, !magic.ion_chain<0, [0:1]>
  return
}

// -----

func.func @shuttle_two_ions() {
  %a, %b = magic.init : !magic.ion_chain<0, [0:1, 1:1]>, !magic.ion_chain<1, [2:1]>
  // expected-error @+1 {{'magic.shuttle' op expected the destination to receive exactly one ion at its front, got '!magic.ion_chain<1, [2:1]>' -> '!magic.ion_chain<1, [0:1, 1:1, 2:1]>'}}
  %a1, %b1 = magic.shuttle %a, %b : !magic.ion_chain<0, [0:1, 1:1]>, !magic.ion_chain<1, [2:1]> -> !magic.ion_chain<0, []>, !magic.ion_chain<1, [0:1, 1:1, 2:1]>
  return
}

// -----

func.func @shuttle_not_to_front() {
  %a, %b = magic.init : !magic.ion_chain<0, [0:1, 1:1]>, !magic.ion_chain<1, [2:1]>
  // expected-error @+1 {{'magic.shuttle' op expected the destination to receive exactly one ion at its front, got '!magic.ion_chain<1, [2:1]>' -> '!magic.ion_chain<1, [2:1, 0:1]>'}}
  %a1, %b1 = magic.shuttle %a, %b : !magic.ion_chain<0, [0:1, 1:1]>, !magic.ion_chain<1, [2:1]> -> !magic.ion_chain<0, [1:1]>, !magic.ion_chain<1, [2:1, 0:1]>
  return
}

// -----

func.func @shuttle_not_from_front() {
  %a, %b = magic.init : !magic.ion_chain<0, [0:1, 1:1]>, !magic.ion_chain<1, [2:1]>
  // expected-error @+1 {{'magic.shuttle' op can only shuttle the front ion of the source chain, got ion 1 at position 1 of '!magic.ion_chain<0, [0:1, 1:1]>'}}
  %a1, %b1 = magic.shuttle %a, %b : !magic.ion_chain<0, [0:1, 1:1]>, !magic.ion_chain<1, [2:1]> -> !magic.ion_chain<0, [0:1]>, !magic.ion_chain<1, [1:1, 2:1]>
  return
}

// -----

func.func @shuttle_wrong_source_result() {
  %a, %b = magic.init : !magic.ion_chain<0, [0:1, 1:1]>, !magic.ion_chain<1, [2:1]>
  // expected-error @+1 {{'magic.shuttle' op expected the source to lose exactly ion 0, got '!magic.ion_chain<0, [0:1, 1:1]>' -> '!magic.ion_chain<0, [0:1]>'}}
  %a1, %b1 = magic.shuttle %a, %b : !magic.ion_chain<0, [0:1, 1:1]>, !magic.ion_chain<1, [2:1]> -> !magic.ion_chain<0, [0:1]>, !magic.ion_chain<1, [0:1, 2:1]>
  return
}

// -----

func.func @shuttle_changes_activation() {
  %a, %b = magic.init : !magic.ion_chain<0, [0:1, 1:1]>, !magic.ion_chain<1, [2:1]>
  // expected-error @+1 {{'magic.shuttle' op ion 0 must keep its activation}}
  %a1, %b1 = magic.shuttle %a, %b : !magic.ion_chain<0, [0:1, 1:1]>, !magic.ion_chain<1, [2:1]> -> !magic.ion_chain<0, [1:1]>, !magic.ion_chain<1, [0:0, 2:1]>
  return
}

// -----

func.func @mzd_result_count() {
  %c0 = magic.init : !magic.ion_chain<0, [0:1, 1:1]>
  // expected-error @+1 {{'magic.mzd' op expected one result per ion, got 1 for 2 ions}}
  %m = magic.mzd %c0 : !magic.ion_chain<0, [0:1, 1:1]> -> i1
  return
}

// -----

func.func @inter_trap_zz_same_trap() {
  %a, %b = magic.init : !magic.ion_chain<0, [0:1]>, !magic.ion_chain<1, [1:1]>
  %a1 = magic.rz %a ions [0] {angles = [0.0]} : !magic.ion_chain<0, [0:1]>
  // expected-error @+1 {{'magic.inter_trap_zz' op chains must belong to different traps, both are trap 0}}
  %a2, %a3 = magic.inter_trap_zz %a1, %a1 ions [0, 0] {angle = 1.0} : !magic.ion_chain<0, [0:1]>, !magic.ion_chain<0, [0:1]>
  return
}

// -----

func.func @inter_trap_zz_ion_not_in_chain() {
  %a, %b = magic.init : !magic.ion_chain<0, [0:1]>, !magic.ion_chain<1, [1:1]>
  // expected-error @+1 {{'magic.inter_trap_zz' op ion 1 is not in the first chain '!magic.ion_chain<0, [0:1]>'}}
  %a1, %b1 = magic.inter_trap_zz %a, %b ions [1, 0] {angle = 1.0} : !magic.ion_chain<0, [0:1]>, !magic.ion_chain<1, [1:1]>
  return
}

// -----

func.func @swap_one_ion() {
  %c0 = magic.init : !magic.ion_chain<0, [0:1, 1:1]>
  // expected-error @+1 {{'magic.swap' op expected exactly two ions, got 1}}
  %c1 = magic.swap %c0 ions [0] : !magic.ion_chain<0, [0:1, 1:1]>
  return
}

// -----

func.func @swap_same_ion() {
  %c0 = magic.init : !magic.ion_chain<0, [0:1, 1:1]>
  // expected-error @+1 {{'magic.swap' op ion 0 is listed more than once}}
  %c1 = magic.swap %c0 ions [0, 0] : !magic.ion_chain<0, [0:1, 1:1]>
  return
}
