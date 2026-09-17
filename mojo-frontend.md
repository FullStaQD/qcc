TODO: sort this document into an appropriate place.

# Mojo eDSL design.

We outline how a Mojo eDSL connecting to the Prelim-HLEP dialect should look like.
This should serve as a rough guide, not set in stone.

## Variant A

No custom syntax: partial linearization is a higher order operation taking in one function and producing another.

### Partial Linearization

```mojo
# We only give the signature
partial_lin[InLinearize, OutLinearize, OutCarry](
    in_value: Lin[InLinearize]
    f: InLinearize -> tuple[OutLineariye, OutCarry]
) -> tuple[Lin[OutLinearize], OutCarry]
# InCapture is missing because capture is implicit. Does this always work?
```

### X-Gate

```mojo
@linear_halo
def x(qubit: Lin[Bool]) -> Lin[Bool]:
    return lin(  # convenience function wrapping partial_lin
        qubit,
        lambda (bit: Bool) -> Bool: not bit
    )
```

### CNOT-Gate

```mojo
@linear_halo
def cx(control: Lin[Bool], target: Lin[Bool]) -> tuple[Lin[Bool], Lin[Bool]]:
    return lin(
        (control, target),
        lambda (control_bit: Bool, target_bit: Bool) -> Bool:
            (not target_bit) if control_bit else target_bit
    )
```

### State preparation

```mojo
@linear_halo
def make_qubit(bit: Bool) -> Lin[Bool]:
    return lin(
        None,
        lambda () {bit: Bool} -> Bool: bit
    )
```

### Measure

```mojo
@linear_halo
def measure(qubit: Lin[Bool]) -> Lin[Bool]:
    return lin_measure(  # convenience function wrapping partial_lin
        None,
        lambda (bit: Bool) -> Bool: bit
    )
```

## Variant B

Custom Syntax: partial linearization is a new, first-order concept in the language.

### X-Gate

```mojo
@linear_halo
def x(qubit: Lin[Bool]) -> Lin[Bool]:
    linearize (bit from qubit) into inverted_qubit:
        output not bit
    return inverted_qubit
```

### CX-Gate

```mojo
@linear_halo
def cx(control: Lin[Bool], target: Lin[Bool]) -> tuple[Lin[Bool], Lin[Bool]]:
    linearize (control_bit from control, target_bit from target) into (out_control, out_target):
        # Here with if-else regions, ternary operation would be possible as well.
        if control_bit:
            out_bit = not target_bit
        else:
            out_bit = target_bit
        output control_bit, out_bit
    return inverted_qubit
```

### State preparation

```mojo
@linear_halo
def make_qubit(bit: Bool) -> Lin[Bool]:
    linearize () into qubit:
        output bit
    return qubit
```

### Measure

```mojo
@linear_halo
def measure(qubit: Lin[Bool]) -> Lin[Bool]:
    linearize (bit from qubit):
        pass
    return bit  # The fact that `bit` is used outside the linearize scope implies that `bit` is carried. Is this possible?
```
