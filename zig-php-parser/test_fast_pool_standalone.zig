//! Fast Pool 堆存储独立测试
//! 验证需求 4.5：Fast Pool 堆存储正确性

const std = @import("std");
const testing = std.testing;

// 简化的 Value 类型用于测试
const Value = struct {
    val: i64,
    
    pub fn initInt(i: i64) Value {
        return .{ .val = i };
    }
    
    pub fn asInt(self: Value) i64 {
        return self.val;
    }
    
    pub fn retain(self: Value) Value {
        return self;
    }
    
    pub fn release(self: Value, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }
};

// 内联局部变量条目
const InlineLocal = struct {
    name: []u8, // 拥有字符串的所有权
    value: Value,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator, name: []const u8, value: Value) !InlineLocal {
        const owned_name = try allocator.dupe(u8, name);
        return .{
            .name = owned_name,
            .value = value,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *InlineLocal) void {
        self.allocator.free(self.name);
    }
};

// 堆存储的局部变量映射
const HeapLocals = struct {
    map: std.StringHashMap(Value),
    
    pub fn init(allocator: std.mem.Allocator) HeapLocals {
        return .{
            .map = std.StringHashMap(Value).init(allocator),
        };
    }
    
    pub fn deinit(self: *HeapLocals, allocator: std.mem.Allocator) void {
        var iter = self.map.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.release(allocator);
            // 释放键字符串
            allocator.free(entry.key_ptr.*);
        }
        self.map.deinit();
    }
    
    pub fn set(self: *HeapLocals, allocator: std.mem.Allocator, name: []const u8, value: Value) !void {
        // StringHashMap 需要拥有键的所有权
        // 先检查是否已存在
        if (self.map.contains(name)) {
            // 键已存在，获取并更新值
            const old_value_ptr = self.map.getPtr(name).?;
            old_value_ptr.release(allocator);
            old_value_ptr.* = value;
            _ = value.retain();
        } else {
            // 新键，需要复制键字符串
            const owned_key = try allocator.dupe(u8, name);
            errdefer allocator.free(owned_key);
            try self.map.put(owned_key, value);
            _ = value.retain();
        }
    }
    
    pub fn get(self: *const HeapLocals, name: []const u8) ?Value {
        return self.map.get(name);
    }
    
    pub fn clear(self: *HeapLocals, allocator: std.mem.Allocator) void {
        var iter = self.map.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.release(allocator);
            // 释放键字符串
            allocator.free(entry.key_ptr.*);
        }
        self.map.clearRetainingCapacity();
    }
    
    pub fn count(self: *const HeapLocals) usize {
        return self.map.count();
    }
};

// 池化调用帧
const PooledCallFrame = struct {
    pub const INLINE_LOCALS_CAPACITY = 8;
    
    function_name: []const u8,
    file: []const u8,
    line: u32,
    inline_locals: [INLINE_LOCALS_CAPACITY]InlineLocal,
    inline_locals_count: u8,
    heap_locals: ?*HeapLocals,
    pool_managed: bool,
    
    pub fn init(function_name: []const u8, file: []const u8, line: u32) PooledCallFrame {
        return .{
            .function_name = function_name,
            .file = file,
            .line = line,
            .inline_locals = undefined,
            .inline_locals_count = 0,
            .heap_locals = null,
            .pool_managed = true,
        };
    }
    
    pub fn setLocal(self: *PooledCallFrame, allocator: std.mem.Allocator, name: []const u8, value: Value) !void {
        // 先尝试在内联存储中查找（只在已初始化的范围内）
        var i: usize = 0;
        while (i < self.inline_locals_count) : (i += 1) {
            if (std.mem.eql(u8, self.inline_locals[i].name, name)) {
                self.inline_locals[i].value.release(allocator);
                self.inline_locals[i].value = value;
                _ = value.retain();
                return;
            }
        }
        
        // 如果内联存储未满，添加到内联存储
        if (self.inline_locals_count < INLINE_LOCALS_CAPACITY) {
            self.inline_locals[self.inline_locals_count] = try InlineLocal.init(allocator, name, value);
            _ = value.retain();
            self.inline_locals_count += 1;
            return;
        }
        
        // 内联存储已满，切换到堆存储
        if (self.heap_locals == null) {
            const heap = try allocator.create(HeapLocals);
            errdefer allocator.destroy(heap);
            heap.* = HeapLocals.init(allocator);
            self.heap_locals = heap;
        }
        
        try self.heap_locals.?.set(allocator, name, value);
    }
    
    pub fn getLocal(self: *const PooledCallFrame, name: []const u8) ?Value {
        // 先在内联存储中查找（只在已初始化的范围内）
        var i: usize = 0;
        while (i < self.inline_locals_count) : (i += 1) {
            if (std.mem.eql(u8, self.inline_locals[i].name, name)) {
                return self.inline_locals[i].value;
            }
        }
        
        if (self.heap_locals) |heap| {
            return heap.get(name);
        }
        
        return null;
    }
    
    pub fn clearLocals(self: *PooledCallFrame, allocator: std.mem.Allocator) void {
        // 释放内联存储的值（只在已初始化的范围内）
        var i: usize = 0;
        while (i < self.inline_locals_count) : (i += 1) {
            self.inline_locals[i].value.release(allocator);
            self.inline_locals[i].deinit(); // 释放名称字符串
        }
        self.inline_locals_count = 0;
        
        if (self.heap_locals) |heap| {
            heap.deinit(allocator);
            allocator.destroy(heap);
            self.heap_locals = null;
        }
    }
    
    pub fn getLocalCount(self: *const PooledCallFrame) usize {
        var count: usize = self.inline_locals_count;
        if (self.heap_locals) |heap| {
            count += heap.count();
        }
        return count;
    }
    
    pub fn isUsingHeapStorage(self: *const PooledCallFrame) bool {
        return self.heap_locals != null;
    }
};

