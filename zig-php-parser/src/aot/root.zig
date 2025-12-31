//! AOT (Ahead-of-Time) Compiler Module
//!
//! This module provides functionality to compile PHP source code directly
//! into native binary executables without requiring a PHP runtime.
//!
//! ## Architecture
//!
//! The AOT compiler pipeline:
//! ```
//! PHP Source → Lexer → Parser → AST → Type Inference → IR Generation →
//! LLVM IR → Machine Code → Linker → Executable
//! ```
//!
//! ## Components
//!
//! - `compiler.zig`: Main AOT compiler entry point
//! - `diagnostics.zig`: Error/warning collection and reporting
//! - `ir.zig`: Intermediate Representation definitions (future)
//! - `ir_generator.zig`: AST to IR conversion (future)
//! - `type_inference.zig`: Static type inference (future)
//! - `codegen.zig`: LLVM code generation (future)
//! - `linker.zig`: Static linking (future)
//! - `runtime_lib.zig`: Runtime library interface (future)

const std = @import("std");

// Re-export public interfaces
pub const Diagnostics = @import("diagnostics.zig");
pub const DiagnosticEngine = Diagnostics.DiagnosticEngine;
pub const Diagnostic = Diagnostics.Diagnostic;
pub const Severity = Diagnostics.Severity;
pub const SourceLocation = Diagnostics.SourceLocation;

// IR module
pub const IR = @import("ir.zig");
pub const Module = IR.Module;
pub const Function = IR.Function;
pub const BasicBlock = IR.BasicBlock;
pub const Instruction = IR.Instruction;
pub const Register = IR.Register;
pub const Type = IR.Type;
pub const Terminator = IR.Terminator;
pub const IRPrinter = IR.IRPrinter;
pub const serializeModule = IR.serializeModule;

// Symbol Table module
pub const SymbolTableMod = @import("symbol_table.zig");
pub const SymbolTable = SymbolTableMod.SymbolTable;
pub const Symbol = SymbolTableMod.Symbol;
pub const Scope = SymbolTableMod.Scope;
pub const InferredType = SymbolTableMod.InferredType;
pub const ConcreteType = SymbolTableMod.ConcreteType;
pub const SymbolKind = SymbolTableMod.SymbolKind;

// Type Inference module
pub const TypeInferenceMod = @import("type_inference.zig");
pub const TypeInferencer = TypeInferenceMod.TypeInferencer;
pub const TypeContext = TypeInferenceMod.TypeContext;
pub const InferenceNode = TypeInferenceMod.InferenceNode;
pub const NodeTag = TypeInferenceMod.NodeTag;
pub const OperatorKind = TypeInferenceMod.OperatorKind;
pub const getBuiltinReturnType = TypeInferenceMod.getBuiltinReturnType;

// IR Generator module
pub const IRGeneratorMod = @import("ir_generator.zig");
pub const IRGenerator = IRGeneratorMod.IRGenerator;

// AOT Compiler module
pub const CompilerMod = @import("compiler.zig");
pub const AOTCompiler = CompilerMod.AOTCompiler;
pub const CompileResult = CompilerMod.CompileResult;
pub const CompileError = CompilerMod.CompileError;
pub const CompileOptions = CompilerMod.CompileOptions;
pub const OptimizeLevel = CompilerMod.OptimizeLevel;
pub const Target = CompilerMod.Target;
pub const supported_targets = CompilerMod.supported_targets;
pub const listTargets = CompilerMod.listTargets;

// Runtime Library module
pub const RuntimeLib = @import("runtime_lib.zig");
pub const PHPValue = RuntimeLib.PHPValue;
pub const PHPString = RuntimeLib.PHPString;
pub const PHPArray = RuntimeLib.PHPArray;
pub const PHPObject = RuntimeLib.PHPObject;
pub const PHPCallable = RuntimeLib.PHPCallable;
pub const ValueTag = RuntimeLib.ValueTag;
pub const ArrayKey = RuntimeLib.ArrayKey;

// Code Generator module
pub const CodeGen = @import("codegen.zig");
pub const CodeGenerator = CodeGen.CodeGenerator;
pub const CodeGenTarget = CodeGen.Target;
pub const CodeGenOptimizeLevel = CodeGen.OptimizeLevel;
pub const CodeGenError = CodeGen.CodeGenError;

// Linker module
pub const LinkerMod = @import("linker.zig");
pub const StaticLinker = LinkerMod.StaticLinker;
pub const LinkerConfig = LinkerMod.LinkerConfig;
pub const LinkerError = LinkerMod.LinkerError;
pub const ObjectCode = LinkerMod.ObjectCode;
pub const ObjectFormat = LinkerMod.ObjectFormat;

// Runtime library functions
pub const php_value_create_null = RuntimeLib.php_value_create_null;
pub const php_value_create_bool = RuntimeLib.php_value_create_bool;
pub const php_value_create_int = RuntimeLib.php_value_create_int;
pub const php_value_create_float = RuntimeLib.php_value_create_float;
pub const php_value_create_string = RuntimeLib.php_value_create_string;
pub const php_value_create_array = RuntimeLib.php_value_create_array;
pub const php_value_create_object = RuntimeLib.php_value_create_object;
pub const php_gc_retain = RuntimeLib.php_gc_retain;
pub const php_gc_release = RuntimeLib.php_gc_release;
pub const php_echo = RuntimeLib.php_echo;
pub const php_print = RuntimeLib.php_print;

// Property tests (included for test runs)
test {
    _ = @import("test_type_inference_property.zig");
    _ = @import("test_ir_generator_property.zig");
    _ = @import("runtime_lib.zig");
    _ = @import("test_runtime_lib_property.zig");
    _ = @import("codegen.zig");
    _ = @import("test_codegen_property.zig");
    _ = @import("linker.zig");
    _ = @import("test_linker_property.zig");
    _ = @import("compiler.zig");
}

// Tests for re-exported types
test "Target.native" {
    const target = Target.native();
    _ = target.arch.toString();
    _ = target.os.toString();
    _ = target.abi.toString();
}

test "Target.fromString" {
    const target = try Target.fromString("x86_64-linux-gnu");
    try std.testing.expectEqual(Target.Arch.x86_64, target.arch);
    try std.testing.expectEqual(Target.OS.linux, target.os);
    try std.testing.expectEqual(Target.ABI.gnu, target.abi);
}

test "Target.fromString macos" {
    const target = try Target.fromString("aarch64-macos-none");
    try std.testing.expectEqual(Target.Arch.aarch64, target.arch);
    try std.testing.expectEqual(Target.OS.macos, target.os);
    try std.testing.expectEqual(Target.ABI.none, target.abi);
}

test "OptimizeLevel.fromString" {
    try std.testing.expectEqual(OptimizeLevel.debug, OptimizeLevel.fromString("debug").?);
    try std.testing.expectEqual(OptimizeLevel.release_fast, OptimizeLevel.fromString("release-fast").?);
    try std.testing.expect(OptimizeLevel.fromString("invalid") == null);
}
