const std = @import("std");
const testing = std.testing;
const Value = @import("compiler").value.zig.Value;
const MemoryManager = @import("memory_manager.zig").MemoryManager;
const JsonFunctions = @import("stdlib_ext.zig").JsonFunctions;

/// 模拟 VM 结构用于测试
const TestVM = struct {
    allocator: std.mem.Allocator,
    memory_manager: MemoryManager,

    fn init(allocator: std.mem.Allocator) !TestVM {
        return TestVM{
            .allocator = allocator,
            .memory_manager = try MemoryManager.init(allocator),
        };
    }

    fn deinit(self: *TestVM) void {
        self.memory_manager.deinit();
    }
};

test "json_encode - 基本类型" {
    var vm = try TestVM.init(testing.allocator);
    defer vm.deinit();

    // null
    {
        const args = [_]Value{Value.initNull()};
        const result = try JsonFunctions.jsonEncode(&vm, &args);
        try testing.expect(result.getTag() == .string);
        try testing.expectEqualStrings("null", result.getAsString().data.data);
    }

    // boolean
    {
        const args = [_]Value{Value.initBool(true)};
        const result = try JsonFunctions.jsonEncode(&vm, &args);
        try testing.expectEqualStrings("true", result.getAsString().data.data);
    }

    {
        const args = [_]Value{Value.initBool(false)};
        const result = try JsonFunctions.jsonEncode(&vm, &args);
        try testing.expectEqualStrings("false", result.getAsString().data.data);
    }

    // integer
    {
        const args = [_]Value{Value.initInt(42)};
        const result = try JsonFunctions.jsonEncode(&vm, &args);
        try testing.expectEqualStrings("42", result.getAsString().data.data);
    }

    // float
    {
        const args = [_]Value{Value.initFloat(3.14)};
        const result = try JsonFunctions.jsonEncode(&vm, &args);
        const str = result.getAsString().data.data;
        try testing.expect(std.mem.startsWith(u8, str, "3.14"));
    }
}

test "json_encode - 字符串转义" {
    var vm = try TestVM.init(testing.allocator);
    defer vm.deinit();

    const test_str = try vm.memory_manager.createString("Hello\n\"World\"\t\\");
    const args = [_]Value{Value.initString(test_str)};
    const result = try JsonFunctions.jsonEncode(&vm, &args);

    try testing.expectEqualStrings("\"Hello\\n\\\"World\\\"\\t\\\\\"", result.getAsString().data.data);
}

test "json_encode - 数组" {
    var vm = try TestVM.init(testing.allocator);
    defer vm.deinit();

    const arr = try vm.memory_manager.createArray();
    try arr.data.set(Value.initInt(0), Value.initInt(1));
    try arr.data.set(Value.initInt(1), Value.initInt(2));
    try arr.data.set(Value.initInt(2), Value.initInt(3));

    const args = [_]Value{Value.initArray(arr)};
    const result = try JsonFunctions.jsonEncode(&vm, &args);

    try testing.expectEqualStrings("[1,2,3]", result.getAsString().data.data);
}

test "json_encode - 对象" {
    var vm = try TestVM.init(testing.allocator);
    defer vm.deinit();

    const arr = try vm.memory_manager.createArray();
    const key1 = try vm.memory_manager.createString("name");
    const val1 = try vm.memory_manager.createString("John");
    try arr.data.set(Value.initString(key1), Value.initString(val1));

    const key2 = try vm.memory_manager.createString("age");
    try arr.data.set(Value.initString(key2), Value.initInt(30));

    const args = [_]Value{Value.initArray(arr)};
    const result = try JsonFunctions.jsonEncode(&vm, &args);

    const json = result.getAsString().data.data;
    // 对象键顺序可能不同，检查包含关系
    try testing.expect(std.mem.indexOf(u8, json, "\"name\":\"John\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"age\":30") != null);
}

test "json_encode - 嵌套结构" {
    var vm = try TestVM.init(testing.allocator);
    defer vm.deinit();

    // 创建嵌套对象: {"user": {"name": "Alice", "scores": [90, 85, 95]}}
    const scores = try vm.memory_manager.createArray();
    try scores.data.set(Value.initInt(0), Value.initInt(90));
    try scores.data.set(Value.initInt(1), Value.initInt(85));
    try scores.data.set(Value.initInt(2), Value.initInt(95));

    const user = try vm.memory_manager.createArray();
    const name_key = try vm.memory_manager.createString("name");
    const name_val = try vm.memory_manager.createString("Alice");
    try user.data.set(Value.initString(name_key), Value.initString(name_val));

    const scores_key = try vm.memory_manager.createString("scores");
    try user.data.set(Value.initString(scores_key), Value.initArray(scores));

    const root = try vm.memory_manager.createArray();
    const user_key = try vm.memory_manager.createString("user");
    try root.data.set(Value.initString(user_key), Value.initArray(user));

    const args = [_]Value{Value.initArray(root)};
    const result = try JsonFunctions.jsonEncode(&vm, &args);

    const json = result.getAsString().data.data;
    try testing.expect(std.mem.indexOf(u8, json, "\"user\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"name\":\"Alice\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"scores\":[90,85,95]") != null);
}

