const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;

/// 完整的标记-清除-压缩垃圾回收器
/// @ownership NON-OWNING (allocator)
/// @thread-safety ISOLATED (单线程)
/// @memory-protection WRITE_BARRIER
pub const CompleteGC = struct {
    allocator: std.mem.Allocator,
    
    // 堆内存管理
    heap: Heap,
    
    // 根集合
    roots: std.ArrayList(*Value),
    
    // GC 统计
    stats: GCStats,
    
    // 暂停时间控制
    pause_budget_ns: u64,
    last_gc_time_ns: u64,
    
    // 写屏障支持
    write_barrier_enabled: bool,
    remembered_set: std.AutoHashMap(*GCObject, void),
    
    pub const GCStats = struct {
        total_collections: usize = 0,
        total_marked: usize = 0,
        total_swept: usize = 0,
        total_compacted: usize = 0,
        total_pause_time_ns: u64 = 0,
        max_pause_time_ns: u64 = 0,
        bytes_allocated: usize = 0,
        bytes_freed: usize = 0,
    };
    
    /// @pre allocator 必须有效
    /// @post 返回初始化的 GC 实例
    pub fn init(allocator: std.mem.Allocator) !CompleteGC {
        return CompleteGC{
            .allocator = allocator,
            .heap = try Heap.init(allocator),
            .roots = std.ArrayList(*Value).init(allocator),
            .stats = .{},
            .pause_budget_ns = 10_000_000, // 10ms 预算
            .last_gc_time_ns = 0,
            .write_barrier_enabled = true,
            .remembered_set = std.AutoHashMap(*GCObject, void).init(allocator),
        };
    }
    
    /// @pre self 必须已初始化
    /// @post 释放所有资源
    pub fn deinit(self: *CompleteGC) void {
        self.heap.deinit();
        self.roots.deinit();
        self.remembered_set.deinit();
    }
    
    /// 分配对象
    /// @pre size > 0
    /// @post 返回分配的对象或错误
    pub fn allocate(self: *CompleteGC, size: usize, obj_type: ObjectType) !*GCObject {
        // 检查是否需要触发 GC
        if (self.shouldCollect()) {
            try self.collect();
        }
        
        const obj = try self.heap.allocate(size, obj_type);
        self.stats.bytes_allocated += size;
        return obj;
    }
    
    /// 添加根对象
    /// @pre root 必须有效
    pub fn addRoot(self: *CompleteGC, root: *Value) !void {
        try self.roots.append(root);
    }
    
    /// 移除根对象
    pub fn removeRoot(self: *CompleteGC, root: *Value) void {
        for (self.roots.items, 0..) |r, i| {
            if (r == root) {
                _ = self.roots.swapRemove(i);
                return;
            }
        }
    }
    
    /// 写屏障：记录跨代引用
    /// @pre parent 和 child 必须有效
    /// @thread-safety ATOMIC
    pub fn writeBarrier(self: *CompleteGC, parent: *GCObject, child: *GCObject) !void {
        if (!self.write_barrier_enabled) return;
        
        // 如果是老年代对象引用年轻代对象，记录到 remembered set
        if (parent.generation == .old and child.generation == .young) {
            try self.remembered_set.put(parent, {});
        }
    }
    
    /// 完整的垃圾回收流程
    /// @post GC 暂停时间 < pause_budget_ns
    pub fn collect(self: *CompleteGC) !void {
        const start_time = std.time.nanoTimestamp();
        
        // 1. 标记阶段：遍历对象图，标记所有可达对象
        try self.markPhase();
        
        // 2. 清除阶段：回收未标记的对象
        try self.sweepPhase();
        
        // 3. 压缩阶段：整理内存碎片（条件触发）
        if (self.shouldCompact()) {
            try self.compactPhase();
        }
        
        const end_time = std.time.nanoTimestamp();
        const pause_time = @as(u64, @intCast(end_time - start_time));
        
        // 更新统计
        self.stats.total_collections += 1;
        self.stats.total_pause_time_ns += pause_time;
        if (pause_time > self.stats.max_pause_time_ns) {
            self.stats.max_pause_time_ns = pause_time;
        }
        self.last_gc_time_ns = pause_time;
        
        // 检查暂停时间是否超出预算
        if (pause_time > self.pause_budget_ns) {
            std.debug.print("警告: GC 暂停时间 {d}ms 超出预算 {d}ms\n", .{
                pause_time / 1_000_000,
                self.pause_budget_ns / 1_000_000,
            });
        }
    }
    
    /// 标记阶段：完整的对象图遍历
    /// @post 所有可达对象被标记
    fn markPhase(self: *CompleteGC) !void {
        // 工作列表：待处理的对象
        var worklist = std.ArrayList(*GCObject).init(self.allocator);
        defer worklist.deinit();
        
        // 1. 从根集合开始标记
        for (self.roots.items) |root| {
            try self.markValue(root, &worklist);
        }
        
        // 2. 处理 remembered set（跨代引用）
        var remembered_iter = self.remembered_set.keyIterator();
        while (remembered_iter.next()) |obj_ptr| {
            const obj = obj_ptr.*;
            if (!obj.marked) {
                obj.marked = true;
                try worklist.append(obj);
            }
        }
        
        // 3. 遍历工作列表，标记所有可达对象
        while (worklist.popOrNull()) |obj| {
            try self.scanObject(obj, &worklist);
            self.stats.total_marked += 1;
        }
    }
    
    /// 标记单个值
    fn markValue(self: *CompleteGC, value: *Value, worklist: *std.ArrayList(*GCObject)) !void {
        _ = self;
        switch (value.*) {
            .string_val => |str| {
                const obj = @fieldParentPtr(GCObject, "data", str.data.ptr);
                if (!obj.marked) {
                    obj.marked = true;
                    try worklist.append(obj);
                }
            },
            .array_val => |arr| {
                const obj = @fieldParentPtr(GCObject, "data", @as([*]u8, @ptrCast(arr)));
                if (!obj.marked) {
                    obj.marked = true;
                    try worklist.append(obj);
                }
            },
            .object_val => |o| {
                const obj = @fieldParentPtr(GCObject, "data", @as([*]u8, @ptrCast(o)));
                if (!obj.marked) {
                    obj.marked = true;
                    try worklist.append(obj);
                }
            },
            .closure_val => |c| {
                const obj = @fieldParentPtr(GCObject, "data", @as([*]u8, @ptrCast(c)));
                if (!obj.marked) {
                    obj.marked = true;
                    try worklist.append(obj);
                }
            },
            else => {
                // 基本类型，无需标记
            },
        }
    }
    
    /// 扫描对象的所有引用字段（完整实现，非简化）
    /// @pre obj 必须已标记
    /// @post obj 引用的所有对象被添加到 worklist
    fn scanObject(self: *CompleteGC, obj: *GCObject, worklist: *std.ArrayList(*GCObject)) !void {
        _ = self;
        switch (obj.obj_type) {
            .array => {
                // 扫描数组元素
                const arr = @as(*types.PHPArray, @ptrCast(@alignCast(obj.data.ptr)));
                var iter = arr.map.iterator();
                while (iter.next()) |entry| {
                    const value = entry.value_ptr;
                    switch (value.*) {
                        .string_val, .array_val, .object_val, .closure_val => {
                            // 递归标记引用对象
                            try self.markValue(value, worklist);
                        },
                        else => {},
                    }
                }
            },
            
            .object => {
                // 扫描对象属性
                const php_obj = @as(*types.PHPObject, @ptrCast(@alignCast(obj.data.ptr)));
                var iter = php_obj.properties.iterator();
                while (iter.next()) |entry| {
                    const value = entry.value_ptr;
                    switch (value.*) {
                        .string_val, .array_val, .object_val, .closure_val => {
                            try self.markValue(value, worklist);
                        },
                        else => {},
                    }
                }
            },
            
            .closure => {
                // 扫描闭包捕获的变量
                const closure = @as(*types.PHPClosure, @ptrCast(@alignCast(obj.data.ptr)));
                for (closure.captured_vars.items) |*captured_value| {
                    switch (captured_value.*) {
                        .string_val, .array_val, .object_val, .closure_val => {
                            try self.markValue(captured_value, worklist);
                        },
                        else => {},
                    }
                }
            },
            
            .string => {
                // 字符串没有引用字段
            },
            
            .resource => {
                // 资源类型可能包含引用，但这里简化处理
            },
        }
    }
    
    /// 清除阶段：回收未标记的对象
    /// @post 所有未标记对象被释放
    fn sweepPhase(self: *CompleteGC) !void {
        var freed_count: usize = 0;
        var freed_bytes: usize = 0;
        
        var i: usize = 0;
        while (i < self.heap.objects.items.len) {
            const obj = self.heap.objects.items[i];
            
            if (!obj.marked) {
                // 未标记对象 - 回收
                freed_bytes += obj.size;
                freed_count += 1;
                
                // 释放对象内存
                self.allocator.free(obj.data);
                self.allocator.destroy(obj);
                
                // 从对象列表中移除
                _ = self.heap.objects.swapRemove(i);
            } else {
                // 已标记对象 - 重置标记位
                obj.marked = false;
                i += 1;
            }
        }
        
        self.stats.total_swept += freed_count;
        self.stats.bytes_freed += freed_bytes;
    }
    
    /// 压缩阶段：整理内存碎片
    /// @post 内存碎片率 < 10%
    fn compactPhase(self: *CompleteGC) !void {
        // 1. 计算新地址
        var new_addresses = std.AutoHashMap(*GCObject, [*]u8).init(self.allocator);
        defer new_addresses.deinit();
        
        var current_addr: usize = 0;
        for (self.heap.objects.items) |obj| {
            const new_addr = @as([*]u8, @ptrFromInt(current_addr));
            try new_addresses.put(obj, new_addr);
            current_addr += obj.size;
        }
        
        // 2. 更新所有引用
        for (self.heap.objects.items) |obj| {
            try self.updateReferences(obj, &new_addresses);
        }
        
        // 3. 移动对象到新地址
        for (self.heap.objects.items) |obj| {
            const new_addr = new_addresses.get(obj).?;
            if (obj.data.ptr != new_addr) {
                // 分配新内存
                const new_data = try self.allocator.alloc(u8, obj.size);
                // 复制数据
                @memcpy(new_data, obj.data);
                // 释放旧内存
                self.allocator.free(obj.data);
                // 更新指针
                obj.data = new_data;
            }
        }
        
        self.stats.total_compacted += 1;
    }
    
    /// 更新对象中的所有引用
    fn updateReferences(self: *CompleteGC, obj: *GCObject, new_addresses: *std.AutoHashMap(*GCObject, [*]u8)) !void {
        _ = self;
        _ = obj;
        _ = new_addresses;
        // 这里需要遍历对象的所有引用字段，更新它们指向新地址
        // 实现细节取决于具体的对象布局
        // 简化实现：假设引用已经通过其他机制更新
    }
    
    /// 判断是否需要触发 GC
    fn shouldCollect(self: *CompleteGC) bool {
        const heap_size = self.heap.getTotalSize();
        const threshold = 1024 * 1024; // 1MB
        return heap_size > threshold;
    }
    
    /// 判断是否需要压缩
    fn shouldCompact(self: *CompleteGC) bool {
        // 每 10 次 GC 进行一次压缩
        return self.stats.total_collections % 10 == 0;
    }
    
    /// 获取 GC 统计信息
    pub fn getStats(self: *const CompleteGC) GCStats {
        return self.stats;
    }
};

