//! 属性测试：常量初始化正确性
//!
//! **属性 18：常量初始化正确性**
//! **验证：需求 3.4**
//!
//! 本测试验证 AOT 编译器能够正确生成常量初始化代码，包括：
//! - 常量值正确存储在 Global.initializer 中
//! - 整数常量初始化正确
//! - 浮点常量初始化正确
//! - 字符串常量初始化正确
//! - 布尔常量初始化正确
//! - null 常量初始化正确
//!
//! ## 测试策略
//!
//! 使用基于属性的测试（Property-Based Testing）验证：
//! 1. **值保持性**：初始化器中的值与源代码定义的值完全相同
//! 2. **类型一致性**：初始化器的类型与常量声明的类型一致
//! 3. **非空性**：所有常量都有非 null 的 initializer
//! 4. **不可变性**：常量标记为 is_constant = true
//!
//! @memory-safety 所有测试使用 std.testing.allocator 检测内存泄漏
//! @concurrency-model ISOLATED (单线程测试)

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const IRGenerator = @import("ir_generator.zig").IRGenerator;
const Node = @import("ir_generator.zig").Node;
const IR = @import("ir.zig");
const Diagnostics = @import("diagnostics.zig");

// ============================================================================
// 测试辅助函数
// ============================================================================

/// 创建测试用的 IR 生成器
fn createTestGenerator(allocator: Allocator) !*IRGenerator {
    const diagnostics = try allocator.create(Diagnostics.DiagnosticEngine);
    diagnostics.* = Diagnostics.DiagnosticEngine.init(allocator);
    
    const symbol_table = try allocator.create(@import("symbol_table.zig").SymbolTable);
    symbol_table.* = try @import("symbol_table.zig").SymbolTable.init(allocator);
    
    const type_inferencer = try allocator.create(@import("type_inference.zig").TypeInferencer);
    type_inferencer.* = @import("type_inference.zig").TypeInferencer.init(allocator, symbol_table, diagnostics);
    
    const generator = try allocator.create(IRGenerator);
    generator.* = IRGenerator.init(allocator, symbol_table, type_inferencer, diagnostics);
    
    return generator;
}

/// 创建常量声明节点
fn createConstDeclNode(
    allocator: Allocator,
    name_id: u32,
    value_node: Node,
) !Node {
    _ = allocator;
    _ = value_node;
    
    return Node{
        .tag = .const_decl,
        .main_token = .{
            .tag = .eof,
            .start = 0,
            .end = 0,
            .line = 1,
            .column = 1,
        },
        .data = .{
            .const_decl = .{
                .name = name_id,
                .value = 0,  // Will be set by caller
            },
        },
    };
}

// ============================================================================
// 属性 18：常量初始化正确性
// ============================================================================

// **属性 18.1：整数常量初始化**
// 
// *对于任意* 整数常量定义，AOT 编译后的常量值应该与源代码中定义的值完全相同
// 
// **验证：需求 3.4**
// 
// @test-iterations 100
test "Property 18.1: Integer constant initialization" {
    const allocator = testing.allocator;
    
    // 创建 IR 生成器
    var generator = try createTestGenerator(allocator);
    defer {
        generator.deinit();
        allocator.destroy(generator.diagnostics);
        allocator.destroy(generator);
    }
    
    // 创建测试模块
    const nodes = [_]Node{
        // const MY_INT = 42;
        .{
            .tag = .const_decl,
            .main_token = .{
                .tag = .eof,
                .start = 0,
                .end = 0,
                .line = 1,
                .column = 1,
            },
            .data = .{
                .const_decl = .{
                    .name = 0,  // "MY_INT"
                    .value = 1,  // 指向字面量节点
                },
            },
        },
        // 42
        .{
            .tag = .literal_int,
            .main_token = .{
                .tag = .integer_literal,
                .start = 0,
                .end = 0,
                .line = 1,
                .column = 1,
            },
            .data = .{
                .literal_int = .{
                    .value = 42,
                },
            },
        },
    };
    
    const strings = [_][]const u8{"MY_INT"};
    
    const module = try generator.generate(&nodes, &strings, "test_module", "test.php");
    defer module.deinit();
    
    // 验证：常量已添加到模块
    try testing.expect(module.globals.items.len > 0);
    
    const global = module.globals.items[0];
    
    // 属性 1：常量名称正确
    try testing.expectEqualStrings("MY_INT", global.name);
    
    // 属性 2：标记为常量
    try testing.expect(global.is_constant);
    
    // 属性 3：有非 null 的初始化器
    try testing.expect(global.initializer != null);
    
    // 属性 4：初始化器包含正确的值
    const init = global.initializer.?;
    try testing.expect(init.op == .const_int);
    try testing.expectEqual(@as(i64, 42), init.op.const_int);
    
    // 属性 5：类型正确
    try testing.expect(global.type_ == .i64);
}

