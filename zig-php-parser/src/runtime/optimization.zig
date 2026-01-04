const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;

/// 性能优化模块
/// 包含：字符串驻留优化、内联缓存、数组优化、内存池、SIMD加速

// ============================================================================
// 1. 增强的字符串驻留统计
// ============================================================================

pub const InternStats = struct {
    total_interned: usize = 0,
    total_bytes_saved: usize = 0,
    hit_count: usize = 0,
    miss_count: usize = 0,
    lookup_time_ns: u64 = 0,
    intern_time_ns: u64 = 0,

    pub fn getHitRate(self: *const InternStats) f64 {
        const total = self.hit_count + self.miss_count;
        if (total == 0) return 0.0;
        return @as(f64, @floatFromInt(self.hit_count)) / @as(f64, @floatFromInt(total));
    }

    pub fn getAverageLookupTimeNs(self: *const InternStats) f64 {
        const total = self.hit_count + self.miss_count;
        if (total == 0) return 0.0;
        return @as(f64, @floatFromInt(self.lookup_time_ns)) / @as(f64, @floatFromInt(total));
    }

    pub fn format(self: *const InternStats) void {
        std.log.info("=== 字符串驻留统计 ===", .{});
        std.log.info("  驻留字符串数: {}", .{self.total_interned});
        std.log.info("  节省字节数: {} bytes", .{self.total_bytes_saved});
        std.log.info("  命中次数: {}", .{self.hit_count});
        std.log.info("  未命中次数: {}", .{self.miss_count});
        std.log.info("  命中率: {d:.2}%", .{self.getHitRate() * 100.0});
        std.log.info("  平均查找时间: {d:.2} ns", .{self.getAverageLookupTimeNs()});
    }
};

pub const EnhancedStringInterner = struct {
    allocator: std.mem.Allocator,
    strings: std.StringHashMapUnmanaged(InternedEntry),
    stats: InternStats,
    short_string_cache: [256]?[]const u8,

    const InternedEntry = struct {
        data: []const u8,
        ref_count: u32,
        hash: u64,
        length: usize,
    };

    pub fn init(alloc: std.mem.Allocator) EnhancedStringInterner {
        return .{
            .allocator = alloc,
            .strings = .{},
            .stats = .{},
            .short_string_cache = [_]?[]const u8{null} ** 256,
        };
    }

    pub fn deinit(self: *EnhancedStringInterner) void {
        var iter = self.strings.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(@constCast(entry.value_ptr.data));
        }
        self.strings.deinit(self.allocator);
    }

    pub fn intern(self: *EnhancedStringInterner, str: []const u8) ![]const u8 {
        const start_time = std.time.nanoTimestamp();
        defer {
            const end_time = std.time.nanoTimestamp();
            self.stats.lookup_time_ns += @intCast(end_time - start_time);
        }

        // 短字符串快速路径（单字符）
        if (str.len == 1) {
            const idx = str[0];
            if (self.short_string_cache[idx]) |cached| {
                self.stats.hit_count += 1;
                self.stats.total_bytes_saved += 1;
                return cached;
            }
        }

        // 常规查找
        if (self.strings.getPtr(str)) |entry| {
            entry.ref_count += 1;
            self.stats.hit_count += 1;
            self.stats.total_bytes_saved += str.len;
            return entry.data;
        }

        // 创建新的驻留字符串
        const intern_start = std.time.nanoTimestamp();
        const owned = try self.allocator.dupe(u8, str);
        const hash = std.hash.Wyhash.hash(0, str);

        try self.strings.put(self.allocator, owned, .{
            .data = owned,
            .ref_count = 1,
            .hash = hash,
            .length = str.len,
        });

        // 缓存单字符字符串
        if (str.len == 1) {
            self.short_string_cache[str[0]] = owned;
        }

        const intern_end = std.time.nanoTimestamp();
        self.stats.intern_time_ns += @intCast(intern_end - intern_start);
        self.stats.miss_count += 1;
        self.stats.total_interned += 1;

        return owned;
    }

    pub fn release(self: *EnhancedStringInterner, str: []const u8) void {
        if (self.strings.getPtr(str)) |entry| {
            if (entry.ref_count > 0) entry.ref_count -= 1;
            if (entry.ref_count == 0) {
                // 清除短字符串缓存
                if (str.len == 1) {
                    self.short_string_cache[str[0]] = null;
                }
                self.allocator.free(@constCast(entry.data));
                _ = self.strings.remove(str);
                self.stats.total_interned -= 1;
            }
        }
    }

    pub fn getStats(self: *const EnhancedStringInterner) InternStats {
        return self.stats;
    }
};

