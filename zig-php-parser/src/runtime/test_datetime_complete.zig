const std = @import("std");
const testing = std.testing;
const datetime = @import("datetime_complete.zig");
const types = @import("types.zig");
const Value = types.Value;

/// 模拟VM结构用于测试
const MockVM = struct {
    allocator: std.mem.Allocator,
    memory_manager: types.MemoryManager,

    fn init(allocator: std.mem.Allocator) !MockVM {
        return MockVM{
            .allocator = allocator,
            .memory_manager = try types.MemoryManager.init(allocator),
        };
    }

    fn deinit(self: *MockVM) void {
        self.memory_manager.deinit();
    }
};

test "date - 基本格式化" {
    var vm = try MockVM.init(testing.allocator);
    defer vm.deinit();

    const dt = datetime.DateTimeFunctions.init(testing.allocator);

    // 测试基本格式
    const format_val = Value.initStringOwned("Y-m-d");
    const timestamp_val = Value.initInt(1705665600); // 2024-01-19 12:00:00 UTC
    const args = [_]Value{ format_val, timestamp_val };

    const result = try dt.date(&vm, &args);
    try testing.expect(result.tag == .string);
    
    const result_str = result.data.string.data.data;
    try testing.expect(std.mem.startsWith(u8, result_str, "2024-01-19"));
}

test "date - 完整格式选项" {
    var vm = try MockVM.init(testing.allocator);
    defer vm.deinit();

    const dt = datetime.DateTimeFunctions.init(testing.allocator);
    const timestamp_val = Value.initInt(1705665600); // 2024-01-19 12:00:00 UTC

    // 测试年份格式
    {
        const format_val = Value.initStringOwned("Y");
        const args = [_]Value{ format_val, timestamp_val };
        const result = try dt.date(&vm, &args);
        try testing.expectEqualStrings("2024", result.data.string.data.data);
    }

    // 测试月份格式
    {
        const format_val = Value.initStringOwned("m");
        const args = [_]Value{ format_val, timestamp_val };
        const result = try dt.date(&vm, &args);
        try testing.expectEqualStrings("01", result.data.string.data.data);
    }

    // 测试日期格式
    {
        const format_val = Value.initStringOwned("d");
        const args = [_]Value{ format_val, timestamp_val };
        const result = try dt.date(&vm, &args);
        try testing.expectEqualStrings("19", result.data.string.data.data);
    }

    // 测试时间格式
    {
        const format_val = Value.initStringOwned("H:i:s");
        const args = [_]Value{ format_val, timestamp_val };
        const result = try dt.date(&vm, &args);
        try testing.expectEqualStrings("12:00:00", result.data.string.data.data);
    }
}

test "date - ISO 8601格式" {
    var vm = try MockVM.init(testing.allocator);
    defer vm.deinit();

    const dt = datetime.DateTimeFunctions.init(testing.allocator);
    const timestamp_val = Value.initInt(1705665600);

    const format_val = Value.initStringOwned("c");
    const args = [_]Value{ format_val, timestamp_val };
    const result = try dt.date(&vm, &args);
    
    try testing.expect(result.tag == .string);
    try testing.expect(std.mem.indexOf(u8, result.data.string.data.data, "2024-01-19T") != null);
}

test "date - RFC 2822格式" {
    var vm = try MockVM.init(testing.allocator);
    defer vm.deinit();

    const dt = datetime.DateTimeFunctions.init(testing.allocator);
    const timestamp_val = Value.initInt(1705665600);

    const format_val = Value.initStringOwned("r");
    const args = [_]Value{ format_val, timestamp_val };
    const result = try dt.date(&vm, &args);
    
    try testing.expect(result.tag == .string);
    try testing.expect(std.mem.indexOf(u8, result.data.string.data.data, "2024") != null);
}

test "strtotime - 特殊关键字" {
    var vm = try MockVM.init(testing.allocator);
    defer vm.deinit();

    const dt = datetime.DateTimeFunctions.init(testing.allocator);

    // 测试 "now"
    {
        const str_val = Value.initStringOwned("now");
        const args = [_]Value{str_val};
        const result = try dt.strtotime(&vm, &args);
        try testing.expect(result.tag == .integer);
        try testing.expect(result.data.integer > 0);
    }

    // 测试 "today"
    {
        const str_val = Value.initStringOwned("today");
        const args = [_]Value{str_val};
        const result = try dt.strtotime(&vm, &args);
        try testing.expect(result.tag == .integer);
    }

    // 测试 "tomorrow"
    {
        const str_val = Value.initStringOwned("tomorrow");
        const args = [_]Value{str_val};
        const result = try dt.strtotime(&vm, &args);
        try testing.expect(result.tag == .integer);
    }

    // 测试 "yesterday"
    {
        const str_val = Value.initStringOwned("yesterday");
        const args = [_]Value{str_val};
        const result = try dt.strtotime(&vm, &args);
        try testing.expect(result.tag == .integer);
    }
}

