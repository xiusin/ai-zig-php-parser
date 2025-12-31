//! AOT Runtime Library
//!
//! This module provides the runtime support for AOT-compiled PHP programs.
//! It includes:
//! - PHPValue: The dynamic PHP value type with tagged union representation
//! - Reference counting garbage collection
//! - Array operations
//! - String operations
//! - I/O functions
//! - Exception handling
//!
//! These functions are designed to be statically linked into the final executable.

const std = @import("std");
const Allocator = std.mem.Allocator;

// ============================================================================
// Global Allocator for Runtime
// ============================================================================

/// Thread-local allocator for runtime operations
/// In production, this would be initialized at program startup
var global_gpa: ?std.heap.GeneralPurposeAllocator(.{}) = null;

/// Get the global allocator for runtime operations
pub fn getGlobalAllocator() Allocator {
    if (global_gpa == null) {
        global_gpa = std.heap.GeneralPurposeAllocator(.{}){};
    }
    return global_gpa.?.allocator();
}

/// Initialize the runtime with a custom allocator (for testing)
pub fn initRuntime() void {
    if (global_gpa == null) {
        global_gpa = std.heap.GeneralPurposeAllocator(.{}){};
    }
}

/// Deinitialize the runtime and free all resources
pub fn deinitRuntime() void {
    if (global_gpa) |*gpa| {
        _ = gpa.deinit();
        global_gpa = null;
    }
}

// ============================================================================
// PHP Value Type System
// ============================================================================

/// Value type tag for PHPValue
pub const ValueTag = enum(u8) {
    null = 0,
    bool = 1,
    int = 2,
    float = 3,
    string = 4,
    array = 5,
    object = 6,
    resource = 7,
    callable = 8,

    /// Convert tag to PHP type name string
    pub fn toTypeName(self: ValueTag) []const u8 {
        return switch (self) {
            .null => "NULL",
            .bool => "boolean",
            .int => "integer",
            .float => "double",
            .string => "string",
            .array => "array",
            .object => "object",
            .resource => "resource",
            .callable => "callable",
        };
    }
};

/// Internal data union for PHPValue
pub const ValueData = extern union {
    bool_val: bool,
    int_val: i64,
    float_val: f64,
    string_ptr: ?*PHPString,
    array_ptr: ?*PHPArray,
    object_ptr: ?*PHPObject,
    resource_ptr: ?*anyopaque,
    callable_ptr: ?*PHPCallable,
};

/// The main PHP value type - a tagged union with reference counting
/// Memory layout: 24 bytes (tag: 1, padding: 3, ref_count: 4, data: 16)
pub const PHPValue = extern struct {
    /// Type tag
    tag: ValueTag,
    /// Padding for alignment
    _padding: [3]u8 = .{ 0, 0, 0 },
    /// Reference count for garbage collection
    ref_count: u32,
    /// Value data
    data: ValueData,

    const Self = @This();

    /// Check if this value is null
    pub fn isNull(self: *const Self) bool {
        return self.tag == .null;
    }

    /// Check if this value is truthy (PHP truthiness rules)
    pub fn isTruthy(self: *const Self) bool {
        return switch (self.tag) {
            .null => false,
            .bool => self.data.bool_val,
            .int => self.data.int_val != 0,
            .float => self.data.float_val != 0.0 and !std.math.isNan(self.data.float_val),
            .string => blk: {
                if (self.data.string_ptr) |str| {
                    // Empty string or "0" is falsy
                    if (str.length == 0) break :blk false;
                    if (str.length == 1 and str.data[0] == '0') break :blk false;
                    break :blk true;
                }
                break :blk false;
            },
            .array => blk: {
                if (self.data.array_ptr) |arr| {
                    break :blk arr.count() > 0;
                }
                break :blk false;
            },
            .object => self.data.object_ptr != null,
            .resource => self.data.resource_ptr != null,
            .callable => self.data.callable_ptr != null,
        };
    }

    /// Get the type name of this value
    pub fn getTypeName(self: *const Self) []const u8 {
        return self.tag.toTypeName();
    }

    /// Convert to integer (PHP type juggling)
    pub fn toInt(self: *const Self) i64 {
        return switch (self.tag) {
            .null => 0,
            .bool => if (self.data.bool_val) @as(i64, 1) else @as(i64, 0),
            .int => self.data.int_val,
            .float => @intFromFloat(self.data.float_val),
            .string => blk: {
                if (self.data.string_ptr) |str| {
                    break :blk parseIntFromString(str.getData()) catch 0;
                }
                break :blk 0;
            },
            .array => blk: {
                if (self.data.array_ptr) |arr| {
                    break :blk if (arr.count() > 0) @as(i64, 1) else @as(i64, 0);
                }
                break :blk 0;
            },
            .object => 1, // Objects convert to 1
            .resource => 1, // Resources convert to their ID (simplified to 1)
            .callable => 1,
        };
    }

    /// Convert to float (PHP type juggling)
    pub fn toFloat(self: *const Self) f64 {
        return switch (self.tag) {
            .null => 0.0,
            .bool => if (self.data.bool_val) @as(f64, 1.0) else @as(f64, 0.0),
            .int => @floatFromInt(self.data.int_val),
            .float => self.data.float_val,
            .string => blk: {
                if (self.data.string_ptr) |str| {
                    break :blk parseFloatFromString(str.getData()) catch 0.0;
                }
                break :blk 0.0;
            },
            .array => blk: {
                if (self.data.array_ptr) |arr| {
                    break :blk if (arr.count() > 0) @as(f64, 1.0) else @as(f64, 0.0);
                }
                break :blk 0.0;
            },
            .object => 1.0,
            .resource => 1.0,
            .callable => 1.0,
        };
    }

    /// Convert to boolean (PHP type juggling)
    pub fn toBool(self: *const Self) bool {
        return self.isTruthy();
    }
};

// ============================================================================
// PHP String Type
// ============================================================================

/// PHP String - reference counted, immutable string
pub const PHPString = struct {
    /// String data (not null-terminated internally, but we keep a null for C compat)
    data: [*]u8,
    /// String length (not including null terminator)
    length: usize,
    /// Capacity of allocated buffer
    capacity: usize,
    /// Reference count
    ref_count: u32,
    /// Hash cache (0 = not computed)
    hash: u32,

    const Self = @This();

    /// Create a new PHPString from a slice
    pub fn init(allocator: Allocator, str: []const u8) !*Self {
        const capacity = str.len + 1; // +1 for null terminator
        const data = try allocator.alloc(u8, capacity);
        @memcpy(data[0..str.len], str);
        data[str.len] = 0; // Null terminate for C compatibility

        const self = try allocator.create(Self);
        self.* = .{
            .data = data.ptr,
            .length = str.len,
            .capacity = capacity,
            .ref_count = 1,
            .hash = 0,
        };
        return self;
    }

    /// Create an empty string
    pub fn initEmpty(allocator: Allocator) !*Self {
        return init(allocator, "");
    }

    /// Deinitialize and free resources
    pub fn deinit(self: *Self, allocator: Allocator) void {
        if (self.capacity > 0) {
            allocator.free(self.data[0..self.capacity]);
        }
        allocator.destroy(self);
    }

    /// Get string data as a slice
    pub fn getData(self: *const Self) []const u8 {
        return self.data[0..self.length];
    }

    /// Get null-terminated C string
    pub fn getCString(self: *const Self) [*:0]const u8 {
        return @ptrCast(self.data);
    }

    /// Concatenate two strings
    pub fn concat(self: *const Self, other: *const Self, allocator: Allocator) !*Self {
        const new_len = self.length + other.length;
        const capacity = new_len + 1;
        const data = try allocator.alloc(u8, capacity);

        @memcpy(data[0..self.length], self.data[0..self.length]);
        @memcpy(data[self.length..new_len], other.data[0..other.length]);
        data[new_len] = 0;

        const result = try allocator.create(Self);
        result.* = .{
            .data = data.ptr,
            .length = new_len,
            .capacity = capacity,
            .ref_count = 1,
            .hash = 0,
        };
        return result;
    }

    /// Compute hash (FNV-1a)
    pub fn computeHash(self: *Self) u32 {
        if (self.hash != 0) return self.hash;

        var h: u32 = 2166136261;
        for (self.data[0..self.length]) |byte| {
            h ^= byte;
            h *%= 16777619;
        }
        self.hash = if (h == 0) 1 else h; // Avoid 0 as it means "not computed"
        return self.hash;
    }

    /// Check equality with another string
    pub fn eql(self: *const Self, other: *const Self) bool {
        if (self.length != other.length) return false;
        return std.mem.eql(u8, self.data[0..self.length], other.data[0..other.length]);
    }

    /// Compare with another string (for sorting)
    pub fn compare(self: *const Self, other: *const Self) std.math.Order {
        return std.mem.order(u8, self.data[0..self.length], other.data[0..other.length]);
    }
};

// ============================================================================
// PHP Array Type
// ============================================================================

/// Array key - can be integer or string
pub const ArrayKey = union(enum) {
    int: i64,
    string: *PHPString,

    pub fn eql(self: ArrayKey, other: ArrayKey) bool {
        return switch (self) {
            .int => |i| switch (other) {
                .int => |j| i == j,
                .string => false,
            },
            .string => |s| switch (other) {
                .int => false,
                .string => |t| s.eql(t),
            },
        };
    }

    pub fn hash(self: ArrayKey) u64 {
        return switch (self) {
            .int => |i| @bitCast(i),
            .string => |s| @as(u64, s.computeHash()),
        };
    }
};

/// PHP Array entry
pub const ArrayEntry = struct {
    key: ArrayKey,
    value: *PHPValue,
    /// For maintaining insertion order
    next_order: ?*ArrayEntry,
    prev_order: ?*ArrayEntry,
};

