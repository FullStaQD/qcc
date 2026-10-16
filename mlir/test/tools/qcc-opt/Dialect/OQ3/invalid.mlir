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

// expected-error @below {{unsupported OpenQASM version 3.5, supported are 3.0, 3.1, and 3.2}}
module attributes {oq3.version = #oq3.version<3, 5>} {}

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
  // expected-error @below {{'llvm.func' op is the entry function of an OpenQASM program, so it must be a 'func.func'}}
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
    // expected-error @below {{'oq3.comment' op is tagged 'oq3.from_include = 3', but no include has that id}}
    oq3.comment "// from nowhere" {oq3.from_include = 3}
    return
  }
}

// -----

module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @main() attributes {qcc.entry_point} {
    // expected-error @below {{'oq3.unresolved' op is only valid in a program with an unresolved include}}
    %n = oq3.unresolved "n" : !oq3.unknown
    // TODO: We may relax this. Custom gates may be used by name-convention for special purposes.
    return
  }
}

// -----

module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @main() attributes {qcc.entry_point} {
    // expected-error @below {{'oq3.qubit_decl' op has a result of type '!oq3.qreg<?>', which is only valid in a program with an unresolved include}}
    %q = oq3.qubit_decl "q" : !oq3.qreg<?>
    return
  }
}

// -----

module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @main() attributes {qcc.entry_point} {
    oq3.include "vendor.inc" id 0 unresolved
    %q = oq3.qubit_decl "q" : !qcc.qubit_ref
    // expected-note @below {{the other call is here}}
    oq3.gate_call @vendor [%q : !qcc.qubit_ref]
    // expected-error @below {{'oq3.gate_call' op calls the unknown gate '@vendor' with 0 parameter(s) and 2 qubit(s), but another call uses 0 and 1}}
    oq3.gate_call @vendor [%q, %q : !qcc.qubit_ref, !qcc.qubit_ref]
    return
  }
}

// -----

module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @main() attributes {qcc.entry_point} {
    oq3.include "vendor.inc" id 0 unresolved
    // expected-note @below {{the other call is here}}
    %a = oq3.unresolved_call "f"() : () -> !oq3.unknown
    // expected-error @below {{'oq3.unresolved_call' op calls 'f' with 1 argument(s), but another call uses 0}}
    %b = oq3.unresolved_call "f"(%a) : (!oq3.unknown) -> !oq3.unknown
    return
  }
}

// -----

//===----------------------------------------------------------------------===//
// Directives and comments
//===----------------------------------------------------------------------===//

module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @main() attributes {qcc.entry_point} {
    // expected-error @below {{'oq3.comment' op text must be one complete comment ('// ...' or '/* ... */'), got '/* open'}}
    oq3.comment "/* open"
    return
  }
}

// -----

module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @main() attributes {qcc.entry_point} {
    oq3.comment "// first"
    // expected-error @below {{'oq3.comment' op is a header comment, so it must precede all other statements}}
    oq3.comment "// header" header
    return
  }
}

// -----

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
    // expected-error @below {{'oq3.qubit_decl' op attribute 'oq3.trailing_comment' must be the text of comments on one line, got "not a comment"}}
    %q = oq3.qubit_decl "q" {oq3.trailing_comment = "not a comment"} : !qcc.qubit_ref
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

module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @main() attributes {qcc.entry_point} {
    %q = oq3.qubit_decl "q" : !qcc.qubit_ref
    %m = oq3.measure %q : !qcc.qubit_ref -> !oq3.bit
    %c = oq3.declare "c" : !qcc.ref<!oq3.bit>
    %d = qcc.ref.load %c : !qcc.ref<!oq3.bit>
    // expected-error @below {{'qcc.ref.store' op attribute 'oq3.arrow' is only valid on a 'qcc.ref.store' of a measurement}}
    qcc.ref.store %d, %c {oq3.arrow} : !qcc.ref<!oq3.bit>
    return
  }
}

// -----

// expected-error @below {{'func.func' op has the unknown attribute 'oq3.unknown_attribute'}}
func.func private @f() attributes {oq3.unknown_attribute}

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
    // expected-error @below {{'oq3.qubit_decl' op designator must be an unsized integer or unknown type, got '!oq3.bit'}}
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

// expected-error @below {{'oq3.constant' op only integer literals have a radix}}
%x = oq3.constant #oq3.float<"1.0"> : !oq3.float radix hex

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

//===----------------------------------------------------------------------===//
// Gate calls
//===----------------------------------------------------------------------===//

module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @main() attributes {qcc.entry_point} {
    %q = oq3.qubit_decl "q" : !qcc.qubit_ref
    // expected-error @below {{'oq3.gate_call' op calls the unknown gate 'h'}}
    // expected-note @below {{'h' is a standard gate; it needs an earlier 'include "stdgates.inc";'}}
    oq3.gate_call @h [%q : !qcc.qubit_ref]
    oq3.include "stdgates.inc" id 0 unresolved
    return
  }
}

// -----

module attributes {oq3.version = #oq3.version<3, 1>} {
  func.func @main() attributes {qcc.entry_point} {
    oq3.include "stdgates.inc" id 0 unresolved
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
    oq3.include "stdgates.inc" id 0 unresolved
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
