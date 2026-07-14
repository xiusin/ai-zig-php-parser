const std = @import("std");
const Allocator = std.mem.Allocator;

/// CoW 字符串
pub const CowString = struct {
    data: []const u8,
    ref_count: *std.atomic.Value(u32),
    allocator: Allocator,

    pub fn init(allocator: Allocator, str: []const u8) !CowString {
        const data = try allocator.dupe(u8, str);
        const ref_count = try allocator.create(std.atomic.Value(u32));
        ref_count.* = std.atomic.Value(u32).init(1);

        return CowString{
            .data = data,
            .ref_count = ref_count,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CowString) void {
        const count = self.ref_count.fetchSub(1, .monotonic);
        if (count == 1) {
            self.allocator.free(self.data);
            self.allocator.destroy(self.ref_count);
        }
    }

    /// 获取可写副本
    pub fn makeMutable(self: *CowString) ![]u8 {
        if (self.ref_count.load(.monotonic) > 1) {
            // 创建新副本
            const new_data = try self.allocator.dupe(u8, self.data);
            self.deinit();

            const ref_count = try self.allocator.create(std.atomic.Value(u32));
            ref_count.* = std.atomic.Value(u32).init(1);

            self.data = new_data;
            self.ref_count = ref_count;

            return @constCast(new_data);
        }
        return @constCast(self.data);
    }

    /// 共享只读数据
    pub fn share(self: *CowString) CowString {
        _ = self.ref_count.fetchAdd(1, .monotonic);
        return CowString{
            .data = self.data,
            .ref_count = self.ref_count,
            .allocator = self.allocator,
        };
    }
};

/// CoW 数组
pub const CowArray = struct {
    elements: []i32,
    ref_count: *std.atomic.Value(u32),
    allocator: Allocator,

    pub fn init(allocator: Allocator, arr: []const i32) !CowArray {
        const elements = try allocator.dupe(i32, arr);
        const ref_count = try allocator.create(std.atomic.Value(u32));
        ref_count.* = std.atomic.Value(u32).init(1);

        return CowArray{
            .elements = elements,
            .ref_count = ref_count,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CowArray) void {
        const count = self.ref_count.fetchSub(1, .monotonic);
        if (count == 1) {
            self.allocator.free(self.elements);
            self.allocator.destroy(self.ref_count);
        }
    }

    /// 获取可写副本
    pub fn makeMutable(self: *CowArray) ![]i32 {
        if (self.ref_count.load(.monotonic) > 1) {
            const new_elements = try self.allocator.dupe(i32, self.elements);
            self.deinit();

            const ref_count = try self.allocator.create(std.atomic.Value(u32));
            ref_count.* = std.atomic.Value(u32).init(1);

            self.elements = new_elements;
            self.ref_count = ref_count;
        }
        return self.elements;
    }

    /// 共享只读数据
    pub fn share(self: *CowArray) CowArray {
        _ = self.ref_count.fetchAdd(1, .monotonic);
        return CowArray{
            .elements = self.elements,
            .ref_count = self.ref_count,
            .allocator = self.allocator,
        };
    }
};