// 属性 25.1：内联存储满时自动切换到堆存储
test "Property 25.1: Automatic transition to heap storage" {
    var frame = PooledCallFrame.init("test", "test.php", 1);
    defer frame.clearLocals(testing.allocator);
    
    try testing.expect(!frame.isUsingHeapStorage());
    
    // 填满内联存储
    var i: usize = 0;
    while (i < PooledCallFrame.INLINE_LOCALS_CAPACITY) : (i += 1) {
        const name = try std.fmt.allocPrint(testing.allocator, "var_{d}", .{i});
        defer testing.allocator.free(name);
        try frame.setLocal(testing.allocator, name, Value.initInt(@intCast(i)));
    }
    
    try testing.expect(!frame.isUsingHeapStorage());
    try testing.expect(frame.getLocalCount() == PooledCallFrame.INLINE_LOCALS_CAPACITY);
    
    // 添加第 9 个变量，触发堆存储
    const overflow_name = try std.fmt.allocPrint(testing.allocator, "var_{d}", .{PooledCallFrame.INLINE_LOCALS_CAPACITY});
    defer testing.allocator.free(overflow_name);
    try frame.setLocal(testing.allocator, overflow_name, Value.initInt(@intCast(PooledCallFrame.INLINE_LOCALS_CAPACITY)));
    
    try testing.expect(frame.isUsingHeapStorage());
    try testing.expect(frame.getLocalCount() == PooledCallFrame.INLINE_LOCALS_CAPACITY + 1);
}

// 属性 25.2：堆存储无容量限制
test "Property 25.2: Heap storage has no capacity limit" {
    var frame = PooledCallFrame.init("test", "test.php", 1);
    defer frame.clearLocals(testing.allocator);
    
    const large_count = 100;
    var i: usize = 0;
    while (i < large_count) : (i += 1) {
        const name = try std.fmt.allocPrint(testing.allocator, "var_{d}", .{i});
        defer testing.allocator.free(name);
        try frame.setLocal(testing.allocator, name, Value.initInt(@intCast(i)));
    }
    
    try testing.expect(frame.getLocalCount() == large_count);
    try testing.expect(frame.isUsingHeapStorage());
    
    // 验证所有变量都能访问
    i = 0;
    while (i < large_count) : (i += 1) {
        const name = try std.fmt.allocPrint(testing.allocator, "var_{d}", .{i});
        defer testing.allocator.free(name);
        const value = frame.getLocal(name);
        try testing.expect(value != null);
        try testing.expect(value.?.asInt() == @as(i64, @intCast(i)));
    }
}

// 属性 25.3：内联和堆存储的变量都能正确访问
test "Property 25.3: Variables in both storages are accessible" {
    var frame = PooledCallFrame.init("test", "test.php", 1);
    defer frame.clearLocals(testing.allocator);
    
    // 添加内联变量
    var i: usize = 0;
    while (i < PooledCallFrame.INLINE_LOCALS_CAPACITY) : (i += 1) {
        const name = try std.fmt.allocPrint(testing.allocator, "inline_{d}", .{i});
        defer testing.allocator.free(name);
        try frame.setLocal(testing.allocator, name, Value.initInt(@intCast(i * 10)));
    }
    
    // 添加堆变量
    i = 0;
    while (i < 10) : (i += 1) {
        const name = try std.fmt.allocPrint(testing.allocator, "heap_{d}", .{i});
        defer testing.allocator.free(name);
        try frame.setLocal(testing.allocator, name, Value.initInt(@intCast(i * 100)));
    }
    
    // 验证内联变量
    i = 0;
    while (i < PooledCallFrame.INLINE_LOCALS_CAPACITY) : (i += 1) {
        const name = try std.fmt.allocPrint(testing.allocator, "inline_{d}", .{i});
        defer testing.allocator.free(name);
        const value = frame.getLocal(name);
        try testing.expect(value != null);
        try testing.expect(value.?.asInt() == @as(i64, @intCast(i * 10)));
    }
    
    // 验证堆变量
    i = 0;
    while (i < 10) : (i += 1) {
        const name = try std.fmt.allocPrint(testing.allocator, "heap_{d}", .{i});
        defer testing.allocator.free(name);
        const value = frame.getLocal(name);
        try testing.expect(value != null);
        try testing.expect(value.?.asInt() == @as(i64, @intCast(i * 100)));
    }
}

