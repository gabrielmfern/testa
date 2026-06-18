# testa

## FFI boundary: the C++ shim holds only shims

`src/node_embed.cpp` (and any future FFI/C++ glue) must contain only thin 1:1
wrappers — exactly one Node/V8/uv call per function, with no branching, ordering,
or policy. All orchestration lives in Zig (`src/main.zig`): create/teardown
sequences, control flow, and decisions such as which `EnvironmentFlags` to pass
(the shim just takes a plain `uint64_t`).

Why: keep the unsafe, hard-to-debug language boundary mechanical and auditable,
and keep real logic in Zig where it can be read and tested. If a wrapper wants an
`if`, a loop, or a specific call order, that's the signal it belongs in Zig, not
the shim.