/// PHP Array - ordered hash map
pub const PHPArray = struct {
    allocator: Allocator,
    /// Hash buckets
    buckets: []?*ArrayEntry,
    /// Number of buckets
    bucket_count: usize,
    /// Number of entries
    entry_count: usize,
    /// First entry (for iteration order)
    first: ?*ArrayEntry,
    /// Last entry (for iteration order)
    last: ?*ArrayEntry,
    /// Next integer key for append operations
    next_int_key: i64,
    /// Reference count
    ref_count: u32,

    const Self = @This();
    const INITIAL_BUCKET_COUNT = 8;
    const LOAD_FACTOR = 0.75;

    /// Create a new empty array
    pub fn init(allocator: Allocator) !*Self {
        const buckets = try allocator.alloc(?*ArrayEntry, INITIAL_BUCKET_COUNT);
        @memset(buckets, null);

        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .buckets = buckets,
            .bucket_count = INITIAL_BUCKET_COUNT,
            .entry_count = 0,
            .first = null,
            .last = null,
            .next_int_key = 0,
            .ref_count = 1,
        };
        return self;
    }

    /// Deinitialize and free all resources
    pub fn deinit(self: *Self, allocator: Allocator) void {
        // Free all entries
        var entry = self.first;
        while (entry) |e| {
            const next = e.next_order;
            // Release the value
            php_gc_release(e.value);
            // Free string key if present
            if (e.key == .string) {
                e.key.string.ref_count -= 1;
                if (e.key.string.ref_count == 0) {
                    e.key.string.deinit(allocator);
                }
            }
            allocator.destroy(e);
            entry = next;
        }

        allocator.free(self.buckets);
        allocator.destroy(self);
    }

    /// Get number of elements
    pub fn count(self: *const Self) usize {
        return self.entry_count;
    }

    /// Find entry by key
    fn findEntry(self: *const Self, key: ArrayKey) ?*ArrayEntry {
        const bucket_idx = key.hash() % self.bucket_count;
        var entry = self.buckets[bucket_idx];
        while (entry) |e| {
            if (e.key.eql(key)) return e;
            // Linear probing within bucket (simplified - real impl would use chaining)
            entry = e.next_order;
            if (entry) |next| {
                const next_bucket = next.key.hash() % self.bucket_count;
                if (next_bucket != bucket_idx) break;
            }
        }
        return null;
    }

    /// Get value by key
    pub fn get(self: *const Self, key: ArrayKey) ?*PHPValue {
        if (self.findEntry(key)) |entry| {
            return entry.value;
        }
        return null;
    }

    /// Set value by key
    pub fn set(self: *Self, key: ArrayKey, value: *PHPValue) !void {
        // Check if key exists
        if (self.findEntry(key)) |entry| {
            // Release old value
            php_gc_release(entry.value);
            // Set new value
            entry.value = value;
            php_gc_retain(value);
            return;
        }

        // Check if we need to resize
        if (@as(f64, @floatFromInt(self.entry_count + 1)) > @as(f64, @floatFromInt(self.bucket_count)) * LOAD_FACTOR) {
            try self.resize();
        }

        // Create new entry
        const entry = try self.allocator.create(ArrayEntry);
        entry.* = .{
            .key = key,
            .value = value,
            .next_order = null,
            .prev_order = self.last,
        };

        // Retain the value
        php_gc_retain(value);

        // Retain string key if present
        if (key == .string) {
            key.string.ref_count += 1;
        }

        // Update order links
        if (self.last) |last| {
            last.next_order = entry;
        } else {
            self.first = entry;
        }
        self.last = entry;

        // Insert into bucket
        const bucket_idx = key.hash() % self.bucket_count;
        self.buckets[bucket_idx] = entry;

        self.entry_count += 1;

        // Update next_int_key if this is an integer key
        if (key == .int) {
            if (key.int >= self.next_int_key) {
                self.next_int_key = key.int + 1;
            }
        }
    }

    /// Push value (append with auto-incrementing integer key)
    pub fn push(self: *Self, value: *PHPValue) !void {
        const key = ArrayKey{ .int = self.next_int_key };
        try self.set(key, value);
    }

    /// Check if key exists
    pub fn keyExists(self: *const Self, key: ArrayKey) bool {
        return self.findEntry(key) != null;
    }

    /// Remove entry by key
    pub fn unset(self: *Self, key: ArrayKey) void {
        const bucket_idx = key.hash() % self.bucket_count;

        // Find and remove entry
        var entry = self.buckets[bucket_idx];
        var prev: ?*ArrayEntry = null;

        while (entry) |e| {
            if (e.key.eql(key)) {
                // Update bucket chain
                if (prev) |p| {
                    _ = p; // Simplified - would update chain
                }
                self.buckets[bucket_idx] = null;

                // Update order links
                if (e.prev_order) |p| {
                    p.next_order = e.next_order;
                } else {
                    self.first = e.next_order;
                }
                if (e.next_order) |n| {
                    n.prev_order = e.prev_order;
                } else {
                    self.last = e.prev_order;
                }

                // Release value
                php_gc_release(e.value);

                // Free string key if present
                if (e.key == .string) {
                    e.key.string.ref_count -= 1;
                    if (e.key.string.ref_count == 0) {
                        e.key.string.deinit(self.allocator);
                    }
                }

                self.allocator.destroy(e);
                self.entry_count -= 1;
                return;
            }
            prev = e;
            entry = e.next_order;
        }
    }

    /// Resize the hash table
    fn resize(self: *Self) !void {
        const new_bucket_count = self.bucket_count * 2;
        const new_buckets = try self.allocator.alloc(?*ArrayEntry, new_bucket_count);
        @memset(new_buckets, null);

        // Rehash all entries
        var entry = self.first;
        while (entry) |e| {
            const bucket_idx = e.key.hash() % new_bucket_count;
            new_buckets[bucket_idx] = e;
            entry = e.next_order;
        }

        self.allocator.free(self.buckets);
        self.buckets = new_buckets;
        self.bucket_count = new_bucket_count;
    }
};

// ============================================================================
// PHP Object Type
// ============================================================================

/// PHP Object
pub const PHPObject = struct {
    allocator: Allocator,
    /// Class name
    class_name: []const u8,
    /// Properties (stored as array)
    properties: *PHPArray,
    /// Reference count
    ref_count: u32,

    const Self = @This();

    /// Create a new object
    pub fn init(allocator: Allocator, class_name: []const u8) !*Self {
        const properties = try PHPArray.init(allocator);

        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .class_name = class_name,
            .properties = properties,
            .ref_count = 1,
        };
        return self;
    }

    /// Deinitialize and free resources
    pub fn deinit(self: *Self, allocator: Allocator) void {
        self.properties.deinit(allocator);
        allocator.destroy(self);
    }

    /// Get property value
    pub fn getProperty(self: *const Self, name: *PHPString) ?*PHPValue {
        return self.properties.get(.{ .string = name });
    }

    /// Set property value
    pub fn setProperty(self: *Self, name: *PHPString, value: *PHPValue) !void {
        try self.properties.set(.{ .string = name }, value);
    }
};

/// PHP Callable (function reference)
pub const PHPCallable = struct {
    /// Function name or closure
    name: ?[]const u8,
    /// Object for method calls
    object: ?*PHPObject,
    /// Method name for method calls
    method: ?[]const u8,
    /// Reference count
    ref_count: u32,

    const Self = @This();

    pub fn init(allocator: Allocator, name: []const u8) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .name = name,
            .object = null,
            .method = null,
            .ref_count = 1,
        };
        return self;
    }

    pub fn deinit(self: *Self, allocator: Allocator) void {
        allocator.destroy(self);
    }
};


// ============================================================================
// Value Creation Functions
// ============================================================================

/// Create a null value
pub fn php_value_create_null() *PHPValue {
    const allocator = getGlobalAllocator();
    const val = allocator.create(PHPValue) catch return null_sentinel;
    val.* = .{
        .tag = .null,
        .ref_count = 1,
        .data = .{ .int_val = 0 },
    };
    return val;
}

/// Create a boolean value
pub fn php_value_create_bool(b: bool) *PHPValue {
    const allocator = getGlobalAllocator();
    const val = allocator.create(PHPValue) catch return null_sentinel;
    val.* = .{
        .tag = .bool,
        .ref_count = 1,
        .data = .{ .bool_val = b },
    };
    return val;
}

/// Create an integer value
pub fn php_value_create_int(i: i64) *PHPValue {
    const allocator = getGlobalAllocator();
    const val = allocator.create(PHPValue) catch return null_sentinel;
    val.* = .{
        .tag = .int,
        .ref_count = 1,
        .data = .{ .int_val = i },
    };
    return val;
}

/// Create a float value
pub fn php_value_create_float(f: f64) *PHPValue {
    const allocator = getGlobalAllocator();
    const val = allocator.create(PHPValue) catch return null_sentinel;
    val.* = .{
        .tag = .float,
        .ref_count = 1,
        .data = .{ .float_val = f },
    };
    return val;
}

/// Create a string value from a slice
pub fn php_value_create_string(data: []const u8) *PHPValue {
    const allocator = getGlobalAllocator();
    const str = PHPString.init(allocator, data) catch return null_sentinel;
    const val = allocator.create(PHPValue) catch {
        str.deinit(allocator);
        return null_sentinel;
    };
    val.* = .{
        .tag = .string,
        .ref_count = 1,
        .data = .{ .string_ptr = str },
    };
    return val;
}

/// Create a string value from a C string pointer and length
pub fn php_value_create_string_raw(data: [*]const u8, len: usize) *PHPValue {
    return php_value_create_string(data[0..len]);
}

/// Create an empty array value
pub fn php_value_create_array() *PHPValue {
    const allocator = getGlobalAllocator();
    const arr = PHPArray.init(allocator) catch return null_sentinel;
    const val = allocator.create(PHPValue) catch {
        arr.deinit(allocator);
        return null_sentinel;
    };
    val.* = .{
        .tag = .array,
        .ref_count = 1,
        .data = .{ .array_ptr = arr },
    };
    return val;
}

/// Create an object value
pub fn php_value_create_object(class_name: []const u8) *PHPValue {
    const allocator = getGlobalAllocator();
    const obj = PHPObject.init(allocator, class_name) catch return null_sentinel;
    const val = allocator.create(PHPValue) catch {
        obj.deinit(allocator);
        return null_sentinel;
    };
    val.* = .{
        .tag = .object,
        .ref_count = 1,
        .data = .{ .object_ptr = obj },
    };
    return val;
}

// ============================================================================
// Type Conversion Functions
// ============================================================================

/// Get the type tag of a value
pub fn php_value_get_type(val: *const PHPValue) u8 {
    return @intFromEnum(val.tag);
}

/// Get the type name of a value
pub fn php_value_get_type_name(val: *const PHPValue) []const u8 {
    return val.getTypeName();
}

/// Convert value to integer
pub fn php_value_to_int(val: *const PHPValue) i64 {
    return val.toInt();
}

/// Convert value to float
pub fn php_value_to_float(val: *const PHPValue) f64 {
    return val.toFloat();
}

/// Convert value to boolean
pub fn php_value_to_bool(val: *const PHPValue) bool {
    return val.toBool();
}

/// Convert value to string (returns a new PHPValue)
pub fn php_value_to_string(val: *const PHPValue) *PHPValue {
    const allocator = getGlobalAllocator();

    switch (val.tag) {
        .null => return php_value_create_string(""),
        .bool => return php_value_create_string(if (val.data.bool_val) "1" else ""),
        .int => {
            var buf: [32]u8 = undefined;
            const result = std.fmt.bufPrint(&buf, "{d}", .{val.data.int_val}) catch return php_value_create_string("0");
            return php_value_create_string(result);
        },
        .float => {
            var buf: [64]u8 = undefined;
            const result = std.fmt.bufPrint(&buf, "{d}", .{val.data.float_val}) catch return php_value_create_string("0");
            return php_value_create_string(result);
        },
        .string => {
            // Return a copy with incremented ref count
            if (val.data.string_ptr) |str| {
                const new_val = allocator.create(PHPValue) catch return null_sentinel;
                new_val.* = .{
                    .tag = .string,
                    .ref_count = 1,
                    .data = .{ .string_ptr = str },
                };
                str.ref_count += 1;
                return new_val;
            }
            return php_value_create_string("");
        },
        .array => return php_value_create_string("Array"),
        .object => {
            // In real PHP, this would call __toString() if defined
            if (val.data.object_ptr) |obj| {
                var buf: [256]u8 = undefined;
                const result = std.fmt.bufPrint(&buf, "Object({s})", .{obj.class_name}) catch return php_value_create_string("Object");
                return php_value_create_string(result);
            }
            return php_value_create_string("Object");
        },
        .resource => return php_value_create_string("Resource"),
        .callable => return php_value_create_string("Callable"),
    }
}

