// A device with one trap that holds a single ion.
#trap = #magic.trap<capacity = 1, couplings = [dense<0.0> : tensor<1x1xf64>]>

module attributes {qcc.device = #magic.device<name = "one-ion", time_unit_ns = 1000, traps = [#trap]>} {}