test "json_encode - 选项支持 (PRETTY_PRINT)" {
    var vm = try TestVM.init(testing.allocator);
    defer vm.deinit();

    const arr = try vm.memory_manager.createArray();
    try arr.data.set(Value.initInt(0), Value.initInt(1));
    try arr.data.set(Value.initInt(1), Value.initInt(2));

    // JSON_PRETTY_PRINT = 128
    const args = [_]Value{ Value.initArray(arr), Value.initInt(128) };
    const result = try JsonFunctions.jsonEncode(&vm, &args);

    const json = result.getAsString().data.data;
    // 应该包含换行符
    try testing.expect(std.mem.indexOf(u8, json, "\n") != null);
}

test "json_decode - 基本类型" {
    var vm = try TestVM.init(testing.allocator);
    defer vm.deinit();

    // null
    {
        const json_str = try vm.memory_manager.createString("null");
        const args = [_]Value{Value.initString(json_str)};
        const result = try JsonFunctions.jsonDecode(&vm, &args);
        try testing.expect(result.getTag() == .null);
    }

    // boolean
    {
        const json_str = try vm.memory_manager.createString("true");
        const args = [_]Value{Value.initString(json_str)};
        const result = try JsonFunctions.jsonDecode(&vm, &args);
        try testing.expect(result.getTag() == .boolean);
        try testing.expect(result.asBool() == true);
    }

    {
        const json_str = try vm.memory_manager.createString("false");
        const args = [_]Value{Value.initString(json_str)};
        const result = try JsonFunctions.jsonDecode(&vm, &args);
        try testing.expect(result.getTag() == .boolean);
        try testing.expect(result.asBool() == false);
    }

    // integer
    {
        const json_str = try vm.memory_manager.createString("42");
        const args = [_]Value{Value.initString(json_str)};
        const result = try JsonFunctions.jsonDecode(&vm, &args);
        try testing.expect(result.getTag() == .integer);
        try testing.expectEqual(@as(i64, 42), result.asInt());
    }

    // float
    {
        const json_str = try vm.memory_manager.createString("3.14");
        const args = [_]Value{Value.initString(json_str)};
        const result = try JsonFunctions.jsonDecode(&vm, &args);
        try testing.expect(result.getTag() == .float);
        try testing.expectApproxEqAbs(@as(f64, 3.14), result.asFloat(), 0.001);
    }

    // string
    {
        const json_str = try vm.memory_manager.createString("\"Hello World\"");
        const args = [_]Value{Value.initString(json_str)};
        const result = try JsonFunctions.jsonDecode(&vm, &args);
        try testing.expect(result.getTag() == .string);
        try testing.expectEqualStrings("Hello World", result.getAsString().data.data);
    }
}

test "json_decode - 字符串转义" {
    var vm = try TestVM.init(testing.allocator);
    defer vm.deinit();

    const json_str = try vm.memory_manager.createString("\"Hello\\n\\\"World\\\"\\t\\\\\"");
    const args = [_]Value{Value.initString(json_str)};
    const result = try JsonFunctions.jsonDecode(&vm, &args);

    try testing.expect(result.getTag() == .string);
    try testing.expectEqualStrings("Hello\n\"World\"\t\\", result.getAsString().data.data);
}

test "json_decode - Unicode 转义" {
    var vm = try TestVM.init(testing.allocator);
    defer vm.deinit();

    const json_str = try vm.memory_manager.createString("\"\\u4F60\\u597D\"");
    const args = [_]Value{Value.initString(json_str)};
    const result = try JsonFunctions.jsonDecode(&vm, &args);

    try testing.expect(result.getTag() == .string);
    // "你好" in UTF-8
    try testing.expectEqualStrings("你好", result.getAsString().data.data);
}

