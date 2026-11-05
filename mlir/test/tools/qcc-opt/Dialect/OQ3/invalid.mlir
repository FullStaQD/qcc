// RUN: qcc-opt %s --split-input-file --verify-diagnostics

//===----------------------------------------------------------------------===//
// The program
//===----------------------------------------------------------------------===//

// expected-error @below {{'builtin.module' op is an OpenQASM program ('oq3.version'), so it needs an entry function ('qcc.entry_point')}}
module attributes {oq3.version = #oq3.version<3, 1>} {}

// -----

// expected-error @below {{'func.func' op attribute 'oq3.version' is only valid on a module}}
func.func @f() attributes {oq3.version = #oq3.version<3, 1>} {
  return
}

// -----

// expected-error-re @below {{unsupported OpenQASM version 1.9, supported are {{.*}}}}
module attributes {oq3.version = #oq3.version<1, 9>} {}

// -----

module attributes {oq3.version = #oq3.version<3, 1>} {
  // expected-note @below {{the first entry function is here}}
  func.func @main() attributes {qcc.entry_point} {
    return
  }
  // expected-error @below {{'func.func' op is a second entry function, but a program has exactly one}}
  func.func @other() attributes {qcc.entry_point} {
    return
  }
}

// -----

module attributes {oq3.version = #oq3.version<3, 1>} {
  // expected-error @below {{'llvm.func' op cannot be an entry point: oq3 allows only 'func.func' entry points}}
  llvm.func @main() attributes {qcc.entry_point} {
    llvm.return
  }
}

// -----

module attributes {oq3.version = #oq3.version<3, 1>} {
  // expected-error @below {{'func.func' op is the entry function of an OpenQASM program, so it takes no arguments and returns no results}}
  func.func @main(%arg: i1) attributes {qcc.entry_point} {
    return
  }
}

// -----

module attributes {oq3.version = #oq3.version<3, 1>} {
  // expected-error @below {{'func.func' op is a global definition, but the entry body has no 'oq3.defined @f' marker for its position}}
  func.func private @f()
  func.func @main() attributes {qcc.entry_point} {
    return
  }
}

// -----

module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @main() attributes {qcc.entry_point} {
    // expected-error @below {{'oq3.defined' op marks '@g', which is no global definition of the module}}
    oq3.defined @g
    return
  }
}

// -----

module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func private @f()
  func.func @main() attributes {qcc.entry_point} {
    // expected-note @below {{the first marker is here}}
    oq3.defined @f
    // expected-error @below {{'oq3.defined' op marks '@f' a second time}}
    oq3.defined @f
    return
  }
}

// -----

module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func private @f()
  func.func @main() attributes {qcc.entry_point} {
    // expected-error @below {{'func.call' op uses '@f' before its definition}}
    func.call @f() : () -> ()
    // expected-note @below {{it is defined here}}
    oq3.defined @f
    return
  }
}

// -----

// A definition may use itself and what is defined before it, but nothing defined after it.
module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @f() {
    func.call @f() : () -> ()
    // expected-error @below {{'func.call' op uses '@g' before its definition}}
    func.call @g() : () -> ()
    return
  }
  func.func private @g()
  func.func @main() attributes {qcc.entry_point} {
    oq3.defined @f
    // expected-note @below {{it is defined here}}
    oq3.defined @g
    return
  }
}

// -----

func.func @not_entry() {
  // expected-error @below {{'oq3.defined' op is only valid directly in the entry function ('qcc.entry_point')}}
  oq3.defined @not_entry
  return
}

// -----

// expected-error @below {{'builtin.module' op attribute 'oq3.version' must be an '#oq3.version', got "3.1"}}
module attributes {oq3.version = "3.1"} {}

// -----

module attributes {oq3.version = #oq3.version<3, 1>} {
  // expected-error @below {{'func.func' op is the entry function of an OpenQASM program, so it needs a body of one block}}
  func.func private @main() attributes {qcc.entry_point}
}

// -----

//===----------------------------------------------------------------------===//
// Includes
//===----------------------------------------------------------------------===//

module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @main() attributes {qcc.entry_point} {
    // expected-note @below {{the other include is here}}
    oq3.include "a.inc" id 0
    // expected-error @below {{'oq3.include' op has the id 0 of another include}}
    oq3.include "b.inc" id 0
    return
  }
}

// -----