/// Cast value to a specific type (PHP-style type juggling)
pub fn php_value_cast(val: *const PHPValue, target_type: ValueTag) *PHPValue {
    return switch (target_type) {
        .null => php_value_create_null(),
        .bool => php_value_create_bool(val.toBool()),
        .int => php_value_create_int(val.toInt()),
        .float => php_value_create_float(val.toFloat()),
        .string => php_value_to_string(val),
        .array => blk: {
            // Casting to array wraps the value
            const arr = php_value_create_array();
            if (arr.data.array_ptr) |array| {
                // For non-null values, create array with single element
                if (val.tag != .null) {
                    const val_copy = php_value_clone(val);
                    array.push(val_copy) catch {};
                }
            }
            break :blk arr;
        },
        .object => blk: {
            // Casting to object creates stdClass
            const obj = php_value_create_object("stdClass");
            if (obj.data.object_ptr) |object| {
                // For arrays, convert to object properties
                if (val.tag == .array) {
                    if (val.data.array_ptr) |arr| {
                        var entry = arr.first;
                        while (entry) |e| {
                            if (e.key == .string) {
                                object.setProperty(e.key.string, e.value) catch {};
                            }
                            entry = e.next_order;
                        }
                    }
                }
            }
            break :blk obj;
        },
        .resource, .callable => php_value_create_null(), // Cannot cast to these
    };
}