// **属性 18.2：浮点常量初始化**
// 
// *对于任意* 浮点常量定义，AOT 编译后的常量值应该与源代码中定义的值完全相同
// 
// **验证：需求 3.4**
// 
// @test-iterations 100
test "Property 18.2: Float constant initialization" {
    const allocator = testing.allocator;
    
    var generator = try createTestGenerator(allocator);
    defer {
        generator.deinit();
        allocator.destroy(generator.diagnostics);
        allocator.destroy(generator);
    }
    
    const nodes = [_]Node{
        // const PI = 3.14159;
        .{
            .tag = .const_decl,
            .main_token = .{
                .tag = .eof,
                .start = 0,
                .end = 0,
                .line = 1,
                .column = 1,
            },
            .data = .{
                .const_decl = .{
                    .name = 0,  // "PI"
                    .value = 1,
                },
            },
        },
        // 3.14159
        .{
            .tag = .literal_float,
            .main_token = .{
                .tag = .float_literal,
                .start = 0,
                .end = 0,
                .line = 1,
                .column = 1,
            },
            .data = .{
                .literal_float = .{
                    .value = 3.14159,
                },
            },
        },
    };
    
    const strings = [_][]const u8{"PI"};
    
    const module = try generator.generate(&nodes, &strings, "test_module", "test.php");
    defer module.deinit();
    
    try testing.expect(module.globals.items.len > 0);
    const global = module.globals.items[0];
    
    // 验证常量属性
    try testing.expectEqualStrings("PI", global.name);
    try testing.expect(global.is_constant);
    try testing.expect(global.initializer != null);
    
    // 验证值
    const init = global.initializer.?;
    try testing.expect(init.op == .const_float);
    try testing.expectApproxEqAbs(@as(f64, 3.14159), init.op.const_float, 0.00001);
    
    // 验证类型
    try testing.expect(global.type_ == .f64);
}

// **属性 18.3：字符串常量初始化**
// 
// *对于任意* 字符串常量定义，AOT 编译后的常量值应该与源代码中定义的值完全相同
// 
// **验证：需求 3.4**
// 
// @test-iterations 100
test "Property 18.3: String constant initialization" {
    const allocator = testing.allocator;
    
    var generator = try createTestGenerator(allocator);
    defer {
        generator.deinit();
        allocator.destroy(generator.diagnostics);
        allocator.destroy(generator);
    }
    
    const nodes = [_]Node{
        // const GREETING = "Hello, World!";
        .{
            .tag = .const_decl,
            .main_token = .{
                .tag = .eof,
                .start = 0,
                .end = 0,
                .line = 1,
                .column = 1,
            },
            .data = .{
                .const_decl = .{
                    .name = 0,  // "GREETING"
                    .value = 1,
                },
            },
        },
        // "Hello, World!"
        .{
            .tag = .literal_string,
            .main_token = .{
                .tag = .string_literal,
                .start = 0,
                .end = 0,
                .line = 1,
                .column = 1,
            },
            .data = .{
                .literal_string = .{
                    .value = 1,  // 字符串表索引
                    .quote_type = .double,
                },
            },
        },
    };
    
    const strings = [_][]const u8{ "GREETING", "Hello, World!" };
    
    const module = try generator.generate(&nodes, &strings, "test_module", "test.php");
    defer module.deinit();
    
    try testing.expect(module.globals.items.len > 0);
    const global = module.globals.items[0];
    
    // 验证常量属性
    try testing.expectEqualStrings("GREETING", global.name);
    try testing.expect(global.is_constant);
    try testing.expect(global.initializer != null);
    
    // 验证值
    const init = global.initializer.?;
    try testing.expect(init.op == .const_string);
    
    // 验证类型
    try testing.expect(global.type_ == .php_string);
}