module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @main() attributes {qcc.entry_point} {
    // expected-error @below {{'oq3.qubit_decl' op is tagged 'oq3.from_include = 3', but no include has that id}}
    %q = oq3.qubit_decl "q" {oq3.from_include = 3} : !qcc.qubit_ref
    return
  }
}

// -----

module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @main() attributes {qcc.entry_point} {
    // expected-error @below {{'oq3.include' op path must be non-empty, a single line, and not contain both kinds of quotes}}
    oq3.include "" id 0
    return
  }
}

// -----

module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @main() attributes {qcc.entry_point} {
    // expected-error @below {{'oq3.qubit_decl' op attribute 'oq3.from_include' must be an include id, got "a.inc"}}
    %q = oq3.qubit_decl "q" {oq3.from_include = "a.inc"} : !qcc.qubit_ref
    return
  }
}

// -----

//===----------------------------------------------------------------------===//
// Directives
//===----------------------------------------------------------------------===//

module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @main() attributes {qcc.entry_point} {
    // expected-error @below {{'oq3.pragma' op text must be a non-empty single line without leading whitespace}}
    oq3.pragma " x"
    return
  }
}

// -----

module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @main() attributes {qcc.entry_point} {
    // expected-error @below {{'oq3.qubit_decl' op attribute 'oq3.annotations' must be an array of '#oq3.annotation', got ["x"]}}
    %q = oq3.qubit_decl "q" {oq3.annotations = ["x"]} : !qcc.qubit_ref
    return
  }
}

// -----

// expected-error @below {{annotation keyword must be a dotted identifier without '@', got '@ns'}}
func.func private @f() attributes {a = #oq3.annotation<"@ns", "">}

// -----

// expected-error @below {{'func.func' op has the unknown attribute 'oq3.unknown_attribute'}}
func.func private @f() attributes {oq3.unknown_attribute}

// -----

// expected-error @below {{'func.func' op attribute 'oq3.annotations' is only valid on a statement}}
func.func private @f() attributes {oq3.annotations = [#oq3.annotation<"ns.name", "">]}

// -----

// expected-error @below {{annotation content must be a single line}}
func.func private @f() attributes {a = #oq3.annotation<"ns.name", "a\nb">}

// -----

//===----------------------------------------------------------------------===//
// Declarations
//===----------------------------------------------------------------------===//

func.func @not_entry() {
  // expected-error @below {{'oq3.qubit_decl' op is only valid directly in the entry function ('qcc.entry_point')}}
  %q = oq3.qubit_decl "q" : !qcc.qubit_ref
  return
}

// -----

module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @main() attributes {qcc.entry_point} {
    %three = oq3.constant #oq3.int<3> : !oq3.int
    // expected-error @below {{'oq3.qubit_decl' op designator evaluates to 3, but the type has size 2}}
    %q = oq3.qubit_decl "q" [%three : !oq3.int] : !oq3.qreg<2>
    return
  }
}

// -----

module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @main() attributes {qcc.entry_point} {
    %two = oq3.constant #oq3.int<2> : !oq3.int
    // expected-error @below {{'oq3.qubit_decl' op declares a single qubit, so it takes no designator}}
    %q = oq3.qubit_decl "q" [%two : !oq3.int] : !qcc.qubit_ref
    return
  }
}

// -----

module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @main() attributes {qcc.entry_point} {
    %c = oq3.declare "c" : !qcc.ref<!oq3.bit>
    %bit = qcc.ref.load %c : !qcc.ref<!oq3.bit>
    // expected-error @below {{'oq3.qubit_decl' op designator must be an unsized integer, got '!oq3.bit'}}
    %q = oq3.qubit_decl "q" [%bit : !oq3.bit] : !oq3.qreg<1>
    return
  }
}

// -----

module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @main() attributes {qcc.entry_point} {
    // expected-error @below {{'oq3.declare' op declares a variable of type '!oq3.int', but only 'bit' and 'bit[n]' variables are supported yet}}
    %i = oq3.declare "i" : !qcc.ref<!oq3.int>
    return
  }
}

// -----

module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @main() attributes {qcc.entry_point} {
    %bits = oq3.constant #oq3.bitstring<"01"> : !oq3.bits<2>
    // expected-error @below {{'oq3.declare' op initial value of type '!oq3.bits<2>' does not match the variable type '!oq3.bit'}}
    %c = oq3.declare "c" = %bits : !oq3.bits<2> : !qcc.ref<!oq3.bit>
    return
  }
}