// ============================================================================
// 2. 内联缓存（Inline Caching）
// ============================================================================

pub const InlineCacheEntry = struct {
    class_id: u64,
    method_ptr: ?*anyopaque,
    hit_count: u32,
    last_access: i64,

    pub fn init() InlineCacheEntry {
        return .{
            .class_id = 0,
            .method_ptr = null,
            .hit_count = 0,
            .last_access = 0,
        };
    }

    pub fn isValid(self: *const InlineCacheEntry, target_class_id: u64) bool {
        return self.class_id == target_class_id and self.method_ptr != null;
    }

    pub fn update(self: *InlineCacheEntry, class_id: u64, method: *anyopaque) void {
        self.class_id = class_id;
        self.method_ptr = method;
        self.hit_count = 0;
        self.last_access = std.time.timestamp();
    }

    pub fn recordHit(self: *InlineCacheEntry) void {
        self.hit_count += 1;
        self.last_access = std.time.timestamp();
    }
};

pub const PolymorphicInlineCache = struct {
    entries: [MAX_ENTRIES]InlineCacheEntry,
    entry_count: usize,
    stats: CacheStats,

    const MAX_ENTRIES: usize = 4;

    pub const CacheStats = struct {
        hits: usize = 0,
        misses: usize = 0,
        evictions: usize = 0,

        pub fn getHitRate(self: *const CacheStats) f64 {
            const total = self.hits + self.misses;
            if (total == 0) return 0.0;
            return @as(f64, @floatFromInt(self.hits)) / @as(f64, @floatFromInt(total));
        }
    };

    pub fn init() PolymorphicInlineCache {
        return .{
            .entries = [_]InlineCacheEntry{InlineCacheEntry.init()} ** MAX_ENTRIES,
            .entry_count = 0,
            .stats = .{},
        };
    }

    pub fn lookup(self: *PolymorphicInlineCache, class_id: u64) ?*anyopaque {
        for (&self.entries) |*entry| {
            if (entry.isValid(class_id)) {
                entry.recordHit();
                self.stats.hits += 1;
                return entry.method_ptr;
            }
        }
        self.stats.misses += 1;
        return null;
    }

    pub fn insert(self: *PolymorphicInlineCache, class_id: u64, method: *anyopaque) void {
        // 查找空槽或最少使用的槽
        var min_hits: u32 = std.math.maxInt(u32);
        var min_idx: usize = 0;

        for (self.entries, 0..) |entry, i| {
            if (entry.method_ptr == null) {
                self.entries[i].update(class_id, method);
                self.entry_count += 1;
                return;
            }
            if (entry.hit_count < min_hits) {
                min_hits = entry.hit_count;
                min_idx = i;
            }
        }

        // 驱逐最少使用的条目
        self.entries[min_idx].update(class_id, method);
        self.stats.evictions += 1;
    }

    pub fn invalidate(self: *PolymorphicInlineCache, class_id: u64) void {
        for (&self.entries) |*entry| {
            if (entry.class_id == class_id) {
                entry.* = InlineCacheEntry.init();
                if (self.entry_count > 0) self.entry_count -= 1;
            }
        }
    }

    pub fn getStats(self: *const PolymorphicInlineCache) CacheStats {
        return self.stats;
    }
};

