// circomlibjs and snarkjs ship no type declarations of their own — every
// call site here already treats their exports as untyped (matching how the
// rest of this codebase uses them), so this just satisfies the compiler
// rather than papering over a real type mismatch.
declare module "circomlibjs";
declare module "snarkjs";