test "json_decode - 数组" {
    var vm = try TestVM.init(testing.allocator);
    defer vm.deinit();

    const json_str = try vm.memory_manager.createString("[1, 2, 3]");
    const args = [_]Value{Value.initString(json_str)};
    const result = try JsonFunctions.jsonDecode(&vm, &args);

    try testing.expect(result.getTag() == .array);
    const arr = result.getAsArray().data;

    const val0 = arr.elements.get(Value.initInt(0)).?;
    try testing.expectEqual(@as(i64, 1), val0.asInt());

    const val1 = arr.elements.get(Value.initInt(1)).?;
    try testing.expectEqual(@as(i64, 2), val1.asInt());

    const val2 = arr.elements.get(Value.initInt(2)).?;
    try testing.expectEqual(@as(i64, 3), val2.asInt());
}

test "json_decode - 空数组" {
    var vm = try TestVM.init(testing.allocator);
    defer vm.deinit();

    const json_str = try vm.memory_manager.createString("[]");
    const args = [_]Value{Value.initString(json_str)};
    const result = try JsonFunctions.jsonDecode(&vm, &args);

    try testing.expect(result.getTag() == .array);
    const arr = result.getAsArray().data;
    try testing.expectEqual(@as(usize, 0), arr.elements.count());
}

test "json_decode - 对象" {
    var vm = try TestVM.init(testing.allocator);
    defer vm.deinit();

    const json_str = try vm.memory_manager.createString("{\"name\": \"John\", \"age\": 30}");
    const args = [_]Value{Value.initString(json_str)};
    const result = try JsonFunctions.jsonDecode(&vm, &args);

    try testing.expect(result.getTag() == .array);
    const arr = result.getAsArray().data;

    const name_key = try vm.memory_manager.createString("name");
    const name_val = arr.elements.get(Value.initString(name_key)).?;
    try testing.expectEqualStrings("John", name_val.getAsString().data.data);

    const age_key = try vm.memory_manager.createString("age");
    const age_val = arr.elements.get(Value.initString(age_key)).?;
    try testing.expectEqual(@as(i64, 30), age_val.asInt());
}

test "json_decode - 空对象" {
    var vm = try TestVM.init(testing.allocator);
    defer vm.deinit();

    const json_str = try vm.memory_manager.createString("{}");
    const args = [_]Value{Value.initString(json_str)};
    const result = try JsonFunctions.jsonDecode(&vm, &args);

    try testing.expect(result.getTag() == .array);
    const arr = result.getAsArray().data;
    try testing.expectEqual(@as(usize, 0), arr.elements.count());
}

test "json_decode - 嵌套结构" {
    var vm = try TestVM.init(testing.allocator);
    defer vm.deinit();

    const json_str = try vm.memory_manager.createString(
        \\{"user": {"name": "Alice", "scores": [90, 85, 95]}}
    );
    const args = [_]Value{Value.initString(json_str)};
    const result = try JsonFunctions.jsonDecode(&vm, &args);

    try testing.expect(result.getTag() == .array);
    const root = result.getAsArray().data;

    const user_key = try vm.memory_manager.createString("user");
    const user_val = root.elements.get(Value.initString(user_key)).?;
    try testing.expect(user_val.getTag() == .array);

    const user = user_val.getAsArray().data;
    const name_key = try vm.memory_manager.createString("name");
    const name_val = user.elements.get(Value.initString(name_key)).?;
    try testing.expectEqualStrings("Alice", name_val.getAsString().data.data);

    const scores_key = try vm.memory_manager.createString("scores");
    const scores_val = user.elements.get(Value.initString(scores_key)).?;
    try testing.expect(scores_val.getTag() == .array);

    const scores = scores_val.getAsArray().data;
    try testing.expectEqual(@as(i64, 90), scores.elements.get(Value.initInt(0)).?.asInt());
    try testing.expectEqual(@as(i64, 85), scores.elements.get(Value.initInt(1)).?.asInt());
    try testing.expectEqual(@as(i64, 95), scores.elements.get(Value.initInt(2)).?.asInt());
}

test "json_decode - 混合数组" {
    var vm = try TestVM.init(testing.allocator);
    defer vm.deinit();

    const json_str = try vm.memory_manager.createString("[1, \"hello\", true, null, 3.14]");
    const args = [_]Value{Value.initString(json_str)};
    const result = try JsonFunctions.jsonDecode(&vm, &args);

    try testing.expect(result.getTag() == .array);
    const arr = result.getAsArray().data;

    try testing.expectEqual(@as(i64, 1), arr.elements.get(Value.initInt(0)).?.asInt());
    try testing.expectEqualStrings("hello", arr.elements.get(Value.initInt(1)).?.getAsString().data.data);
    try testing.expect(arr.elements.get(Value.initInt(2)).?.asBool() == true);
    try testing.expect(arr.elements.get(Value.initInt(3)).?.getTag() == .null);
    try testing.expectApproxEqAbs(@as(f64, 3.14), arr.elements.get(Value.initInt(4)).?.asFloat(), 0.001);
}