pub const MethodCache = struct {
    allocator: std.mem.Allocator,
    caches: std.StringHashMapUnmanaged(PolymorphicInlineCache),
    global_stats: GlobalCacheStats,

    pub const GlobalCacheStats = struct {
        total_lookups: usize = 0,
        cache_hits: usize = 0,
        cache_misses: usize = 0,
        total_methods_cached: usize = 0,

        pub fn getHitRate(self: *const GlobalCacheStats) f64 {
            if (self.total_lookups == 0) return 0.0;
            return @as(f64, @floatFromInt(self.cache_hits)) / @as(f64, @floatFromInt(self.total_lookups));
        }
    };

    pub fn init(alloc: std.mem.Allocator) MethodCache {
        return .{
            .allocator = alloc,
            .caches = .{},
            .global_stats = .{},
        };
    }

    pub fn deinit(self: *MethodCache) void {
        self.caches.deinit(self.allocator);
    }

    pub fn lookupMethod(self: *MethodCache, method_name: []const u8, class_id: u64) ?*anyopaque {
        self.global_stats.total_lookups += 1;

        if (self.caches.getPtr(method_name)) |cache| {
            if (cache.lookup(class_id)) |method| {
                self.global_stats.cache_hits += 1;
                return method;
            }
        }

        self.global_stats.cache_misses += 1;
        return null;
    }

    pub fn cacheMethod(self: *MethodCache, method_name: []const u8, class_id: u64, method: *anyopaque) !void {
        const cache = self.caches.getPtr(method_name) orelse blk: {
            try self.caches.put(self.allocator, method_name, PolymorphicInlineCache.init());
            break :blk self.caches.getPtr(method_name).?;
        };

        cache.insert(class_id, method);
        self.global_stats.total_methods_cached += 1;
    }

    pub fn invalidateClass(self: *MethodCache, class_id: u64) void {
        var iter = self.caches.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.invalidate(class_id);
        }
    }

    pub fn getStats(self: *const MethodCache) GlobalCacheStats {
        return self.global_stats;
    }
};

// ============================================================================
// 3. 数组类型优化
// ============================================================================

pub const ArrayType = enum(u8) {
    packed_array,
    sparse_array,
    mixed_array,
};