/// Clone a value (deep copy for complex types)
pub fn php_value_clone(val: *const PHPValue) *PHPValue {
    const allocator = getGlobalAllocator();

    switch (val.tag) {
        .null, .bool, .int, .float => {
            // Simple types - create new value
            const new_val = allocator.create(PHPValue) catch return null_sentinel;
            new_val.* = val.*;
            new_val.ref_count = 1;
            return new_val;
        },
        .string => {
            // Strings are immutable, so we can share with ref count
            if (val.data.string_ptr) |str| {
                str.ref_count += 1;
                const new_val = allocator.create(PHPValue) catch return null_sentinel;
                new_val.* = val.*;
                new_val.ref_count = 1;
                return new_val;
            }
            return php_value_create_string("");
        },
        .array => {
            // Deep copy array
            const new_arr = php_value_create_array();
            if (val.data.array_ptr) |arr| {
                if (new_arr.data.array_ptr) |new_array| {
                    var entry = arr.first;
                    while (entry) |e| {
                        const cloned_val = php_value_clone(e.value);
                        new_array.set(e.key, cloned_val) catch {};
                        entry = e.next_order;
                    }
                }
            }
            return new_arr;
        },
        .object => {
            // Clone object
            if (val.data.object_ptr) |obj| {
                const new_obj = php_value_create_object(obj.class_name);
                if (new_obj.data.object_ptr) |new_object| {
                    // Clone properties
                    var entry = obj.properties.first;
                    while (entry) |e| {
                        if (e.key == .string) {
                            const cloned_val = php_value_clone(e.value);
                            new_object.setProperty(e.key.string, cloned_val) catch {};
                        }
                        entry = e.next_order;
                    }
                }
                return new_obj;
            }
            return php_value_create_null();
        },
        .resource, .callable => {
            // Resources and callables cannot be cloned
            return php_value_create_null();
        },
    }
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Parse integer from string (PHP-style)
fn parseIntFromString(str: []const u8) !i64 {
    if (str.len == 0) return 0;

    // Skip leading whitespace
    var start: usize = 0;
    while (start < str.len and (str[start] == ' ' or str[start] == '\t' or str[start] == '\n' or str[start] == '\r')) {
        start += 1;
    }
    if (start >= str.len) return 0;

    // Check for sign
    var negative = false;
    if (str[start] == '-') {
        negative = true;
        start += 1;
    } else if (str[start] == '+') {
        start += 1;
    }

    // Parse digits
    var result: i64 = 0;
    var has_digits = false;
    while (start < str.len) {
        const c = str[start];
        if (c >= '0' and c <= '9') {
            result = result * 10 + @as(i64, c - '0');
            has_digits = true;
            start += 1;
        } else {
            break;
        }
    }

    if (!has_digits) return 0;
    return if (negative) -result else result;
}

/// Parse float from string (PHP-style)
fn parseFloatFromString(str: []const u8) !f64 {
    if (str.len == 0) return 0.0;

    // Use std.fmt.parseFloat for simplicity
    return std.fmt.parseFloat(f64, str) catch 0.0;
}

/// Undefined value sentinel (for error cases)
var null_sentinel_value: PHPValue = .{
    .tag = .null,
    .ref_count = 1,
    .data = .{ .int_val = 0 },
};

const null_sentinel = &null_sentinel_value;


// ============================================================================
// Reference Counting Garbage Collection
// ============================================================================

/// Increment reference count
pub fn php_gc_retain(val: *PHPValue) void {
    if (val == null_sentinel) return;
    val.ref_count += 1;
}

/// Decrement reference count and free if zero
pub fn php_gc_release(val: *PHPValue) void {
    if (val == null_sentinel) return;
    if (val.ref_count == 0) return; // Already freed or static

    val.ref_count -= 1;
    if (val.ref_count == 0) {
        php_gc_free_value(val);
    }
}

/// Free a value and its internal data
fn php_gc_free_value(val: *PHPValue) void {
    const allocator = getGlobalAllocator();

    // Free internal data based on type
    switch (val.tag) {
        .string => {
            if (val.data.string_ptr) |str| {
                str.ref_count -= 1;
                if (str.ref_count == 0) {
                    str.deinit(allocator);
                }
            }
        },
        .array => {
            if (val.data.array_ptr) |arr| {
                arr.ref_count -= 1;
                if (arr.ref_count == 0) {
                    arr.deinit(allocator);
                }
            }
        },
        .object => {
            if (val.data.object_ptr) |obj| {
                obj.ref_count -= 1;
                if (obj.ref_count == 0) {
                    obj.deinit(allocator);
                }
            }
        },
        .callable => {
            if (val.data.callable_ptr) |callable| {
                callable.ref_count -= 1;
                if (callable.ref_count == 0) {
                    callable.deinit(allocator);
                }
            }
        },
        // Simple types have no internal data to free
        .null, .bool, .int, .float, .resource => {},
    }

    // Free the value itself
    allocator.destroy(val);
}

/// Get current reference count (for debugging/testing)
pub fn php_gc_get_ref_count(val: *const PHPValue) u32 {
    return val.ref_count;
}

/// Check if value is shared (ref_count > 1)
pub fn php_gc_is_shared(val: *const PHPValue) bool {
    return val.ref_count > 1;
}

/// Copy-on-write: ensure value is not shared before modification
/// Returns a new value if shared, or the same value if not
pub fn php_gc_copy_on_write(val: *PHPValue) *PHPValue {
    if (val.ref_count <= 1) {
        return val;
    }

    // Value is shared, need to make a copy
    const copy = php_value_clone(val);
    php_gc_release(val);
    return copy;
}


// ============================================================================
// Array Runtime Operations
// ============================================================================

/// Create a new empty array
pub fn php_array_create() *PHPArray {
    const allocator = getGlobalAllocator();
    return PHPArray.init(allocator) catch {
        // Return a static empty array on failure
        return null_array;
    };
}

/// Create a new array with initial capacity
pub fn php_array_create_with_capacity(capacity: usize) *PHPArray {
    const allocator = getGlobalAllocator();
    const arr = PHPArray.init(allocator) catch return null_array;
    // Pre-allocate buckets if needed
    if (capacity > PHPArray.INITIAL_BUCKET_COUNT) {
        arr.resize() catch {};
    }
    return arr;
}

/// Get array element by integer key
pub fn php_array_get_int(arr: *PHPArray, key: i64) *PHPValue {
    if (arr.get(.{ .int = key })) |val| {
        php_gc_retain(val);
        return val;
    }
    return php_value_create_null();
}

/// Get array element by string key
pub fn php_array_get_string(arr: *PHPArray, key: *PHPString) *PHPValue {
    if (arr.get(.{ .string = key })) |val| {
        php_gc_retain(val);
        return val;
    }
    return php_value_create_null();
}

/// Get array element by PHPValue key
pub fn php_array_get(arr: *PHPArray, key: *PHPValue) *PHPValue {
    const array_key = valueToArrayKey(key);
    if (arr.get(array_key)) |val| {
        php_gc_retain(val);
        return val;
    }
    return php_value_create_null();
}

/// Set array element by integer key
pub fn php_array_set_int(arr: *PHPArray, key: i64, value: *PHPValue) void {
    arr.set(.{ .int = key }, value) catch {};
}

/// Set array element by string key
pub fn php_array_set_string(arr: *PHPArray, key: *PHPString, value: *PHPValue) void {
    arr.set(.{ .string = key }, value) catch {};
}

/// Set array element by PHPValue key
pub fn php_array_set(arr: *PHPArray, key: *PHPValue, value: *PHPValue) void {
    const array_key = valueToArrayKey(key);
    arr.set(array_key, value) catch {};
}

/// Push value to array (append)
pub fn php_array_push(arr: *PHPArray, value: *PHPValue) void {
    arr.push(value) catch {};
}

/// Get array count
pub fn php_array_count(arr: *PHPArray) i64 {
    return @intCast(arr.count());
}

/// Check if key exists in array
pub fn php_array_key_exists(arr: *PHPArray, key: *PHPValue) bool {
    const array_key = valueToArrayKey(key);
    return arr.keyExists(array_key);
}

/// Check if key exists (integer key)
pub fn php_array_key_exists_int(arr: *PHPArray, key: i64) bool {
    return arr.keyExists(.{ .int = key });
}

/// Check if key exists (string key)
pub fn php_array_key_exists_string(arr: *PHPArray, key: *PHPString) bool {
    return arr.keyExists(.{ .string = key });
}

/// Unset array element
pub fn php_array_unset(arr: *PHPArray, key: *PHPValue) void {
    const array_key = valueToArrayKey(key);
    arr.unset(array_key);
}

/// Unset array element by integer key
pub fn php_array_unset_int(arr: *PHPArray, key: i64) void {
    arr.unset(.{ .int = key });
}

/// Unset array element by string key
pub fn php_array_unset_string(arr: *PHPArray, key: *PHPString) void {
    arr.unset(.{ .string = key });
}

/// Get array keys as a new array
pub fn php_array_keys(arr: *PHPArray) *PHPValue {
    const result = php_value_create_array();
    if (result.data.array_ptr) |result_arr| {
        var entry = arr.first;
        while (entry) |e| {
            const key_val = switch (e.key) {
                .int => |i| php_value_create_int(i),
                .string => |s| blk: {
                    s.ref_count += 1;
                    const val = php_value_create_string(s.getData());
                    break :blk val;
                },
            };
            result_arr.push(key_val) catch {};
            entry = e.next_order;
        }
    }
    return result;
}

/// Get array values as a new array (re-indexed)
pub fn php_array_values(arr: *PHPArray) *PHPValue {
    const result = php_value_create_array();
    if (result.data.array_ptr) |result_arr| {
        var entry = arr.first;
        while (entry) |e| {
            php_gc_retain(e.value);
            result_arr.push(e.value) catch {};
            entry = e.next_order;
        }
    }
    return result;
}

/// Merge two arrays
pub fn php_array_merge(arr1: *PHPArray, arr2: *PHPArray) *PHPValue {
    const result = php_value_create_array();
    if (result.data.array_ptr) |result_arr| {
        // Copy arr1 (re-index integer keys)
        var entry = arr1.first;
        while (entry) |e| {
            php_gc_retain(e.value);
            switch (e.key) {
                .int => result_arr.push(e.value) catch {},
                .string => |s| result_arr.set(.{ .string = s }, e.value) catch {},
            }
            entry = e.next_order;
        }

        // Copy arr2 (re-index integer keys, overwrite string keys)
        entry = arr2.first;
        while (entry) |e| {
            php_gc_retain(e.value);
            switch (e.key) {
                .int => result_arr.push(e.value) catch {},
                .string => |s| result_arr.set(.{ .string = s }, e.value) catch {},
            }
            entry = e.next_order;
        }
    }
    return result;
}

/// Check if array is empty
pub fn php_array_is_empty(arr: *PHPArray) bool {
    return arr.count() == 0;
}

/// Get first element of array
pub fn php_array_first(arr: *PHPArray) *PHPValue {
    if (arr.first) |entry| {
        php_gc_retain(entry.value);
        return entry.value;
    }
    return php_value_create_null();
}

/// Get last element of array
pub fn php_array_last(arr: *PHPArray) *PHPValue {
    if (arr.last) |entry| {
        php_gc_retain(entry.value);
        return entry.value;
    }
    return php_value_create_null();
}

/// Convert PHPValue to ArrayKey
fn valueToArrayKey(val: *PHPValue) ArrayKey {
    return switch (val.tag) {
        .int => .{ .int = val.data.int_val },
        .float => .{ .int = @intFromFloat(val.data.float_val) },
        .bool => .{ .int = if (val.data.bool_val) 1 else 0 },
        .null => .{ .int = 0 },
        .string => blk: {
            if (val.data.string_ptr) |str| {
                // Try to parse as integer
                const int_val = parseIntFromString(str.getData()) catch {
                    break :blk ArrayKey{ .string = str };
                };
                // Check if the entire string is a valid integer
                var buf: [32]u8 = undefined;
                const result = std.fmt.bufPrint(&buf, "{d}", .{int_val}) catch {
                    break :blk ArrayKey{ .string = str };
                };
                if (result.len == str.length and std.mem.eql(u8, result, str.getData())) {
                    break :blk ArrayKey{ .int = int_val };
                }
                break :blk ArrayKey{ .string = str };
            }
            break :blk ArrayKey{ .int = 0 };
        },
        else => .{ .int = 0 },
    };
}

/// Static null array for error cases
var null_array_storage: PHPArray = .{
    .allocator = std.heap.page_allocator,
    .buckets = &[_]?*ArrayEntry{},
    .bucket_count = 0,
    .entry_count = 0,
    .first = null,
    .last = null,
    .next_int_key = 0,
    .ref_count = 1,
};
var null_array: *PHPArray = &null_array_storage;


// ============================================================================
// String Runtime Operations
// ============================================================================

/// Concatenate two values as strings
pub fn php_string_concat(a: *PHPValue, b: *PHPValue) *PHPValue {
    const allocator = getGlobalAllocator();

    // Convert both values to strings
    const str_a = php_value_to_string(a);
    defer php_gc_release(str_a);
    const str_b = php_value_to_string(b);
    defer php_gc_release(str_b);

    // Get string pointers
    const ptr_a = str_a.data.string_ptr orelse return php_value_create_string("");
    const ptr_b = str_b.data.string_ptr orelse return php_value_clone(str_a);

    // Concatenate
    const result_str = ptr_a.concat(ptr_b, allocator) catch return php_value_create_string("");

    const result = allocator.create(PHPValue) catch {
        result_str.deinit(allocator);
        return null_sentinel;
    };
    result.* = .{
        .tag = .string,
        .ref_count = 1,
        .data = .{ .string_ptr = result_str },
    };
    return result;
}

/// Get string length
pub fn php_string_length(val: *PHPValue) i64 {
    if (val.tag != .string) return 0;
    if (val.data.string_ptr) |str| {
        return @intCast(str.length);
    }
    return 0;
}

/// Get string length from PHPString
pub fn php_string_len(str: *PHPString) i64 {
    return @intCast(str.length);
}

/// String interpolation - concatenate multiple parts
pub fn php_string_interpolate(parts: []const *PHPValue) *PHPValue {
    if (parts.len == 0) return php_value_create_string("");
    if (parts.len == 1) return php_value_to_string(parts[0]);

    const allocator = getGlobalAllocator();

    // Calculate total length
    var total_len: usize = 0;
    for (parts) |part| {
        const str_part = php_value_to_string(part);
        defer php_gc_release(str_part);
        if (str_part.data.string_ptr) |str| {
            total_len += str.length;
        }
    }

    // Allocate result buffer
    const capacity = total_len + 1;
    const data = allocator.alloc(u8, capacity) catch return php_value_create_string("");

    // Copy parts
    var offset: usize = 0;
    for (parts) |part| {
        const str_part = php_value_to_string(part);
        defer php_gc_release(str_part);
        if (str_part.data.string_ptr) |str| {
            @memcpy(data[offset .. offset + str.length], str.data[0..str.length]);
            offset += str.length;
        }
    }
    data[total_len] = 0;

    // Create result string
    const result_str = allocator.create(PHPString) catch {
        allocator.free(data);
        return php_value_create_string("");
    };
    result_str.* = .{
        .data = data.ptr,
        .length = total_len,
        .capacity = capacity,
        .ref_count = 1,
        .hash = 0,
    };

    const result = allocator.create(PHPValue) catch {
        result_str.deinit(allocator);
        return null_sentinel;
    };
    result.* = .{
        .tag = .string,
        .ref_count = 1,
        .data = .{ .string_ptr = result_str },
    };
    return result;
}

/// Get substring
pub fn php_string_substr(val: *PHPValue, start: i64, length: ?i64) *PHPValue {
    if (val.tag != .string) return php_value_create_string("");
    const str = val.data.string_ptr orelse return php_value_create_string("");

    const str_len: i64 = @intCast(str.length);

    // Handle negative start
    var actual_start: i64 = start;
    if (actual_start < 0) {
        actual_start = str_len + actual_start;
        if (actual_start < 0) actual_start = 0;
    }
    if (actual_start >= str_len) return php_value_create_string("");

    // Handle length
    var actual_len: i64 = undefined;
    if (length) |len| {
        if (len < 0) {
            actual_len = str_len - actual_start + len;
        } else {
            actual_len = len;
        }
    } else {
        actual_len = str_len - actual_start;
    }

    if (actual_len <= 0) return php_value_create_string("");

    // Clamp to string bounds
    const ustart: usize = @intCast(actual_start);
    var ulen: usize = @intCast(actual_len);
    if (ustart + ulen > str.length) {
        ulen = str.length - ustart;
    }

    return php_value_create_string(str.data[ustart .. ustart + ulen]);
}

/// Find position of substring
pub fn php_string_strpos(haystack: *PHPValue, needle: *PHPValue, offset: i64) *PHPValue {
    if (haystack.tag != .string) return php_value_create_bool(false);
    const hay_str = haystack.data.string_ptr orelse return php_value_create_bool(false);

    // Convert needle to string
    const needle_str_val = php_value_to_string(needle);
    defer php_gc_release(needle_str_val);
    const needle_str = needle_str_val.data.string_ptr orelse return php_value_create_bool(false);

    if (needle_str.length == 0) return php_value_create_bool(false);

    // Handle offset
    var search_start: usize = 0;
    if (offset > 0) {
        search_start = @intCast(offset);
        if (search_start >= hay_str.length) return php_value_create_bool(false);
    }

    // Search for needle
    const hay_data = hay_str.data[search_start..hay_str.length];
    const needle_data = needle_str.data[0..needle_str.length];

    if (std.mem.indexOf(u8, hay_data, needle_data)) |pos| {
        return php_value_create_int(@intCast(search_start + pos));
    }

    return php_value_create_bool(false);
}

/// Convert string to uppercase
pub fn php_string_strtoupper(val: *PHPValue) *PHPValue {
    if (val.tag != .string) return php_value_to_string(val);
    const str = val.data.string_ptr orelse return php_value_create_string("");

    const allocator = getGlobalAllocator();
    const data = allocator.alloc(u8, str.length + 1) catch return php_value_create_string("");

    for (str.data[0..str.length], 0..) |c, i| {
        data[i] = std.ascii.toUpper(c);
    }
    data[str.length] = 0;

    const result_str = allocator.create(PHPString) catch {
        allocator.free(data);
        return php_value_create_string("");
    };
    result_str.* = .{
        .data = data.ptr,
        .length = str.length,
        .capacity = str.length + 1,
        .ref_count = 1,
        .hash = 0,
    };

    const result = allocator.create(PHPValue) catch {
        result_str.deinit(allocator);
        return null_sentinel;
    };
    result.* = .{
        .tag = .string,
        .ref_count = 1,
        .data = .{ .string_ptr = result_str },
    };
    return result;
}

/// Convert string to lowercase
pub fn php_string_strtolower(val: *PHPValue) *PHPValue {
    if (val.tag != .string) return php_value_to_string(val);
    const str = val.data.string_ptr orelse return php_value_create_string("");

    const allocator = getGlobalAllocator();
    const data = allocator.alloc(u8, str.length + 1) catch return php_value_create_string("");

    for (str.data[0..str.length], 0..) |c, i| {
        data[i] = std.ascii.toLower(c);
    }
    data[str.length] = 0;

    const result_str = allocator.create(PHPString) catch {
        allocator.free(data);
        return php_value_create_string("");
    };
    result_str.* = .{
        .data = data.ptr,
        .length = str.length,
        .capacity = str.length + 1,
        .ref_count = 1,
        .hash = 0,
    };

    const result = allocator.create(PHPValue) catch {
        result_str.deinit(allocator);
        return null_sentinel;
    };
    result.* = .{
        .tag = .string,
        .ref_count = 1,
        .data = .{ .string_ptr = result_str },
    };
    return result;
}

/// Trim whitespace from string
pub fn php_string_trim(val: *PHPValue) *PHPValue {
    if (val.tag != .string) return php_value_to_string(val);
    const str = val.data.string_ptr orelse return php_value_create_string("");

    const data = str.data[0..str.length];
    const trimmed = std.mem.trim(u8, data, " \t\n\r\x00\x0b");

    return php_value_create_string(trimmed);
}

/// Replace occurrences in string
pub fn php_string_str_replace(search: *PHPValue, replace: *PHPValue, subject: *PHPValue) *PHPValue {
    if (subject.tag != .string) return php_value_to_string(subject);
    const subj_str = subject.data.string_ptr orelse return php_value_create_string("");

    const search_val = php_value_to_string(search);
    defer php_gc_release(search_val);
    const search_str = search_val.data.string_ptr orelse return php_value_clone(subject);

    const replace_val = php_value_to_string(replace);
    defer php_gc_release(replace_val);
    const replace_str = replace_val.data.string_ptr orelse return php_value_clone(subject);

    if (search_str.length == 0) return php_value_clone(subject);

    const allocator = getGlobalAllocator();

    // Simple implementation: find and replace all occurrences
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    const subj_data = subj_str.data[0..subj_str.length];
    const search_data = search_str.data[0..search_str.length];
    const replace_data = replace_str.data[0..replace_str.length];

    var i: usize = 0;
    while (i < subj_str.length) {
        if (i + search_str.length <= subj_str.length and
            std.mem.eql(u8, subj_data[i .. i + search_str.length], search_data))
        {
            result.appendSlice(replace_data) catch return php_value_clone(subject);
            i += search_str.length;
        } else {
            result.append(subj_data[i]) catch return php_value_clone(subject);
            i += 1;
        }
    }

    return php_value_create_string(result.items);
}

/// Split string by delimiter
pub fn php_string_explode(delimiter: *PHPValue, string: *PHPValue) *PHPValue {
    const result = php_value_create_array();
    if (result.data.array_ptr == null) return result;
    const arr = result.data.array_ptr.?;

    if (string.tag != .string) {
        const str_val = php_value_to_string(string);
        arr.push(str_val) catch {};
        return result;
    }

    const str = string.data.string_ptr orelse return result;
    const delim_val = php_value_to_string(delimiter);
    defer php_gc_release(delim_val);
    const delim_str = delim_val.data.string_ptr orelse {
        arr.push(php_value_clone(string)) catch {};
        return result;
    };

    if (delim_str.length == 0) {
        arr.push(php_value_clone(string)) catch {};
        return result;
    }

    const str_data = str.data[0..str.length];
    const delim_data = delim_str.data[0..delim_str.length];

    var iter = std.mem.splitSequence(u8, str_data, delim_data);
    while (iter.next()) |part| {
        arr.push(php_value_create_string(part)) catch {};
    }

    return result;
}

/// Join array elements with delimiter
pub fn php_string_implode(glue: *PHPValue, pieces: *PHPValue) *PHPValue {
    if (pieces.tag != .array) return php_value_create_string("");
    const arr = pieces.data.array_ptr orelse return php_value_create_string("");

    if (arr.count() == 0) return php_value_create_string("");

    const glue_val = php_value_to_string(glue);
    defer php_gc_release(glue_val);
    const glue_str = glue_val.data.string_ptr;

    const allocator = getGlobalAllocator();
    var result = std.ArrayList(u8).init(allocator);
    defer result.deinit();

    var first = true;
    var entry = arr.first;
    while (entry) |e| {
        if (!first) {
            if (glue_str) |gs| {
                result.appendSlice(gs.data[0..gs.length]) catch {};
            }
        }
        first = false;

        const str_val = php_value_to_string(e.value);
        defer php_gc_release(str_val);
        if (str_val.data.string_ptr) |s| {
            result.appendSlice(s.data[0..s.length]) catch {};
        }

        entry = e.next_order;
    }

    return php_value_create_string(result.items);
}


// ============================================================================
// I/O Operations
// ============================================================================

/// Echo a value (output without newline)
pub fn php_echo(val: *PHPValue) void {
    const str_val = php_value_to_string(val);
    defer php_gc_release(str_val);

    if (str_val.data.string_ptr) |str| {
        const stdout = std.io.getStdOut().writer();
        stdout.writeAll(str.data[0..str.length]) catch {};
    }
}

/// Print a value (output with return value 1)
pub fn php_print(val: *PHPValue) i64 {
    php_echo(val);
    return 1;
}

/// Print with newline
pub fn php_println(val: *PHPValue) void {
    php_echo(val);
    const stdout = std.io.getStdOut().writer();
    stdout.writeAll("\n") catch {};
}

/// Print formatted string (printf-style)
pub fn php_printf(format: *PHPValue, args: []const *PHPValue) *PHPValue {
    // Simplified implementation - just concatenate format with args
    _ = args;
    php_echo(format);
    return php_value_create_int(1);
}

// ============================================================================
// Built-in Functions
// ============================================================================

/// strlen - Get string length
pub fn php_builtin_strlen(val: *PHPValue) *PHPValue {
    return php_value_create_int(php_string_length(val));
}

/// count - Get array/object count
pub fn php_builtin_count(val: *PHPValue) *PHPValue {
    return switch (val.tag) {
        .array => blk: {
            if (val.data.array_ptr) |arr| {
                break :blk php_value_create_int(@intCast(arr.count()));
            }
            break :blk php_value_create_int(0);
        },
        .object => blk: {
            if (val.data.object_ptr) |obj| {
                break :blk php_value_create_int(@intCast(obj.properties.count()));
            }
            break :blk php_value_create_int(0);
        },
        .null => php_value_create_int(0),
        else => php_value_create_int(1),
    };
}

/// var_dump - Dump variable information
pub fn php_builtin_var_dump(val: *PHPValue) void {
    const stdout = std.io.getStdOut().writer();
    dumpValue(stdout, val, 0) catch {};
}

/// print_r - Print human-readable representation
pub fn php_builtin_print_r(val: *PHPValue, return_output: bool) *PHPValue {
    if (return_output) {
        const allocator = getGlobalAllocator();
        var buffer = std.ArrayList(u8).init(allocator);
        defer buffer.deinit();

        printValue(buffer.writer(), val, 0) catch {};
        return php_value_create_string(buffer.items);
    } else {
        const stdout = std.io.getStdOut().writer();
        printValue(stdout, val, 0) catch {};
        return php_value_create_bool(true);
    }
}

/// var_export - Output or return a parsable string representation
pub fn php_builtin_var_export(val: *PHPValue, return_output: bool) *PHPValue {
    if (return_output) {
        const allocator = getGlobalAllocator();
        var buffer = std.ArrayList(u8).init(allocator);
        defer buffer.deinit();

        exportValue(buffer.writer(), val) catch {};
        return php_value_create_string(buffer.items);
    } else {
        const stdout = std.io.getStdOut().writer();
        exportValue(stdout, val) catch {};
        return php_value_create_null();
    }
}

/// gettype - Get the type of a variable
pub fn php_builtin_gettype(val: *PHPValue) *PHPValue {
    return php_value_create_string(val.getTypeName());
}

/// is_null - Check if value is null
pub fn php_builtin_is_null(val: *PHPValue) *PHPValue {
    return php_value_create_bool(val.tag == .null);
}

/// is_bool - Check if value is boolean
pub fn php_builtin_is_bool(val: *PHPValue) *PHPValue {
    return php_value_create_bool(val.tag == .bool);
}

/// is_int / is_integer / is_long - Check if value is integer
pub fn php_builtin_is_int(val: *PHPValue) *PHPValue {
    return php_value_create_bool(val.tag == .int);
}

/// is_float / is_double / is_real - Check if value is float
pub fn php_builtin_is_float(val: *PHPValue) *PHPValue {
    return php_value_create_bool(val.tag == .float);
}

/// is_numeric - Check if value is numeric or numeric string
pub fn php_builtin_is_numeric(val: *PHPValue) *PHPValue {
    return switch (val.tag) {
        .int, .float => php_value_create_bool(true),
        .string => blk: {
            if (val.data.string_ptr) |str| {
                const data = str.data[0..str.length];
                // Try to parse as number
                _ = std.fmt.parseFloat(f64, data) catch {
                    break :blk php_value_create_bool(false);
                };
                break :blk php_value_create_bool(true);
            }
            break :blk php_value_create_bool(false);
        },
        else => php_value_create_bool(false),
    };
}

/// is_string - Check if value is string
pub fn php_builtin_is_string(val: *PHPValue) *PHPValue {
    return php_value_create_bool(val.tag == .string);
}

/// is_array - Check if value is array
pub fn php_builtin_is_array(val: *PHPValue) *PHPValue {
    return php_value_create_bool(val.tag == .array);
}

/// is_object - Check if value is object
pub fn php_builtin_is_object(val: *PHPValue) *PHPValue {
    return php_value_create_bool(val.tag == .object);
}

/// is_callable - Check if value is callable
pub fn php_builtin_is_callable(val: *PHPValue) *PHPValue {
    return php_value_create_bool(val.tag == .callable);
}

/// empty - Check if value is empty
pub fn php_builtin_empty(val: *PHPValue) *PHPValue {
    return php_value_create_bool(!val.isTruthy());
}

/// isset - Check if value is set and not null
pub fn php_builtin_isset(val: *PHPValue) *PHPValue {
    return php_value_create_bool(val.tag != .null);
}

/// intval - Get integer value
pub fn php_builtin_intval(val: *PHPValue) *PHPValue {
    return php_value_create_int(val.toInt());
}

/// floatval / doubleval - Get float value
pub fn php_builtin_floatval(val: *PHPValue) *PHPValue {
    return php_value_create_float(val.toFloat());
}

/// strval - Get string value
pub fn php_builtin_strval(val: *PHPValue) *PHPValue {
    return php_value_to_string(val);
}

/// boolval - Get boolean value
pub fn php_builtin_boolval(val: *PHPValue) *PHPValue {
    return php_value_create_bool(val.toBool());
}

/// abs - Absolute value
pub fn php_builtin_abs(val: *PHPValue) *PHPValue {
    return switch (val.tag) {
        .int => php_value_create_int(if (val.data.int_val < 0) -val.data.int_val else val.data.int_val),
        .float => php_value_create_float(@abs(val.data.float_val)),
        else => blk: {
            const num = val.toFloat();
            break :blk php_value_create_float(@abs(num));
        },
    };
}

/// min - Find minimum value
pub fn php_builtin_min(args: []const *PHPValue) *PHPValue {
    if (args.len == 0) return php_value_create_null();
    if (args.len == 1 and args[0].tag == .array) {
        // min of array
        if (args[0].data.array_ptr) |arr| {
            var min_val: ?*PHPValue = null;
            var entry = arr.first;
            while (entry) |e| {
                if (min_val == null or compareValues(e.value, min_val.?) == .lt) {
                    min_val = e.value;
                }
                entry = e.next_order;
            }
            if (min_val) |v| {
                return php_value_clone(v);
            }
        }
        return php_value_create_null();
    }

    var min_val = args[0];
    for (args[1..]) |arg| {
        if (compareValues(arg, min_val) == .lt) {
            min_val = arg;
        }
    }
    return php_value_clone(min_val);
}

/// max - Find maximum value
pub fn php_builtin_max(args: []const *PHPValue) *PHPValue {
    if (args.len == 0) return php_value_create_null();
    if (args.len == 1 and args[0].tag == .array) {
        // max of array
        if (args[0].data.array_ptr) |arr| {
            var max_val: ?*PHPValue = null;
            var entry = arr.first;
            while (entry) |e| {
                if (max_val == null or compareValues(e.value, max_val.?) == .gt) {
                    max_val = e.value;
                }
                entry = e.next_order;
            }
            if (max_val) |v| {
                return php_value_clone(v);
            }
        }
        return php_value_create_null();
    }

    var max_val = args[0];
    for (args[1..]) |arg| {
        if (compareValues(arg, max_val) == .gt) {
            max_val = arg;
        }
    }
    return php_value_clone(max_val);
}

/// floor - Round down
pub fn php_builtin_floor(val: *PHPValue) *PHPValue {
    const f = val.toFloat();
    return php_value_create_float(@floor(f));
}

/// ceil - Round up
pub fn php_builtin_ceil(val: *PHPValue) *PHPValue {
    const f = val.toFloat();
    return php_value_create_float(@ceil(f));
}

/// round - Round to nearest
pub fn php_builtin_round(val: *PHPValue, precision: i64) *PHPValue {
    const f = val.toFloat();
    if (precision == 0) {
        return php_value_create_float(@round(f));
    }
    const multiplier = std.math.pow(f64, 10.0, @floatFromInt(precision));
    return php_value_create_float(@round(f * multiplier) / multiplier);
}

// ============================================================================
// Helper Functions for Output
// ============================================================================

/// Dump value with type information (for var_dump)
fn dumpValue(writer: anytype, val: *PHPValue, indent: usize) !void {
    const indent_str = "  ";

    // Write indentation
    for (0..indent) |_| {
        try writer.writeAll(indent_str);
    }

    switch (val.tag) {
        .null => try writer.writeAll("NULL\n"),
        .bool => {
            try writer.writeAll("bool(");
            try writer.writeAll(if (val.data.bool_val) "true" else "false");
            try writer.writeAll(")\n");
        },
        .int => {
            try writer.print("int({d})\n", .{val.data.int_val});
        },
        .float => {
            try writer.print("float({d})\n", .{val.data.float_val});
        },
        .string => {
            if (val.data.string_ptr) |str| {
                try writer.print("string({d}) \"{s}\"\n", .{ str.length, str.data[0..str.length] });
            } else {
                try writer.writeAll("string(0) \"\"\n");
            }
        },
        .array => {
            if (val.data.array_ptr) |arr| {
                try writer.print("array({d}) {{\n", .{arr.count()});
                var entry = arr.first;
                while (entry) |e| {
                    for (0..indent + 1) |_| {
                        try writer.writeAll(indent_str);
                    }
                    switch (e.key) {
                        .int => |i| try writer.print("[{d}]=>\n", .{i}),
                        .string => |s| try writer.print("[\"{s}\"]=>\n", .{s.data[0..s.length]}),
                    }
                    try dumpValue(writer, e.value, indent + 1);
                    entry = e.next_order;
                }
                for (0..indent) |_| {
                    try writer.writeAll(indent_str);
                }
                try writer.writeAll("}\n");
            } else {
                try writer.writeAll("array(0) {}\n");
            }
        },
        .object => {
            if (val.data.object_ptr) |obj| {
                try writer.print("object({s})#{d} ({d}) {{\n", .{
                    obj.class_name,
                    @intFromPtr(obj),
                    obj.properties.count(),
                });
                var entry = obj.properties.first;
                while (entry) |e| {
                    for (0..indent + 1) |_| {
                        try writer.writeAll(indent_str);
                    }
                    if (e.key == .string) {
                        try writer.print("[\"{s}\"]=>\n", .{e.key.string.data[0..e.key.string.length]});
                    }
                    try dumpValue(writer, e.value, indent + 1);
                    entry = e.next_order;
                }
                for (0..indent) |_| {
                    try writer.writeAll(indent_str);
                }
                try writer.writeAll("}\n");
            } else {
                try writer.writeAll("object(null)\n");
            }
        },
        .resource => try writer.writeAll("resource\n"),
        .callable => try writer.writeAll("callable\n"),
    }
}

/// Print value in human-readable format (for print_r)
fn printValue(writer: anytype, val: *PHPValue, indent: usize) !void {
    const indent_str = "    ";

    switch (val.tag) {
        .null => try writer.writeAll(""),
        .bool => try writer.writeAll(if (val.data.bool_val) "1" else ""),
        .int => try writer.print("{d}", .{val.data.int_val}),
        .float => try writer.print("{d}", .{val.data.float_val}),
        .string => {
            if (val.data.string_ptr) |str| {
                try writer.writeAll(str.data[0..str.length]);
            }
        },
        .array => {
            try writer.writeAll("Array\n");
            for (0..indent) |_| {
                try writer.writeAll(indent_str);
            }
            try writer.writeAll("(\n");
            if (val.data.array_ptr) |arr| {
                var entry = arr.first;
                while (entry) |e| {
                    for (0..indent + 1) |_| {
                        try writer.writeAll(indent_str);
                    }
                    switch (e.key) {
                        .int => |i| try writer.print("[{d}] => ", .{i}),
                        .string => |s| try writer.print("[{s}] => ", .{s.data[0..s.length]}),
                    }
                    try printValue(writer, e.value, indent + 1);
                    try writer.writeAll("\n");
                    entry = e.next_order;
                }
            }
            for (0..indent) |_| {
                try writer.writeAll(indent_str);
            }
            try writer.writeAll(")\n");
        },
        .object => {
            if (val.data.object_ptr) |obj| {
                try writer.print("{s} Object\n", .{obj.class_name});
                for (0..indent) |_| {
                    try writer.writeAll(indent_str);
                }
                try writer.writeAll("(\n");
                var entry = obj.properties.first;
                while (entry) |e| {
                    for (0..indent + 1) |_| {
                        try writer.writeAll(indent_str);
                    }
                    if (e.key == .string) {
                        try writer.print("[{s}] => ", .{e.key.string.data[0..e.key.string.length]});
                    }
                    try printValue(writer, e.value, indent + 1);
                    try writer.writeAll("\n");
                    entry = e.next_order;
                }
                for (0..indent) |_| {
                    try writer.writeAll(indent_str);
                }
                try writer.writeAll(")\n");
            }
        },
        .resource => try writer.writeAll("Resource"),
        .callable => try writer.writeAll("Callable"),
    }
}

/// Export value as parsable PHP code (for var_export)
fn exportValue(writer: anytype, val: *PHPValue) !void {
    switch (val.tag) {
        .null => try writer.writeAll("NULL"),
        .bool => try writer.writeAll(if (val.data.bool_val) "true" else "false"),
        .int => try writer.print("{d}", .{val.data.int_val}),
        .float => try writer.print("{d}", .{val.data.float_val}),
        .string => {
            if (val.data.string_ptr) |str| {
                try writer.writeAll("'");
                // Escape single quotes
                for (str.data[0..str.length]) |c| {
                    if (c == '\'') {
                        try writer.writeAll("\\'");
                    } else if (c == '\\') {
                        try writer.writeAll("\\\\");
                    } else {
                        try writer.writeByte(c);
                    }
                }
                try writer.writeAll("'");
            } else {
                try writer.writeAll("''");
            }
        },
        .array => {
            try writer.writeAll("array (\n");
            if (val.data.array_ptr) |arr| {
                var entry = arr.first;
                while (entry) |e| {
                    try writer.writeAll("  ");
                    switch (e.key) {
                        .int => |i| try writer.print("{d}", .{i}),
                        .string => |s| {
                            try writer.writeAll("'");
                            try writer.writeAll(s.data[0..s.length]);
                            try writer.writeAll("'");
                        },
                    }
                    try writer.writeAll(" => ");
                    try exportValue(writer, e.value);
                    try writer.writeAll(",\n");
                    entry = e.next_order;
                }
            }
            try writer.writeAll(")");
        },
        .object => {
            if (val.data.object_ptr) |obj| {
                try writer.print("(object) array(\n", .{});
                var entry = obj.properties.first;
                while (entry) |e| {
                    try writer.writeAll("   '");
                    if (e.key == .string) {
                        try writer.writeAll(e.key.string.data[0..e.key.string.length]);
                    }
                    try writer.writeAll("' => ");
                    try exportValue(writer, e.value);
                    try writer.writeAll(",\n");
                    entry = e.next_order;
                }
                try writer.writeAll(")");
            }
        },
        .resource => try writer.writeAll("NULL /* resource */"),
        .callable => try writer.writeAll("NULL /* callable */"),
    }
}

/// Compare two values (for min/max)
fn compareValues(a: *PHPValue, b: *PHPValue) std.math.Order {
    // Numeric comparison if both are numeric
    if ((a.tag == .int or a.tag == .float) and (b.tag == .int or b.tag == .float)) {
        const fa = a.toFloat();
        const fb = b.toFloat();
        return std.math.order(fa, fb);
    }

    // String comparison if both are strings
    if (a.tag == .string and b.tag == .string) {
        if (a.data.string_ptr) |sa| {
            if (b.data.string_ptr) |sb| {
                return sa.compare(sb);
            }
        }
    }

    // Default: compare as floats
    const fa = a.toFloat();
    const fb = b.toFloat();
    return std.math.order(fa, fb);
}


// ============================================================================
// Exception Handling Runtime
// ============================================================================

/// Stack frame for exception stack trace
pub const StackFrame = struct {
    /// Function name
    function_name: []const u8,
    /// File name
    file_name: []const u8,
    /// Line number
    line: u32,
    /// Column number
    column: u32,
    /// Class name (for methods)
    class_name: ?[]const u8,
    /// Next frame in the stack
    next: ?*StackFrame,
};

/// Exception state
pub const ExceptionState = struct {
    /// Current exception (if any)
    current_exception: ?*PHPValue,
    /// Exception message
    message: ?[]const u8,
    /// Exception code
    code: i64,
    /// Stack trace
    stack_trace: ?*StackFrame,
    /// Previous exception (for chaining)
    previous: ?*ExceptionState,
};

/// Thread-local exception state
var exception_state: ExceptionState = .{
    .current_exception = null,
    .message = null,
    .code = 0,
    .stack_trace = null,
    .previous = null,
};

/// Throw an exception
pub fn php_throw(exception: *PHPValue) void {
    exception_state.current_exception = exception;
    php_gc_retain(exception);

    // Extract message if it's an object with a message property
    if (exception.tag == .object) {
        if (exception.data.object_ptr) |obj| {
            // Try to get message property
            const allocator = getGlobalAllocator();
            const msg_key = PHPString.init(allocator, "message") catch return;
            defer msg_key.deinit(allocator);

            if (obj.getProperty(msg_key)) |msg_val| {
                if (msg_val.tag == .string) {
                    if (msg_val.data.string_ptr) |str| {
                        exception_state.message = str.getData();
                    }
                }
            }
        }
    } else if (exception.tag == .string) {
        if (exception.data.string_ptr) |str| {
            exception_state.message = str.getData();
        }
    }
}

/// Throw an exception with message
pub fn php_throw_message(message: []const u8) void {
    const exception = php_value_create_string(message);
    php_throw(exception);
    // php_throw retains the exception, so we release our reference
    php_gc_release(exception);
}

/// Throw a typed exception
pub fn php_throw_exception(class_name: []const u8, message: []const u8, code: i64) void {
    const allocator = getGlobalAllocator();

    // Create exception object
    const exception = php_value_create_object(class_name);
    if (exception.data.object_ptr) |obj| {
        // Set message property
        const msg_key = PHPString.init(allocator, "message") catch return;
        const msg_val = php_value_create_string(message);
        obj.setProperty(msg_key, msg_val) catch {};

        // Set code property
        const code_key = PHPString.init(allocator, "code") catch return;
        const code_val = php_value_create_int(code);
        obj.setProperty(code_key, code_val) catch {};
    }

    exception_state.code = code;
    php_throw(exception);
}

/// Catch the current exception
pub fn php_catch() ?*PHPValue {
    const ex = exception_state.current_exception;
    exception_state.current_exception = null;
    exception_state.message = null;
    exception_state.code = 0;
    return ex;
}

/// Catch exception of specific type
pub fn php_catch_type(class_name: []const u8) ?*PHPValue {
    if (exception_state.current_exception) |ex| {
        if (ex.tag == .object) {
            if (ex.data.object_ptr) |obj| {
                if (std.mem.eql(u8, obj.class_name, class_name)) {
                    return php_catch();
                }
            }
        }
    }
    return null;
}

/// Check if there's a pending exception
pub fn php_has_exception() bool {
    return exception_state.current_exception != null;
}

/// Get current exception without clearing it
pub fn php_get_exception() ?*PHPValue {
    return exception_state.current_exception;
}

/// Clear current exception without returning it
pub fn php_clear_exception() void {
    if (exception_state.current_exception) |ex| {
        php_gc_release(ex);
    }
    exception_state.current_exception = null;
    exception_state.message = null;
    exception_state.code = 0;
}

/// Get exception message
pub fn php_get_exception_message() ?[]const u8 {
    return exception_state.message;
}

/// Get exception code
pub fn php_get_exception_code() i64 {
    return exception_state.code;
}

/// Push a stack frame (called on function entry)
pub fn php_push_stack_frame(function_name: []const u8, file_name: []const u8, line: u32, column: u32, class_name: ?[]const u8) void {
    const allocator = getGlobalAllocator();
    const frame = allocator.create(StackFrame) catch return;
    frame.* = .{
        .function_name = function_name,
        .file_name = file_name,
        .line = line,
        .column = column,
        .class_name = class_name,
        .next = exception_state.stack_trace,
    };
    exception_state.stack_trace = frame;
}

/// Pop a stack frame (called on function exit)
pub fn php_pop_stack_frame() void {
    if (exception_state.stack_trace) |frame| {
        exception_state.stack_trace = frame.next;
        const allocator = getGlobalAllocator();
        allocator.destroy(frame);
    }
}

/// Get stack trace as array
pub fn php_get_stack_trace() *PHPValue {
    const result = php_value_create_array();
    if (result.data.array_ptr == null) return result;
    const arr = result.data.array_ptr.?;

    var frame = exception_state.stack_trace;
    while (frame) |f| {
        const frame_arr = php_value_create_array();
        if (frame_arr.data.array_ptr) |fa| {
            // Add function name
            const func_key = php_value_create_string("function");
            const func_val = php_value_create_string(f.function_name);
            php_array_set(fa, func_key, func_val);
            php_gc_release(func_key);

            // Add file name
            const file_key = php_value_create_string("file");
            const file_val = php_value_create_string(f.file_name);
            php_array_set(fa, file_key, file_val);
            php_gc_release(file_key);

            // Add line number
            const line_key = php_value_create_string("line");
            const line_val = php_value_create_int(@intCast(f.line));
            php_array_set(fa, line_key, line_val);
            php_gc_release(line_key);

            // Add class name if present
            if (f.class_name) |cn| {
                const class_key = php_value_create_string("class");
                const class_val = php_value_create_string(cn);
                php_array_set(fa, class_key, class_val);
                php_gc_release(class_key);
            }
        }
        arr.push(frame_arr) catch {};
        frame = f.next;
    }

    return result;
}

/// Print stack trace to stderr
pub fn php_print_stack_trace() void {
    const stderr = std.io.getStdErr().writer();

    stderr.writeAll("Stack trace:\n") catch {};

    var frame = exception_state.stack_trace;
    var depth: usize = 0;
    while (frame) |f| {
        stderr.print("#{d} {s}", .{ depth, f.file_name }) catch {};
        stderr.print("({d}): ", .{f.line}) catch {};
        if (f.class_name) |cn| {
            stderr.print("{s}::", .{cn}) catch {};
        }
        stderr.print("{s}()\n", .{f.function_name}) catch {};

        frame = f.next;
        depth += 1;
    }
}

/// Handle uncaught exception (called at program exit if exception is pending)
pub fn php_handle_uncaught_exception() void {
    if (exception_state.current_exception) |ex| {
        const stderr = std.io.getStdErr().writer();

        stderr.writeAll("\nFatal error: Uncaught ") catch {};

        if (ex.tag == .object) {
            if (ex.data.object_ptr) |obj| {
                stderr.print("{s}", .{obj.class_name}) catch {};
            }
        }

        if (exception_state.message) |msg| {
            stderr.print(": {s}", .{msg}) catch {};
        }

        stderr.writeAll("\n") catch {};
        php_print_stack_trace();

        php_clear_exception();
    }
}

/// Rethrow current exception
pub fn php_rethrow() void {
    // Exception is already set, just return to propagate
}

/// Create a new Exception object
pub fn php_create_exception(class_name: []const u8, message: []const u8, code: i64, previous: ?*PHPValue) *PHPValue {
    const allocator = getGlobalAllocator();

    const exception = php_value_create_object(class_name);
    if (exception.data.object_ptr) |obj| {
        // Set message
        const msg_key = PHPString.init(allocator, "message") catch return exception;
        const msg_val = php_value_create_string(message);
        obj.setProperty(msg_key, msg_val) catch {};

        // Set code
        const code_key = PHPString.init(allocator, "code") catch return exception;
        const code_val = php_value_create_int(code);
        obj.setProperty(code_key, code_val) catch {};

        // Set previous exception
        if (previous) |prev| {
            const prev_key = PHPString.init(allocator, "previous") catch return exception;
            php_gc_retain(prev);
            obj.setProperty(prev_key, prev) catch {};
        }

        // Set file and line from current stack frame
        if (exception_state.stack_trace) |frame| {
            const file_key = PHPString.init(allocator, "file") catch return exception;
            const file_val = php_value_create_string(frame.file_name);
            obj.setProperty(file_key, file_val) catch {};

            const line_key = PHPString.init(allocator, "line") catch return exception;
            const line_val = php_value_create_int(@intCast(frame.line));
            obj.setProperty(line_key, line_val) catch {};
        }
    }

    return exception;
}


// ============================================================================
// Mutex / Concurrency Runtime
// ============================================================================

/// Mutex type for lock statement
pub const PHPMutex = struct {
    /// Internal mutex implementation
    mutex: std.Thread.Mutex,
    /// Reference count
    ref_count: u32,

    /// Initialize a new mutex
    pub fn init() PHPMutex {
        return .{
            .mutex = .{},
            .ref_count = 1,
        };
    }

    /// Lock the mutex
    pub fn lock(self: *PHPMutex) void {
        self.mutex.lock();
    }

    /// Unlock the mutex
    pub fn unlock(self: *PHPMutex) void {
        self.mutex.unlock();
    }

    /// Try to lock the mutex (non-blocking)
    pub fn tryLock(self: *PHPMutex) bool {
        return self.mutex.tryLock();
    }
};

/// Thread-local global mutex for lock {} blocks
/// This is a simple implementation - each lock {} block uses the same global mutex
/// For more advanced use cases, users should use explicit mutex objects
var global_mutex: ?*PHPMutex = null;

/// Get or create the global mutex
fn getGlobalMutex() *PHPMutex {
    if (global_mutex == null) {
        const allocator = getGlobalAllocator();
        global_mutex = allocator.create(PHPMutex) catch {
            // Fallback to static mutex if allocation fails
            const static = struct {
                var mutex: PHPMutex = PHPMutex.init();
            };
            return &static.mutex;
        };
        global_mutex.?.* = PHPMutex.init();
    }
    return global_mutex.?;
}

/// Create a new mutex
pub fn php_mutex_new() *PHPMutex {
    const allocator = getGlobalAllocator();
    const mutex = allocator.create(PHPMutex) catch {
        // Return global mutex as fallback
        return getGlobalMutex();
    };
    mutex.* = PHPMutex.init();
    return mutex;
}

/// Acquire the global mutex lock (for lock {} blocks)
pub fn php_mutex_lock() void {
    const mutex = getGlobalMutex();
    mutex.lock();
}

/// Release the global mutex lock (for lock {} blocks)
pub fn php_mutex_unlock() void {
    const mutex = getGlobalMutex();
    mutex.unlock();
}

/// Acquire a specific mutex lock
pub fn php_mutex_lock_ptr(mutex: *PHPMutex) void {
    mutex.lock();
}

/// Release a specific mutex lock
pub fn php_mutex_unlock_ptr(mutex: *PHPMutex) void {
    mutex.unlock();
}

/// Try to acquire a specific mutex lock (non-blocking)
pub fn php_mutex_trylock_ptr(mutex: *PHPMutex) bool {
    return mutex.tryLock();
}

/// Retain mutex reference
pub fn php_mutex_retain(mutex: *PHPMutex) void {
    mutex.ref_count += 1;
}

/// Release mutex reference
pub fn php_mutex_release(mutex: *PHPMutex) void {
    if (mutex.ref_count == 0) return;
    mutex.ref_count -= 1;
    if (mutex.ref_count == 0) {
        // Don't free the global mutex
        if (mutex == global_mutex) return;
        const allocator = getGlobalAllocator();
        allocator.destroy(mutex);
    }
}


// ============================================================================
// Unit Tests
// ============================================================================

test "PHPValue creation - null" {
    initRuntime();
    defer deinitRuntime();

    const val = php_value_create_null();
    defer php_gc_release(val);

    try std.testing.expectEqual(ValueTag.null, val.tag);
    try std.testing.expectEqual(@as(u32, 1), val.ref_count);
    try std.testing.expect(val.isNull());
    try std.testing.expect(!val.isTruthy());
}

test "PHPValue creation - bool" {
    initRuntime();
    defer deinitRuntime();

    const val_true = php_value_create_bool(true);
    defer php_gc_release(val_true);
    const val_false = php_value_create_bool(false);
    defer php_gc_release(val_false);

    try std.testing.expectEqual(ValueTag.bool, val_true.tag);
    try std.testing.expect(val_true.data.bool_val);
    try std.testing.expect(val_true.isTruthy());

    try std.testing.expectEqual(ValueTag.bool, val_false.tag);
    try std.testing.expect(!val_false.data.bool_val);
    try std.testing.expect(!val_false.isTruthy());
}

test "PHPValue creation - int" {
    initRuntime();
    defer deinitRuntime();

    const val = php_value_create_int(42);
    defer php_gc_release(val);

    try std.testing.expectEqual(ValueTag.int, val.tag);
    try std.testing.expectEqual(@as(i64, 42), val.data.int_val);
    try std.testing.expect(val.isTruthy());

    const zero = php_value_create_int(0);
    defer php_gc_release(zero);
    try std.testing.expect(!zero.isTruthy());
}

test "PHPValue creation - float" {
    initRuntime();
    defer deinitRuntime();

    const val = php_value_create_float(3.14);
    defer php_gc_release(val);

    try std.testing.expectEqual(ValueTag.float, val.tag);
    try std.testing.expectApproxEqAbs(@as(f64, 3.14), val.data.float_val, 0.001);
    try std.testing.expect(val.isTruthy());
}

test "PHPValue creation - string" {
    initRuntime();
    defer deinitRuntime();

    const val = php_value_create_string("hello");
    defer php_gc_release(val);

    try std.testing.expectEqual(ValueTag.string, val.tag);
    try std.testing.expect(val.data.string_ptr != null);
    try std.testing.expectEqualStrings("hello", val.data.string_ptr.?.getData());
    try std.testing.expect(val.isTruthy());

    // Empty string is falsy
    const empty = php_value_create_string("");
    defer php_gc_release(empty);
    try std.testing.expect(!empty.isTruthy());

    // "0" is falsy
    const zero_str = php_value_create_string("0");
    defer php_gc_release(zero_str);
    try std.testing.expect(!zero_str.isTruthy());
}

test "PHPValue creation - array" {
    initRuntime();
    defer deinitRuntime();

    const val = php_value_create_array();
    defer php_gc_release(val);

    try std.testing.expectEqual(ValueTag.array, val.tag);
    try std.testing.expect(val.data.array_ptr != null);
    try std.testing.expectEqual(@as(usize, 0), val.data.array_ptr.?.count());
    try std.testing.expect(!val.isTruthy()); // Empty array is falsy
}

test "Type conversion - toInt" {
    initRuntime();
    defer deinitRuntime();

    const null_val = php_value_create_null();
    defer php_gc_release(null_val);
    try std.testing.expectEqual(@as(i64, 0), null_val.toInt());

    const bool_true = php_value_create_bool(true);
    defer php_gc_release(bool_true);
    try std.testing.expectEqual(@as(i64, 1), bool_true.toInt());

    const float_val = php_value_create_float(3.7);
    defer php_gc_release(float_val);
    try std.testing.expectEqual(@as(i64, 3), float_val.toInt());

    const str_val = php_value_create_string("42");
    defer php_gc_release(str_val);
    try std.testing.expectEqual(@as(i64, 42), str_val.toInt());
}

test "Type conversion - toFloat" {
    initRuntime();
    defer deinitRuntime();

    const int_val = php_value_create_int(42);
    defer php_gc_release(int_val);
    try std.testing.expectApproxEqAbs(@as(f64, 42.0), int_val.toFloat(), 0.001);

    const bool_val = php_value_create_bool(true);
    defer php_gc_release(bool_val);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), bool_val.toFloat(), 0.001);
}

