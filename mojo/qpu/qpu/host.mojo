# ===----------------------------------------------------------------------=== #
#
# Part of the FullStaQD Project, under the Apache License v2.0 with LLVM
# Exceptions.
# See <repo-root>/LICENSE.txt for license information.
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#
# ===----------------------------------------------------------------------=== #
"""Running a compiled quantum kernel from the host program that contains it.

The compiler has already done the quantum half by the time any of this runs.
`kgen` handed each exported kernel to qcc, and embedded the artifact that came
back as a pair of C-ABI accessors named after the kernel:

    __qpu_artifact_<name>()       the address of the artifact's bytes
    __qpu_artifact_size_<name>()  how many bytes there are

`artifact_of[kernel]()` is the whole of the compiler-to-runtime interface: it
turns a kernel, named as a comptime parameter, into those bytes. Everything
below it is an ordinary host library that submits bytes to a device.

The first device is the QIR simulator, which is the `qir-runner` executable
run as a subprocess. That is the same process boundary the compiler already
uses to reach qcc, and for the same reason: the artifact is an interchange
format, not something to link against.

One kernel invocation is one shot. `shots` is a submission argument, so a
distribution is something the runtime collects, never something the kernel
knows about.
"""

from std.collections.string.string_span import get_static_string
from std.ffi import external_call
from std.os.env import getenv
from std.reflection import get_linkage_name
from std.subprocess import run
from std.tempfile import mkdtemp
from std.os.path import exists
from std.os import remove, rmdir


# ===----------------------------------------------------------------------=== #
# The compiled artifact
# ===----------------------------------------------------------------------=== #


def artifact_of[
    kernel_type: AnyType, //, kernel: kernel_type
]() -> StaticString:
    """The artifact qcc compiled for `kernel`, as it sits in this program.

    The kernel is named as a comptime parameter rather than called, because
    there is nothing to call: `kgen` erased the kernel from the host module
    once qcc had compiled it. What is left is the artifact, and its address is
    resolved at link time from the kernel's exported name.

    Parameters:
        kernel_type: Type of the kernel function.
        kernel: An `@export`ed quantum kernel in this program.

    Returns:
        The artifact's bytes, which live in this program's constant data.
    """
    comptime name = get_linkage_name[kernel]()
    comptime address_symbol = get_static_string["__qpu_artifact_", name]()
    comptime size_symbol = get_static_string["__qpu_artifact_size_", name]()

    var address = external_call[address_symbol, Int]()
    var size = external_call[size_symbol, Int]()
    var bytes = Span[Byte, ImmStaticOrigin](
        unsafe_ptr=ImmPointer[Byte, ImmStaticOrigin](
            unsafe_from_address=address
        ),
        length=size,
    )
    return StaticString(unsafe_from_utf8=bytes)


# ===----------------------------------------------------------------------=== #
# Outcomes
# ===----------------------------------------------------------------------=== #


@fieldwise_init
struct Histogram(Copyable, Movable, Writable):
    """How many times each outcome came up across a submission's shots.

    An outcome is the kernel's returned value, rendered the way the device
    recorded it: `"true, true"` for a kernel returning two `Bool`s, `"10"` for
    one returning a `UInt4`. A kernel that returns several values gives one
    key per shot holding all of them, so correlations between them survive --
    which for a Bell pair is the entire point.
    """

    var counts: Dict[String, Int]
    """Outcome to the number of shots that produced it."""

    var shots: Int
    """How many shots were run, which is `sum(counts.values())`."""

    def count(self, outcome: StringSlice) -> Int:
        """The number of shots that produced `outcome`, possibly zero.

        Args:
            outcome: The outcome to look up.

        Returns:
            How many shots produced it.
        """
        return self.counts.get(String(outcome), 0)

    def frequency(self, outcome: StringSlice) -> Float64:
        """The fraction of shots that produced `outcome`.

        Args:
            outcome: The outcome to look up.

        Returns:
            Its share of the shots, or 0.0 when no shots were run.
        """
        if self.shots == 0:
            return 0.0
        return Float64(self.count(outcome)) / Float64(self.shots)

    def most_common(self) raises -> String:
        """The outcome that came up most often.

        Returns:
            The most frequent outcome.

        Raises:
            If no shots were run, so there is no such outcome.
        """
        if not self.counts:
            raise Error("the submission produced no outcomes")
        var best = String("")
        var best_count = -1
        for entry in self.counts.items():
            if entry.value > best_count:
                best = entry.key
                best_count = entry.value
        return best

    def write_to[W: Writer](self, mut writer: W):
        """Write the histogram as `{outcome: count, ...}`.

        Parameters:
            W: The writer type.

        Args:
            writer: Where to write.
        """
        writer.write("{")
        var first = True
        for entry in self.counts.items():
            if not first:
                writer.write(", ")
            first = False
            writer.write(entry.key, ": ", entry.value)
        writer.write("}")