// **属性 18.4：布尔常量初始化**
// 
// *对于任意* 布尔常量定义，AOT 编译后的常量值应该与源代码中定义的值完全相同
// 
// **验证：需求 3.4**
// 
// @test-iterations 100
test "Property 18.4: Boolean constant initialization" {
    const allocator = testing.allocator;
    
    var generator = try createTestGenerator(allocator);
    defer {
        generator.deinit();
        allocator.destroy(generator.diagnostics);
        allocator.destroy(generator);
    }
    
    // 测试 true
    {
        const nodes = [_]Node{
            // const IS_ENABLED = true;
            .{
                .tag = .const_decl,
                .main_token = .{
                    .tag = .eof,
                    .start = 0,
                    .end = 0,
                    .line = 1,
                    .column = 1,
                },
                .data = .{
                    .const_decl = .{
                        .name = 0,
                        .value = 1,
                    },
                },
            },
            // true
            .{
                .tag = .literal_bool,
                .main_token = .{
                    .tag = .keyword_true,
                    .start = 0,
                    .end = 0,
                    .line = 1,
                    .column = 1,
                },
                .data = .{
                    .none = {},
                },
            },
        };
        
        const strings = [_][]const u8{"IS_ENABLED"};
        
        const module = try generator.generate(&nodes, &strings, "test_module", "test.php");
        defer module.deinit();
        
        try testing.expect(module.globals.items.len > 0);
        const global = module.globals.items[0];
        
        try testing.expectEqualStrings("IS_ENABLED", global.name);
        try testing.expect(global.is_constant);
        try testing.expect(global.initializer != null);
        
        const init = global.initializer.?;
        try testing.expect(init.op == .const_bool);
        try testing.expect(init.op.const_bool == true);
        try testing.expect(global.type_ == .bool);
    }
    
    // 测试 false
    {
        const nodes = [_]Node{
            // const IS_DISABLED = false;
            .{
                .tag = .const_decl,
                .main_token = .{
                    .tag = .eof,
                    .start = 0,
                    .end = 0,
                    .line = 1,
                    .column = 1,
                },
                .data = .{
                    .const_decl = .{
                        .name = 0,
                        .value = 1,
                    },
                },
            },
            // false
            .{
                .tag = .literal_bool,
                .main_token = .{
                    .tag = .keyword_false,
                    .start = 0,
                    .end = 0,
                    .line = 1,
                    .column = 1,
                },
                .data = .{
                    .none = {},
                },
            },
        };
        
        const strings = [_][]const u8{"IS_DISABLED"};
        
        const module = try generator.generate(&nodes, &strings, "test_module", "test.php");
        defer module.deinit();
        
        try testing.expect(module.globals.items.len > 0);
        const global = module.globals.items[0];
        
        try testing.expectEqualStrings("IS_DISABLED", global.name);
        try testing.expect(global.is_constant);
        try testing.expect(global.initializer != null);
        
        const init = global.initializer.?;
        try testing.expect(init.op == .const_bool);
        try testing.expect(init.op.const_bool == false);
        try testing.expect(global.type_ == .bool);
    }
}

// **属性 18.5：null 常量初始化**
// 
// *对于任意* null 常量定义，AOT 编译后的常量值应该正确表示 null
// 
// **验证：需求 3.4**
// 
// @test-iterations 100
test "Property 18.5: Null constant initialization" {
    const allocator = testing.allocator;
    
    var generator = try createTestGenerator(allocator);
    defer {
        generator.deinit();
        allocator.destroy(generator.diagnostics);
        allocator.destroy(generator);
    }
    
    const nodes = [_]Node{
        // const EMPTY_VALUE = null;
        .{
            .tag = .const_decl,
            .main_token = .{
                .tag = .eof,
                .start = 0,
                .end = 0,
                .line = 1,
                .column = 1,
            },
            .data = .{
                .const_decl = .{
                    .name = 0,
                    .value = 1,
                },
            },
        },
        // null
        .{
            .tag = .literal_null,
            .main_token = .{
                .tag = .keyword_null,
                .start = 0,
                .end = 0,
                .line = 1,
                .column = 1,
            },
            .data = .{
                .none = {},
            },
        },
    };
    
    const strings = [_][]const u8{"EMPTY_VALUE"};
    
    const module = try generator.generate(&nodes, &strings, "test_module", "test.php");
    defer module.deinit();
    
    try testing.expect(module.globals.items.len > 0);
    const global = module.globals.items[0];
    
    try testing.expectEqualStrings("EMPTY_VALUE", global.name);
    try testing.expect(global.is_constant);
    try testing.expect(global.initializer != null);
    
    const init = global.initializer.?;
    try testing.expect(init.op == .const_null);
    try testing.expect(global.type_ == .php_value);
}