test "Type conversion - toBool" {
    initRuntime();
    defer deinitRuntime();

    const int_zero = php_value_create_int(0);
    defer php_gc_release(int_zero);
    try std.testing.expect(!int_zero.toBool());

    const int_nonzero = php_value_create_int(1);
    defer php_gc_release(int_nonzero);
    try std.testing.expect(int_nonzero.toBool());

    const str_empty = php_value_create_string("");
    defer php_gc_release(str_empty);
    try std.testing.expect(!str_empty.toBool());

    const str_nonempty = php_value_create_string("hello");
    defer php_gc_release(str_nonempty);
    try std.testing.expect(str_nonempty.toBool());
}

test "Reference counting" {
    initRuntime();
    defer deinitRuntime();

    const val = php_value_create_int(42);
    try std.testing.expectEqual(@as(u32, 1), val.ref_count);

    php_gc_retain(val);
    try std.testing.expectEqual(@as(u32, 2), val.ref_count);

    php_gc_retain(val);
    try std.testing.expectEqual(@as(u32, 3), val.ref_count);

    php_gc_release(val);
    try std.testing.expectEqual(@as(u32, 2), val.ref_count);

    php_gc_release(val);
    try std.testing.expectEqual(@as(u32, 1), val.ref_count);

    php_gc_release(val);
    // Value should be freed now
}