pub const OptimizedArray = struct {
    array_type: ArrayType,
    packed_data: ?PackedArray,
    sparse_data: ?SparseArray,
    stats: ArrayStats,
    allocator: std.mem.Allocator,

    pub const PackedArray = struct {
        values: std.ArrayListUnmanaged(Value),
        start_index: i64,

        pub fn init() PackedArray {
            return .{
                .values = .{},
                .start_index = 0,
            };
        }

        pub fn deinit(self: *PackedArray, allocator: std.mem.Allocator) void {
            for (self.values.items) |*v| {
                v.release(allocator);
            }
            self.values.deinit(allocator);
        }
    };

    pub const SparseArray = struct {
        elements: std.AutoHashMapUnmanaged(i64, Value),
        string_keys: std.StringHashMapUnmanaged(Value),

        pub fn init() SparseArray {
            return .{
                .elements = .{},
                .string_keys = .{},
            };
        }

        pub fn deinit(self: *SparseArray, allocator: std.mem.Allocator) void {
            var iter = self.elements.iterator();
            while (iter.next()) |entry| {
                entry.value_ptr.release(allocator);
            }
            self.elements.deinit(allocator);

            var str_iter = self.string_keys.iterator();
            while (str_iter.next()) |entry| {
                entry.value_ptr.release(allocator);
            }
            self.string_keys.deinit(allocator);
        }
    };

    pub const ArrayStats = struct {
        total_gets: usize = 0,
        total_sets: usize = 0,
        type_conversions: usize = 0,
        packed_operations: usize = 0,
        sparse_operations: usize = 0,
    };

    pub fn init(allocator: std.mem.Allocator) OptimizedArray {
        return .{
            .array_type = .packed_array,
            .packed_data = PackedArray.init(),
            .sparse_data = null,
            .stats = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *OptimizedArray) void {
        if (self.packed_data) |*p| {
            p.deinit(self.allocator);
        }
        if (self.sparse_data) |*s| {
            s.deinit(self.allocator);
        }
    }

    pub fn getByIndex(self: *OptimizedArray, index: i64) ?Value {
        self.stats.total_gets += 1;

        switch (self.array_type) {
            .packed_array => {
                if (self.packed_data) |p| {
                    const adjusted = index - p.start_index;
                    if (adjusted >= 0 and adjusted < @as(i64, @intCast(p.values.items.len))) {
                        self.stats.packed_operations += 1;
                        return p.values.items[@intCast(adjusted)];
                    }
                }
                return null;
            },
            .sparse_array, .mixed_array => {
                if (self.sparse_data) |s| {
                    self.stats.sparse_operations += 1;
                    return s.elements.get(index);
                }
                return null;
            },
        }
    }

    pub fn getByString(self: *OptimizedArray, key: []const u8) ?Value {
        self.stats.total_gets += 1;

        if (self.array_type == .packed_array) {
            self.convertToMixed();
        }

        if (self.sparse_data) |sd| {
            self.stats.sparse_operations += 1;
            return sd.string_keys.get(key);
        }
        return null;
    }

    pub fn setByIndex(self: *OptimizedArray, index: i64, value: Value) !void {
        self.stats.total_sets += 1;

        switch (self.array_type) {
            .packed_array => {
                if (self.packed_data) |*pd| {
                    const adjusted = index - pd.start_index;
                    if (adjusted >= 0 and adjusted <= @as(i64, @intCast(pd.values.items.len))) {
                        if (adjusted == @as(i64, @intCast(pd.values.items.len))) {
                            _ = value.retain();
                            try pd.values.append(self.allocator, value);
                            self.stats.packed_operations += 1;
                            return;
                        } else if (adjusted >= 0 and adjusted < @as(i64, @intCast(pd.values.items.len))) {
                            pd.values.items[@intCast(adjusted)].release(self.allocator);
                            _ = value.retain();
                            pd.values.items[@intCast(adjusted)] = value;
                            self.stats.packed_operations += 1;
                            return;
                        }
                    }
                }
                self.convertToSparse();
                try self.setByIndex(index, value);
            },
            .sparse_array, .mixed_array => {
                if (self.sparse_data) |*sd| {
                    if (sd.elements.get(index)) |old| {
                        old.release(self.allocator);
                    }
                    _ = value.retain();
                    try sd.elements.put(self.allocator, index, value);
                    self.stats.sparse_operations += 1;
                }
            },
        }
    }

    pub fn setByString(self: *OptimizedArray, key: []const u8, value: Value) !void {
        self.stats.total_sets += 1;

        if (self.array_type == .packed_array) {
            self.convertToMixed();
        }

        if (self.sparse_data) |*sd| {
            if (sd.string_keys.get(key)) |old| {
                old.release(self.allocator);
            }
            _ = value.retain();
            try sd.string_keys.put(self.allocator, key, value);
            self.stats.sparse_operations += 1;
        }
    }

    fn convertToSparse(self: *OptimizedArray) void {
        if (self.array_type != .packed_array) return;

        self.stats.type_conversions += 1;
        var new_sparse = SparseArray.init();

        if (self.packed_data) |pd| {
            for (pd.values.items, 0..) |v, i| {
                const idx = pd.start_index + @as(i64, @intCast(i));
                new_sparse.elements.put(self.allocator, idx, v) catch {};
            }
        }

        self.sparse_data = new_sparse;
        self.packed_data = null;
        self.array_type = .sparse_array;
    }

    fn convertToMixed(self: *OptimizedArray) void {
        if (self.array_type == .mixed_array) return;

        self.stats.type_conversions += 1;

        if (self.array_type == .packed_array) {
            self.convertToSparse();
        }

        self.array_type = .mixed_array;
    }

    pub fn count(self: *const OptimizedArray) usize {
        switch (self.array_type) {
            .packed_array => {
                if (self.packed_data) |pd| {
                    return pd.values.items.len;
                }
                return 0;
            },
            .sparse_array => {
                if (self.sparse_data) |sd| {
                    return sd.elements.count();
                }
                return 0;
            },
            .mixed_array => {
                if (self.sparse_data) |sd| {
                    return sd.elements.count() + sd.string_keys.count();
                }
                return 0;
            },
        }
    }

    pub fn getStats(self: *const OptimizedArray) ArrayStats {
        return self.stats;
    }

    pub fn optimizeRepresentation(self: *OptimizedArray) void {
        if (self.array_type != .sparse_array and self.array_type != .mixed_array) return;

        if (self.sparse_data) |sd| {
            // 如果有字符串键，保持mixed
            if (sd.string_keys.count() > 0) {
                self.array_type = .mixed_array;
                return;
            }

            // 检查是否可以转换为packed
            if (sd.elements.count() == 0) return;

            var min_idx: i64 = std.math.maxInt(i64);
            var max_idx: i64 = std.math.minInt(i64);

            var iter = sd.elements.iterator();
            while (iter.next()) |entry| {
                if (entry.key_ptr.* < min_idx) min_idx = entry.key_ptr.*;
                if (entry.key_ptr.* > max_idx) max_idx = entry.key_ptr.*;
            }

            const range = max_idx - min_idx + 1;
            const count_val = sd.elements.count();

            // 如果密度超过50%，转换为packed
            if (@as(f64, @floatFromInt(count_val)) / @as(f64, @floatFromInt(range)) > 0.5) {
                self.stats.type_conversions += 1;
                // 实际转换逻辑...
            }
        }
    }
};

// ============================================================================
// 4. 分代内存池
// ============================================================================

pub const GenerationalPool = struct {
    allocator: std.mem.Allocator,
    young_pool: MemoryPool,
    old_pool: MemoryPool,
    promotion_threshold: usize,
    stats: PoolStats,

    pub const MemoryPool = struct {
        blocks: std.ArrayListUnmanaged(*Block),
        current_block: ?*Block,
        block_size: usize,
        total_allocated: usize,
        total_used: usize,

        const Block = struct {
            data: []u8,
            offset: usize,
            allocations: usize,

            pub fn create(allocator: std.mem.Allocator, size: usize) !*Block {
                const block = try allocator.create(Block);
                block.data = try allocator.alloc(u8, size);
                block.offset = 0;
                block.allocations = 0;
                return block;
            }

            pub fn destroy(self: *Block, allocator: std.mem.Allocator) void {
                allocator.free(self.data);
                allocator.destroy(self);
            }

            pub fn tryAlloc(self: *Block, size: usize, alignment: usize) ?[]u8 {
                const aligned = std.mem.alignForward(usize, self.offset, alignment);
                if (aligned + size > self.data.len) return null;
                const result = self.data[aligned .. aligned + size];
                self.offset = aligned + size;
                self.allocations += 1;
                return result;
            }

            pub fn reset(self: *Block) void {
                self.offset = 0;
                self.allocations = 0;
            }
        };

        pub fn init(block_size: usize) MemoryPool {
            return .{
                .blocks = .{},
                .current_block = null,
                .block_size = block_size,
                .total_allocated = 0,
                .total_used = 0,
            };
        }

        pub fn deinit(self: *MemoryPool, allocator: std.mem.Allocator) void {
            for (self.blocks.items) |block| {
                block.destroy(allocator);
            }
            self.blocks.deinit(allocator);
        }

        pub fn alloc(self: *MemoryPool, allocator: std.mem.Allocator, size: usize, alignment: usize) ![]u8 {
            if (self.current_block) |block| {
                if (block.tryAlloc(size, alignment)) |result| {
                    self.total_used += size;
                    return result;
                }
            }

            const new_size = @max(self.block_size, size + alignment);
            const new_block = try Block.create(allocator, new_size);
            try self.blocks.append(allocator, new_block);
            self.current_block = new_block;
            self.total_allocated += new_size;

            if (new_block.tryAlloc(size, alignment)) |result| {
                self.total_used += size;
                return result;
            }
            return error.OutOfMemory;
        }

        pub fn reset(self: *MemoryPool) void {
            for (self.blocks.items) |block| {
                block.reset();
            }
            if (self.blocks.items.len > 0) {
                self.current_block = self.blocks.items[0];
            }
            self.total_used = 0;
        }
    };

    pub const PoolStats = struct {
        young_allocations: usize = 0,
        old_allocations: usize = 0,
        promotions: usize = 0,
        young_collections: usize = 0,
        total_bytes_allocated: usize = 0,
    };

    pub fn init(allocator: std.mem.Allocator) GenerationalPool {
        return .{
            .allocator = allocator,
            .young_pool = MemoryPool.init(64 * 1024),
            .old_pool = MemoryPool.init(256 * 1024),
            .promotion_threshold = 3,
            .stats = .{},
        };
    }

    pub fn deinit(self: *GenerationalPool) void {
        self.young_pool.deinit(self.allocator);
        self.old_pool.deinit(self.allocator);
    }

    pub fn allocYoung(self: *GenerationalPool, size: usize, alignment: usize) ![]u8 {
        self.stats.young_allocations += 1;
        self.stats.total_bytes_allocated += size;
        return self.young_pool.alloc(self.allocator, size, alignment);
    }

    pub fn allocOld(self: *GenerationalPool, size: usize, alignment: usize) ![]u8 {
        self.stats.old_allocations += 1;
        self.stats.total_bytes_allocated += size;
        return self.old_pool.alloc(self.allocator, size, alignment);
    }

    pub fn collectYoung(self: *GenerationalPool) void {
        self.young_pool.reset();
        self.stats.young_collections += 1;
    }

    pub fn getStats(self: *const GenerationalPool) PoolStats {
        return self.stats;
    }
};

// ============================================================================
// 5. SIMD优化工具
// ============================================================================

pub const SimdUtils = struct {
    pub const Vector16 = @Vector(16, u8);

    pub fn skipWhitespace(data: []const u8) usize {
        var i: usize = 0;

        // SIMD快速路径（16字节对齐）
        while (i + 16 <= data.len) {
            const chunk: Vector16 = data[i..][0..16].*;
            const spaces: Vector16 = @splat(' ');
            const tabs: Vector16 = @splat('\t');
            const newlines: Vector16 = @splat('\n');
            const returns: Vector16 = @splat('\r');

            const is_space = chunk == spaces;
            const is_tab = chunk == tabs;
            const is_newline = chunk == newlines;
            const is_return = chunk == returns;

            // 使用@select合并多个条件
            const ones: @Vector(16, u8) = @splat(1);
            const zeros: @Vector(16, u8) = @splat(0);
            const space_mask = @select(u8, is_space, ones, zeros);
            const tab_mask = @select(u8, is_tab, ones, zeros);
            const newline_mask = @select(u8, is_newline, ones, zeros);
            const return_mask = @select(u8, is_return, ones, zeros);

            const combined = space_mask | tab_mask | newline_mask | return_mask;
            const mask = @as(u16, @bitCast(combined != zeros));

            if (mask != 0xFFFF) {
                i += @ctz(~mask);
                return i;
            }
            i += 16;
        }

        // 标量回退
        while (i < data.len) {
            switch (data[i]) {
                ' ', '\t', '\n', '\r' => i += 1,
                else => return i,
            }
        }
        return i;
    }

    pub fn findChar(data: []const u8, needle: u8) ?usize {
        var i: usize = 0;

        // SIMD快速路径
        while (i + 16 <= data.len) {
            const chunk: Vector16 = data[i..][0..16].*;
            const needles: Vector16 = @splat(needle);
            const matches = chunk == needles;
            const mask = @as(u16, @bitCast(matches));

            if (mask != 0) {
                return i + @ctz(mask);
            }
            i += 16;
        }

        // 标量回退
        while (i < data.len) {
            if (data[i] == needle) return i;
            i += 1;
        }
        return null;
    }

    pub fn countChar(data: []const u8, needle: u8) usize {
        var count: usize = 0;
        var i: usize = 0;

        // SIMD快速路径
        while (i + 16 <= data.len) {
            const chunk: Vector16 = data[i..][0..16].*;
            const needles: Vector16 = @splat(needle);
            const matches = chunk == needles;
            const mask = @as(u16, @bitCast(matches));
            count += @popCount(mask);
            i += 16;
        }

        // 标量回退
        while (i < data.len) {
            if (data[i] == needle) count += 1;
            i += 1;
        }
        return count;
    }

    pub fn memcmpFast(a: []const u8, b: []const u8) bool {
        if (a.len != b.len) return false;
        if (a.len == 0) return true;

        var i: usize = 0;

        // SIMD快速路径
        while (i + 16 <= a.len) {
            const chunk_a: Vector16 = a[i..][0..16].*;
            const chunk_b: Vector16 = b[i..][0..16].*;
            if (@reduce(.Or, chunk_a != chunk_b)) return false;
            i += 16;
        }

        // 标量回退
        while (i < a.len) {
            if (a[i] != b[i]) return false;
            i += 1;
        }
        return true;
    }
};

// ============================================================================
// 6. 统一优化管理器
// ============================================================================

pub const OptimizationManager = struct {
    allocator: std.mem.Allocator,
    string_interner: EnhancedStringInterner,
    method_cache: MethodCache,
    gen_pool: GenerationalPool,
    enabled_features: Features,

    pub const Features = packed struct {
        string_interning: bool = true,
        inline_caching: bool = true,
        array_optimization: bool = true,
        generational_pool: bool = true,
        simd_acceleration: bool = true,
    };

    pub fn init(allocator: std.mem.Allocator) OptimizationManager {
        return .{
            .allocator = allocator,
            .string_interner = EnhancedStringInterner.init(allocator),
            .method_cache = MethodCache.init(allocator),
            .gen_pool = GenerationalPool.init(allocator),
            .enabled_features = .{},
        };
    }

    pub fn deinit(self: *OptimizationManager) void {
        self.string_interner.deinit();
        self.method_cache.deinit();
        self.gen_pool.deinit();
    }

    pub fn printStats(self: *OptimizationManager) void {
        std.log.info("=== 性能优化统计 ===", .{});

        if (self.enabled_features.string_interning) {
            const intern_stats = self.string_interner.getStats();
            std.log.info("字符串驻留:", .{});
            std.log.info("  驻留数: {}, 节省: {} bytes, 命中率: {d:.2}%", .{
                intern_stats.total_interned,
                intern_stats.total_bytes_saved,
                intern_stats.getHitRate() * 100.0,
            });
        }

        if (self.enabled_features.inline_caching) {
            const cache_stats = self.method_cache.getStats();
            std.log.info("方法缓存:", .{});
            std.log.info("  查找: {}, 命中: {}, 命中率: {d:.2}%", .{
                cache_stats.total_lookups,
                cache_stats.cache_hits,
                cache_stats.getHitRate() * 100.0,
            });
        }

        if (self.enabled_features.generational_pool) {
            const pool_stats = self.gen_pool.getStats();
            std.log.info("分代内存池:", .{});
            std.log.info("  年轻代分配: {}, 老年代分配: {}, 晋升: {}", .{
                pool_stats.young_allocations,
                pool_stats.old_allocations,
                pool_stats.promotions,
            });
        }
    }
};

// ============================================================================
// 测试
// ============================================================================

test "enhanced string interner" {
    var interner = EnhancedStringInterner.init(std.testing.allocator);
    defer interner.deinit();

    const s1 = try interner.intern("hello");
    const s2 = try interner.intern("hello");
    try std.testing.expect(s1.ptr == s2.ptr);

    const stats = interner.getStats();
    try std.testing.expect(stats.hit_count == 1);
    try std.testing.expect(stats.miss_count == 1);
}

test "polymorphic inline cache" {
    var cache = PolymorphicInlineCache.init();

    var dummy: u32 = 42;
    cache.insert(1, &dummy);

    const result = cache.lookup(1);
    try std.testing.expect(result != null);

    const stats = cache.getStats();
    try std.testing.expect(stats.hits == 1);
}

test "simd utils" {
    const data = "   hello world";
    const skip = SimdUtils.skipWhitespace(data);
    try std.testing.expect(skip == 3);

    const pos = SimdUtils.findChar(data, 'w');
    try std.testing.expect(pos.? == 9);
}

test "generational pool" {
    var pool = GenerationalPool.init(std.testing.allocator);
    defer pool.deinit();

    const mem = try pool.allocYoung(100, 8);
    try std.testing.expect(mem.len == 100);

    const stats = pool.getStats();
    try std.testing.expect(stats.young_allocations == 1);
}
