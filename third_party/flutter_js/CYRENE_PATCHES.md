# Local flutter_js patch

Based on flutter_js 0.8.7 (MIT; see LICENSE). The C bridge originated at
https://github.com/abner/quickjs-c-bridge commit
7204d9bf1afbe0550d51d7decdcce398b2c22e1a.

## Engine provenance

Windows, Linux and Android build quickjs-ng **v0.18.0** from the same checked-in
sources, pinned to https://github.com/quickjs-ng/quickjs commit
`d7215b0ad3fc2c562e8317fd9bca058fd4863804`.
`native/quickjs/UPSTREAM.json` records SHA-256 hashes of every vendored engine
file. The core source/header dependency closure and LICENSE are copied verbatim;
CLI programs, the OS/standard-library modules and upstream build tooling are not
bundled. The common `native/CMakeLists.txt` builds the four upstream core source
files (`quickjs.c`, `dtoa.c`, `libregexp.c`, `libunicode.c`) and the local bridge.
No configure-time downloads or prebuilt engine binaries are used.
Apple platforms retain the upstream JavaScriptCore implementation.

## Bridge and Dart changes

- Keep JS values opaque at the FFI boundary. A stable bridge-owned value-kind
  enum replaces Dart's hard-coded internal engine tags, including rope strings
  and short/heap BigInts. BigInt transfer preserves arbitrary precision.
- Match quickjs-ng's context-based interrupt handler, boolean callbacks,
  per-runtime class IDs, and array/promise/error predicates. Class IDs and
  callbacks remain isolated across independently staged source runtimes.
- Use explicit UTF-8 byte lengths for string transfer, preserving embedded NUL.
  Probe ArrayBuffers without leaving a spurious JS exception on normal objects.
  Preserve array-proxy classification using the native proxy APIs and propagate
  revoked-proxy/getter failures instead of silently returning null.
- Release callback heap wrappers after taking ownership of their JS values;
  release conversion values and property-name arrays even when getters throw.
- Honor the execution timeout using a monotonic clock. Nested calls and result
  conversion share the outer deadline. A complete Promise job drain shares one
  deadline, rather than resetting it for each microtask.
- Update the engine stack top at each outer execution entry, including after
  Dart isolate thread migration, without resetting it for reentrant callbacks.
  The default JS stack allowance is 256 KiB, leaving headroom for Dart/FFI on
  native threads with a 1 MiB stack. Recursive JS must fail before OS overflow.
- Keep execution budgets in a synchronized runtime registry, independent of the
  current OS thread. Every runtime is owned by exactly one Dart isolate.
- Retain quickjs-ng's native regexp interruption, instead of applying the old
  engine's regexp/MSVC patches. Vendored engine files have no local patches.
- Export memory limits and native version diagnostics; clean runtime budgets and
  Dart channel registry entries when disposing runtimes.
- Build C11 atomics with modern MSVC; retain Android 16 KiB page-size alignment.

The application uses 5 seconds per initialization turn, 1500 ms per resolution
turn/drain and 64 MiB of QuickJS-managed memory. Remaining operation deadlines
can shorten these bounds. Script initialization has a separate 12-second total
deadline. A failed candidate is disposed without replacing the active source.
These bounds protect script execution; they do not constitute a process sandbox.

## Validation

`quickjs_vendor_test.dart` checks the engine provenance hashes.
Set `CYRENE_LX_NATIVE_TEST=1` and `LIBQUICKJSC_TEST_PATH` to the built bridge to run
`quickjs_ng_bridge_native_test.dart` and the LX native/worker tests. The quality
workflow runs native tests on Windows and Linux. Windows application builds also
run the bridge tests against the DLL in the final Release bundle.
Native tests require an external process/job timeout: a broken interrupt handler
can block Dart's own timeout mechanism.
