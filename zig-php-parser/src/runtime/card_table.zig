const std = @import("std");

/// Card Table - 跨代引用追踪
/// 用于高效追踪老年代到年轻代的引用，避免 Minor GC 时扫描整个老年代
///
/// 设计：
/// - 每个 Card 覆盖 512 字节的内存区域
/// - Card 状态：clean（无跨代引用）或 dirty（有跨代引用）
/// - Minor GC 时只需扫描 dirty cards

// ============================================================================
// 常量定义
// ============================================================================

pub const CARD_SIZE: usize = 512; // 每个 Card 覆盖 512 字节
pub const CARD_SHIFT: u6 = 9; // log2(512) = 9
pub const CARDS_PER_BYTE: usize = 8; // 每字节存储 8 个 card 状态

// ============================================================================
// Card 状态
// ============================================================================

pub const CardState = enum(u1) {
    clean = 0, // 无跨代引用
    dirty = 1, // 有跨代引用，需要扫描
};

// ============================================================================
// Card Table 主结构
// ============================================================================

pub const CardTable = struct {
    /// 后备分配器
    allocator: std.mem.Allocator,
    /// Card 位图（每位表示一个 card 的状态）
    cards: []u8,
    /// 覆盖的内存起始地址
    base_addr: usize,
    /// 覆盖的内存大小
    covered_size: usize,
    /// Card 数量
    card_count: usize,
    /// Dirty card 数量（用于统计）
    dirty_count: usize,
    /// 统计信息
    stats: CardTableStats,

    pub const CardTableStats = struct {
        /// 标记为 dirty 的次数
        mark_dirty_count: u64 = 0,
        /// 清除 dirty 的次数
        clear_count: u64 = 0,
        /// 扫描 dirty cards 的次数
        scan_count: u64 = 0,
        /// 扫描的 dirty cards 总数
        scanned_dirty_cards: u64 = 0,
    };

    /// 初始化 Card Table
    /// base_addr: 覆盖的内存区域起始地址
    /// size: 覆盖的内存区域大小
    pub fn init(allocator: std.mem.Allocator, base_addr: usize, size: usize) !CardTable {
        // 计算需要的 card 数量
        const card_count = (size + CARD_SIZE - 1) / CARD_SIZE;
        // 计算需要的字节数（每字节存储 8 个 card）
        const byte_count = (card_count + CARDS_PER_BYTE - 1) / CARDS_PER_BYTE;

        const cards = try allocator.alloc(u8, byte_count);
        @memset(cards, 0); // 初始化为 clean

        return .{
            .allocator = allocator,
            .cards = cards,
            .base_addr = base_addr,
            .covered_size = size,
            .card_count = card_count,
            .dirty_count = 0,
            .stats = .{},
        };
    }

    pub fn deinit(self: *CardTable) void {
        self.allocator.free(self.cards);
    }

    /// 获取地址对应的 card 索引
    fn getCardIndex(self: *const CardTable, addr: usize) ?usize {
        if (addr < self.base_addr) return null;
        const offset = addr - self.base_addr;
        if (offset >= self.covered_size) return null;
        return offset >> CARD_SHIFT;
    }

    /// 获取 card 索引对应的字节索引和位偏移
    fn getByteAndBit(card_index: usize) struct { byte_idx: usize, bit_idx: u3 } {
        return .{
            .byte_idx = card_index / CARDS_PER_BYTE,
            .bit_idx = @intCast(card_index % CARDS_PER_BYTE),
        };
    }

    /// 标记地址所在的 card 为 dirty
    pub fn markDirty(self: *CardTable, addr: usize) void {
        const card_index = self.getCardIndex(addr) orelse return;
        const pos = getByteAndBit(card_index);

        const mask: u8 = @as(u8, 1) << pos.bit_idx;
        if (self.cards[pos.byte_idx] & mask == 0) {
            self.cards[pos.byte_idx] |= mask;
            self.dirty_count += 1;
        }

        self.stats.mark_dirty_count += 1;
    }

    /// 标记地址范围内的所有 cards 为 dirty
    pub fn markDirtyRange(self: *CardTable, start_addr: usize, end_addr: usize) void {
        var addr = start_addr;
        while (addr < end_addr) : (addr += CARD_SIZE) {
            self.markDirty(addr);
        }
    }

    /// 检查地址所在的 card 是否为 dirty
    pub fn isDirty(self: *const CardTable, addr: usize) bool {
        const card_index = self.getCardIndex(addr) orelse return false;
        const pos = getByteAndBit(card_index);
        const mask: u8 = @as(u8, 1) << pos.bit_idx;
        return (self.cards[pos.byte_idx] & mask) != 0;
    }

    /// 清除地址所在的 card
    pub fn clearCard(self: *CardTable, addr: usize) void {
        const card_index = self.getCardIndex(addr) orelse return;
        const pos = getByteAndBit(card_index);

        const mask: u8 = @as(u8, 1) << pos.bit_idx;
        if (self.cards[pos.byte_idx] & mask != 0) {
            self.cards[pos.byte_idx] &= ~mask;
            if (self.dirty_count > 0) {
                self.dirty_count -= 1;
            }
        }

        self.stats.clear_count += 1;
    }

    /// 清除所有 cards
    pub fn clearAll(self: *CardTable) void {
        @memset(self.cards, 0);
        self.dirty_count = 0;
        self.stats.clear_count += 1;
    }

    /// 迭代所有 dirty cards
    pub fn iterateDirtyCards(self: *CardTable) DirtyCardIterator {
        self.stats.scan_count += 1;
        return .{
            .card_table = self,
            .current_byte = 0,
            .current_bit = 0,
        };
    }

    pub const DirtyCardIterator = struct {
        card_table: *CardTable,
        current_byte: usize,
        current_bit: usize,

        /// 返回下一个 dirty card 覆盖的地址范围
        pub fn next(self: *DirtyCardIterator) ?AddressRange {
            while (self.current_byte < self.card_table.cards.len) {
                const byte = self.card_table.cards[self.current_byte];

                // 快速跳过全 0 字节
                if (byte == 0) {
                    self.current_byte += 1;
                    self.current_bit = 0;
                    continue;
                }

                // 检查当前位
                while (self.current_bit < CARDS_PER_BYTE) {
                    const bit_idx: u3 = @intCast(self.current_bit);
                    const mask: u8 = @as(u8, 1) << bit_idx;
                    if (byte & mask != 0) {
                        const card_index = self.current_byte * CARDS_PER_BYTE + self.current_bit;
                        self.current_bit += 1;
                        if (self.current_bit >= CARDS_PER_BYTE) {
                            self.current_byte += 1;
                            self.current_bit = 0;
                        }

                        self.card_table.stats.scanned_dirty_cards += 1;

                        const start = self.card_table.base_addr + card_index * CARD_SIZE;
                        return .{
                            .start = start,
                            .end = @min(start + CARD_SIZE, self.card_table.base_addr + self.card_table.covered_size),
                        };
                    }
                    self.current_bit += 1;
                }

                self.current_byte += 1;
                self.current_bit = 0;
            }

            return null;
        }
    };

    pub const AddressRange = struct {
        start: usize,
        end: usize,

        pub fn contains(self: AddressRange, addr: usize) bool {
            return addr >= self.start and addr < self.end;
        }

        pub fn size(self: AddressRange) usize {
            return self.end - self.start;
        }
    };

    /// 获取 dirty card 数量
    pub fn getDirtyCount(self: *const CardTable) usize {
        return self.dirty_count;
    }

    /// 获取统计信息
    pub fn getStats(self: *const CardTable) CardTableStats {
        return self.stats;
    }

    /// 获取覆盖率信息
    pub fn getCoverage(self: *const CardTable) Coverage {
        return .{
            .base_addr = self.base_addr,
            .covered_size = self.covered_size,
            .card_count = self.card_count,
            .dirty_count = self.dirty_count,
            .dirty_ratio = if (self.card_count > 0)
                @as(f64, @floatFromInt(self.dirty_count)) / @as(f64, @floatFromInt(self.card_count))
            else
                0.0,
        };
    }

    pub const Coverage = struct {
        base_addr: usize,
        covered_size: usize,
        card_count: usize,
        dirty_count: usize,
        dirty_ratio: f64,
    };
};

