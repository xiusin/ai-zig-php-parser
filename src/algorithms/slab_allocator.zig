const std = @import("std");
const Allocator = std.mem.Allocator;

/// Slab 分配器，用于固定大小对象
pub fn SlabAllocator(comptime T: type) type {
    return struct {
        const Self = @This();
        const slab_size = 64; // 每个 slab 包含 64 个对象

        pub const Slab = struct {
            objects: [slab_size]T,
            free_bitmap: u64, // 位图标记空闲对象
            next: ?*Slab,
        };

        head: ?*Slab,
        allocator: Allocator,

        pub fn init(allocator: Allocator) Self {
            return Self{
                .head = null,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            var current = self.head;
            while (current) |slab| {
                const next = slab.next;
                self.allocator.destroy(slab);
                current = next;
            }
        }

        pub fn alloc(self: *Self) !*T {
            // 查找有空闲对象的 slab
            var current = self.head;
            while (current) |slab| {
                if (slab.free_bitmap != 0) {
                    // 找到空闲位
                    const idx = @ctz(slab.free_bitmap);
                    slab.free_bitmap &= ~(@as(u64, 1) << @intCast(idx));
                    return &slab.objects[idx];
                }
                current = slab.next;
            }

            // 没有空闲对象，分配新 slab
            const new_slab = try self.allocator.create(Slab);
            new_slab.* = .{
                .objects = undefined,
                .free_bitmap = ~@as(u64, 0), // 全部标记为空闲
                .next = self.head,
            };
            self.head = new_slab;

            // 分配第一个对象
            new_slab.free_bitmap &= ~@as(u64, 1);
            return &new_slab.objects[0];
        }

        pub fn free(self: *Self, ptr: *T) void {
            // 查找对象所属的 slab
            var current = self.head;
            while (current) |slab| {
                const slab_start = @intFromPtr(&slab.objects[0]);
                const slab_end = slab_start + @sizeOf(T) * slab_size;
                const ptr_addr = @intFromPtr(ptr);

                if (ptr_addr >= slab_start and ptr_addr < slab_end) {
                    const idx = (ptr_addr - slab_start) / @sizeOf(T);
                    slab.free_bitmap |= @as(u64, 1) << @intCast(idx);
                    return;
                }

                current = slab.next;
            }
        }
    };
}