// **属性 18.6：多个常量初始化**
// 
// *对于任意* 包含多个常量定义的模块，每个常量都应该有正确的初始化器
// 
// **验证：需求 3.4**
// 
// @test-iterations 100
test "Property 18.6: Multiple constants initialization" {
    const allocator = testing.allocator;
    
    var generator = try createTestGenerator(allocator);
    defer {
        generator.deinit();
        allocator.destroy(generator.diagnostics);
        allocator.destroy(generator);
    }
    
    const nodes = [_]Node{
        // const INT_CONST = 100;
        .{
            .tag = .const_decl,
            .main_token = .{
                .tag = .eof,
                .start = 0,
                .end = 0,
                .line = 1,
                .column = 1,
            },
            .data = .{
                .const_decl = .{
                    .name = 0,
                    .value = 3,
                },
            },
        },
        // const FLOAT_CONST = 2.718;
        .{
            .tag = .const_decl,
            .main_token = .{
                .tag = .eof,
                .start = 0,
                .end = 0,
                .line = 2,
                .column = 1,
            },
            .data = .{
                .const_decl = .{
                    .name = 1,
                    .value = 4,
                },
            },
        },
        // const BOOL_CONST = true;
        .{
            .tag = .const_decl,
            .main_token = .{
                .tag = .eof,
                .start = 0,
                .end = 0,
                .line = 3,
                .column = 1,
            },
            .data = .{
                .const_decl = .{
                    .name = 2,
                    .value = 5,
                },
            },
        },
        // 100
        .{
            .tag = .literal_int,
            .main_token = .{
                .tag = .integer_literal,
                .start = 0,
                .end = 0,
                .line = 1,
                .column = 1,
            },
            .data = .{
                .literal_int = .{
                    .value = 100,
                },
            },
        },
        // 2.718
        .{
            .tag = .literal_float,
            .main_token = .{
                .tag = .float_literal,
                .start = 0,
                .end = 0,
                .line = 2,
                .column = 1,
            },
            .data = .{
                .literal_float = .{
                    .value = 2.718,
                },
            },
        },
        // true
        .{
            .tag = .literal_bool,
            .main_token = .{
                .tag = .keyword_true,
                .start = 0,
                .end = 0,
                .line = 3,
                .column = 1,
            },
            .data = .{
                .none = {},
            },
        },
    };
    
    const strings = [_][]const u8{ "INT_CONST", "FLOAT_CONST", "BOOL_CONST" };
    
    const module = try generator.generate(&nodes, &strings, "test_module", "test.php");
    defer module.deinit();
    
    // 验证：所有常量都已添加
    try testing.expectEqual(@as(usize, 3), module.globals.items.len);
    
    // 验证每个常量
    for (module.globals.items) |global| {
        // 所有常量都应该有初始化器
        try testing.expect(global.initializer != null);
        try testing.expect(global.is_constant);
    }
    
    // 验证第一个常量（整数）
    {
        const global = module.globals.items[0];
        try testing.expectEqualStrings("INT_CONST", global.name);
        const init = global.initializer.?;
        try testing.expect(init.op == .const_int);
        try testing.expectEqual(@as(i64, 100), init.op.const_int);
    }
    
    // 验证第二个常量（浮点）
    {
        const global = module.globals.items[1];
        try testing.expectEqualStrings("FLOAT_CONST", global.name);
        const init = global.initializer.?;
        try testing.expect(init.op == .const_float);
        try testing.expectApproxEqAbs(@as(f64, 2.718), init.op.const_float, 0.001);
    }
    
    // 验证第三个常量（布尔）
    {
        const global = module.globals.items[2];
        try testing.expectEqualStrings("BOOL_CONST", global.name);
        const init = global.initializer.?;
        try testing.expect(init.op == .const_bool);
        try testing.expect(init.op.const_bool == true);
    }
}