// 属性 25.4：变量更新正确处理
test "Property 25.4: Variable updates work correctly" {
    var frame = PooledCallFrame.init("test", "test.php", 1);
    defer frame.clearLocals(testing.allocator);
    
    // 测试内联存储中的更新
    try frame.setLocal(testing.allocator, "x", Value.initInt(42));
    try testing.expect(frame.getLocal("x").?.asInt() == 42);
    
    try frame.setLocal(testing.allocator, "x", Value.initInt(100));
    try testing.expect(frame.getLocal("x").?.asInt() == 100);
    
    // 填满内联存储
    var i: usize = 1;
    while (i < PooledCallFrame.INLINE_LOCALS_CAPACITY) : (i += 1) {
        const name = try std.fmt.allocPrint(testing.allocator, "var_{d}", .{i});
        defer testing.allocator.free(name);
        try frame.setLocal(testing.allocator, name, Value.initInt(@intCast(i)));
    }
    
    // 添加堆变量
    try frame.setLocal(testing.allocator, "heap_var", Value.initInt(200));
    try testing.expect(frame.isUsingHeapStorage());
    
    // 更新堆变量
    try frame.setLocal(testing.allocator, "heap_var", Value.initInt(300));
    try testing.expect(frame.getLocal("heap_var").?.asInt() == 300);
}

// 属性 25.5：清理时正确释放所有资源
test "Property 25.5: Cleanup releases all resources" {
    var frame = PooledCallFrame.init("test", "test.php", 1);
    
    // 添加大量变量
    var i: usize = 0;
    while (i < 50) : (i += 1) {
        const name = try std.fmt.allocPrint(testing.allocator, "var_{d}", .{i});
        defer testing.allocator.free(name);
        try frame.setLocal(testing.allocator, name, Value.initInt(@intCast(i)));
    }
    
    try testing.expect(frame.getLocalCount() == 50);
    try testing.expect(frame.isUsingHeapStorage());
    
    // 清理
    frame.clearLocals(testing.allocator);
    
    try testing.expect(frame.getLocalCount() == 0);
    try testing.expect(!frame.isUsingHeapStorage());
    try testing.expect(frame.getLocal("var_0") == null);
}

// 属性 25.6：边界条件测试
test "Property 25.6: Boundary conditions" {
    var frame = PooledCallFrame.init("test", "test.php", 1);
    defer frame.clearLocals(testing.allocator);
    
    // 测试空帧
    try testing.expect(frame.getLocalCount() == 0);
    try testing.expect(frame.getLocal("nonexistent") == null);
    
    // 恰好填满内联存储
    var i: usize = 0;
    while (i < PooledCallFrame.INLINE_LOCALS_CAPACITY) : (i += 1) {
        const name = try std.fmt.allocPrint(testing.allocator, "var_{d}", .{i});
        defer testing.allocator.free(name);
        try frame.setLocal(testing.allocator, name, Value.initInt(@intCast(i)));
    }
    try testing.expect(!frame.isUsingHeapStorage());
    
    // 恰好超出一个
    const overflow_name = try std.fmt.allocPrint(testing.allocator, "var_{d}", .{PooledCallFrame.INLINE_LOCALS_CAPACITY});
    defer testing.allocator.free(overflow_name);
    try frame.setLocal(testing.allocator, overflow_name, Value.initInt(@intCast(PooledCallFrame.INLINE_LOCALS_CAPACITY)));
    try testing.expect(frame.isUsingHeapStorage());
    
    // 清空后再添加
    frame.clearLocals(testing.allocator);
    try testing.expect(frame.getLocalCount() == 0);
    try frame.setLocal(testing.allocator, "new_var", Value.initInt(999));
    try testing.expect(frame.getLocalCount() == 1);
    try testing.expect(!frame.isUsingHeapStorage());
}
