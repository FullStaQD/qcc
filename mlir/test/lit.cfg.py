import os
import shutil
import sys
from pathlib import Path

import lit.formats
import lit.util

from lit.llvm import llvm_config

# Configuration file for the 'lit' test runner.

# name: The name of this test suite.
config.name = "QCC_MLIR_COMPILER"

config.test_format = lit.formats.ShTest(execute_external=False)

# suffixes: A list of file extensions to treat as test files.
config.suffixes = [".mlir", ".test"]

# test_source_root: The root path where tests are located.
config.test_source_root = Path(__file__).parent

config.substitutions.append(("%PATH%", config.environment["PATH"]))
config.substitutions.append(("%shlibext", config.llvm_shlib_ext))
config.substitutions.append(("%project_source_dir", config.project_source_dir))

llvm_config.with_system_environment(["HOME", "INCLUDE", "LIB", "TMP", "TEMP"])

llvm_config.use_default_substitutions()

# excludes: A list of directories and filenames to exclude from the testsuite.
config.excludes = []

# Gate HiSEP-Q target tests: only available when qcc was built with the HiSEP-Q
# target (QCC_ENABLE_HISEPQ). Tests opt in via `REQUIRES: hisepq` (or exclude
# with `UNSUPPORTED: hisepq`).
if config.enable_hisepq:
    config.available_features.add("hisepq")

# test_exec_root: The root path where tests should be run.
config.test_exec_root = Path(config.project_binary_dir) / "test"
config.project_tools_dir = Path(config.project_binary_dir) / "bin"

# Tweak the PATH to include the tools dir.
llvm_config.with_environment("PATH", config.llvm_tools_dir, append_path=True)

# Successively check directories whether they contain the qcc and qcc-opt tools
exe_suffix = ".exe" if sys.platform == "win32" else ""
base_tool_dir = config.project_tools_dir

candidate_dirs = [base_tool_dir]
if config.cmake_build_type:
    candidate_dirs.append(base_tool_dir / config.cmake_build_type)
for cfg in ["Debug", "Release", "RelWithDebInfo", "MinSizeRel"]:
    cfg_dir = base_tool_dir / cfg
    if cfg_dir not in candidate_dirs:
        candidate_dirs.append(cfg_dir)

found = False
for candidate_dir in candidate_dirs:
    if (candidate_dir / f"qcc{exe_suffix}").exists() and (candidate_dir / f"qcc-opt{exe_suffix}").exists():
        llvm_config.add_tool_substitutions(["qcc", "qcc-opt"], [str(candidate_dir)])
        found = True
        break

if not found:
    lit_config.fatal(f"Could not find qcc and qcc-opt anywhere under {base_tool_dir}.")

if config.enable_hisepq:
    llvm_config.add_tool_substitutions(["hisepq-elf2mem"], [str(candidate_dir)])

    # Optional prebuilt HiSEP-Q testbench `sim_hisepq`: Provision it with
    # `utils/provision-sim-hisepq`, or point CMake at your own build via
    # `-DQCC_SIM_HISEPQ_EXECUTABLE=...`.
    sim_hisepq = config.sim_hisepq_executable
    if os.path.isfile(sim_hisepq) and os.access(sim_hisepq, os.X_OK):
        config.available_features.add("sim-hisepq")
        config.substitutions.append((r"\bsim_hisepq\b", sim_hisepq))

# Gate the cross-repository PrelimHLEP tests on a Mojo fork checkout being
# configured (CMake cache variable QCC_MOJO_FORK) and its `kgen-opt` being
# built. Tests opt in via `REQUIRES: mojo-fork`.
if config.mojo_fork and os.path.isdir(config.mojo_fork) and os.path.isfile(config.mojo_kgen_opt):
    config.available_features.add("mojo-fork")
    config.substitutions.append(("%mojo_fork", config.mojo_fork))
    config.substitutions.append(("%kgen_opt", config.mojo_kgen_opt))