// ============================================================================
// Card Table 管理器 - 管理多个内存区域的 Card Tables
// ============================================================================

pub const CardTableManager = struct {
    allocator: std.mem.Allocator,
    tables: std.ArrayListUnmanaged(ManagedTable),

    const ManagedTable = struct {
        name: []const u8,
        table: CardTable,
    };

    pub fn init(allocator: std.mem.Allocator) CardTableManager {
        return .{
            .allocator = allocator,
            .tables = .{},
        };
    }

    pub fn deinit(self: *CardTableManager) void {
        for (self.tables.items) |*item| {
            item.table.deinit();
        }
        self.tables.deinit(self.allocator);
    }

    /// 为内存区域创建 Card Table
    pub fn createTable(self: *CardTableManager, name: []const u8, base_addr: usize, size: usize) !*CardTable {
        const table = try CardTable.init(self.allocator, base_addr, size);
        try self.tables.append(self.allocator, .{
            .name = name,
            .table = table,
        });
        return &self.tables.items[self.tables.items.len - 1].table;
    }

    /// 查找地址所属的 Card Table
    pub fn findTable(self: *CardTableManager, addr: usize) ?*CardTable {
        for (self.tables.items) |*item| {
            if (addr >= item.table.base_addr and
                addr < item.table.base_addr + item.table.covered_size)
            {
                return &item.table;
            }
        }
        return null;
    }

    /// 标记地址为 dirty（自动查找对应的 Card Table）
    pub fn markDirty(self: *CardTableManager, addr: usize) void {
        if (self.findTable(addr)) |table| {
            table.markDirty(addr);
        }
    }

    /// 清除所有 Card Tables
    pub fn clearAll(self: *CardTableManager) void {
        for (self.tables.items) |*item| {
            item.table.clearAll();
        }
    }

    /// 获取所有 dirty cards 的总数
    pub fn getTotalDirtyCount(self: *const CardTableManager) usize {
        var total: usize = 0;
        for (self.tables.items) |item| {
            total += item.table.dirty_count;
        }
        return total;
    }
};