// -----

module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @main() attributes {qcc.entry_point} {
    %c = oq3.declare "c" : !qcc.ref<!oq3.bit>
    %zero = oq3.constant #oq3.int<0> : !oq3.int
    // expected-error @below {{'oq3.subref' op can only index a bit register, got '!qcc.ref<!oq3.bit>'}}
    %c0 = oq3.subref %c[%zero] : !qcc.ref<!oq3.bit>, !oq3.int -> !qcc.ref<!oq3.bit>
    return
  }
}

// -----

module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @main() attributes {qcc.entry_point} {
    %two = oq3.constant #oq3.int<2> : !oq3.int
    %q = oq3.qubit_decl "q" [%two : !oq3.int] : !oq3.qreg<2>
    // expected-error @below {{'oq3.qubit_index' op index 2 is out of range for size 2}}
    %q2 = oq3.qubit_index %q[%two] : !oq3.qreg<2>, !oq3.int
    return
  }
}

// -----

module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @main() attributes {qcc.entry_point} {
    %one = oq3.constant #oq3.int<1> : !oq3.int
    %zero = oq3.constant #oq3.int<0> : !oq3.int
    %size = oq3.binary div %one, %zero : !oq3.int
    // expected-error @below {{'oq3.qubit_decl' op designator must be a constant expression}}
    %q = oq3.qubit_decl "q" [%size : !oq3.int] : !oq3.qreg<1>
    return
  }
}

// -----

module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @main() attributes {qcc.entry_point} {
    %one = oq3.constant #oq3.int<1> : !oq3.int
    // expected-error @below {{'oq3.declare' op declares a single bit, so it takes no designator}}
    %c = oq3.declare "c" [%one : !oq3.int] : !qcc.ref<!oq3.bit>
    return
  }
}

// -----

module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @main() attributes {qcc.entry_point} {
    %two = oq3.constant #oq3.int<2> : !oq3.int
    %c = oq3.declare "c" [%two : !oq3.int] : !qcc.ref<!oq3.bits<2>>
    %zero = oq3.constant #oq3.int<0> : !oq3.int
    // expected-error @below {{'oq3.subref' op a bit of a bit register has type '!qcc.ref<!oq3.bit>', got '!qcc.ref<!oq3.bits<1>>'}}
    %c0 = oq3.subref %c[%zero] : !qcc.ref<!oq3.bits<2>>, !oq3.int -> !qcc.ref<!oq3.bits<1>>
    return
  }
}

// -----

//===----------------------------------------------------------------------===//
// Expressions
//===----------------------------------------------------------------------===//

// expected-error @below {{an integer literal has type '!oq3.int', got '!oq3.float'}}
%x = oq3.constant #oq3.int<1> : !oq3.float

// -----

// expected-error @below {{a bitstring of 2 bit(s) has type '!oq3.bits<2>', got '!oq3.bits<3>'}}
%x = oq3.constant #oq3.bitstring<"01"> : !oq3.bits<3>

// -----

// expected-error @below {{an integer literal is non-negative}}
%x = oq3.constant #oq3.int<-1> : !oq3.int

// -----

%a = oq3.constant #oq3.int<1> : !oq3.int
%b = oq3.constant #oq3.float<"1.0"> : !oq3.float
// expected-error @below {{'oq3.binary' op unsupported operand types '!oq3.int' and '!oq3.float' with result type '!oq3.float' for 'add'}}
%c = oq3.binary add %a, %b : (!oq3.int, !oq3.float) -> !oq3.float

// -----

%f = oq3.constant #oq3.float<"1.0"> : !oq3.float
%a = oq3.cast %f implicit : !oq3.float -> !qcc.angle
// expected-error @below {{'oq3.binary' op cannot multiply two angles; scale an angle by an integer instead}}
%c = oq3.binary mul %a, %a : !qcc.angle

// -----

%f = oq3.constant #oq3.float<"1.0"> : !oq3.float
// expected-error @below {{'oq3.cast' op unsupported cast from '!oq3.float' to '!oq3.int'}}
%i = oq3.cast %f implicit : !oq3.float -> !oq3.int

// -----

%c = oq3.declare "c" : !qcc.ref<!oq3.bit>
%b = qcc.ref.load %c : !qcc.ref<!oq3.bit>
// expected-error @below {{'oq3.unary' op unsupported operand type '!oq3.bit'}}
%n = oq3.unary neg %b : !oq3.bit

