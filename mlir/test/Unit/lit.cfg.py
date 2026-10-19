import os

import lit.formats

# Configuration file for the 'lit' test runner, for the gtest unit tests in `mlir/unittests`.

# name: The name of this test suite.
config.name = "QCC-Unit"

# suffixes: A list of file extensions to treat as test files.
config.suffixes = []

# test_source_root: The root path where tests are located.
# test_exec_root: The root path where tests should be run.
config.test_exec_root = os.path.join(config.project_binary_dir, "mlir", "unittests")
config.test_source_root = config.test_exec_root

# testFormat: The test format to use to interpret tests.
config.test_format = lit.formats.GoogleTest(config.llvm_build_mode, "Tests")

# Propagate the temp directory. Windows requires this because it uses \Windows\
# if none of these are present.
for var in ["TMP", "TEMP", "HOME"]:
    if var in os.environ:
        config.environment[var] = os.environ[var]