test "Array operations" {
    initRuntime();
    defer deinitRuntime();

    const arr_val = php_value_create_array();
    defer php_gc_release(arr_val);
    const arr = arr_val.data.array_ptr.?;

    // Push values - array retains them, so we release our reference after push
    const val1 = php_value_create_int(10);
    php_array_push(arr, val1);
    php_gc_release(val1); // Release our reference, array still holds it

    const val2 = php_value_create_int(20);
    php_array_push(arr, val2);
    php_gc_release(val2);

    const val3 = php_value_create_string("hello");
    php_array_push(arr, val3);
    php_gc_release(val3);

    try std.testing.expectEqual(@as(i64, 3), php_array_count(arr));

    // Get by index
    const got1 = php_array_get_int(arr, 0);
    defer php_gc_release(got1);
    try std.testing.expectEqual(@as(i64, 10), got1.data.int_val);

    const got2 = php_array_get_int(arr, 1);
    defer php_gc_release(got2);
    try std.testing.expectEqual(@as(i64, 20), got2.data.int_val);

    // Key exists
    try std.testing.expect(php_array_key_exists_int(arr, 0));
    try std.testing.expect(php_array_key_exists_int(arr, 1));
    try std.testing.expect(!php_array_key_exists_int(arr, 10));
}

test "String operations" {
    initRuntime();
    defer deinitRuntime();

    const str1 = php_value_create_string("Hello");
    defer php_gc_release(str1);
    const str2 = php_value_create_string(" World");
    defer php_gc_release(str2);

    // Concatenation
    const concat = php_string_concat(str1, str2);
    defer php_gc_release(concat);
    try std.testing.expectEqualStrings("Hello World", concat.data.string_ptr.?.getData());

    // Length
    try std.testing.expectEqual(@as(i64, 5), php_string_length(str1));
    try std.testing.expectEqual(@as(i64, 6), php_string_length(str2));
    try std.testing.expectEqual(@as(i64, 11), php_string_length(concat));
}

