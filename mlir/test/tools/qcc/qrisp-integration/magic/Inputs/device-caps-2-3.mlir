// A two-trap device with capacities 2 and 3 and a time unit of 1 us. The couplings (rad/s) have a realistic order of
// magnitude: neighbours couple more strongly than the two outer ions.
#trap0 = #magic.trap<capacity = 2, couplings = [
  dense<0.0> : tensor<1x1xf64>,
  dense<[[0.0, 1200.0], [1200.0, 0.0]]> : tensor<2x2xf64>]>
#trap1 = #magic.trap<capacity = 3, couplings = [
  dense<0.0> : tensor<1x1xf64>,
  dense<[[0.0, 1200.0], [1200.0, 0.0]]> : tensor<2x2xf64>,
  dense<[[0.0, 1200.0, 900.0], [1200.0, 0.0, 1200.0], [900.0, 1200.0, 0.0]]> : tensor<3x3xf64>]>

module attributes {qcc.device = #magic.device<name = "two-trap-2-3", time_unit_ns = 1000, traps = [#trap0, #trap1]>} {}