test "strtotime - 相对时间" {
    var vm = try MockVM.init(testing.allocator);
    defer vm.deinit();

    const dt = datetime.DateTimeFunctions.init(testing.allocator);
    const base_time = Value.initInt(1705665600);

    // 测试 "+1 day"
    {
        const str_val = Value.initStringOwned("+1 day");
        const args = [_]Value{ str_val, base_time };
        const result = try dt.strtotime(&vm, &args);
        try testing.expect(result.tag == .integer);
        try testing.expectEqual(1705665600 + 86400, result.data.integer);
    }

    // 测试 "-2 hours"
    {
        const str_val = Value.initStringOwned("-2 hours");
        const args = [_]Value{ str_val, base_time };
        const result = try dt.strtotime(&vm, &args);
        try testing.expect(result.tag == .integer);
        try testing.expectEqual(1705665600 - 7200, result.data.integer);
    }

    // 测试 "+1 week"
    {
        const str_val = Value.initStringOwned("+1 week");
        const args = [_]Value{ str_val, base_time };
        const result = try dt.strtotime(&vm, &args);
        try testing.expect(result.tag == .integer);
        try testing.expectEqual(1705665600 + 604800, result.data.integer);
    }
}

test "strtotime - ISO 8601格式" {
    var vm = try MockVM.init(testing.allocator);
    defer vm.deinit();

    const dt = datetime.DateTimeFunctions.init(testing.allocator);

    // 测试完整格式
    {
        const str_val = Value.initStringOwned("2024-01-19T12:00:00");
        const args = [_]Value{str_val};
        const result = try dt.strtotime(&vm, &args);
        try testing.expect(result.tag == .integer);
        try testing.expectEqual(1705665600, result.data.integer);
    }

    // 测试带Z的格式
    {
        const str_val = Value.initStringOwned("2024-01-19T12:00:00Z");
        const args = [_]Value{str_val};
        const result = try dt.strtotime(&vm, &args);
        try testing.expect(result.tag == .integer);
        try testing.expectEqual(1705665600, result.data.integer);
    }
}

test "strtotime - 常见格式" {
    var vm = try MockVM.init(testing.allocator);
    defer vm.deinit();

    const dt = datetime.DateTimeFunctions.init(testing.allocator);

    // 测试 YYYY-MM-DD
    {
        const str_val = Value.initStringOwned("2024-01-19");
        const args = [_]Value{str_val};
        const result = try dt.strtotime(&vm, &args);
        try testing.expect(result.tag == .integer);
    }

    // 测试 YYYY-MM-DD HH:MM:SS
    {
        const str_val = Value.initStringOwned("2024-01-19 12:00:00");
        const args = [_]Value{str_val};
        const result = try dt.strtotime(&vm, &args);
        try testing.expect(result.tag == .integer);
        try testing.expectEqual(1705665600, result.data.integer);
    }
}

test "strtotime - 美式格式" {
    var vm = try MockVM.init(testing.allocator);
    defer vm.deinit();

    const dt = datetime.DateTimeFunctions.init(testing.allocator);

    // 测试 MM/DD/YYYY
    const str_val = Value.initStringOwned("01/19/2024");
    const args = [_]Value{str_val};
    const result = try dt.strtotime(&vm, &args);
    try testing.expect(result.tag == .integer);
}

test "mktime - 精确计算" {
    var vm = try MockVM.init(testing.allocator);
    defer vm.deinit();

    const dt = datetime.DateTimeFunctions.init(testing.allocator);

    // 测试基本时间戳计算
    {
        const args = [_]Value{
            Value.initInt(12), // hour
            Value.initInt(0),  // minute
            Value.initInt(0),  // second
            Value.initInt(1),  // month
            Value.initInt(19), // day
            Value.initInt(2024), // year
        };
        const result = try dt.mktime(&vm, &args);
        try testing.expect(result.tag == .integer);
        try testing.expectEqual(1705665600, result.data.integer);
    }

    // 测试1970-01-01 00:00:00
    {
        const args = [_]Value{
            Value.initInt(0),
            Value.initInt(0),
            Value.initInt(0),
            Value.initInt(1),
            Value.initInt(1),
            Value.initInt(1970),
        };
        const result = try dt.mktime(&vm, &args);
        try testing.expect(result.tag == .integer);
        try testing.expectEqual(0, result.data.integer);
    }

    // 测试闰年
    {
        const args = [_]Value{
            Value.initInt(0),
            Value.initInt(0),
            Value.initInt(0),
            Value.initInt(2),  // 2月
            Value.initInt(29), // 29日
            Value.initInt(2024), // 闰年
        };
        const result = try dt.mktime(&vm, &args);
        try testing.expect(result.tag == .integer);
        try testing.expect(result.data.integer > 0);
    }
}

