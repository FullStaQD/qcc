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
config.suffixes = [".mlir", ".qasm", ".test"]

# test_source_root: The root path where tests are located.
config.test_source_root = Path(__file__).parent

config.substitutions.append(("%PATH%", config.environment["PATH"]))
config.substitutions.append(("%shlibext", config.llvm_shlib_ext))
config.substitutions.append(("%project_source_dir", config.project_source_dir))
config.substitutions.append(("%qcc_version", config.qcc_version))

llvm_config.with_system_environment(["HOME", "INCLUDE", "LIB", "TMP", "TEMP"])

llvm_config.use_default_substitutions()

# excludes: A list of directories and filenames to exclude from the testsuite.
# `Inputs` directories hold files that tests read (e.g. device files), not tests.
config.excludes = ["Inputs"]

# `Unit` is the nested suite of the gtest unit tests. Its site config only
# exists when qcc was configured with QCC_INCLUDE_UNITTESTS.
if not config.include_unittests:
    config.excludes.append("Unit")

# Gate HiSEP-Q target tests: only available when qcc was built with the HiSEP-Q
# target (QCC_ENABLE_HISEPQ). Tests opt in via `REQUIRES: hisepq` (or exclude
# with `UNSUPPORTED: hisepq`).
if config.enable_hisepq:
    config.available_features.add("hisepq")

# test_exec_root: The root path where tests should be run. It must be the
# directory of the generated lit.site.cfg.py because lit looks up the site
# configs of nested suites (`Unit`) relative to it.
config.test_exec_root = Path(config.project_binary_dir) / "mlir" / "test"
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
        llvm_config.add_tool_substitutions(["qcc", "qcc-opt", "qcc-translate"], [str(candidate_dir)])
        found = True
        break

if not found:
    lit_config.fatal(f"Could not find qcc and qcc-opt anywhere under {base_tool_dir}.")

if config.enable_hisepq:
    llvm_config.add_tool_substitutions(["hisepq-elf2mem"], [str(candidate_dir)])

    # Tests that link and run on the testbench opt in via `REQUIRES: hisepq-sim`.
    if config.hisepq_sim_tests:
        opt_out = "or configure with -DQCC_HISEPQ_SIM_TESTS=OFF to skip the tests that need it"
        sim_hisepq = config.sim_hisepq_executable
        if not (os.path.isfile(sim_hisepq) and os.access(sim_hisepq, os.X_OK)):
            lit_config.fatal(
                f"testing HiSEP-Q needs sim_hisepq (not found: '{sim_hisepq}'): "
                f"run utils/provision-sim-hisepq and reconfigure, {opt_out}"
            )
        if shutil.which("ld.lld", path=config.environment["PATH"]) is None:
            lit_config.fatal(f"testing HiSEP-Q needs ld.lld on PATH: install it, {opt_out}")
        config.available_features.add("hisepq-sim")
        config.substitutions.append((r"\bsim_hisepq\b", sim_hisepq))

# `magic-runner` is a simulator for MAGIC programs.
magic_runner = Path(config.project_source_dir) / "mlir" / "utils" / "magic-runner"
config.substitutions.append((r"\bmagic-runner\b", f'"{sys.executable}" {magic_runner}'))

# If `qir-runner` is not already available in the environment, fall back to
# running it ephemerally via `uvx`.
if shutil.which("qir-runner", path=config.environment["PATH"]) is None:
    if shutil.which("uv", path=config.environment["PATH"]) is None:
        lit_config.fatal(
            "Could not find the 'qir-runner' executable, which is required to run some tests. "
            "Either install it yourself, or install 'uv' (see README) to run it ephemerally instead."
        )
    config.substitutions.append((r"\bqir-runner\b", "uv tool run --from qirrunner qir-runner"))