# ===----------------------------------------------------------------------=== #
# Devices
# ===----------------------------------------------------------------------=== #


@fieldwise_init
struct Device(Copyable, Movable, Writable):
    """A place a kernel can run."""

    var id: Int
    """Its index in `available_devices()`."""

    var name: String
    """A short name, for diagnostics."""

    var command: String
    """The command that runs an artifact on it."""

    var accepts_arguments: Bool
    """Whether an entry point may take classical arguments.

    False for every QIR device: the profile's entry point takes none, and
    results leave through the output records rather than a return value.
    """

    def write_to[W: Writer](self, mut writer: W):
        """Write the device as `name (#id)`.

        Parameters:
            W: The writer type.

        Args:
            writer: Where to write.
        """
        writer.write(self.name, " (#", self.id, ")")


def _simulator_command() -> String:
    """The command that runs a QIR artifact on the simulator.

    `QPU_QIR_RUNNER` overrides it, and holds a command rather than a path so
    that a runner which is not a plain executable -- `uv tool run --from
    qirrunner qir-runner`, which is how the test suite reaches one -- works
    without a wrapper script.
    """
    var override = getenv("QPU_QIR_RUNNER")
    if override:
        return override
    return String("qir-runner")


def available_devices() -> List[Device]:
    """Every device this program can submit to, cheapest first.

    Returns:
        The devices, which is empty when none can be reached.
    """
    var devices = List[Device]()
    var command = _simulator_command()
    # `command -v` covers a bare executable on PATH; a multi-word override is
    # taken on trust, because there is nothing single-word to look up.
    var reachable = " " in command
    if not reachable:
        try:
            reachable = Bool(run(String("command -v ") + command + " 2>/dev/null"))
        except:
            reachable = False
    if reachable:
        devices.append(
            Device(
                id=len(devices),
                name=String("qir-simulator"),
                command=command,
                accepts_arguments=False,
            )
        )
    return devices^


# ===----------------------------------------------------------------------=== #
# Submission
# ===----------------------------------------------------------------------=== #


struct Job(Movable):
    """A submission in flight.

    The simulator runs synchronously, so `result()` does the work. The type
    exists so that a device which really does queue -- hardware, or a remote
    simulator -- can be added without changing how a caller writes a launch.
    """

    var _device: Device
    var _artifact: StaticString
    var _shots: Int

    def __init__(
        out self, var device: Device, artifact: StaticString, shots: Int
    ) raises:
        """Submit `artifact` to `device`.

        Args:
            device: Where to run it.
            artifact: The compiled kernel.
            shots: How many times to run it.

        Raises:
            If `shots` is not positive.
        """
        if shots <= 0:
            raise Error("a submission needs at least one shot, got ", shots)
        self._device = device^
        self._artifact = artifact
        self._shots = shots

    def result(self) raises -> Histogram:
        """Run the submission and collect its outcomes.

        Returns:
            One entry per distinct outcome.

        Raises:
            If the device could not be run, or rejected the artifact.
        """
        var directory = mkdtemp()
        var path = directory + "/kernel.ll"
        try:
            with open(path, "w") as artifact_file:
                artifact_file.write_bytes(self._artifact.as_bytes())

            # The exit status travels back in the output, because `run` gives
            # stdout and nothing else. A device that failed after printing
            # some records is a failure, not a short histogram.
            var command = String(
                self._device.command,
                " --file ",
                path,
                " --shots ",
                self._shots,
                " 2>&1; echo __qpu_exit:$?",
            )
            var output = run(command)
            return _parse_records(output, self._device)
        finally:
            if exists(path):
                remove(path)
            if exists(directory):
                rmdir(directory)


