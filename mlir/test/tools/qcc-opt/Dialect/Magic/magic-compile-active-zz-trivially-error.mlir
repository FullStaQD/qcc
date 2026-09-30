// RUN: qcc-opt %s --magic-compile-active-zz-trivially --split-input-file --verify-diagnostics

// A device whose outer ions of a full trap do not couple.
#trap = #magic.trap<capacity = 3, couplings = [
  dense<0.0> : tensor<1x1xf64>,
  dense<[[0.0, 1.0],
         [1.0, 0.0]]> : tensor<2x2xf64>,
  dense<[[0.0, 1.0, 0.0],
         [1.0, 0.0, 1.0],
         [0.0, 1.0, 0.0]]> : tensor<3x3xf64>]>

module attributes {qcc.device = #magic.device<name = "no-outer-coupling", time_unit_ns = 1000, initial_occupancies = [3], traps = [#trap]>} {
  func.func @zero_coupling() {
    %c0 = magic.init : !magic.ion_chain<0, [0:1, 1:1, 2:1]>
    // expected-error @+1 {{cannot couple ions 0 and 2: the device's coupling between them is zero}}
    %c1 = magic.active_zz %c0 {angles = dense<[[0.0, 0.0, 1.0],
                                               [0.0, 0.0, 0.0],
                                               [1.0, 0.0, 0.0]]> : tensor<3x3xf64>} : !magic.ion_chain<0, [0:1, 1:1, 2:1]>
    %m0, %m1, %m2 = magic.mzd %c1 : !magic.ion_chain<0, [0:1, 1:1, 2:1]> -> i1, i1, i1
    return
  }
}

// -----

// expected-error @+1 {{module carries no 'qcc.device' attribute}}
module {
  func.func @no_device() {
    %c0 = magic.init : !magic.ion_chain<0, [0:1, 1:1]>
    %c1 = magic.active_zz %c0 {angles = dense<[[0.0, 1.0], [1.0, 0.0]]> : tensor<2x2xf64>} : !magic.ion_chain<0, [0:1, 1:1]>
    %m0, %m1 = magic.mzd %c1 : !magic.ion_chain<0, [0:1, 1:1]> -> i1, i1
    return
  }
}