// -----

module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @main() attributes {qcc.entry_point} {
    %two = oq3.constant #oq3.int<2> : !oq3.int
    %q = oq3.qubit_decl "q" [%two : !oq3.int] : !oq3.qreg<2>
    // expected-error @below {{'oq3.measure' op measuring '!oq3.qreg<2>' cannot yield '!oq3.bits<3>' (a qubit yields a bit, n qubits yield n bits)}}
    %m = oq3.measure %q : !oq3.qreg<2> -> !oq3.bits<3>
    return
  }
}

// -----

// expected-error @below {{expected the text of a floating-point literal, got 'one'}}
%x = oq3.constant #oq3.float<"one"> : !oq3.float

// -----

// expected-error @below {{a floating-point literal has type '!oq3.float', got '!oq3.int'}}
%x = oq3.constant #oq3.float<"1.0"> : !oq3.int

// -----

// expected-error @below {{a bitstring is a non-empty string of '0' and '1', got '012'}}
%x = oq3.constant #oq3.bitstring<"012"> : !oq3.bits<3>

// -----

// expected-error @below {{'oq3.constant' op unsupported literal 1 : i64}}
%x = "oq3.constant"() {value = 1 : i64} : () -> i64

// -----

module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @main() attributes {qcc.entry_point} {
    %two = oq3.constant #oq3.int<2> : !oq3.int
    %q = oq3.qubit_decl "q" [%two : !oq3.int] : !oq3.qreg<2>
    %zero = oq3.constant #oq3.float<"0.0"> : !oq3.float
    // expected-error @below {{'oq3.qubit_index' op index must be an unsized integer, got '!oq3.float'}}
    %q0 = oq3.qubit_index %q[%zero] : !oq3.qreg<2>, !oq3.float
    return
  }
}

// -----

//===----------------------------------------------------------------------===//
// Gate calls
//===----------------------------------------------------------------------===//

module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @main() attributes {qcc.entry_point} {
    %q = oq3.qubit_decl "q" : !qcc.qubit_ref
    // expected-error @below {{'oq3.gate_call' op calls the unknown gate 'h'}}
    // expected-note @below {{'h' is a standard gate; it needs an earlier 'include "stdgates.inc";'}}
    oq3.gate_call @h [%q : !qcc.qubit_ref]
    oq3.include "stdgates.inc" id 0
    return
  }
}

// -----

module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @main() attributes {qcc.entry_point} {
    oq3.include "stdgates.inc" id 0
    %q = oq3.qubit_decl "q" : !qcc.qubit_ref
    // expected-error @below {{'oq3.gate_call' op gate 'cx' takes 0 parameter(s) and 2 qubit(s), got 0 and 1}}
    oq3.gate_call @cx [%q : !qcc.qubit_ref]
    return
  }
}

// -----

module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @main() attributes {qcc.entry_point} {
    %q = oq3.qubit_decl "q" : !qcc.qubit_ref
    // expected-error @below {{'oq3.gate_call' op gate 'gphase' takes 1 parameter(s) and 0 qubit(s), got 0 and 1}}
    oq3.gate_call @gphase [%q : !qcc.qubit_ref]
    return
  }
}

// -----

module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @main() attributes {qcc.entry_point} {
    oq3.include "stdgates.inc" id 0
    %two = oq3.constant #oq3.int<2> : !oq3.int
    %three = oq3.constant #oq3.int<3> : !oq3.int
    %a = oq3.qubit_decl "a" [%two : !oq3.int] : !oq3.qreg<2>
    %b = oq3.qubit_decl "b" [%three : !oq3.int] : !oq3.qreg<3>
    // expected-error @below {{'oq3.gate_call' op registers of sizes 2 and 3 cannot be broadcast together}}
    oq3.gate_call @cx [%a, %b : !oq3.qreg<2>, !oq3.qreg<3>]
    return
  }
}

// -----

module attributes {oq3.version = #oq3.version<3, 1>} {
  // expected-note @below {{'@f' is defined here}}
  func.func private @f()
  func.func @main() attributes {qcc.entry_point} {
    oq3.defined @f
    // expected-error @below {{'oq3.gate_call' op calls '@f', which is not a gate}}
    oq3.gate_call @f
    return
  }
}

// -----

// expected-error @below {{size must be non-negative, got -1}}
func.func private @f() -> !oq3.qreg<-1>