test "json_decode - 科学计数法" {
    var vm = try TestVM.init(testing.allocator);
    defer vm.deinit();

    const json_str = try vm.memory_manager.createString("1.23e10");
    const args = [_]Value{Value.initString(json_str)};
    const result = try JsonFunctions.jsonDecode(&vm, &args);

    try testing.expect(result.getTag() == .float);
    try testing.expectApproxEqAbs(@as(f64, 1.23e10), result.asFloat(), 1.0);
}

test "json_decode - 负数" {
    var vm = try TestVM.init(testing.allocator);
    defer vm.deinit();

    {
        const json_str = try vm.memory_manager.createString("-42");
        const args = [_]Value{Value.initString(json_str)};
        const result = try JsonFunctions.jsonDecode(&vm, &args);
        try testing.expectEqual(@as(i64, -42), result.asInt());
    }

    {
        const json_str = try vm.memory_manager.createString("-3.14");
        const args = [_]Value{Value.initString(json_str)};
        const result = try JsonFunctions.jsonDecode(&vm, &args);
        try testing.expectApproxEqAbs(@as(f64, -3.14), result.asFloat(), 0.001);
    }
}

test "json_decode - 空白字符处理" {
    var vm = try TestVM.init(testing.allocator);
    defer vm.deinit();

    const json_str = try vm.memory_manager.createString(
        \\  {  "name"  :  "John"  ,  "age"  :  30  }  
    );
    const args = [_]Value{Value.initString(json_str)};
    const result = try JsonFunctions.jsonDecode(&vm, &args);

    try testing.expect(result.getTag() == .array);
    const arr = result.getAsArray().data;

    const name_key = try vm.memory_manager.createString("name");
    const name_val = arr.elements.get(Value.initString(name_key)).?;
    try testing.expectEqualStrings("John", name_val.getAsString().data.data);
}

test "json_decode - 无效 JSON 返回 null" {
    var vm = try TestVM.init(testing.allocator);
    defer vm.deinit();

    const invalid_cases = [_][]const u8{
        "invalid",
        "{invalid}",
        "[1, 2,]",
        "{\"key\": }",
        "\"unclosed string",
    };

    for (invalid_cases) |case| {
        const json_str = try vm.memory_manager.createString(case);
        const args = [_]Value{Value.initString(json_str)};
        const result = try JsonFunctions.jsonDecode(&vm, &args);
        try testing.expect(result.getTag() == .null);
    }
}

test "json 往返测试 - 基本类型" {
    var vm = try TestVM.init(testing.allocator);
    defer vm.deinit();

    const test_cases = [_]Value{
        Value.initNull(),
        Value.initBool(true),
        Value.initBool(false),
        Value.initInt(42),
        Value.initInt(-100),
    };

    for (test_cases) |original| {
        // Encode
        const encode_args = [_]Value{original};
        const json = try JsonFunctions.jsonEncode(&vm, &encode_args);

        // Decode
        const decode_args = [_]Value{json};
        const decoded = try JsonFunctions.jsonDecode(&vm, &decode_args);

        // Verify
        try testing.expectEqual(original.getTag(), decoded.getTag());
        switch (original.getTag()) {
            .null => {},
            .boolean => try testing.expectEqual(original.asBool(), decoded.asBool()),
            .integer => try testing.expectEqual(original.asInt(), decoded.asInt()),
            else => {},
        }
    }
}

test "json 往返测试 - 数组" {
    var vm = try TestVM.init(testing.allocator);
    defer vm.deinit();

    const arr = try vm.memory_manager.createArray();
    try arr.data.set(Value.initInt(0), Value.initInt(1));
    try arr.data.set(Value.initInt(1), Value.initInt(2));
    try arr.data.set(Value.initInt(2), Value.initInt(3));

    // Encode
    const encode_args = [_]Value{Value.initArray(arr)};
    const json = try JsonFunctions.jsonEncode(&vm, &encode_args);

    // Decode
    const decode_args = [_]Value{json};
    const decoded = try JsonFunctions.jsonDecode(&vm, &decode_args);

    // Verify
    try testing.expect(decoded.getTag() == .array);
    const decoded_arr = decoded.getAsArray().data;
    try testing.expectEqual(@as(i64, 1), decoded_arr.elements.get(Value.initInt(0)).?.asInt());
    try testing.expectEqual(@as(i64, 2), decoded_arr.elements.get(Value.initInt(1)).?.asInt());
    try testing.expectEqual(@as(i64, 3), decoded_arr.elements.get(Value.initInt(2)).?.asInt());
}
