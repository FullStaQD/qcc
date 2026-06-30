// RUN: qcc-opt %s --add-entrypoint-to-main --verify-diagnostics

// expected-error @below {{could not find entry-point function 'main'}}
module {
  func.func @not_main() {
    return
  }
}
