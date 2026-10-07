const std = @import("std");
const Token = @import("token.zig").Token;

/// 关键字表项原始清单（唯一事实源：87 枚 = 80 枚全小写关键字 + 7 枚全大写魔术常量键）。
/// 抽出为独立 comptime 元组，供敏感查表、R-4 长度上限与 R-2 穷举单测共用，防止键清单多处漂移。
const raw_entries = .{
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
    // range 是 PHP 内置函数，不是关键字 — 移除以避免与函数调用冲突
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
};

/// 高性能关键词查找模块
/// 使用std.StaticStringMap实现O(1)查找，替代原有70+次链式比较
const keyword_map = std.StaticStringMap(Token.Tag).initComptime(raw_entries);

/// 表内最长键长度（R-4：lexer 查表长度上限按本值计算，消除硬编码 `len <= 15`；
/// 实测最长键为 `__NAMESPACE__` = 13 字符，新增更长键时本值随表自动增长）
pub const max_key_len = blk: {
    var m: usize = 0;
    for (raw_entries) |e| {
        if (e[0].len > m) m = e[0].len;
    }
    break :blk m;
};

/// 大小写不敏感查表（R-2，AOT-CODEGEN-010）：复用同一张表，按表内两族拼写规范分别折形——
/// 80 枚 k_ 键全小写 ⇒ 原文折小写查；7 枚 m_ 键全大写 ⇒ 原文折大写查。
/// 两族键字母大小写互斥（k_ 键不含大写字母、m_ 键不含小写字母）⇒ 任一原文至多命中一族，
/// 无交叉误命中；折形只落栈上缓冲（≤max_key_len），零堆分配。调用方约束：
/// 仅 AOT 编译路径（`Lexer.case_insensitive_keywords = true`）启用；token 文本仍交原始切片，
/// 名位语义取原文（见 parser 名位容忍支）。
pub fn lookupIgnoreCase(text: []const u8) ?Token.Tag {
    if (text.len == 0 or text.len > max_key_len) return null;
    var folded: [max_key_len]u8 = undefined;
    for (text, 0..) |c, i| folded[i] = std.ascii.toLower(c);
    if (keyword_map.get(folded[0..text.len])) |tag| return tag;
    for (text, 0..) |c, i| folded[i] = std.ascii.toUpper(c);
    if (keyword_map.get(folded[0..text.len])) |tag| return tag;
    return null;
}

/// 主查找函数
pub inline fn lookup(text: []const u8) ?Token.Tag {
    return keyword_map.get(text);
}

/// 快速查找入口（供lexer调用）
pub inline fn lookupFast(text: []const u8) ?Token.Tag {
    return keyword_map.get(text);
}

/// comptime 折形助手：以容器级 const 数组承载结果（地址 comptime 已知，可安全取切片），
/// 避免「返回 comptime 局部变量地址」在运行期分析下的非法性。
fn FoldedKey(comptime s: []const u8, comptime to_upper: bool) type {
    return struct {
        const data: [s.len]u8 = blk: {
            var buf: [s.len]u8 = undefined;
            for (s, 0..) |c, i| {
                buf[i] = if (to_upper) std.ascii.toUpper(c) else std.ascii.toLower(c);
            }
            break :blk buf;
        };
    };
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

test "lookupIgnoreCase 原表 87 枚键三种拼写变体全命中（R-2 穷举）" {
    const testing = std.testing;
    inline for (raw_entries) |e| {
        try testing.expectEqual(e[1], lookupIgnoreCase(e[0]).?);
        try testing.expectEqual(e[1], lookupIgnoreCase(&FoldedKey(e[0], false).data).?);
        try testing.expectEqual(e[1], lookupIgnoreCase(&FoldedKey(e[0], true).data).?);
    }
}

test "lookupIgnoreCase 非关键字/空串/截断与超长变体不命中" {
    const testing = std.testing;
    try testing.expect(lookupIgnoreCase("myVariable") == null);
    try testing.expect(lookupIgnoreCase("") == null);
    try testing.expect(lookupIgnoreCase("__dir") == null);
    try testing.expect(lookupIgnoreCase("__DIR__X") == null);
    try testing.expect(lookupIgnoreCase("elseifX") == null);
}

test "max_key_len 与最长键一致（R-4 回归钉）" {
    const testing = std.testing;
    try testing.expectEqual(@as(usize, 13), max_key_len);
    try testing.expectEqual(Token.Tag.m_namespace, lookupIgnoreCase("__NAMESPACE__").?);
}
