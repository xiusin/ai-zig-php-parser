const std = @import("std");

pub const TypeSpecializer = struct {
    pub const Type = enum { int, float, string, array, object, bool, null_ };

    pub const TypeFeedback = struct {
        allocator: std.mem.Allocator,
        observed_types: std.ArrayList(Type),
        stability: f32,
        observation_count: u32,

        pub fn init(allocator: std.mem.Allocator) TypeFeedback {
            return .{
                .allocator = allocator,
                .observed_types = std.ArrayList(Type).initCapacity(allocator, 0) catch unreachable,
                .stability = 0.0,
                .observation_count = 0,
            };
        }

        pub fn deinit(self: *TypeFeedback) void {
            self.observed_types.deinit(self.allocator);
        }

        pub fn recordType(self: *TypeFeedback, type_: Type) !void {
            try self.observed_types.append(self.allocator, type_);
            self.observation_count += 1;
            self.updateStability();
        }

        fn updateStability(self: *TypeFeedback) void {
            if (self.observed_types.items.len == 0) {
                self.stability = 0.0;
                return;
            }

            var type_counts = std.EnumArray(Type, u32).initFill(0);
            for (self.observed_types.items) |t| {
                type_counts.set(t, type_counts.get(t) + 1);
            }

            var max_count: u32 = 0;
            for (type_counts.values) |count| {
                if (count > max_count) max_count = count;
            }

            self.stability = @as(f32, @floatFromInt(max_count)) /
                @as(f32, @floatFromInt(self.observed_types.items.len));
        }

        pub fn getDominantType(self: *TypeFeedback) ?Type {
            if (self.observed_types.items.len == 0) return null;

            var type_counts = std.EnumArray(Type, u32).initFill(0);
            for (self.observed_types.items) |t| {
                type_counts.set(t, type_counts.get(t) + 1);
            }

            var max_count: u32 = 0;
            var dominant_type: ?Type = null;

            var it = type_counts.iterator();
            while (it.next()) |entry| {
                if (entry.value.* > max_count) {
                    max_count = entry.value.*;
                    dominant_type = entry.key;
                }
            }

            return dominant_type;
        }
    };

    pub const SpecializedFunction = struct {
        original_name: []const u8,
        specialized_type: Type,
        code: []const u8,
    };

    allocator: std.mem.Allocator,
    specialized_functions: std.StringHashMap(std.ArrayList(SpecializedFunction)),

    pub fn init(allocator: std.mem.Allocator) TypeSpecializer {
        return .{
            .allocator = allocator,
            .specialized_functions = std.StringHashMap(std.ArrayList(SpecializedFunction)).init(allocator),
        };
    }

    pub fn deinit(self: *TypeSpecializer) void {
        var it = self.specialized_functions.valueIterator();
        while (it.next()) |list| {
            for (list.items) |spec| {
                self.allocator.free(spec.code);
            }
            list.deinit(self.allocator);
        }
        self.specialized_functions.deinit();
    }

    pub fn specialize(self: *TypeSpecializer, function_name: []const u8, feedback: *TypeFeedback) !?SpecializedFunction {
        if (feedback.stability < 0.95) return null;

        const dominant_type = feedback.getDominantType() orelse return null;
        const specialized_code = try self.generateSpecializedCode(function_name, dominant_type);

        const specialized_func = SpecializedFunction{
            .original_name = function_name,
            .specialized_type = dominant_type,
            .code = specialized_code,
        };

        const entry = try self.specialized_functions.getOrPut(function_name);
        if (!entry.found_existing) {
            entry.value_ptr.* = try std.ArrayList(SpecializedFunction).initCapacity(self.allocator, 0);
        }
        try entry.value_ptr.append(self.allocator, specialized_func);

        return specialized_func;
    }

    fn generateSpecializedCode(self: *TypeSpecializer, function_name: []const u8, type_: Type) ![]const u8 {
        return switch (type_) {
            .int => try std.fmt.allocPrint(self.allocator, "// Specialized for int\nfn {s}_int(x: i64) i64 {{ return x * 2; }}", .{function_name}),
            .float => try std.fmt.allocPrint(self.allocator, "// Specialized for float\nfn {s}_float(x: f64) f64 {{ return x * 2.0; }}", .{function_name}),
            .string => try std.fmt.allocPrint(self.allocator, "// Specialized for string\nfn {s}_string(x: []const u8) []const u8 {{ return x; }}", .{function_name}),
            else => try std.fmt.allocPrint(self.allocator, "// Generic version\nfn {s}_generic(x: anytype) anytype {{ return x; }}", .{function_name}),
        };
    }
};