// ============================================================================
// 写屏障集成辅助函数
// ============================================================================

/// 写屏障钩子 - 在指针写入时调用
pub fn writeBarrierHook(
    card_table: *CardTable,
    source_addr: usize,
    source_gen: u2, // 0=nursery, 1=survivor, 2=old, 3=large
    target_gen: u2,
) void {
    // 只有老年代/大对象空间写入年轻代引用时才标记
    if ((source_gen == 2 or source_gen == 3) and (target_gen == 0 or target_gen == 1)) {
        card_table.markDirty(source_addr);
    }
}

/// 批量写屏障 - 用于数组/对象批量更新
pub fn batchWriteBarrier(
    card_table: *CardTable,
    start_addr: usize,
    count: usize,
    element_size: usize,
) void {
    const end_addr = start_addr + count * element_size;
    card_table.markDirtyRange(start_addr, end_addr);
}

// ============================================================================
// 测试
// ============================================================================

test "card table basic operations" {
    var ct = try CardTable.init(std.testing.allocator, 0x1000, 0x10000);
    defer ct.deinit();

    // 初始状态应该是 clean
    try std.testing.expect(!ct.isDirty(0x1000));
    try std.testing.expect(ct.getDirtyCount() == 0);

    // 标记为 dirty
    ct.markDirty(0x1000);
    try std.testing.expect(ct.isDirty(0x1000));
    try std.testing.expect(ct.getDirtyCount() == 1);

    // 同一个 card 内的地址也应该是 dirty
    try std.testing.expect(ct.isDirty(0x1100)); // 0x1000 + 256 < 0x1000 + 512

    // 不同 card 应该是 clean
    try std.testing.expect(!ct.isDirty(0x1200)); // 0x1000 + 512

    // 清除
    ct.clearCard(0x1000);
    try std.testing.expect(!ct.isDirty(0x1000));
    try std.testing.expect(ct.getDirtyCount() == 0);
}

