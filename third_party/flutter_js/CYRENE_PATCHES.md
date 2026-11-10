# Local flutter_js patch

Based on flutter_js 0.8.7 (MIT; see LICENSE). Native sources are from
https://github.com/abner/quickjs-c-bridge at
7204d9bf1afbe0550d51d7decdcce398b2c22e1a (QuickJS 2021-03-27).
QuickJS license notices are retained in each source file.

Windows, Linux and Android now build the bridge from the same checked-in
sources rather than shipping an opaque prebuilt binary. Apple platforms retain
the upstream JavaScriptCore implementation.

Local changes:

- Honor the existing timeout argument in milliseconds with a monotonic native
  interrupt handler. Nested execution shares its outer deadline.
- Guard evaluation (including result conversion), calls and the entire Promise
  job drain. Idle time does not consume the next call's budget.
- Check interruptions during regexp backtracking, preserving the interrupt
  exception instead of relabeling it as allocation failure.
- Export the existing memory-limit API; release runtime budget and Dart channel
  registry entries when their runtime is destroyed.
- Use math wrappers for MSVC C static initializer compatibility.
- Correct two legacy pointer/integer conversions for current Android NDK Clang.
- Keep budgets in a synchronized runtime registry, independent of the current
  OS thread. Serialize the process-wide class ID allocator used by FFI objects.
- Allow changing the synchronous execution budget between initialization and
  resolution. Every runtime remains exclusively owned by one Dart isolate.

The application uses 5 seconds per initialization turn, 1500 ms per resolution
turn/drain and 64 MiB of QuickJS-managed memory. Remaining operation deadlines
can shorten these bounds. Script initialization has a separate 12-second total
deadline. A failed candidate is disposed without replacing the active source.
These bounds protect script execution; they do not constitute a process sandbox.

Run `test/services/lx_execution_limits_native_test.dart` with
`CYRENE_LX_NATIVE_TEST=1` and the built library available to the loader.
Native regression tests must also have an external process/job timeout because
a broken interrupt handler can block Dart's own timeout mechanism.
