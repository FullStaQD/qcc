// RUN: qcc-opt %s --magic-verify --split-input-file --verify-diagnostics

// OK: One `magic.init` per program, creating the chains of every trap.
func.func @one_init() {
  %a, %b = magic.init : !magic.ion_chain<0, [0:1]>, !magic.ion_chain<1, [1:1]>
  %m0 = magic.mzd %a : !magic.ion_chain<0, [0:1]> -> i1
  %m1 = magic.mzd %b : !magic.ion_chain<1, [1:1]> -> i1
  return
}

// -----

func.func @two_inits() {
  // expected-note @+1 {{the program's 'magic.init' is here}}
  %a = magic.init : !magic.ion_chain<0, [0:1]>
  // expected-error @+1 {{a program has at most one 'magic.init': one op creates the chains of all traps}}
  %b = magic.init : !magic.ion_chain<1, [1:1]>
  %m0 = magic.mzd %a : !magic.ion_chain<0, [0:1]> -> i1
  %m1 = magic.mzd %b : !magic.ion_chain<1, [1:1]> -> i1
  return
}

// -----

// OK: A program is one function, so a module may hold several, each with its own `magic.init`.
func.func @program_one() {
  %a = magic.init : !magic.ion_chain<0, [0:1]>
  %m0 = magic.mzd %a : !magic.ion_chain<0, [0:1]> -> i1
  return
}

func.func @program_two() {
  %b = magic.init : !magic.ion_chain<1, [1:1]>
  %m1 = magic.mzd %b : !magic.ion_chain<1, [1:1]> -> i1
  return
}

// -----

// OK: A module without magic code.
func.func @no_magic() {
  return
}
