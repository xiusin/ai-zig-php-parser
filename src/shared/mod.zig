//! Shared Module
//!
//! 导出 compiler 模块的 Parser 相关类型，供 aot 模块使用

const compiler = @import("compiler");

pub const Parser = compiler.Parser;
pub const PHPContext = compiler.PHPContext;
pub const SyntaxMode = compiler.SyntaxMode;
pub const Lexer = compiler.Lexer;
pub const Token = compiler.Token;
pub const ast = compiler.ast;

pub const time_compat = @import("time_compat.zig");