def _parse_records(output: StringSlice, device: Device) raises -> Histogram:
    """Turn a QIR runner's output records into a histogram.

    The format is one tab-separated record per line, `START` and `END` framing
    each shot and `OUTPUT` carrying the values. `TUPLE` and `ARRAY` records
    announce how many leaves follow rather than carrying a value, so only the
    leaves reach the outcome; the shape they describe is the kernel's return
    type, which the caller already knows.
    """
    var counts = Dict[String, Int]()
    var shots = 0
    var leaves = List[String]()
    var in_shot = False
    var status = String("")

    # Split on "\n" rather than with `splitlines`, which in this standard
    # library also breaks on "\t" -- and a record's fields are tab-separated,
    # so every record would arrive as several lines.
    for line in output.split("\n"):
        var fields = line.split("\t")
        var kind = fields[0].strip()
        if kind == "START":
            in_shot = True
            leaves = List[String]()
        elif kind == "OUTPUT":
            if len(fields) < 3:
                raise Error("malformed record from ", device, ": ", line)
            var value_kind = String(fields[1].strip())
            # A tuple or array header states a length, not a value.
            if value_kind != "TUPLE" and value_kind != "ARRAY":
                leaves.append(String(fields[2].strip()))
        elif kind == "END":
            if not in_shot:
                raise Error(
                    "record from ", device, " ends a shot that never began"
                )
            # `END` carries the shot's own status. A shot that failed has no
            # outcome, and counting it as one would quietly bias the
            # histogram towards whatever it managed to record first.
            var shot_status = String(fields[1].strip()) if len(
                fields
            ) > 1 else String("0")
            if shot_status != "0":
                raise Error(
                    "a shot failed on ", device, " with status ", shot_status
                )
            in_shot = False
            shots += 1
            var outcome = String(", ").join(leaves)
            counts[outcome] = counts.get(outcome, 0) + 1
        elif kind.startswith("__qpu_exit:"):
            status = String(kind.removeprefix("__qpu_exit:"))

    if status != "0":
        raise Error(
            "could not run the kernel on ",
            device,
            ": the device exited with status ",
            status,
            " and said:\n",
            output,
        )
    if shots == 0:
        raise Error("the device ran but recorded no shots; it said:\n", output)
    return Histogram(counts=counts^, shots=shots)


# ===----------------------------------------------------------------------=== #
# The context
# ===----------------------------------------------------------------------=== #


struct QPUContext(Movable):
    """A chosen device, and the way to launch kernels on it.

    Mirrors `DeviceContext` on the GPU side: pick a device once, then launch
    against it. A kernel is named as a comptime parameter rather than called,
    because by the time this runs the kernel is an artifact and not code.
    """

    var device: Device
    """The device this context submits to."""

    def __init__(out self, device_id: Int = 0) raises:
        """Take the device with the given index.

        Args:
            device_id: Its index in `available_devices()`.

        Raises:
            If there is no such device.
        """
        var devices = available_devices()
        if not devices:
            raise Error(
                "no quantum device is available: this program submits QIR to"
                " the 'qir-runner' simulator, which was not found on PATH."
                " Install it, or set QPU_QIR_RUNNER to the command that runs"
                " it"
            )
        if device_id < 0 or device_id >= len(devices):
            raise Error(
                "there is no device #",
                device_id,
                ": this program can reach ",
                len(devices),
                " device(s)",
            )
        self.device = devices[device_id].copy()

    def enqueue[
        kernel_type: AnyType, //, kernel: kernel_type
    ](self, *, shots: Int = 1) raises -> Job:
        """Submit `kernel` to this context's device.

        Parameters:
            kernel_type: Type of the kernel function.
            kernel: An `@export`ed quantum kernel in this program.

        Args:
            shots: How many times to run it. One invocation is one shot.

        Returns:
            The submission, whose `result()` collects the outcomes.

        Raises:
            If the submission could not be made.
        """
        return Job(self.device.copy(), artifact_of[kernel](), shots)
