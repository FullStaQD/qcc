// RUN: qcc-opt %s --magic-layer --split-input-file --verify-diagnostics

!a = !magic.ion_chain<0, [0:1]>
!b = !magic.ion_chain<1, [1:1]>

func.func @second_init() {
  %a0 = magic.init : !a
  // expected-error @+1 {{'magic.init' op is the second 'magic.init' of the program: expected at most one}}
  %b0 = magic.init : !b
  return
}

// -----

!c = !magic.ion_chain<0, [0:1]>

func.func @chain_returned() -> !c {
  %c0 = magic.init : !c
  %c1 = magic.rz %c0 ions [0] {angles = [0.5]} : !c
  // expected-error @+1 {{'func.return' op is not a magic op but uses an ion chain, which magic-layer does not support}}
  return %c1 : !c
}

// -----

!c = !magic.ion_chain<0, [0:1]>

func.func private @sink(!c)

func.func @chain_used_in_region(%flag: i1) {
  %c0 = magic.init : !c
  %c1 = magic.rz %c0 ions [0] {angles = [0.5]} : !c
  scf.if %flag {
    // expected-error @+1 {{'func.call' op is not a magic op but uses an ion chain, which magic-layer does not support}}
    func.call @sink(%c1) : (!c) -> ()
  }
  return
}
