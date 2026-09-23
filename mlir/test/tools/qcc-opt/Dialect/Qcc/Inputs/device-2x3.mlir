// A two-trap device with capacity 3 per trap, two ions loaded into each trap, a uniform coupling of 1.0 and a time
// unit of 1 us. Shared by tests that only need *a* device.
#trap = #magic.trap<capacity = 3, couplings = [
  dense<0.0> : tensor<1x1xf64>,
  dense<[[0.0, 1.0], [1.0, 0.0]]> : tensor<2x2xf64>,
  dense<[[0.0, 1.0, 1.0], [1.0, 0.0, 1.0], [1.0, 1.0, 0.0]]> : tensor<3x3xf64>]>

module attributes {qcc.device = #magic.device<name = "two-trap-2x3", time_unit_ns = 1000, initial_occupancies = [2, 2], traps = [#trap, #trap]>} {}