test "mktime - 月份规范化" {
    var vm = try MockVM.init(testing.allocator);
    defer vm.deinit();

    const dt = datetime.DateTimeFunctions.init(testing.allocator);

    // 测试月份超出范围（13月 = 下一年1月）
    {
        const args = [_]Value{
            Value.initInt(0),
            Value.initInt(0),
            Value.initInt(0),
            Value.initInt(13), // 13月
            Value.initInt(1),
            Value.initInt(2024),
        };
        const result = try dt.mktime(&vm, &args);
        try testing.expect(result.tag == .integer);
        
        // 应该等于2025-01-01
        const expected_args = [_]Value{
            Value.initInt(0),
            Value.initInt(0),
            Value.initInt(0),
            Value.initInt(1),
            Value.initInt(1),
            Value.initInt(2025),
        };
        const expected = try dt.mktime(&vm, &expected_args);
        try testing.expectEqual(expected.data.integer, result.data.integer);
    }
}

test "time - 当前时间戳" {
    var vm = try MockVM.init(testing.allocator);
    defer vm.deinit();

    const dt = datetime.DateTimeFunctions.init(testing.allocator);
    const args = [_]Value{};
    
    const result = try dt.time(&vm, &args);
    try testing.expect(result.tag == .integer);
    try testing.expect(result.data.integer > 1700000000); // 应该大于2023年
}

test "microtime - 微秒时间" {
    var vm = try MockVM.init(testing.allocator);
    defer vm.deinit();

    const dt = datetime.DateTimeFunctions.init(testing.allocator);

    // 测试返回浮点数
    {
        const args = [_]Value{Value.initBool(true)};
        const result = try dt.microtime(&vm, &args);
        try testing.expect(result.tag == .float);
        try testing.expect(result.data.float > 1700000000.0);
    }

    // 测试返回字符串
    {
        const args = [_]Value{Value.initBool(false)};
        const result = try dt.microtime(&vm, &args);
        try testing.expect(result.tag == .string);
    }
}

test "sleep - 休眠功能" {
    var vm = try MockVM.init(testing.allocator);
    defer vm.deinit();

    const dt = datetime.DateTimeFunctions.init(testing.allocator);

    const start = std.time.milliTimestamp();
    const args = [_]Value{Value.initInt(0)}; // 0秒，快速测试
    const result = try dt.sleep(&vm, &args);
    const end = std.time.milliTimestamp();

    try testing.expect(result.tag == .integer);
    try testing.expectEqual(0, result.data.integer);
    try testing.expect(end >= start);
}

test "usleep - 微秒休眠" {
    var vm = try MockVM.init(testing.allocator);
    defer vm.deinit();

    const dt = datetime.DateTimeFunctions.init(testing.allocator);

    const start = std.time.milliTimestamp();
    const args = [_]Value{Value.initInt(1000)}; // 1000微秒 = 1毫秒
    const result = try dt.usleep(&vm, &args);
    const end = std.time.milliTimestamp();

    try testing.expect(result.tag == .null);
    try testing.expect(end >= start);
}

test "辅助函数 - isLeapYear" {
    const isLeapYear = @import("datetime_complete.zig").isLeapYear;
    
    try testing.expect(isLeapYear(2024)); // 闰年
    try testing.expect(!isLeapYear(2023)); // 平年
    try testing.expect(isLeapYear(2000)); // 400的倍数
    try testing.expect(!isLeapYear(1900)); // 100的倍数但不是400的倍数
}

test "辅助函数 - getDaysInMonth" {
    const getDaysInMonth = @import("datetime_complete.zig").getDaysInMonth;
    
    try testing.expectEqual(31, getDaysInMonth(2024, .jan));
    try testing.expectEqual(29, getDaysInMonth(2024, .feb)); // 闰年
    try testing.expectEqual(28, getDaysInMonth(2023, .feb)); // 平年
    try testing.expectEqual(30, getDaysInMonth(2024, .apr));
    try testing.expectEqual(31, getDaysInMonth(2024, .dec));
}

test "辅助函数 - calculateTimestamp" {
    const calculateTimestamp = @import("datetime_complete.zig").calculateTimestamp;
    
    // 测试1970-01-01 00:00:00
    {
        const ts = try calculateTimestamp(1970, 1, 1, 0, 0, 0);
        try testing.expectEqual(0, ts);
    }
    
    // 测试2024-01-19 12:00:00
    {
        const ts = try calculateTimestamp(2024, 1, 19, 12, 0, 0);
        try testing.expectEqual(1705665600, ts);
    }
    
    // 测试月份规范化
    {
        const ts1 = try calculateTimestamp(2024, 13, 1, 0, 0, 0);
        const ts2 = try calculateTimestamp(2025, 1, 1, 0, 0, 0);
        try testing.expectEqual(ts2, ts1);
    }
}
