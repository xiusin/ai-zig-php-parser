const std = @import("std");
const Token = @import("token.zig").Token;

/// 高性能关键词查找模块
/// 使用std.StaticStringMap实现O(1)查找，替代原有70+次链式比较
const keyword_map = std.StaticStringMap(Token.Tag).initComptime(.{
    .{ "fn", .k_fn },
    .{ "if", .k_if },
    .{ "do", .k_do },
    .{ "as", .k_as },
    .{ "go", .k_go },
    .{ "or", .k_or },
    .{ "new", .k_new },
    .{ "for", .k_for },
    .{ "use", .k_use },
    .{ "try", .k_try },
    .{ "get", .k_get },
    .{ "set", .k_set },
    .{ "and", .k_and },
    .{ "xor", .k_xor },
    .{ "var", .k_var },
    .{ "else", .k_else },
    .{ "echo", .k_echo },
    .{ "case", .k_case },
    .{ "true", .k_true },
    .{ "null", .k_null },
    .{ "void", .k_void },
    .{ "enum", .k_enum },
    .{ "goto", .k_goto },
    .{ "lock", .k_lock },
    .{ "list", .k_list },
    .{ "from", .k_from },
    .{ "self", .k_self },
    .{ "with", .k_with },
    .{ "class", .k_class },
    .{ "trait", .k_trait },
    .{ "while", .k_while },
    .{ "break", .k_break },
    .{ "catch", .k_catch },
    .{ "clone", .k_clone },
    .{ "const", .k_const },
    .{ "false", .k_false },
    .{ "final", .k_final },
    .{ "mixed", .k_mixed },
    .{ "never", .k_never },
    .{ "print", .k_print },
    .{ "throw", .k_throw },
    .{ "unset", .k_unset },
    .{ "yield", .k_yield },
    .{ "match", .k_match },
    .{ "array", .k_array },
    .{ "range", .k_range },
    .{ "elseif", .k_elseif },
    .{ "public", .k_public },
    .{ "static", .k_static },
    .{ "struct", .k_struct },
    .{ "parent", .k_parent },
    .{ "return", .k_return },
    .{ "switch", .k_switch },
    .{ "global", .k_global },
    .{ "object", .k_object },
    .{ "extends", .k_extends },
    .{ "private", .k_private },
    .{ "foreach", .k_foreach },
    .{ "default", .k_default },
    .{ "declare", .k_declare },
    .{ "finally", .k_finally },
    .{ "include", .k_include },
    .{ "require", .k_require },
    .{ "abstract", .k_abstract },
    .{ "function", .k_function },
    .{ "callable", .k_callable },
    .{ "continue", .k_continue },
    .{ "iterable", .k_iterable },
    .{ "readonly", .k_readonly },
    .{ "interface", .k_interface },
    .{ "protected", .k_protected },
    .{ "namespace", .k_namespace },
    .{ "implements", .k_implements },
    .{ "instanceof", .k_instanceof },
    .{ "__DIR__", .m_dir },
    .{ "__FILE__", .m_file },
    .{ "__LINE__", .m_line },
    .{ "__CLASS__", .m_class },
    .{ "__METHOD__", .m_method },
    .{ "__FUNCTION__", .m_function },
    .{ "__NAMESPACE__", .m_namespace },
    .{ "include_once", .k_include_once },
    .{ "require_once", .k_require_once },
    // 替代语法结束符
    .{ "endif", .k_endif },
    .{ "endwhile", .k_endwhile },
    .{ "endfor", .k_endfor },
    .{ "endforeach", .k_endforeach },
    .{ "endswitch", .k_endswitch },
});

/// 主查找函数
pub inline fn lookup(text: []const u8) ?Token.Tag {
    return keyword_map.get(text);
}

/// 快速查找入口（供lexer调用）
pub inline fn lookupFast(text: []const u8) ?Token.Tag {
    return keyword_map.get(text);
}

test "keyword lookup" {
    const testing = std.testing;
    try testing.expectEqual(Token.Tag.k_if, lookup("if").?);
    try testing.expectEqual(Token.Tag.k_else, lookup("else").?);
    try testing.expectEqual(Token.Tag.k_class, lookup("class").?);
    try testing.expectEqual(Token.Tag.k_function, lookup("function").?);
    try testing.expectEqual(Token.Tag.k_interface, lookup("interface").?);
    try testing.expect(lookup("foo") == null);
    try testing.expect(lookup("myVariable") == null);
    try testing.expectEqual(Token.Tag.m_file, lookup("__FILE__").?);
}