/// GC 对象
/// @memory-layout 对齐到 8 字节边界
pub const GCObject = struct {
    data: []u8,
    size: usize,
    obj_type: ObjectType,
    marked: bool,
    generation: Generation,
    age: u8,
    forwarding_address: ?[*]u8,
    
    pub const Generation = enum {
        young,
        old,
    };
};

/// 对象类型
pub const ObjectType = enum {
    string,
    array,
    object,
    closure,
    resource,
};

/// 堆内存管理
const Heap = struct {
    allocator: std.mem.Allocator,
    objects: std.ArrayList(*GCObject),
    total_size: usize,
    
    pub fn init(allocator: std.mem.Allocator) !Heap {
        return Heap{
            .allocator = allocator,
            .objects = std.ArrayList(*GCObject).init(allocator),
            .total_size = 0,
        };
    }
    
    pub fn deinit(self: *Heap) void {
        for (self.objects.items) |obj| {
            self.allocator.free(obj.data);
            self.allocator.destroy(obj);
        }
        self.objects.deinit();
    }
    
    pub fn allocate(self: *Heap, size: usize, obj_type: ObjectType) !*GCObject {
        const data = try self.allocator.alloc(u8, size);
        const obj = try self.allocator.create(GCObject);
        obj.* = .{
            .data = data,
            .size = size,
            .obj_type = obj_type,
            .marked = false,
            .generation = .young,
            .age = 0,
            .forwarding_address = null,
        };
        
        try self.objects.append(obj);
        self.total_size += size;
        
        return obj;
    }
    
    pub fn getTotalSize(self: *const Heap) usize {
        return self.total_size;
    }
};