test "String substr" {
    initRuntime();
    defer deinitRuntime();

    const str = php_value_create_string("Hello World");
    defer php_gc_release(str);

    // Basic substr
    const sub1 = php_string_substr(str, 0, 5);
    defer php_gc_release(sub1);
    try std.testing.expectEqualStrings("Hello", sub1.data.string_ptr.?.getData());

    // Substr from middle
    const sub2 = php_string_substr(str, 6, null);
    defer php_gc_release(sub2);
    try std.testing.expectEqualStrings("World", sub2.data.string_ptr.?.getData());

    // Negative start
    const sub3 = php_string_substr(str, -5, null);
    defer php_gc_release(sub3);
    try std.testing.expectEqualStrings("World", sub3.data.string_ptr.?.getData());
}

test "Built-in functions - strlen" {
    initRuntime();
    defer deinitRuntime();

    const str = php_value_create_string("Hello");
    defer php_gc_release(str);

    const len = php_builtin_strlen(str);
    defer php_gc_release(len);

    try std.testing.expectEqual(ValueTag.int, len.tag);
    try std.testing.expectEqual(@as(i64, 5), len.data.int_val);
}

test "Built-in functions - count" {
    initRuntime();
    defer deinitRuntime();

    const arr_val = php_value_create_array();
    defer php_gc_release(arr_val);
    const arr = arr_val.data.array_ptr.?;

    // Push values - array retains them, so we release our reference after push
    const v1 = php_value_create_int(1);
    php_array_push(arr, v1);
    php_gc_release(v1);

    const v2 = php_value_create_int(2);
    php_array_push(arr, v2);
    php_gc_release(v2);

    const v3 = php_value_create_int(3);
    php_array_push(arr, v3);
    php_gc_release(v3);

    const count = php_builtin_count(arr_val);
    defer php_gc_release(count);

    try std.testing.expectEqual(ValueTag.int, count.tag);
    try std.testing.expectEqual(@as(i64, 3), count.data.int_val);
}

