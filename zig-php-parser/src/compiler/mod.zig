// Compiler 模块统一入口
// 用于解决 Zig 0.15.2 模块系统的导入问题

// 核心编译器组件
pub const ast = @import("ast.zig");
pub const parser = @import("parser.zig");
pub const token = @import("token.zig");
pub const lexer = @import("lexer.zig");
pub const syntax_mode = @import("syntax_mode.zig");

// 导出常用类型
pub const Node = ast.Node;
pub const Token = token.Token;
pub const Parser = parser.Parser;
pub const PHPContext = parser.PHPContext;
pub const SyntaxMode = syntax_mode.SyntaxMode;
pub const SyntaxConfig = syntax_mode.SyntaxConfig;