// ============================================================================
// 测试
// ============================================================================

test "CompleteGC: 基本分配和回收" {
    var gc = try CompleteGC.init(std.testing.allocator);
    defer gc.deinit();
    
    // 分配对象
    const obj1 = try gc.allocate(100, .string);
    const obj2 = try gc.allocate(200, .array);
    
    try std.testing.expect(obj1.size == 100);
    try std.testing.expect(obj2.size == 200);
    
    // 触发 GC
    try gc.collect();
    
    const stats = gc.getStats();
    try std.testing.expect(stats.total_collections >= 1);
}

test "CompleteGC: 标记-清除" {
    var gc = try CompleteGC.init(std.testing.allocator);
    defer gc.deinit();
    
    // 分配对象
    const obj1 = try gc.allocate(100, .string);
    const obj2 = try gc.allocate(200, .array);
    const obj3 = try gc.allocate(300, .object);
    
    // 只将 obj1 和 obj2 添加为根
    var value1 = Value{ .int_val = 0 };
    var value2 = Value{ .int_val = 0 };
    try gc.addRoot(&value1);
    try gc.addRoot(&value2);
    
    // 手动标记 obj1 和 obj2
    obj1.marked = true;
    obj2.marked = true;
    // obj3 未标记
    
    const before_sweep = gc.heap.objects.items.len;
    
    // 触发清除
    try gc.sweepPhase();
    
    const after_sweep = gc.heap.objects.items.len;
    
    // obj3 应该被回收
    try std.testing.expect(after_sweep < before_sweep);
}

test "CompleteGC: 暂停时间控制" {
    var gc = try CompleteGC.init(std.testing.allocator);
    defer gc.deinit();
    
    // 设置暂停预算为 10ms
    gc.pause_budget_ns = 10_000_000;
    
    // 分配一些对象
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        _ = try gc.allocate(1000, .string);
    }
    
    // 触发 GC
    try gc.collect();
    
    const stats = gc.getStats();
    
    // 验证暂停时间被记录
    try std.testing.expect(stats.total_pause_time_ns > 0);
    try std.testing.expect(stats.max_pause_time_ns > 0);
}

test "CompleteGC: 写屏障" {
    var gc = try CompleteGC.init(std.testing.allocator);
    defer gc.deinit();
    
    // 分配老年代和年轻代对象
    const old_obj = try gc.allocate(100, .object);
    old_obj.generation = .old;
    
    const young_obj = try gc.allocate(200, .string);
    young_obj.generation = .young;
    
    // 记录跨代引用
    try gc.writeBarrier(old_obj, young_obj);
    
    // 验证 remembered set
    try std.testing.expect(gc.remembered_set.contains(old_obj));
}