test "Built-in functions - type checking" {
    initRuntime();
    defer deinitRuntime();

    const null_val = php_value_create_null();
    defer php_gc_release(null_val);
    const int_val = php_value_create_int(42);
    defer php_gc_release(int_val);
    const str_val = php_value_create_string("hello");
    defer php_gc_release(str_val);
    const arr_val = php_value_create_array();
    defer php_gc_release(arr_val);

    // is_null
    const is_null_result = php_builtin_is_null(null_val);
    defer php_gc_release(is_null_result);
    try std.testing.expect(is_null_result.data.bool_val);

    // is_int
    const is_int_result = php_builtin_is_int(int_val);
    defer php_gc_release(is_int_result);
    try std.testing.expect(is_int_result.data.bool_val);

    // is_string
    const is_string_result = php_builtin_is_string(str_val);
    defer php_gc_release(is_string_result);
    try std.testing.expect(is_string_result.data.bool_val);

    // is_array
    const is_array_result = php_builtin_is_array(arr_val);
    defer php_gc_release(is_array_result);
    try std.testing.expect(is_array_result.data.bool_val);
}

test "Exception handling" {
    initRuntime();
    defer deinitRuntime();

    // Initially no exception
    try std.testing.expect(!php_has_exception());

    // Throw exception
    php_throw_message("Test error");
    try std.testing.expect(php_has_exception());

    // Get message
    const msg = php_get_exception_message();
    try std.testing.expect(msg != null);
    try std.testing.expectEqualStrings("Test error", msg.?);

    // Catch exception
    const ex = php_catch();
    try std.testing.expect(ex != null);
    try std.testing.expect(!php_has_exception());

    php_gc_release(ex.?);
}

test "Value cloning" {
    initRuntime();
    defer deinitRuntime();

    // Clone int
    const int_val = php_value_create_int(42);
    defer php_gc_release(int_val);
    const int_clone = php_value_clone(int_val);
    defer php_gc_release(int_clone);
    try std.testing.expectEqual(@as(i64, 42), int_clone.data.int_val);
    try std.testing.expect(int_val != int_clone);

    // Clone string (shares data)
    const str_val = php_value_create_string("hello");
    defer php_gc_release(str_val);
    const str_clone = php_value_clone(str_val);
    defer php_gc_release(str_clone);
    try std.testing.expectEqualStrings("hello", str_clone.data.string_ptr.?.getData());
}

test "Math functions" {
    initRuntime();
    defer deinitRuntime();

    // abs
    const neg = php_value_create_int(-42);
    defer php_gc_release(neg);
    const abs_result = php_builtin_abs(neg);
    defer php_gc_release(abs_result);
    try std.testing.expectEqual(@as(i64, 42), abs_result.data.int_val);

    // floor
    const float_val = php_value_create_float(3.7);
    defer php_gc_release(float_val);
    const floor_result = php_builtin_floor(float_val);
    defer php_gc_release(floor_result);
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), floor_result.data.float_val, 0.001);

    // ceil
    const ceil_result = php_builtin_ceil(float_val);
    defer php_gc_release(ceil_result);
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), ceil_result.data.float_val, 0.001);
}