test "card table range marking" {
    var ct = try CardTable.init(std.testing.allocator, 0x1000, 0x10000);
    defer ct.deinit();

    // 标记范围
    ct.markDirtyRange(0x1000, 0x2000);

    // 检查范围内的 cards
    try std.testing.expect(ct.isDirty(0x1000));
    try std.testing.expect(ct.isDirty(0x1200));
    try std.testing.expect(ct.isDirty(0x1400));
    try std.testing.expect(ct.isDirty(0x1600));
    try std.testing.expect(ct.isDirty(0x1800));
    try std.testing.expect(ct.isDirty(0x1A00));
    try std.testing.expect(ct.isDirty(0x1C00));
    try std.testing.expect(ct.isDirty(0x1E00));

    // 范围外应该是 clean
    try std.testing.expect(!ct.isDirty(0x2000));
}

test "card table iterator" {
    var ct = try CardTable.init(std.testing.allocator, 0x1000, 0x10000);
    defer ct.deinit();

    // 标记几个不连续的 cards
    ct.markDirty(0x1000); // card 0
    ct.markDirty(0x2000); // card 8
    ct.markDirty(0x3000); // card 16

    // 迭代 dirty cards
    var iter = ct.iterateDirtyCards();
    var count: usize = 0;

    while (iter.next()) |range| {
        count += 1;
        try std.testing.expect(range.size() == CARD_SIZE);
    }

    try std.testing.expect(count == 3);
}

test "card table clear all" {
    var ct = try CardTable.init(std.testing.allocator, 0x1000, 0x10000);
    defer ct.deinit();

    // 标记多个 cards
    ct.markDirty(0x1000);
    ct.markDirty(0x2000);
    ct.markDirty(0x3000);
    try std.testing.expect(ct.getDirtyCount() == 3);

    // 清除所有
    ct.clearAll();
    try std.testing.expect(ct.getDirtyCount() == 0);
    try std.testing.expect(!ct.isDirty(0x1000));
    try std.testing.expect(!ct.isDirty(0x2000));
    try std.testing.expect(!ct.isDirty(0x3000));
}

test "card table manager" {
    var manager = CardTableManager.init(std.testing.allocator);
    defer manager.deinit();

    // 创建两个 card tables
    _ = try manager.createTable("heap1", 0x10000, 0x10000);
    _ = try manager.createTable("heap2", 0x30000, 0x10000);

    // 通过 manager 查找并标记
    if (manager.findTable(0x10000)) |table1| {
        table1.markDirty(0x10000);
    }
    if (manager.findTable(0x30000)) |table2| {
        table2.markDirty(0x30000);
    }

    // 通过 manager 查找
    try std.testing.expect(manager.findTable(0x10000) != null);
    try std.testing.expect(manager.findTable(0x30000) != null);
    try std.testing.expect(manager.findTable(0x50000) == null);

    // 总 dirty 数
    try std.testing.expect(manager.getTotalDirtyCount() == 2);

    // 清除所有
    manager.clearAll();
    try std.testing.expect(manager.getTotalDirtyCount() == 0);
}

test "write barrier hook" {
    var ct = try CardTable.init(std.testing.allocator, 0x1000, 0x10000);
    defer ct.deinit();

    // 老年代写入年轻代引用 - 应该标记
    writeBarrierHook(&ct, 0x1000, 2, 0);
    try std.testing.expect(ct.isDirty(0x1000));

    ct.clearAll();

    // 年轻代写入 - 不应该标记
    writeBarrierHook(&ct, 0x2000, 0, 0);
    try std.testing.expect(!ct.isDirty(0x2000));

    // 老年代写入老年代 - 不应该标记
    writeBarrierHook(&ct, 0x3000, 2, 2);
    try std.testing.expect(!ct.isDirty(0x3000));
}

test "card table coverage" {
    var ct = try CardTable.init(std.testing.allocator, 0x1000, 0x10000);
    defer ct.deinit();

    const coverage = ct.getCoverage();
    try std.testing.expect(coverage.base_addr == 0x1000);
    try std.testing.expect(coverage.covered_size == 0x10000);
    try std.testing.expect(coverage.dirty_ratio == 0.0);

    ct.markDirty(0x1000);
    const coverage2 = ct.getCoverage();
    try std.testing.expect(coverage2.dirty_count == 1);
    try std.testing.expect(coverage2.dirty_ratio > 0.0);
}
