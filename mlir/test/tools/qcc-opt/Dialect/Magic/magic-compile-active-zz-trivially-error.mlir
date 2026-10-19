// RUN: qcc-opt %s --magic-compile-active-zz-trivially --split-input-file --verify-diagnostics

// expected-error @+1 {{module carries no 'qcc.device' attribute}}
module {
  func.func @no_device() {
    %c0 = magic.init : !magic.ion_chain<0, [0:1, 1:1]>
    %c1 = magic.active_zz %c0 {angles = dense<[[0.0, 1.0], [1.0, 0.0]]> : tensor<2x2xf64>} : !magic.ion_chain<0, [0:1, 1:1]>
    %m0, %m1 = magic.mzd %c1 : !magic.ion_chain<0, [0:1, 1:1]> -> i1, i1
    return
  }
}