# Compiling a Mojo kernel needs the compiler and a built standard library as
# well. Tests opt in via `REQUIRES: mojo-kernels`.
if config.mojo_fork and os.path.isfile(config.mojo_kgen) and os.path.isdir(config.mojo_stdlib):
    config.available_features.add("mojo-kernels")
    config.environment["MODULAR_MOJO_MAX_IMPORT_PATH"] = config.mojo_stdlib
    # `kgen -I <dir>` is how a kernel finds the `hlep` library; the kernels
    # themselves live beside it in the source tree.
    config.substitutions.append(
        ("%kgen", "%s -I %s/mojo/hlep" % (config.mojo_kgen, config.project_source_dir))
    )
    config.substitutions.append(
        ("%mojo_kernels", os.path.join(config.project_source_dir, "mojo", "kernels"))
    )
    # `kgen --qcc=` wants a bare path, which the `qcc` tool substitution cannot
    # give: it rewrites the word `qcc` wherever it appears, including inside
    # the flag's own name.
    config.substitutions.append(
        ("%qcc_bin", os.path.join(str(candidate_dir), "qcc"))
    )
    # The host half of a quantum program imports `qpu.host` the way a kernel
    # imports `hlep`, so both live on the include path.
    config.substitutions.append(
        ("%mojo_qpu", os.path.join(config.project_source_dir, "mojo", "qpu"))
    )

    # Running a kernel, rather than only compiling one, additionally needs the
    # `mojo` driver and the compiler runtime its JIT loads. Tests opt in via
    # `REQUIRES: mojo-run`.
    if os.path.isfile(config.mojo_driver) and os.path.isfile(
        config.mojo_compilerrt
    ):
        config.available_features.add("mojo-run")
        config.environment["MODULAR_MOJO_MAX_COMPILERRT_PATH"] = (
            config.mojo_compilerrt
        )
        # A binary `mojo build` produced links against that same runtime, and
        # finds it at run time only if it is on the loader's path.
        llvm_config.with_environment(
            "LD_LIBRARY_PATH",
            os.path.dirname(config.mojo_compilerrt),
            append_path=True,
        )
        # `mojo run` finds qcc the way any other invocation does. The flag is
        # `kgen`-only, so the environment variable is what the driver reads.
        config.environment["MOJO_QCC"] = os.path.join(
            str(candidate_dir), "qcc"
        )
        # The driver takes its subcommand first, so the include flags cannot
        # ride along in this substitution; `%mojo_libs` carries them and a
        # test writes `%mojo run %mojo_libs <file>`.
        config.substitutions.append((r"%mojo\b", config.mojo_driver))
        config.substitutions.append(
            (
                "%mojo_libs",
                "-I %s/mojo/hlep -I %s/mojo/qpu"
                % (config.project_source_dir, config.project_source_dir),
            )
        )

# Tests opt in via `REQUIRES: lld`.
if shutil.which("ld.lld", path=config.environment["PATH"]) is not None:
    config.available_features.add("lld")

# If `qir-runner` is not already available in the environment, fall back to
# running it ephemerally via `uvx`.
qir_runner = "qir-runner"
if shutil.which("qir-runner", path=config.environment["PATH"]) is None:
    if shutil.which("uv", path=config.environment["PATH"]) is None:
        lit_config.fatal(
            "Could not find the 'qir-runner' executable, which is required to run some tests. "
            "Either install it yourself, or install 'uv' (see README) to run it ephemerally instead."
        )
    qir_runner = "uv tool run --from qirrunner qir-runner"
    config.substitutions.append((r"\bqir-runner\b", qir_runner))

# `qpu.host` picks its device from the environment for the same reason: the
# runner here may be a command rather than an executable on PATH, which is
# exactly what QPU_QIR_RUNNER exists to carry.
config.environment["QPU_QIR_RUNNER"] = qir_runner
