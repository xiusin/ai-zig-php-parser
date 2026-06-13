//! AOT Runtime Library
//!
//! This module provides the runtime support for AOT-compiled PHP programs.
//! It includes:
//! - PHPValue: 8-byte NaN-boxed value representation
//! - Reference counting garbage collection
//! - Array operations
//! - String operations
//! - I/O functions
//! - Exception handling
//!
//! These functions are designed to be statically linked into the final executable.

const std = @import("std");
const Allocator = std.mem.Allocator;
const nanbox = @import("nanbox_abi.zig");

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
pub fn initRuntime(allocator: Allocator) void {
    _ = allocator;
    if (global_gpa == null) {
        global_gpa = std.heap.GeneralPurposeAllocator(.{}){};
    }
}

/// Deinitialize the runtime and free all resources
pub fn deinitRuntime() void {
    global_mutex = null;

    if (global_gpa) |*gpa| {
        const leak_check = gpa.deinit();
        if (leak_check == .leak) {
            std.debug.print("WARNING: Memory leak detected\n", .{});
        }
        global_gpa = null;
    }
}

// ============================================================================
// PHP Value Type System (NaN-boxed, 8 bytes)
// ============================================================================

/// The main PHP value type - an 8-byte NaN-boxed u64.
/// Simple types (null, bool, int, float) are stored entirely in-band.
/// Complex types (string, array, object) encode a pointer to a heap object.
pub const Value = u64;

/// Type alias for backward compatibility
pub const PHPValue = Value;

/// GC header embedded at the start of every heap-allocated PHP type.
pub const GcHeader = extern struct {
    ref_count: u32,
};

// ============================================================================
// Value Type Tag (kept for IR compatibility)
// ============================================================================

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

// ============================================================================
// PHP String Type
// ============================================================================

/// SSO inline buffer threshold: strings <= 23 bytes fit inline (24 bytes with null)
pub const PHP_STRING_SSO_MAX: usize = 23;
pub const PHP_STRING_INLINE_SIZE: usize = 24;

/// PHP String - reference counted, immutable string
/// Uses SSO (Small String Optimization): strings with length <= 23 are stored inline
/// without heap allocation for the string data.
pub const PHPString = struct {
    /// GC header (must be first field for uniform GC access)
    header: GcHeader,
    /// Inline buffer for SSO (23 chars + null terminator = 24 bytes)
    inline_data: [PHP_STRING_INLINE_SIZE]u8,
    /// String data pointer: for inline strings, points to inline_data;
    /// for heap strings, points to the heap-allocated buffer.
    /// Always null-terminated for C compatibility.
    data: [*]u8,
    /// String length (not including null terminator)
    length: usize,
    /// Capacity of allocated buffer, or 0 for inline strings (sentinel)
    capacity: usize,
    /// Hash cache (0 = not computed)
    hash: u32,

    const Self = @This();

    /// Returns true if this string is stored inline (SSO)
    pub fn isInline(self: *const Self) bool {
        return self.capacity == 0;
    }

    /// Create a new PHPString from a slice.
    /// Strings with length <= 23 are stored inline without heap allocation for the data.
    pub fn init(allocator: Allocator, str: []const u8) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        if (str.len <= PHP_STRING_SSO_MAX) {
            // SSO: store inline, no heap allocation for data
            @memcpy(self.inline_data[0..str.len], str);
            self.inline_data[str.len] = 0;
            self.header = .{ .ref_count = 1 };
            self.data = @ptrCast(&self.inline_data);
            self.length = str.len;
            self.capacity = 0; // sentinel: inline
            self.hash = 0;
        } else {
            // Heap allocation
            const capacity = str.len + 1;
            const data = try allocator.alloc(u8, capacity);
            errdefer allocator.free(data);
            @memcpy(data[0..str.len], str);
            data[str.len] = 0;
            self.* = .{
                .header = .{ .ref_count = 1 },
                .inline_data = undefined,
                .data = data.ptr,
                .length = str.len,
                .capacity = capacity,
                .hash = 0,
            };
        }
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

    /// Get string data as a slice (works for both inline and heap)
    pub fn getData(self: *const Self) []const u8 {
        return self.data[0..self.length];
    }

    /// Get null-terminated C string (works for both inline and heap)
    pub fn getCString(self: *const Self) [*:0]const u8 {
        return @ptrCast(self.data);
    }

    /// Concatenate two strings, producing a new PHPString.
    /// Result uses SSO if total length <= 23.
    pub fn concat(self: *const Self, other: *const Self, allocator: Allocator) !*Self {
        const new_len = self.length + other.length;

        const result = try allocator.create(Self);
        errdefer allocator.destroy(result);

        if (new_len <= PHP_STRING_SSO_MAX) {
            // Result fits inline
            @memcpy(result.inline_data[0..self.length], self.data[0..self.length]);
            @memcpy(result.inline_data[self.length..new_len], other.data[0..other.length]);
            result.inline_data[new_len] = 0;
            result.header = .{ .ref_count = 1 };
            result.data = @ptrCast(&result.inline_data);
            result.length = new_len;
            result.capacity = 0;
            result.hash = 0;
        } else {
            // Heap allocation
            const capacity = new_len + 1;
            const data = try allocator.alloc(u8, capacity);
            errdefer allocator.free(data);
            @memcpy(data[0..self.length], self.data[0..self.length]);
            @memcpy(data[self.length..new_len], other.data[0..other.length]);
            data[new_len] = 0;
            result.* = .{
                .header = .{ .ref_count = 1 },
                .inline_data = undefined,
                .data = data.ptr,
                .length = new_len,
                .capacity = capacity,
                .hash = 0,
            };
        }
        return result;
    }

    /// Compute hash (FNV-1a). Works for both inline and heap strings.
    pub fn computeHash(self: *Self) u32 {
        if (self.hash != 0) return self.hash;

        var h: u32 = 2166136261;
        for (self.data[0..self.length]) |byte| {
            h ^= byte;
            h *%= 16777619;
        }
        self.hash = if (h == 0) 1 else h;
        return self.hash;
    }

    /// Check equality with another string. Works for both inline and heap.
    pub fn eql(self: *const Self, other: *const Self) bool {
        if (self.length != other.length) return false;
        return std.mem.eql(u8, self.data[0..self.length], other.data[0..other.length]);
    }

    /// Compare with another string (for sorting). Works for both inline and heap.
    pub fn compare(self: *const Self, other: *const Self) std.math.Order {
        return std.mem.order(u8, self.data[0..self.length], other.data[0..other.length]);
    }
};

// ============================================================================
// PHP String Builder
// ============================================================================

/// PHPStringBuilder - efficient string construction with exponential growth.
/// Builds up a string incrementally and finalizes into a PHPString.
pub const PHPStringBuilder = struct {
    allocator: Allocator,
    buffer: []u8,
    length: usize,
    capacity: usize,

    const Self = @This();

    /// Create a new builder with initial capacity
    pub fn init(allocator: Allocator, initial_capacity: usize) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);
        const cap = @max(initial_capacity, 1);
        self.* = .{
            .allocator = allocator,
            .buffer = try allocator.alloc(u8, cap),
            .length = 0,
            .capacity = cap,
        };
        return self;
    }

    /// Append a string to the builder. Uses exponential growth (2x) for reallocation.
    pub fn append(self: *Self, str: []const u8) !void {
        const needed = self.length + str.len;
        if (needed > self.capacity) {
            // Exponential growth: double until we have enough
            var new_cap = self.capacity;
            while (new_cap < needed) {
                // Guard against overflow: if doubling would overflow, just use needed
                if (new_cap > std.math.maxInt(usize) / 2) {
                    new_cap = needed;
                } else {
                    new_cap *= 2;
                }
            }
            self.buffer = try self.allocator.realloc(self.buffer, new_cap);
            self.capacity = new_cap;
        }
        @memcpy(self.buffer[self.length..needed], str);
        self.length = needed;
    }

    /// Append a single byte
    pub fn appendByte(self: *Self, byte: u8) !void {
        try self.append(&[_]u8{byte});
    }

    /// Finalize the builder into a PHPString. The builder is consumed (do not use after this).
    /// The resulting PHPString may use SSO if the data fits inline.
    pub fn build(self: *Self) !*PHPString {
        const str = try PHPString.init(self.allocator, self.buffer[0..self.length]);
        return str;
    }

    /// Deinitialize and free the builder without building
    pub fn deinit(self: *Self) void {
        if (self.capacity > 0) {
            self.allocator.free(self.buffer);
        }
        self.allocator.destroy(self);
    }
};

/// Create a string builder with initial capacity
pub fn php_string_builder_create(capacity: usize) *PHPStringBuilder {
    const allocator = getGlobalAllocator();
    return PHPStringBuilder.init(allocator, capacity) catch @panic("OOM in php_string_builder_create");
}

/// Append a string to the builder
pub fn php_string_builder_append(builder: *PHPStringBuilder, str: []const u8) void {
    builder.append(str) catch @panic("OOM in php_string_builder_append");
}

/// Finalize the builder into a PHPString
pub fn php_string_builder_build(builder: *PHPStringBuilder) *PHPString {
    const result = builder.build() catch @panic("OOM in php_string_builder_build");
    // Builder is consumed; free its buffer but not the struct (caller should free)
    if (builder.capacity > 0) {
        builder.allocator.free(builder.buffer);
        builder.capacity = 0;
        builder.length = 0;
        builder.buffer = &.{};
    }
    builder.allocator.destroy(builder);
    return result;
}

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
    /// Stored directly as NaN-boxed Value (not a pointer-to-Value)
    value: Value,
    /// For maintaining insertion order
    next_order: ?*ArrayEntry,
    prev_order: ?*ArrayEntry,
    /// Probe sequence length for Robin Hood hashing
    psl: u32,
};

/// PHP Array - ordered hash map using Robin Hood probing for O(1) expected lookup
pub const PHPArray = struct {
    /// GC header (must be first field for uniform GC access)
    header: GcHeader,
    allocator: Allocator,
    /// Hash buckets using Robin Hood open addressing (entries stored directly, not ptrs)
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
    /// Base capacity used for pre-allocation
    base_capacity: usize,

    const Self = @This();
    const INITIAL_BUCKET_COUNT = 8;
    const LOAD_FACTOR_NUM: usize = 3;
    const LOAD_FACTOR_DEN: usize = 4; // 3/4 = 0.75

    /// Create a new empty array
    pub fn init(allocator: Allocator) !*Self {
        return initCapacity(allocator, INITIAL_BUCKET_COUNT);
    }

    /// Create a new array with pre-allocated capacity
    pub fn initCapacity(allocator: Allocator, initial_capacity: usize) !*Self {
        // Use next power of two that satisfies the load factor requirement
        var bucket_count = INITIAL_BUCKET_COUNT;
        while (bucket_count * LOAD_FACTOR_NUM / LOAD_FACTOR_DEN < initial_capacity) {
            bucket_count *= 2;
        }

        const buckets = try allocator.alloc(?*ArrayEntry, bucket_count);
        @memset(buckets, null);

        const self = try allocator.create(Self);
        self.* = .{
            .header = .{ .ref_count = 1 },
            .allocator = allocator,
            .buckets = buckets,
            .bucket_count = bucket_count,
            .entry_count = 0,
            .first = null,
            .last = null,
            .next_int_key = 0,
            .base_capacity = initial_capacity,
        };
        return self;
    }

    /// Deinitialize and free all resources
    pub fn deinit(self: *Self, allocator: Allocator) void {
        var entry = self.first;
        while (entry) |e| {
            const next = e.next_order;
            gcReleaseValue(e.value);
            if (e.key == .string) {
                e.key.string.header.ref_count -= 1;
                if (e.key.string.header.ref_count == 0) {
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

    /// Find entry by key using Robin Hood probing
    fn findEntry(self: *const Self, key: ArrayKey) ?*ArrayEntry {
        const hash = key.hash();
        var idx = hash % self.bucket_count;
        var psl: u32 = 0;

        while (true) {
            const maybe_entry = self.buckets[idx];
            if (maybe_entry) |entry| {
                if (entry.key.eql(key)) {
                    return entry;
                }
                // Robin Hood termination: if current PSL exceeds entry's PSL, key not present
                if (psl > entry.psl) {
                    return null;
                }
                psl += 1;
                idx = (idx + 1) % self.bucket_count;
            } else {
                return null;
            }
        }
    }

    /// Get value by key (returns NaN-boxed Value)
    pub fn getValue(self: *const Self, key: ArrayKey) Value {
        if (self.findEntry(key)) |entry| {
            gcRetainValue(entry.value);
            return entry.value;
        }
        return nanbox.encodeNull();
    }

    /// Ensure capacity for additional elements (2x growth strategy)
    pub fn ensureCapacity(self: *Self, additional: usize) !void {
        const needed = self.entry_count + additional;
        const threshold = self.bucket_count * LOAD_FACTOR_NUM / LOAD_FACTOR_DEN;
        if (needed <= threshold) return;

        var new_bucket_count = self.bucket_count;
        while (needed > new_bucket_count * LOAD_FACTOR_NUM / LOAD_FACTOR_DEN) {
            new_bucket_count *= 2;
        }
        try self.resizeToCapacity(new_bucket_count);
    }

    /// Set value by key using Robin Hood probing
    pub fn set(self: *Self, key: ArrayKey, value: Value) !void {
        // Check if key already exists
        if (self.findEntry(key)) |entry| {
            gcReleaseValue(entry.value);
            entry.value = value;
            gcRetainValue(value);
            return;
        }

        // Check load factor: entry_count + 1 > buckets * 0.75 => 4*(entry_count+1) > 3*buckets
        if ((self.entry_count + 1) * LOAD_FACTOR_DEN > self.bucket_count * LOAD_FACTOR_NUM) {
            try self.resize();
        }

        // Create new entry
        const entry = try self.allocator.create(ArrayEntry);
        entry.* = .{
            .key = key,
            .value = value,
            .next_order = null,
            .prev_order = self.last,
            .psl = 0,
        };

        gcRetainValue(value);

        if (key == .string) {
            key.string.header.ref_count += 1;
        }

        if (self.last) |last| {
            last.next_order = entry;
        } else {
            self.first = entry;
        }
        self.last = entry;

        // Robin Hood insertion: swap entire entry pointers at bucket level
        const hash = key.hash();
        var idx = hash % self.bucket_count;
        entry.psl = 0;

        while (true) {
            const maybe_existing = self.buckets[idx];
            if (maybe_existing) |existing_entry| {
                // Robin Hood: if our PSL (entry.psl) is greater than existing's PSL, swap
                if (entry.psl > existing_entry.psl) {
                    // Swap: entry goes into the bucket, existing_entry becomes our probe entry
                    self.buckets[idx] = entry;
                    entry = existing_entry;
                }
                entry.psl += 1;
                idx = (idx + 1) % self.bucket_count;
            } else {
                // Found empty slot
                self.buckets[idx] = entry;
                self.entry_count += 1;

                if (key == .int) {
                    if (key.int >= self.next_int_key) {
                        self.next_int_key = key.int + 1;
                    }
                }
                return;
            }
        }
    }

    /// Push value (append with auto-incrementing integer key)
    pub fn push(self: *Self, value: Value) !void {
        const key = ArrayKey{ .int = self.next_int_key };
        try self.set(key, value);
    }

    /// Check if key exists
    pub fn keyExists(self: *const Self, key: ArrayKey) bool {
        return self.findEntry(key) != null;
    }

    /// Remove entry by key using Robin Hood probing with backward shift
    pub fn unset(self: *Self, key: ArrayKey) void {
        const hash = key.hash();
        var idx = hash % self.bucket_count;
        var psl: u32 = 0;

        while (true) {
            const maybe_entry = self.buckets[idx];
            if (maybe_entry) |entry| {
                if (entry.key.eql(key)) {
                    // Remove from order list
                    if (entry.prev_order) |p| {
                        p.next_order = entry.next_order;
                    } else {
                        self.first = entry.next_order;
                    }
                    if (entry.next_order) |n| {
                        n.prev_order = entry.prev_order;
                    } else {
                        self.last = entry.prev_order;
                    }

                    gcReleaseValue(entry.value);

                    if (entry.key == .string) {
                        entry.key.string.header.ref_count -= 1;
                        if (entry.key.string.header.ref_count == 0) {
                            entry.key.string.deinit(self.allocator);
                        }
                    }

                    self.allocator.destroy(entry);
                    self.buckets[idx] = null;
                    self.entry_count -= 1;

                    // Robin Hood backward shift: move subsequent entries back
                    var next_idx = (idx + 1) % self.bucket_count;
                    while (true) {
                        const next = self.buckets[next_idx];
                        if (next) |next_entry| {
                            if (next_entry.psl == 0) break;
                            // Shift entry backward
                            next_entry.psl -= 1;
                            self.buckets[idx] = next_entry;
                            self.buckets[next_idx] = null;
                            idx = next_idx;
                            next_idx = (next_idx + 1) % self.bucket_count;
                        } else {
                            break;
                        }
                    }
                    return;
                }

                if (psl > entry.psl) {
                    return; // Key not found
                }

                psl += 1;
                idx = (idx + 1) % self.bucket_count;
            } else {
                return; // Empty slot, key not found
            }
        }
    }

    /// Resize the hash table (2x growth)
    fn resize(self: *Self) !void {
        try self.resizeToCapacity(self.bucket_count * 2);
    }

    /// Resize to a specific bucket count with proper Robin Hood rehashing
    fn resizeToCapacity(self: *Self, new_bucket_count: usize) !void {
        const new_buckets = try self.allocator.alloc(?*ArrayEntry, new_bucket_count);
        @memset(new_buckets, null);

        // Re-insert all entries using Robin Hood probing
        var entry = self.first;
        while (entry) |e| {
            const hash = e.key.hash();
            var idx = hash % new_bucket_count;
            e.psl = 0;

            var current: *ArrayEntry = e;
            while (true) {
                const maybe_entry = new_buckets[idx];
                if (maybe_entry) |existing_entry| {
                    if (current.psl > existing_entry.psl) {
                        // Swap: current goes into the slot, existing becomes current
                        new_buckets[idx] = current;
                        current = existing_entry;
                    }
                    current.psl += 1;
                    idx = (idx + 1) % new_bucket_count;
                } else {
                    new_buckets[idx] = current;
                    break;
                }
            }

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
    /// GC header (must be first field for uniform GC access)
    header: GcHeader,
    allocator: Allocator,
    /// Class name
    class_name: []const u8,
    /// Properties (stored as array)
    properties: *PHPArray,

    const Self = @This();

    /// Create a new object
    pub fn init(allocator: Allocator, class_name: []const u8) !*Self {
        const properties = try PHPArray.init(allocator);

        const self = try allocator.create(Self);
        self.* = .{
            .header = .{ .ref_count = 1 },
            .allocator = allocator,
            .class_name = class_name,
            .properties = properties,
        };
        return self;
    }

    /// Deinitialize and free resources
    pub fn deinit(self: *Self, allocator: Allocator) void {
        self.properties.deinit(allocator);
        allocator.destroy(self);
    }

    /// Get property value (returns NaN-boxed Value)
    pub fn getProperty(self: *const Self, name: *PHPString) Value {
        return self.properties.getValue(.{ .string = name });
    }

    /// Set property value
    pub fn setProperty(self: *Self, name: *PHPString, value: Value) !void {
        try self.properties.set(.{ .string = name }, value);
    }
};

/// PHP Callable (function reference)
pub const PHPCallable = struct {
    header: GcHeader,
    /// Function name or closure
    name: ?[]const u8,
    /// Object for method calls
    object: ?*PHPObject,
    /// Method name for method calls
    method: ?[]const u8,

    const Self = @This();

    pub fn init(allocator: Allocator, name: []const u8) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .header = .{ .ref_count = 1 },
            .name = name,
            .object = null,
            .method = null,
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

/// Create a null value (returns NaN-boxed u64, no allocation)
pub fn php_value_create_null() Value {
    return nanbox.encodeNull();
}

/// Create a boolean value (returns NaN-boxed u64, no allocation)
pub fn php_value_create_bool(b: bool) Value {
    return nanbox.encodeBool(b);
}

/// Create an integer value (returns NaN-boxed u64, no allocation)
pub fn php_value_create_int(i: i64) Value {
    return nanbox.encodeInt(i);
}

/// Create a float value (returns NaN-boxed u64, no allocation)
pub fn php_value_create_float(f: f64) Value {
    return nanbox.encodeFloat(f);
}

/// Create a string value from a slice (heap-allocates PHPString)
pub fn php_value_create_string(data: []const u8) Value {
    const allocator = getGlobalAllocator();
    const str = PHPString.init(allocator, data) catch return nanbox.encodeNull();
    return nanbox.encodePtr(@intFromPtr(str), nanbox.TYPE_STRING);
}

/// Create a string value from a C string pointer and length
pub fn php_value_create_string_raw(data: [*]const u8, len: usize) Value {
    return php_value_create_string(data[0..len]);
}

/// Create an empty array value (heap-allocates PHPArray)
pub fn php_value_create_array() Value {
    const allocator = getGlobalAllocator();
    const arr = PHPArray.init(allocator) catch return nanbox.encodeNull();
    return nanbox.encodePtr(@intFromPtr(arr), nanbox.TYPE_ARRAY);
}

/// Create an object value (heap-allocates PHPObject)
pub fn php_value_create_object(class_name: []const u8) Value {
    const allocator = getGlobalAllocator();
    const obj = PHPObject.init(allocator, class_name) catch return nanbox.encodeNull();
    return nanbox.encodePtr(@intFromPtr(obj), nanbox.TYPE_OBJECT);
}

/// Wrap an existing PHPString pointer into a Value (no allocation).
/// The caller retains ownership of the string; the Value borrows the pointer.
pub fn php_value_create_string_ptr(str: *PHPString) Value {
    return nanbox.encodePtr(@intFromPtr(str), nanbox.TYPE_STRING);
}

/// Wrap an existing PHPArray pointer into a Value (no allocation).
/// The caller retains ownership of the array; the Value borrows the pointer.
pub fn php_value_create_array_ptr(arr: *PHPArray) Value {
    return nanbox.encodePtr(@intFromPtr(arr), nanbox.TYPE_ARRAY);
}

// ============================================================================
// Type Conversion Functions
// ============================================================================

/// Get the type tag of a value
pub fn php_value_get_type(val: Value) u8 {
    if (nanbox.isNull(val)) return @intFromEnum(ValueTag.null);
    if (nanbox.isBool(val)) return @intFromEnum(ValueTag.bool);
    if (nanbox.isInt(val)) return @intFromEnum(ValueTag.int);
    if (nanbox.isFloat(val)) return @intFromEnum(ValueTag.float);
    if (nanbox.isString(val)) return @intFromEnum(ValueTag.string);
    if (nanbox.isArray(val)) return @intFromEnum(ValueTag.array);
    if (nanbox.isObject(val)) return @intFromEnum(ValueTag.object);
    return @intFromEnum(ValueTag.null);
}

/// Get the type name of a value
pub fn php_value_get_type_name(val: Value) []const u8 {
    return valueGetTypeName(val);
}

fn valueGetTypeName(val: Value) []const u8 {
    if (nanbox.isNull(val)) return "NULL";
    if (nanbox.isBool(val)) return "boolean";
    if (nanbox.isInt(val)) return "integer";
    if (nanbox.isFloat(val)) return "double";
    if (nanbox.isString(val)) return "string";
    if (nanbox.isArray(val)) return "array";
    if (nanbox.isObject(val)) return "object";
    return "unknown";
}

/// Check if value is null
pub fn valueIsNull(val: Value) bool {
    return nanbox.isNull(val);
}

/// Check if value is truthy (PHP truthiness rules)
pub fn valueIsTruthy(val: Value) bool {
    if (nanbox.isNull(val)) return false;
    if (nanbox.isBool(val)) return nanbox.decodeBool(val);
    if (nanbox.isInt(val)) return nanbox.decodeInt(val) != 0;
    if (nanbox.isFloat(val)) {
        const f = nanbox.decodeFloat(val);
        return f != 0.0 and !std.math.isNan(f);
    }
    if (nanbox.isString(val)) {
        const str = getStringPtr(val);
        if (str.length == 0) return false;
        if (str.length == 1 and str.data[0] == '0') return false;
        return true;
    }
    if (nanbox.isArray(val)) {
        const arr = getArrayPtr(val);
        return arr.count() > 0;
    }
    if (nanbox.isObject(val)) return true;
    return false;
}

/// Check if value is an array
pub fn valueIsArray(val: Value) bool {
    return nanbox.isArray(val);
}

/// Check if value is a string
pub fn valueIsString(val: Value) bool {
    return nanbox.isString(val);
}

/// Check if value is a bool
pub fn valueIsBool(val: Value) bool {
    return nanbox.isBool(val);
}

/// Check if value is an int
pub fn valueIsInt(val: Value) bool {
    return nanbox.isInt(val);
}

/// Check if value is a float
pub fn valueIsFloat(val: Value) bool {
    return nanbox.isFloat(val);
}

/// Check if value is an object
pub fn valueIsObject(val: Value) bool {
    return nanbox.isObject(val);
}

/// Check if value is a reference
pub fn valueIsRef(val: Value) bool {
    return nanbox.isRef(val);
}

/// Check if value is a function/closure
pub fn valueIsFunction(val: Value) bool {
    return nanbox.isFunction(val);
}

/// Extract the reference pointer from a ref-encoded Value.
/// Caller must ensure the value is a ref type before calling.
pub fn getRefPtr(val: Value) *Value {
    return @ptrFromInt(nanbox.decodePtr(val));
}

/// Convert value to integer (PHP type juggling)
pub fn php_value_to_int(val: Value) i64 {
    if (nanbox.isNull(val)) return 0;
    if (nanbox.isBool(val)) return if (nanbox.decodeBool(val)) @as(i64, 1) else @as(i64, 0);
    if (nanbox.isInt(val)) return nanbox.decodeInt(val);
    if (nanbox.isFloat(val)) return @intFromFloat(nanbox.decodeFloat(val));
    if (nanbox.isString(val)) {
        const str = getStringPtr(val);
        return parseIntFromString(str.getData()) catch 0;
    }
    if (nanbox.isArray(val)) {
        const arr = getArrayPtr(val);
        return if (arr.count() > 0) @as(i64, 1) else @as(i64, 0);
    }
    if (nanbox.isObject(val)) return 1;
    return 0;
}

/// Convert value to float (PHP type juggling)
pub fn php_value_to_float(val: Value) f64 {
    if (nanbox.isNull(val)) return 0.0;
    if (nanbox.isBool(val)) return if (nanbox.decodeBool(val)) @as(f64, 1.0) else @as(f64, 0.0);
    if (nanbox.isInt(val)) return @floatFromInt(nanbox.decodeInt(val));
    if (nanbox.isFloat(val)) return nanbox.decodeFloat(val);
    if (nanbox.isString(val)) {
        const str = getStringPtr(val);
        return parseFloatFromString(str.getData()) catch 0.0;
    }
    if (nanbox.isArray(val)) {
        const arr = getArrayPtr(val);
        return if (arr.count() > 0) @as(f64, 1.0) else @as(f64, 0.0);
    }
    if (nanbox.isObject(val)) return 1.0;
    return 0.0;
}

/// Convert value to boolean (PHP type juggling)
pub fn php_value_to_bool(val: Value) bool {
    return valueIsTruthy(val);
}

/// Convert value to string (returns a new NaN-boxed Value)
pub fn php_value_to_string(val: Value) Value {
    const allocator = getGlobalAllocator();

    if (nanbox.isNull(val)) return php_value_create_string("");
    if (nanbox.isBool(val)) return php_value_create_string(if (nanbox.decodeBool(val)) "1" else "");
    if (nanbox.isInt(val)) {
        var buf: [32]u8 = undefined;
        const result = std.fmt.bufPrint(&buf, "{d}", .{nanbox.decodeInt(val)}) catch return php_value_create_string("0");
        return php_value_create_string(result);
    }
    if (nanbox.isFloat(val)) {
        var buf: [64]u8 = undefined;
        const result = std.fmt.bufPrint(&buf, "{d}", .{nanbox.decodeFloat(val)}) catch return php_value_create_string("0");
        return php_value_create_string(result);
    }
    if (nanbox.isString(val)) {
        const str = getStringPtr(val);
        str.header.ref_count += 1;
        return nanbox.encodePtr(@intFromPtr(str), nanbox.TYPE_STRING);
    }
    if (nanbox.isArray(val)) return php_value_create_string("Array");
    if (nanbox.isObject(val)) {
        const obj = getObjectPtr(val);
        var buf: [256]u8 = undefined;
        const result = std.fmt.bufPrint(&buf, "Object({s})", .{obj.class_name}) catch return php_value_create_string("Object");
        return php_value_create_string(result);
    }
    return php_value_create_string("");
}

/// Cast value to a specific type (PHP-style type juggling)
pub fn php_value_cast(val: Value, target_type: ValueTag) Value {
    return switch (target_type) {
        .null => php_value_create_null(),
        .bool => php_value_create_bool(valueIsTruthy(val)),
        .int => php_value_create_int(php_value_to_int(val)),
        .float => php_value_create_float(php_value_to_float(val)),
        .string => php_value_to_string(val),
        .array => blk: {
            const arr = php_value_create_array();
            if (nanbox.isArray(arr)) {
                const array = getArrayPtr(arr);
                if (!nanbox.isNull(val)) {
                    const val_copy = php_value_clone(val);
                    array.push(val_copy) catch {};
                }
            }
            break :blk arr;
        },
        .object => blk: {
            const obj = php_value_create_object("stdClass");
            if (nanbox.isObject(obj)) {
                const object = getObjectPtr(obj);
                if (nanbox.isArray(val)) {
                    const arr = getArrayPtr(val);
                    var entry = arr.first;
                    while (entry) |e| {
                        if (e.key == .string) {
                            object.setProperty(e.key.string, e.value) catch {};
                        }
                        entry = e.next_order;
                    }
                }
            }
            break :blk obj;
        },
        .resource, .callable => php_value_create_null(),
    };
}

/// Clone a value (deep copy for complex types)
pub fn php_value_clone(val: Value) Value {
    const allocator = getGlobalAllocator();

    if (nanbox.isNull(val) or nanbox.isBool(val) or nanbox.isInt(val) or nanbox.isFloat(val)) {
        return val; // Simple types are value types, just copy the u64
    }
    if (nanbox.isString(val)) {
        const str = getStringPtr(val);
        const new_str = PHPString.init(allocator, str.getData()) catch return nanbox.encodeNull();
        return nanbox.encodePtr(@intFromPtr(new_str), nanbox.TYPE_STRING);
    }
    if (nanbox.isArray(val)) {
        const new_arr = php_value_create_array();
        const arr = getArrayPtr(val);
        if (nanbox.isArray(new_arr)) {
            const new_array = getArrayPtr(new_arr);
            var entry = arr.first;
            while (entry) |e| {
                const cloned_val = php_value_clone(e.value);
                new_array.set(e.key, cloned_val) catch {};
                entry = e.next_order;
            }
        }
        return new_arr;
    }
    if (nanbox.isObject(val)) {
        const obj = getObjectPtr(val);
        const new_obj = php_value_create_object(obj.class_name);
        if (nanbox.isObject(new_obj)) {
            const new_object = getObjectPtr(new_obj);
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
    return nanbox.encodeNull();
}

// ============================================================================
// Helper: extract heap pointers from NaN-boxed values
// ============================================================================

/// Extract the PHPString pointer from a string-encoded Value.
/// Caller must ensure the value is a string type before calling.
pub fn getStringPtr(val: Value) *PHPString {
    return @ptrFromInt(nanbox.decodePtr(val));
}

/// Extract the PHPArray pointer from an array-encoded Value.
/// Caller must ensure the value is an array type before calling.
pub fn getArrayPtr(val: Value) *PHPArray {
    return @ptrFromInt(nanbox.decodePtr(val));
}

/// Extract the PHPObject pointer from an object-encoded Value.
/// Caller must ensure the value is an object type before calling.
pub fn getObjectPtr(val: Value) *PHPObject {
    return @ptrFromInt(nanbox.decodePtr(val));
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Parse integer from string (PHP-style)
fn parseIntFromString(str: []const u8) !i64 {
    if (str.len == 0) return 0;

    var start: usize = 0;
    while (start < str.len and (str[start] == ' ' or str[start] == '\t' or str[start] == '\n' or str[start] == '\r')) {
        start += 1;
    }
    if (start >= str.len) return 0;

    var negative = false;
    if (str[start] == '-') {
        negative = true;
        start += 1;
    } else if (str[start] == '+') {
        start += 1;
    }

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
    return std.fmt.parseFloat(f64, str) catch 0.0;
}

// ============================================================================
// Reference Counting Garbage Collection
// ============================================================================

/// Increment reference count on a heap-allocated Value.
/// For simple types (null, bool, int, float) this is a no-op.
pub fn php_gc_retain(val: Value) void {
    gcRetainValue(val);
}

/// Decrement reference count and free if zero.
pub fn php_gc_release(val: Value) void {
    gcReleaseValue(val);
}

fn gcRetainValue(val: Value) void {
    if (!nanbox.isHeapType(val)) return;
    const ptr = nanbox.decodePtr(val);
    const header: *GcHeader = @ptrFromInt(ptr);
    header.ref_count += 1;
}

fn gcReleaseValue(val: Value) void {
    if (!nanbox.isHeapType(val)) return;
    const ptr = nanbox.decodePtr(val);
    const header: *GcHeader = @ptrFromInt(ptr);
    if (header.ref_count == 0) return;
    header.ref_count -= 1;
    if (header.ref_count == 0) {
        gcFreeValue(val);
    }
}

/// Free a heap-allocated Value and its internal data
fn gcFreeValue(val: Value) void {
    const allocator = getGlobalAllocator();
    const ptr = nanbox.decodePtr(val);

    if (nanbox.isString(val)) {
        const str: *PHPString = @ptrFromInt(ptr);
        str.deinit(allocator);
    } else if (nanbox.isArray(val)) {
        const arr: *PHPArray = @ptrFromInt(ptr);
        arr.deinit(allocator);
    } else if (nanbox.isObject(val)) {
        const obj: *PHPObject = @ptrFromInt(ptr);
        obj.deinit(allocator);
    }
}

/// Get current reference count (for debugging/testing)
pub fn php_gc_get_ref_count(val: Value) u32 {
    if (!nanbox.isHeapType(val)) return 0;
    const ptr = nanbox.decodePtr(val);
    const header: *GcHeader = @ptrFromInt(ptr);
    return header.ref_count;
}

/// Check if value is shared (ref_count > 1)
pub fn php_gc_is_shared(val: Value) bool {
    if (!nanbox.isHeapType(val)) return false;
    const ptr = nanbox.decodePtr(val);
    const header: *GcHeader = @ptrFromInt(ptr);
    return header.ref_count > 1;
}

/// Copy-on-write: ensure value is not shared before modification.
/// For simple types, returns the same value. For heap types with ref_count > 1, clones.
pub fn php_gc_copy_on_write(val: Value) Value {
    if (!nanbox.isHeapType(val)) return val;

    const ptr = nanbox.decodePtr(val);
    const header: *GcHeader = @ptrFromInt(ptr);
    if (header.ref_count <= 1) return val;

    const copy = php_value_clone(val);
    gcReleaseValue(val);
    return copy;
}

// ============================================================================
// Array Runtime Operations
// ============================================================================

/// Create a new empty array (returns raw PHPArray pointer)
pub fn php_array_create() *PHPArray {
    const allocator = getGlobalAllocator();
    return PHPArray.init(allocator) catch {
        return null_array;
    };
}

/// Create a new array with initial capacity (pre-allocated bucket count)
pub fn php_array_create_with_capacity(capacity: usize) *PHPArray {
    const allocator = getGlobalAllocator();
    return PHPArray.initCapacity(allocator, capacity) catch {
        return null_array;
    };
}

/// Pre-allocate capacity in an array for batch push operations (2x growth strategy)
pub fn php_array_ensure_capacity(arr: *PHPArray, additional: usize) void {
    arr.ensureCapacity(additional) catch {};
}

/// Get array element by integer key (returns NaN-boxed Value)
pub fn php_array_get_int(arr: *PHPArray, key: i64) Value {
    return arr.getValue(.{ .int = key });
}

/// Get array element by string key (returns NaN-boxed Value)
pub fn php_array_get_string(arr: *PHPArray, key: *PHPString) Value {
    return arr.getValue(.{ .string = key });
}

/// Get array element by Value key
pub fn php_array_get(arr: *PHPArray, key: Value) Value {
    const array_key = valueToArrayKey(key);
    return arr.getValue(array_key);
}

/// Set array element by integer key
pub fn php_array_set_int(arr: *PHPArray, key: i64, value: Value) void {
    arr.set(.{ .int = key }, value) catch {};
}

/// Set array element by string key
pub fn php_array_set_string(arr: *PHPArray, key: *PHPString, value: Value) void {
    arr.set(.{ .string = key }, value) catch {};
}

/// Set array element by Value key
pub fn php_array_set(arr: *PHPArray, key: Value, value: Value) void {
    const array_key = valueToArrayKey(key);
    arr.set(array_key, value) catch {};
}

/// Push value to array (append)
pub fn php_array_push(arr: *PHPArray, value: Value) void {
    arr.push(value) catch {};
}

/// Get array count
pub fn php_array_count(arr: *PHPArray) i64 {
    return @intCast(arr.count());
}

/// Check if key exists in array
pub fn php_array_key_exists(arr: *PHPArray, key: Value) bool {
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
pub fn php_array_unset(arr: *PHPArray, key: Value) void {
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

/// Get array keys as a new array value
pub fn php_array_keys(arr: *PHPArray) Value {
    const result = php_value_create_array();
    if (nanbox.isArray(result)) {
        const result_arr = getArrayPtr(result);
        var entry = arr.first;
        while (entry) |e| {
            const key_val = switch (e.key) {
                .int => |i| php_value_create_int(i),
                .string => |s| blk: {
                    s.header.ref_count += 1;
                    break :blk php_value_create_string(s.getData());
                },
            };
            result_arr.push(key_val) catch {};
            entry = e.next_order;
        }
    }
    return result;
}

/// Get array values as a new array (re-indexed)
pub fn php_array_values(arr: *PHPArray) Value {
    const result = php_value_create_array();
    if (nanbox.isArray(result)) {
        const result_arr = getArrayPtr(result);
        var entry = arr.first;
        while (entry) |e| {
            gcRetainValue(e.value);
            result_arr.push(e.value) catch {};
            entry = e.next_order;
        }
    }
    return result;
}

/// Merge two arrays
pub fn php_array_merge(arr1: *PHPArray, arr2: *PHPArray) Value {
    const result = php_value_create_array();
    if (nanbox.isArray(result)) {
        const result_arr = getArrayPtr(result);
        var entry = arr1.first;
        while (entry) |e| {
            gcRetainValue(e.value);
            switch (e.key) {
                .int => result_arr.push(e.value) catch {},
                .string => |s| result_arr.set(.{ .string = s }, e.value) catch {},
            }
            entry = e.next_order;
        }

        entry = arr2.first;
        while (entry) |e| {
            gcRetainValue(e.value);
            switch (e.key) {
                .int => result_arr.push(e.value) catch {},
                .string => |s| result_arr.set(.{ .string = s }, e.value) catch {},
            }
            entry = e.next_order;
        }
    }
    return result;
}

/// Check if value exists in array (loose comparison, returns bool)
pub fn php_in_array(needle: Value, haystack: Value) Value {
    if (!nanbox.isArray(haystack)) return php_value_create_bool(false);
    const arr = getArrayPtr(haystack);

    var entry = arr.first;
    while (entry) |e| {
        const eq_result = php_eq(needle, e.value) catch return php_value_create_bool(false);
        if (nanbox.decodeBool(eq_result)) return php_value_create_bool(true);
        entry = e.next_order;
    }

    return php_value_create_bool(false);
}

/// Search for value in array and return first matching key (loose comparison, returns key or false)
pub fn php_array_search(needle: Value, haystack: Value) Value {
    if (!nanbox.isArray(haystack)) return php_value_create_bool(false);
    const arr = getArrayPtr(haystack);

    var entry = arr.first;
    while (entry) |e| {
        const eq_result = php_eq(needle, e.value) catch return php_value_create_bool(false);
        if (nanbox.decodeBool(eq_result)) {
            return switch (e.key) {
                .int => |i| php_value_create_int(i),
                .string => |s| php_value_create_string(s.getData()),
            };
        }
        entry = e.next_order;
    }

    return php_value_create_bool(false);
}

/// Check if array is empty
pub fn php_array_is_empty(arr: *PHPArray) bool {
    return arr.count() == 0;
}

/// Get first element of array
pub fn php_array_first(arr: *PHPArray) Value {
    if (arr.first) |entry| {
        gcRetainValue(entry.value);
        return entry.value;
    }
    return nanbox.encodeNull();
}

/// Get last element of array
pub fn php_array_last(arr: *PHPArray) Value {
    if (arr.last) |entry| {
        gcRetainValue(entry.value);
        return entry.value;
    }
    return nanbox.encodeNull();
}

/// Convert Value to ArrayKey
fn valueToArrayKey(val: Value) ArrayKey {
    if (nanbox.isInt(val)) return .{ .int = nanbox.decodeInt(val) };
    if (nanbox.isFloat(val)) return .{ .int = @intFromFloat(nanbox.decodeFloat(val)) };
    if (nanbox.isBool(val)) return .{ .int = if (nanbox.decodeBool(val)) 1 else 0 };
    if (nanbox.isNull(val)) return .{ .int = 0 };
    if (nanbox.isString(val)) {
        const str = getStringPtr(val);
        const int_val = parseIntFromString(str.getData()) catch {
            return ArrayKey{ .string = str };
        };
        var buf: [32]u8 = undefined;
        const result = std.fmt.bufPrint(&buf, "{d}", .{int_val}) catch {
            return ArrayKey{ .string = str };
        };
        if (result.len == str.length and std.mem.eql(u8, result, str.getData())) {
            return ArrayKey{ .int = int_val };
        }
        return ArrayKey{ .string = str };
    }
    return .{ .int = 0 };
}

/// Static null array for error cases
var null_array_storage: PHPArray = .{
    .header = .{ .ref_count = 1 },
    .allocator = undefined,
    .buckets = undefined,
    .bucket_count = 0,
    .entry_count = 0,
    .first = null,
    .last = null,
    .next_int_key = 0,
};
var null_array: *PHPArray = &null_array_storage;

// ============================================================================
// String Runtime Operations
// ============================================================================

/// Concatenate two values as strings
pub fn php_string_concat(a: Value, b: Value) Value {
    const allocator = getGlobalAllocator();

    const str_a = php_value_to_string(a);
    defer gcReleaseValue(str_a);
    const str_b = php_value_to_string(b);
    defer gcReleaseValue(str_b);

    const ptr_a = getStringPtr(str_a);
    const ptr_b = getStringPtr(str_b);

    const result_str = ptr_a.concat(ptr_b, allocator) catch return nanbox.encodeNull();

    return nanbox.encodePtr(@intFromPtr(result_str), nanbox.TYPE_STRING);
}

/// Get string length
pub fn php_string_length(val: Value) i64 {
    if (!nanbox.isString(val)) return 0;
    const str = getStringPtr(val);
    return @intCast(str.length);
}

/// Get string length from PHPString
pub fn php_string_len(str: *PHPString) i64 {
    return @intCast(str.length);
}

/// String interpolation - concatenate multiple parts
pub fn php_string_interpolate(parts: []const Value) Value {
    if (parts.len == 0) return php_value_create_string("");
    if (parts.len == 1) return php_value_to_string(parts[0]);

    const allocator = getGlobalAllocator();

    var total_len: usize = 0;
    for (parts) |part| {
        const str_part = php_value_to_string(part);
        defer gcReleaseValue(str_part);
        const str = getStringPtr(str_part);
        total_len += str.length;
    }

    const capacity = total_len + 1;
    const data = allocator.alloc(u8, capacity) catch return nanbox.encodeNull();

    var offset: usize = 0;
    for (parts) |part| {
        const str_part = php_value_to_string(part);
        defer gcReleaseValue(str_part);
        const str = getStringPtr(str_part);
        @memcpy(data[offset .. offset + str.length], str.data[0..str.length]);
        offset += str.length;
    }
    data[total_len] = 0;

    const result_str = allocator.create(PHPString) catch {
        allocator.free(data);
        return nanbox.encodeNull();
    };
    result_str.* = .{
        .header = .{ .ref_count = 1 },
        .data = data.ptr,
        .length = total_len,
        .capacity = capacity,
        .hash = 0,
    };

    return nanbox.encodePtr(@intFromPtr(result_str), nanbox.TYPE_STRING);
}

/// Get substring
pub fn php_string_substr(val: Value, start: i64, length: ?i64) Value {
    if (!nanbox.isString(val)) return php_value_create_string("");
    const str = getStringPtr(val);

    const str_len: i64 = @intCast(str.length);

    var actual_start: i64 = start;
    if (actual_start < 0) {
        actual_start = str_len + actual_start;
        if (actual_start < 0) actual_start = 0;
    }
    if (actual_start >= str_len) return php_value_create_string("");

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

    const ustart: usize = @intCast(actual_start);
    var ulen: usize = @intCast(actual_len);
    if (ustart + ulen > str.length) {
        ulen = str.length - ustart;
    }

    return php_value_create_string(str.data[ustart .. ustart + ulen]);
}

/// Find position of substring
pub fn php_string_strpos(haystack: Value, needle: Value, offset: i64) Value {
    if (!nanbox.isString(haystack)) return php_value_create_bool(false);
    const hay_str = getStringPtr(haystack);

    const needle_str_val = php_value_to_string(needle);
    defer gcReleaseValue(needle_str_val);
    const needle_str = getStringPtr(needle_str_val);

    if (needle_str.length == 0) return php_value_create_bool(false);

    var search_start: usize = 0;
    if (offset > 0) {
        search_start = @intCast(offset);
        if (search_start >= hay_str.length) return php_value_create_bool(false);
    }

    const hay_data = hay_str.data[search_start..hay_str.length];
    const needle_data = needle_str.data[0..needle_str.length];

    if (std.mem.indexOf(u8, hay_data, needle_data)) |pos| {
        return php_value_create_int(@intCast(search_start + pos));
    }

    return php_value_create_bool(false);
}

/// Convert string to uppercase
pub fn php_string_strtoupper(val: Value) Value {
    if (!nanbox.isString(val)) return php_value_to_string(val);
    const str = getStringPtr(val);

    const allocator = getGlobalAllocator();
    const data = allocator.alloc(u8, str.length + 1) catch return nanbox.encodeNull();

    for (str.data[0..str.length], 0..) |c, i| {
        data[i] = std.ascii.toUpper(c);
    }
    data[str.length] = 0;

    const result_str = allocator.create(PHPString) catch {
        allocator.free(data);
        return nanbox.encodeNull();
    };
    result_str.* = .{
        .header = .{ .ref_count = 1 },
        .data = data.ptr,
        .length = str.length,
        .capacity = str.length + 1,
        .hash = 0,
    };

    return nanbox.encodePtr(@intFromPtr(result_str), nanbox.TYPE_STRING);
}

/// Convert string to lowercase
pub fn php_string_strtolower(val: Value) Value {
    if (!nanbox.isString(val)) return php_value_to_string(val);
    const str = getStringPtr(val);

    const allocator = getGlobalAllocator();
    const data = allocator.alloc(u8, str.length + 1) catch return nanbox.encodeNull();

    for (str.data[0..str.length], 0..) |c, i| {
        data[i] = std.ascii.toLower(c);
    }
    data[str.length] = 0;

    const result_str = allocator.create(PHPString) catch {
        allocator.free(data);
        return nanbox.encodeNull();
    };
    result_str.* = .{
        .header = .{ .ref_count = 1 },
        .data = data.ptr,
        .length = str.length,
        .capacity = str.length + 1,
        .hash = 0,
    };

    return nanbox.encodePtr(@intFromPtr(result_str), nanbox.TYPE_STRING);
}

/// Trim whitespace from string
pub fn php_string_trim(val: Value) Value {
    if (!nanbox.isString(val)) return php_value_to_string(val);
    const str = getStringPtr(val);

    const data = str.data[0..str.length];
    const trimmed = std.mem.trim(u8, data, " \t\n\r\x00\x0b");

    return php_value_create_string(trimmed);
}

/// Replace occurrences in string
pub fn php_string_str_replace(search: Value, replace: Value, subject: Value) Value {
    if (!nanbox.isString(subject)) return php_value_to_string(subject);
    const subj_str = getStringPtr(subject);

    const search_val = php_value_to_string(search);
    defer gcReleaseValue(search_val);
    const search_str = getStringPtr(search_val);

    const replace_val = php_value_to_string(replace);
    defer gcReleaseValue(replace_val);
    const replace_str = getStringPtr(replace_val);

    if (search_str.length == 0) return php_value_clone(subject);

    const allocator = getGlobalAllocator();

    var result = std.ArrayList(u8).initCapacity(allocator, 0) catch return php_value_clone(subject);
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
pub fn php_string_explode(delimiter: Value, string: Value) Value {
    const result = php_value_create_array();
    if (!nanbox.isArray(result)) return result;
    const arr = getArrayPtr(result);

    if (!nanbox.isString(string)) {
        const str_val = php_value_to_string(string);
        arr.push(str_val) catch {};
        return result;
    }

    const str = getStringPtr(string);
    const delim_val = php_value_to_string(delimiter);
    defer gcReleaseValue(delim_val);
    const delim_str = getStringPtr(delim_val);

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

/// Get a single character from string at index (returns 1-char string or empty string)
pub fn php_string_get_char(val: Value, index: i64) Value {
    if (!nanbox.isString(val)) return php_value_create_string("");
    const str = getStringPtr(val);

    const str_len: i64 = @intCast(str.length);

    var actual_index = index;
    if (actual_index < 0) {
        actual_index = str_len + actual_index;
    }
    if (actual_index < 0 or actual_index >= str_len) {
        return php_value_create_string("");
    }

    const ui: usize = @intCast(actual_index);
    return php_value_create_string(str.data[ui..ui+1]);
}

/// Set a single character in string at index (modifies string in place)
pub fn php_string_set_char(str: *PHPString, index: i64, char_val: Value) void {
    const str_len: i64 = @intCast(str.length);

    var actual_index = index;
    if (actual_index < 0) {
        actual_index = str_len + actual_index;
    }
    if (actual_index < 0 or actual_index >= str_len) {
        return;
    }

    const char_str_val = php_value_to_string(char_val);
    defer gcReleaseValue(char_str_val);
    const char_str = getStringPtr(char_str_val);

    if (char_str.length > 0) {
        const ui: usize = @intCast(actual_index);
        str.data[ui] = char_str.data[0];
    }
}

/// Join array elements with delimiter
pub fn php_string_implode(glue: Value, pieces: Value) Value {
    if (!nanbox.isArray(pieces)) return php_value_create_string("");
    const arr = getArrayPtr(pieces);

    if (arr.count() == 0) return php_value_create_string("");

    const glue_val = php_value_to_string(glue);
    defer gcReleaseValue(glue_val);
    const glue_str = getStringPtr(glue_val);

    const allocator = getGlobalAllocator();
    var result = std.ArrayList(u8).initCapacity(allocator, 0) catch return nanbox.encodeNull();
    defer result.deinit();

    var first = true;
    var entry = arr.first;
    while (entry) |e| {
        if (!first) {
            result.appendSlice(glue_str.data[0..glue_str.length]) catch {};
        }
        first = false;

        const str_val = php_value_to_string(e.value);
        defer gcReleaseValue(str_val);
        const s = getStringPtr(str_val);
        result.appendSlice(s.data[0..s.length]) catch {};

        entry = e.next_order;
    }

    return php_value_create_string(result.items);
}

// ============================================================================
// I/O Operations
// ============================================================================

/// Echo a value (output without newline)
pub fn php_echo(val: Value) !void {
    const str_val = php_value_to_string(val);
    defer gcReleaseValue(str_val);

    const str = getStringPtr(str_val);
    const stdout = std.io.getStdOut().writer();
    stdout.writeAll(str.data[0..str.length]) catch {};
}

/// Print a value (output with return value 1)
pub fn php_print(val: Value) i64 {
    php_echo(val) catch {};
    return 1;
}

/// Print with newline
pub fn php_println(val: Value) void {
    php_echo(val) catch {};
    const stdout = std.io.getStdOut().writer();
    stdout.writeAll("\n") catch {};
}

/// Print formatted string (printf-style)
pub fn php_printf(format: Value, args: []const Value) Value {
    _ = args;
    php_echo(format) catch {};
    return php_value_create_int(1);
}

// ============================================================================
// Include/Require Runtime Support
// ============================================================================

/// Runtime php_include function for dynamic file paths.
/// Since we cannot re-compile at runtime, this generates a warning and returns false.
/// For static paths resolved at compile time, the IR is merged by the multi-file compiler.
pub fn php_include(path_val: Value) Value {
    const str_val = php_value_to_string(path_val);
    defer gcReleaseValue(str_val);

    const stderr = std.io.getStdErr().writer();
    const str = getStringPtr(str_val);
    if (str.length > 0) {
        stderr.print("Warning: include(): Cannot include file '{s}' at runtime in AOT-compiled code. " ++
            "Use a static file path for compile-time inclusion.\n", .{str.data[0..str.length]}) catch {};
    } else {
        stderr.writeAll("Warning: include(): Cannot include file at runtime in AOT-compiled code. " ++
            "Use a static file path for compile-time inclusion.\n") catch {};
    }

    // PHP include returns false on failure in expression context
    return nanbox.encodeBool(false);
}

/// Runtime php_require function for dynamic file paths.
/// Since we cannot re-compile at runtime, this generates a fatal error and terminates.
/// For static paths resolved at compile time, the IR is merged by the multi-file compiler.
pub fn php_require(path_val: Value) Value {
    const str_val = php_value_to_string(path_val);
    defer gcReleaseValue(str_val);

    const stderr = std.io.getStdErr().writer();
    const str = getStringPtr(str_val);
    if (str.length > 0) {
        stderr.print("Fatal error: require(): Cannot require file '{s}' at runtime in AOT-compiled code. " ++
            "Use a static file path for compile-time inclusion.\n", .{str.data[0..str.length]}) catch {};
    } else {
        stderr.writeAll("Fatal error: require(): Cannot require file at runtime in AOT-compiled code. " ++
            "Use a static file path for compile-time inclusion.\n") catch {};
    }

    // PHP require generates a fatal error. In AOT, we call exit(1).
    std.process.exit(1);
}

/// Runtime php_include_once function for dynamic file paths.
/// Since we cannot track state at runtime for AOT, delegates to php_include.
pub fn php_include_once(path_val: Value) Value {
    return php_include(path_val);
}

/// Runtime php_require_once function for dynamic file paths.
/// Since we cannot track state at runtime for AOT, delegates to php_require.
pub fn php_require_once(path_val: Value) Value {
    return php_require(path_val);
}

// ============================================================================
// Built-in Functions
// ============================================================================

/// strlen - Get string length
pub fn php_builtin_strlen(val: Value) Value {
    return php_value_create_int(php_string_length(val));
}

/// count - Get array/object count
pub fn php_builtin_count(val: Value) Value {
    if (nanbox.isArray(val)) {
        const arr = getArrayPtr(val);
        return php_value_create_int(@intCast(arr.count()));
    }
    if (nanbox.isObject(val)) {
        const obj = getObjectPtr(val);
        return php_value_create_int(@intCast(obj.properties.count()));
    }
    if (nanbox.isNull(val)) return php_value_create_int(0);
    return php_value_create_int(1);
}

/// var_dump - Dump variable information
pub fn php_builtin_var_dump(val: Value) void {
    const allocator = getGlobalAllocator();
    var buffer = std.ArrayList(u8).initCapacity(allocator, 0) catch return;
    defer buffer.deinit();

    dumpValue(buffer.writer(), val, 0) catch {};
    const stdout = std.io.getStdOut().writer();
    stdout.writeAll(buffer.items) catch {};
}

/// print_r - Print human-readable representation
pub fn php_builtin_print_r(val: Value, return_output: bool) Value {
    const allocator = getGlobalAllocator();
    var buffer = std.ArrayList(u8).initCapacity(allocator, 0) catch return php_value_create_bool(false);
    defer buffer.deinit();

    printValue(buffer.writer(), val, 0) catch {};

    if (return_output) {
        return php_value_create_string(buffer.items);
    } else {
        const stdout = std.io.getStdOut().writer();
        stdout.writeAll(buffer.items) catch {};
        return php_value_create_bool(true);
    }
}

/// var_export - Output or return a parsable string representation
pub fn php_builtin_var_export(val: Value, return_output: bool) Value {
    const allocator = getGlobalAllocator();
    var buffer = std.ArrayList(u8).initCapacity(allocator, 0) catch return nanbox.encodeNull();
    defer buffer.deinit();

    exportValue(buffer.writer(), val) catch {};

    if (return_output) {
        return php_value_create_string(buffer.items);
    } else {
        const stdout = std.io.getStdOut().writer();
        stdout.writeAll(buffer.items) catch {};
        return nanbox.encodeNull();
    }
}

/// gettype - Get the type of a variable
pub fn php_builtin_gettype(val: Value) Value {
    return php_value_create_string(valueGetTypeName(val));
}

/// is_null - Check if value is null
pub fn php_builtin_is_null(val: Value) Value {
    return php_value_create_bool(nanbox.isNull(val));
}

/// is_bool - Check if value is boolean
pub fn php_builtin_is_bool(val: Value) Value {
    return php_value_create_bool(nanbox.isBool(val));
}

/// is_int / is_integer / is_long - Check if value is integer
pub fn php_builtin_is_int(val: Value) Value {
    return php_value_create_bool(nanbox.isInt(val));
}

/// is_float / is_double / is_real - Check if value is float
pub fn php_builtin_is_float(val: Value) Value {
    return php_value_create_bool(nanbox.isFloat(val));
}

/// is_numeric - Check if value is numeric or numeric string
pub fn php_builtin_is_numeric(val: Value) Value {
    if (nanbox.isInt(val) or nanbox.isFloat(val)) return php_value_create_bool(true);
    if (nanbox.isString(val)) {
        const str = getStringPtr(val);
        const data = str.data[0..str.length];
        _ = std.fmt.parseFloat(f64, data) catch {
            return php_value_create_bool(false);
        };
        return php_value_create_bool(true);
    }
    return php_value_create_bool(false);
}

/// is_string - Check if value is string
pub fn php_builtin_is_string(val: Value) Value {
    return php_value_create_bool(nanbox.isString(val));
}

/// is_array - Check if value is array
pub fn php_builtin_is_array(val: Value) Value {
    return php_value_create_bool(nanbox.isArray(val));
}

/// is_object - Check if value is object
pub fn php_builtin_is_object(val: Value) Value {
    return php_value_create_bool(nanbox.isObject(val));
}

/// is_callable - Check if value is callable
pub fn php_builtin_is_callable(val: Value) Value {
    _ = val;
    return php_value_create_bool(false);
}

/// empty - Check if value is empty
pub fn php_builtin_empty(val: Value) Value {
    return php_value_create_bool(!valueIsTruthy(val));
}

/// isset - Check if value is set and not null
pub fn php_builtin_isset(val: Value) Value {
    return php_value_create_bool(!nanbox.isNull(val));
}

/// intval - Get integer value
pub fn php_builtin_intval(val: Value) Value {
    return php_value_create_int(php_value_to_int(val));
}

/// floatval / doubleval - Get float value
pub fn php_builtin_floatval(val: Value) Value {
    return php_value_create_float(php_value_to_float(val));
}

/// strval - Get string value
pub fn php_builtin_strval(val: Value) Value {
    return php_value_to_string(val);
}

/// boolval - Get boolean value
pub fn php_builtin_boolval(val: Value) Value {
    return php_value_create_bool(valueIsTruthy(val));
}

/// abs - Absolute value
pub fn php_builtin_abs(val: Value) Value {
    if (nanbox.isInt(val)) {
        const i = nanbox.decodeInt(val);
        return php_value_create_int(if (i < 0) -i else i);
    }
    if (nanbox.isFloat(val)) {
        return php_value_create_float(@abs(nanbox.decodeFloat(val)));
    }
    const num = php_value_to_float(val);
    return php_value_create_float(@abs(num));
}

/// min - Find minimum value
pub fn php_builtin_min(args: []const Value) Value {
    if (args.len == 0) return nanbox.encodeNull();
    if (args.len == 1 and nanbox.isArray(args[0])) {
        const arr = getArrayPtr(args[0]);
        var min_val: ?Value = null;
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
        return nanbox.encodeNull();
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
pub fn php_builtin_max(args: []const Value) Value {
    if (args.len == 0) return nanbox.encodeNull();
    if (args.len == 1 and nanbox.isArray(args[0])) {
        const arr = getArrayPtr(args[0]);
        var max_val: ?Value = null;
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
        return nanbox.encodeNull();
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
pub fn php_builtin_floor(val: Value) Value {
    const f = php_value_to_float(val);
    return php_value_create_float(@floor(f));
}

/// ceil - Round up
pub fn php_builtin_ceil(val: Value) Value {
    const f = php_value_to_float(val);
    return php_value_create_float(@ceil(f));
}

/// round - Round to nearest
pub fn php_builtin_round(val: Value, precision: i64) Value {
    const f = php_value_to_float(val);
    if (precision == 0) {
        return php_value_create_float(@round(f));
    }
    const multiplier = std.math.pow(f64, 10.0, @floatFromInt(precision));
    return php_value_create_float(@round(f * multiplier) / multiplier);
}

// ============================================================================
// Arithmetic & Comparison Operators
// ============================================================================

/// Check if a value can be used in arithmetic operations.
fn checkArithmeticOperand(val: Value) bool {
    if (nanbox.isNull(val) or nanbox.isBool(val) or nanbox.isInt(val) or nanbox.isFloat(val)) return true;
    if (nanbox.isString(val)) {
        const str = getStringPtr(val);
        _ = parseIntFromString(str.getData()) catch {
            _ = parseFloatFromString(str.getData()) catch return false;
        };
        return true;
    }
    if (nanbox.isArray(val)) return true;
    if (nanbox.isObject(val)) return true;
    return false;
}

/// Addition (PHP semantics): int+int stays int (overflow → float), otherwise float.
pub fn php_add(lhs: Value, rhs: Value) !Value {
    if (nanbox.isArray(lhs) and nanbox.isArray(rhs)) {
        return php_array_union(lhs, rhs);
    }
    if (nanbox.isInt(lhs) and nanbox.isInt(rhs)) {
        const a = nanbox.decodeInt(lhs);
        const b = nanbox.decodeInt(rhs);
        const result = @addWithOverflow(a, b);
        if (result[1] != 0) {
            return php_value_create_float(@as(f64, @floatFromInt(a)) + @as(f64, @floatFromInt(b)));
        }
        return php_value_create_int(result[0]);
    }
    const a = php_value_to_float(lhs);
    const b = php_value_to_float(rhs);
    return php_value_create_float(a + b);
}

/// Subtraction (PHP semantics).
pub fn php_sub(lhs: Value, rhs: Value) !Value {
    if (nanbox.isInt(lhs) and nanbox.isInt(rhs)) {
        const a = nanbox.decodeInt(lhs);
        const b = nanbox.decodeInt(rhs);
        const result = @subWithOverflow(a, b);
        if (result[1] != 0) {
            return php_value_create_float(@as(f64, @floatFromInt(a)) - @as(f64, @floatFromInt(b)));
        }
        return php_value_create_int(result[0]);
    }
    const a = php_value_to_float(lhs);
    const b = php_value_to_float(rhs);
    return php_value_create_float(a - b);
}

/// Unary negation.
pub fn php_neg(val: Value) !Value {
    if (nanbox.isInt(val)) {
        const a = nanbox.decodeInt(val);
        return php_value_create_int(-a);
    }
    return php_value_create_float(-php_value_to_float(val));
}

/// Multiplication (PHP semantics).
pub fn php_mul(lhs: Value, rhs: Value) !Value {
    if (nanbox.isInt(lhs) and nanbox.isInt(rhs)) {
        const a = nanbox.decodeInt(lhs);
        const b = nanbox.decodeInt(rhs);
        const result = @mulWithOverflow(a, b);
        if (result[1] != 0) {
            return php_value_create_float(@as(f64, @floatFromInt(a)) * @as(f64, @floatFromInt(b)));
        }
        return php_value_create_int(result[0]);
    }
    const a = php_value_to_float(lhs);
    const b = php_value_to_float(rhs);
    return php_value_create_float(a * b);
}

/// Division (PHP semantics).
pub fn php_div(lhs: Value, rhs: Value) !Value {
    const lhs_is_int = nanbox.isInt(lhs) or nanbox.isNull(lhs) or nanbox.isBool(lhs);
    const rhs_is_int = nanbox.isInt(rhs) or nanbox.isNull(rhs) or nanbox.isBool(rhs);

    if (lhs_is_int and rhs_is_int) {
        const a = php_value_to_int(lhs);
        const b = php_value_to_int(rhs);
        if (b == 0) {
            php_throw_message("Division by zero");
            return error.RuntimeError;
        }
        if (@mod(a, b) == 0) {
            const result = @divTrunc(a, b);
            return php_value_create_int(result);
        }
    }

    const a = php_value_to_float(lhs);
    const b = php_value_to_float(rhs);
    if (b == 0.0) {
        php_throw_message("Division by zero");
        return error.RuntimeError;
    }
    return php_value_create_float(a / b);
}

/// Modulo (PHP semantics).
pub fn php_mod(lhs: Value, rhs: Value) !Value {
    const a = php_value_to_int(lhs);
    const b = php_value_to_int(rhs);
    if (b == 0) {
        php_throw_message("Modulo by zero");
        return error.RuntimeError;
    }
    return php_value_create_int(@mod(a, b));
}

/// Power (PHP semantics).
pub fn php_pow(base: Value, exp: Value) !Value {
    if (nanbox.isInt(base) and nanbox.isInt(exp) and php_value_to_int(exp) >= 0) {
        const a_i = php_value_to_int(base);
        const b_i = php_value_to_int(exp);
        var result: i64 = 1;
        var i: i64 = 0;
        while (i < b_i) : (i += 1) {
            const ovf = @mulWithOverflow(result, a_i);
            if (ovf[1] != 0) {
                break;
            }
            result = ovf[0];
        }
        if (i == b_i) {
            return php_value_create_int(result);
        }
    }
    const a = php_value_to_float(base);
    const b = php_value_to_float(exp);
    return php_value_create_float(std.math.pow(f64, a, b));
}

/// Concatenation (the `.` operator in PHP).
pub fn php_concat(lhs: Value, rhs: Value, allocator: Allocator) !Value {
    _ = allocator;
    return php_string_concat(lhs, rhs);
}

/// Concatenation with undefined variable handling (for AOT uninitialized var warnings).
pub fn php_concat_with_undef(lhs: Value, rhs: Value, lhs_undef: bool, lhs_name: []const u8, rhs_undef: bool, rhs_name: []const u8, allocator: Allocator) !Value {
    _ = lhs_undef;
    _ = lhs_name;
    _ = rhs_undef;
    _ = rhs_name;
    return php_concat(lhs, rhs, allocator);
}

/// Equality (==) with PHP type juggling.
pub fn php_eq(lhs: Value, rhs: Value) !Value {
    if (nanbox.isNull(lhs) and nanbox.isNull(rhs)) return php_value_create_bool(true);
    if (nanbox.isNull(lhs) or nanbox.isNull(rhs)) return php_value_create_bool(false);

    if (nanbox.isBool(lhs) or nanbox.isBool(rhs)) {
        return php_value_create_bool(valueIsTruthy(lhs) == valueIsTruthy(rhs));
    }

    if ((nanbox.isInt(lhs) or nanbox.isFloat(lhs)) and (nanbox.isInt(rhs) or nanbox.isFloat(rhs))) {
        return php_value_create_bool(php_value_to_float(lhs) == php_value_to_float(rhs));
    }
    if ((nanbox.isInt(lhs) or nanbox.isFloat(lhs)) and nanbox.isString(rhs)) {
        const f = parseFloatFromString(getStringPtr(rhs).getData()) catch return php_value_create_bool(false);
        return php_value_create_bool(php_value_to_float(lhs) == f);
    }
    if (nanbox.isString(lhs) and (nanbox.isInt(rhs) or nanbox.isFloat(rhs))) {
        const f = parseFloatFromString(getStringPtr(lhs).getData()) catch return php_value_create_bool(false);
        return php_value_create_bool(f == php_value_to_float(rhs));
    }

    if (nanbox.isString(lhs) and nanbox.isString(rhs)) {
        return php_value_create_bool(getStringPtr(lhs).eql(getStringPtr(rhs)));
    }

    if (nanbox.isArray(lhs) and nanbox.isArray(rhs)) {
        return php_value_create_bool(lhs == rhs);
    }

    return php_value_create_bool(valueIsTruthy(lhs) == valueIsTruthy(rhs));
}

/// Not equal (!=) with PHP type juggling.
pub fn php_ne(lhs: Value, rhs: Value) !Value {
    const eq_result = try php_eq(lhs, rhs);
    return php_value_create_bool(!nanbox.decodeBool(eq_result));
}

/// Strict equality (===).
pub fn php_identical(lhs: Value, rhs: Value) !Value {
    // For simple types, identity is bit-exact equality
    if (nanbox.isNull(lhs) or nanbox.isNull(rhs)) {
        return php_value_create_bool(nanbox.isNull(lhs) and nanbox.isNull(rhs));
    }
    if (nanbox.isBool(lhs) or nanbox.isBool(rhs)) {
        if (!nanbox.isBool(lhs) or !nanbox.isBool(rhs)) return php_value_create_bool(false);
        return php_value_create_bool(nanbox.decodeBool(lhs) == nanbox.decodeBool(rhs));
    }
    if (nanbox.isInt(lhs) or nanbox.isInt(rhs)) {
        if (!nanbox.isInt(lhs) or !nanbox.isInt(rhs)) return php_value_create_bool(false);
        return php_value_create_bool(nanbox.decodeInt(lhs) == nanbox.decodeInt(rhs));
    }
    if (nanbox.isFloat(lhs) or nanbox.isFloat(rhs)) {
        if (!nanbox.isFloat(lhs) or !nanbox.isFloat(rhs)) return php_value_create_bool(false);
        return php_value_create_bool(nanbox.decodeFloat(lhs) == nanbox.decodeFloat(rhs));
    }
    if (nanbox.isString(lhs) or nanbox.isString(rhs)) {
        if (!nanbox.isString(lhs) or !nanbox.isString(rhs)) return php_value_create_bool(false);
        return php_value_create_bool(getStringPtr(lhs).eql(getStringPtr(rhs)));
    }
    if (nanbox.isArray(lhs) or nanbox.isArray(rhs)) {
        if (!nanbox.isArray(lhs) or !nanbox.isArray(rhs)) return php_value_create_bool(false);
        return php_value_create_bool(getArrayPtr(lhs) == getArrayPtr(rhs));
    }
    if (nanbox.isObject(lhs) or nanbox.isObject(rhs)) {
        if (!nanbox.isObject(lhs) or !nanbox.isObject(rhs)) return php_value_create_bool(false);
        return php_value_create_bool(getObjectPtr(lhs) == getObjectPtr(rhs));
    }
    return php_value_create_bool(false);
}

/// Strict not equal (!==).
pub fn php_not_identical(lhs: Value, rhs: Value) !Value {
    const result = try php_identical(lhs, rhs);
    return php_value_create_bool(!nanbox.decodeBool(result));
}

/// Less than (<).
pub fn php_lt(lhs: Value, rhs: Value) !Value {
    if ((nanbox.isInt(lhs) or nanbox.isFloat(lhs)) and (nanbox.isInt(rhs) or nanbox.isFloat(rhs))) {
        return php_value_create_bool(php_value_to_float(lhs) < php_value_to_float(rhs));
    }
    const str_a = php_value_to_string(lhs);
    defer gcReleaseValue(str_a);
    const str_b = php_value_to_string(rhs);
    defer gcReleaseValue(str_b);
    return php_value_create_bool(getStringPtr(str_a).compare(getStringPtr(str_b)) == .lt);
}

/// Less than or equal (<=).
pub fn php_le(lhs: Value, rhs: Value) !Value {
    if ((nanbox.isInt(lhs) or nanbox.isFloat(lhs)) and (nanbox.isInt(rhs) or nanbox.isFloat(rhs))) {
        return php_value_create_bool(php_value_to_float(lhs) <= php_value_to_float(rhs));
    }
    const str_a = php_value_to_string(lhs);
    defer gcReleaseValue(str_a);
    const str_b = php_value_to_string(rhs);
    defer gcReleaseValue(str_b);
    const ord = getStringPtr(str_a).compare(getStringPtr(str_b));
    return php_value_create_bool(ord == .lt or ord == .eq);
}

/// Greater than (>).
pub fn php_gt(lhs: Value, rhs: Value) !Value {
    if ((nanbox.isInt(lhs) or nanbox.isFloat(lhs)) and (nanbox.isInt(rhs) or nanbox.isFloat(rhs))) {
        return php_value_create_bool(php_value_to_float(lhs) > php_value_to_float(rhs));
    }
    const str_a = php_value_to_string(lhs);
    defer gcReleaseValue(str_a);
    const str_b = php_value_to_string(rhs);
    defer gcReleaseValue(str_b);
    return php_value_create_bool(getStringPtr(str_a).compare(getStringPtr(str_b)) == .gt);
}

/// Greater than or equal (>=).
pub fn php_ge(lhs: Value, rhs: Value) !Value {
    if ((nanbox.isInt(lhs) or nanbox.isFloat(lhs)) and (nanbox.isInt(rhs) or nanbox.isFloat(rhs))) {
        return php_value_create_bool(php_value_to_float(lhs) >= php_value_to_float(rhs));
    }
    const str_a = php_value_to_string(lhs);
    defer gcReleaseValue(str_a);
    const str_b = php_value_to_string(rhs);
    defer gcReleaseValue(str_b);
    const ord = getStringPtr(str_a).compare(getStringPtr(str_b));
    return php_value_create_bool(ord == .gt or ord == .eq);
}

/// Spaceship operator (<=>).
pub fn php_spaceship(lhs: Value, rhs: Value) !Value {
    if ((nanbox.isInt(lhs) or nanbox.isFloat(lhs)) and (nanbox.isInt(rhs) or nanbox.isFloat(rhs))) {
        return php_value_create_int(@intFromEnum(std.math.order(php_value_to_float(lhs), php_value_to_float(rhs))));
    }
    const str_a = php_value_to_string(lhs);
    defer gcReleaseValue(str_a);
    const str_b = php_value_to_string(rhs);
    defer gcReleaseValue(str_b);
    return php_value_create_int(@intFromEnum(getStringPtr(str_a).compare(getStringPtr(str_b))));
}

/// Bitwise AND (&).
pub fn php_and(lhs: Value, rhs: Value) !Value {
    return php_value_create_int(php_value_to_int(lhs) & php_value_to_int(rhs));
}

/// Bitwise OR (|).
pub fn php_or(lhs: Value, rhs: Value) !Value {
    return php_value_create_int(php_value_to_int(lhs) | php_value_to_int(rhs));
}

/// Bitwise XOR (^).
pub fn php_xor(lhs: Value, rhs: Value) !Value {
    return php_value_create_int(php_value_to_int(lhs) ^ php_value_to_int(rhs));
}

/// Boolean OR (or keyword).
pub fn php_bool_or(lhs: Value, rhs: Value) Value {
    return php_value_create_bool(valueIsTruthy(lhs) or valueIsTruthy(rhs));
}

/// Logical XOR.
pub fn php_logical_xor(lhs: Value, rhs: Value) !Value {
    return php_value_create_bool(valueIsTruthy(lhs) != valueIsTruthy(rhs));
}

/// Array union ($a + $b): left-preferring merge.
pub fn php_array_union(lhs: Value, rhs: Value) !Value {
    if (!nanbox.isArray(lhs) or !nanbox.isArray(rhs)) {
        return php_throw_message("Unsupported operand types for +");
    }
    const lhs_arr = getArrayPtr(lhs);
    const rhs_arr = getArrayPtr(rhs);

    const result = php_value_create_array();
    if (!nanbox.isArray(result)) return result;
    const result_arr = getArrayPtr(result);

    var entry = lhs_arr.first;
    while (entry) |e| {
        gcRetainValue(e.value);
        result_arr.set(e.key, e.value) catch {};
        entry = e.next_order;
    }

    entry = rhs_arr.first;
    while (entry) |e| {
        if (!result_arr.keyExists(e.key)) {
            gcRetainValue(e.value);
            result_arr.set(e.key, e.value) catch {};
        }
        entry = e.next_order;
    }

    return result;
}

/// pow() function (aliased as php_pow_func).
pub fn php_pow_func(base: Value, exponent: Value) !Value {
    return php_pow(base, exponent);
}

/// addslashes() function.
pub fn php_addslashes(str: Value, allocator: Allocator) !Value {
    if (!nanbox.isString(str)) {
        return php_value_to_string(str);
    }
    const s = getStringPtr(str);
    var result_buf = std.ArrayList(u8).init(allocator);
    defer result_buf.deinit();

    for (s.data[0..s.length]) |c| {
        switch (c) {
            '\'', '"', '\\' => try result_buf.appendSlice(&[_]u8{ '\\', c }),
            0 => try result_buf.appendSlice("\\0"),
            else => try result_buf.append(c),
        }
    }
    return php_value_create_string(result_buf.items);
}

/// Check if a value represents an "undefined variable" access.
/// In the NaN-boxed world, undefined is represented as a special null-like pattern.
pub fn php_is_undefined(val: Value) bool {
    return nanbox.isNull(val);
}

// ============================================================================
// Helper Functions for Output
// ============================================================================

/// Dump value with type information (for var_dump)
fn dumpValue(writer: anytype, val: Value, indent: usize) !void {
    const indent_str = "  ";

    for (0..indent) |_| {
        try writer.writeAll(indent_str);
    }

    if (nanbox.isNull(val)) {
        try writer.writeAll("NULL\n");
    } else if (nanbox.isBool(val)) {
        try writer.writeAll("bool(");
        try writer.writeAll(if (nanbox.decodeBool(val)) "true" else "false");
        try writer.writeAll(")\n");
    } else if (nanbox.isInt(val)) {
        try writer.print("int({d})\n", .{nanbox.decodeInt(val)});
    } else if (nanbox.isFloat(val)) {
        try writer.print("float({d})\n", .{nanbox.decodeFloat(val)});
    } else if (nanbox.isString(val)) {
        const str = getStringPtr(val);
        try writer.print("string({d}) \"{s}\"\n", .{ str.length, str.data[0..str.length] });
    } else if (nanbox.isArray(val)) {
        const arr = getArrayPtr(val);
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
    } else if (nanbox.isObject(val)) {
        const obj = getObjectPtr(val);
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
        try writer.writeAll("unknown\n");
    }
}

/// Print value in human-readable format (for print_r)
fn printValue(writer: anytype, val: Value, indent: usize) !void {
    const indent_str = "    ";

    if (nanbox.isNull(val)) {
        try writer.writeAll("");
    } else if (nanbox.isBool(val)) {
        try writer.writeAll(if (nanbox.decodeBool(val)) "1" else "");
    } else if (nanbox.isInt(val)) {
        try writer.print("{d}", .{nanbox.decodeInt(val)});
    } else if (nanbox.isFloat(val)) {
        try writer.print("{d}", .{nanbox.decodeFloat(val)});
    } else if (nanbox.isString(val)) {
        const str = getStringPtr(val);
        try writer.writeAll(str.data[0..str.length]);
    } else if (nanbox.isArray(val)) {
        try writer.writeAll("Array\n");
        for (0..indent) |_| {
            try writer.writeAll(indent_str);
        }
        try writer.writeAll("(\n");
        const arr = getArrayPtr(val);
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
        for (0..indent) |_| {
            try writer.writeAll(indent_str);
        }
        try writer.writeAll(")\n");
    } else if (nanbox.isObject(val)) {
        const obj = getObjectPtr(val);
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
    } else {
        try writer.writeAll("unknown");
    }
}

/// Export value as parsable PHP code (for var_export)
fn exportValue(writer: anytype, val: Value) !void {
    if (nanbox.isNull(val)) {
        try writer.writeAll("NULL");
    } else if (nanbox.isBool(val)) {
        try writer.writeAll(if (nanbox.decodeBool(val)) "true" else "false");
    } else if (nanbox.isInt(val)) {
        try writer.print("{d}", .{nanbox.decodeInt(val)});
    } else if (nanbox.isFloat(val)) {
        try writer.print("{d}", .{nanbox.decodeFloat(val)});
    } else if (nanbox.isString(val)) {
        const str = getStringPtr(val);
        try writer.writeAll("'");
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
    } else if (nanbox.isArray(val)) {
        try writer.writeAll("array (\n");
        const arr = getArrayPtr(val);
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
        try writer.writeAll(")");
    } else if (nanbox.isObject(val)) {
        const obj = getObjectPtr(val);
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
    } else {
        try writer.writeAll("NULL");
    }
}

/// Compare two values (for min/max)
fn compareValues(a: Value, b: Value) std.math.Order {
    if ((nanbox.isInt(a) or nanbox.isFloat(a)) and (nanbox.isInt(b) or nanbox.isFloat(b))) {
        const fa = php_value_to_float(a);
        const fb = php_value_to_float(b);
        return std.math.order(fa, fb);
    }

    if (nanbox.isString(a) and nanbox.isString(b)) {
        const sa = getStringPtr(a);
        const sb = getStringPtr(b);
        return sa.compare(sb);
    }

    const fa = php_value_to_float(a);
    const fb = php_value_to_float(b);
    return std.math.order(fa, fb);
}

// ============================================================================
// Exception Handling Runtime
// ============================================================================

/// Stack frame for exception stack trace
pub const StackFrame = struct {
    function_name: []const u8,
    file_name: []const u8,
    line: u32,
    column: u32,
    class_name: ?[]const u8,
    next: ?*StackFrame,
};

/// Exception state
pub const ExceptionState = struct {
    current_exception: Value,
    message: ?[]const u8,
    code: i64,
    stack_trace: ?*StackFrame,
    previous: ?*ExceptionState,
};

/// Thread-local exception state
var exception_state: ExceptionState = .{
    .current_exception = nanbox.encodeNull(),
    .message = null,
    .code = 0,
    .stack_trace = null,
    .previous = null,
};

/// Throw an exception
pub fn php_throw(exception: Value) void {
    exception_state.current_exception = exception;
    gcRetainValue(exception);

    if (nanbox.isObject(exception)) {
        const obj = getObjectPtr(exception);
        const allocator = getGlobalAllocator();
        const msg_key = PHPString.init(allocator, "message") catch return;
        defer msg_key.deinit(allocator);

        const msg_val = obj.getProperty(msg_key);
        if (nanbox.isString(msg_val)) {
            const str = getStringPtr(msg_val);
            exception_state.message = str.getData();
        }
    } else if (nanbox.isString(exception)) {
        const str = getStringPtr(exception);
        exception_state.message = str.getData();
    }
}

/// Throw an exception with message
pub fn php_throw_message(message: []const u8) void {
    const exception = php_value_create_string(message);
    php_throw(exception);
    gcReleaseValue(exception);
}

/// Throw a typed exception
pub fn php_throw_exception(class_name: []const u8, message: []const u8, code: i64) void {
    const allocator = getGlobalAllocator();

    const exception = php_value_create_object(class_name);
    if (nanbox.isObject(exception)) {
        const obj = getObjectPtr(exception);
        const msg_key = PHPString.init(allocator, "message") catch return;
        const msg_val = php_value_create_string(message);
        obj.setProperty(msg_key, msg_val) catch {};

        const code_key = PHPString.init(allocator, "code") catch return;
        const code_val = php_value_create_int(code);
        obj.setProperty(code_key, code_val) catch {};
    }

    exception_state.code = code;
    php_throw(exception);
}

/// Catch the current exception
pub fn php_catch() Value {
    const ex = exception_state.current_exception;
    exception_state.current_exception = nanbox.encodeNull();
    exception_state.message = null;
    exception_state.code = 0;
    return ex;
}

/// Catch exception of specific type
pub fn php_catch_type(class_name: []const u8) Value {
    if (!nanbox.isNull(exception_state.current_exception)) {
        const ex = exception_state.current_exception;
        if (nanbox.isObject(ex)) {
            const obj = getObjectPtr(ex);
            if (std.mem.eql(u8, obj.class_name, class_name)) {
                return php_catch();
            }
        }
    }
    return nanbox.encodeNull();
}

/// Check if there's a pending exception
pub fn php_has_exception() bool {
    return !nanbox.isNull(exception_state.current_exception);
}

/// Get current exception without clearing it
pub fn php_get_exception() Value {
    return exception_state.current_exception;
}

/// Clear current exception without returning it
pub fn php_clear_exception() void {
    if (!nanbox.isNull(exception_state.current_exception)) {
        gcReleaseValue(exception_state.current_exception);
    }
    exception_state.current_exception = nanbox.encodeNull();
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
pub fn php_get_stack_trace() Value {
    const result = php_value_create_array();
    if (!nanbox.isArray(result)) return result;
    const arr = getArrayPtr(result);

    var frame = exception_state.stack_trace;
    while (frame) |f| {
        const frame_arr = php_value_create_array();
        if (nanbox.isArray(frame_arr)) {
            const fa = getArrayPtr(frame_arr);
            const func_key = php_value_create_string("function");
            const func_val = php_value_create_string(f.function_name);
            php_array_set(fa, func_key, func_val);

            const file_key = php_value_create_string("file");
            const file_val = php_value_create_string(f.file_name);
            php_array_set(fa, file_key, file_val);

            const line_key = php_value_create_string("line");
            const line_val = php_value_create_int(@intCast(f.line));
            php_array_set(fa, line_key, line_val);

            if (f.class_name) |cn| {
                const class_key = php_value_create_string("class");
                const class_val = php_value_create_string(cn);
                php_array_set(fa, class_key, class_val);
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
    if (!nanbox.isNull(exception_state.current_exception)) {
        const ex = exception_state.current_exception;
        const stderr = std.io.getStdErr().writer();

        stderr.writeAll("\nFatal error: Uncaught ") catch {};

        if (nanbox.isObject(ex)) {
            const obj = getObjectPtr(ex);
            stderr.print("{s}", .{obj.class_name}) catch {};
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
pub fn php_rethrow() void {}

/// Create a new Exception object
pub fn php_create_exception(class_name: []const u8, message: []const u8, code: i64, previous: Value) Value {
    const allocator = getGlobalAllocator();

    const exception = php_value_create_object(class_name);
    if (nanbox.isObject(exception)) {
        const obj = getObjectPtr(exception);
        const msg_key = PHPString.init(allocator, "message") catch return exception;
        const msg_val = php_value_create_string(message);
        obj.setProperty(msg_key, msg_val) catch {};

        const code_key = PHPString.init(allocator, "code") catch return exception;
        const code_val = php_value_create_int(code);
        obj.setProperty(code_key, code_val) catch {};

        if (!nanbox.isNull(previous)) {
            const prev_key = PHPString.init(allocator, "previous") catch return exception;
            gcRetainValue(previous);
            obj.setProperty(prev_key, previous) catch {};
        }

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
    mutex: std.Thread.Mutex,
    ref_count: u32,

    pub fn init() PHPMutex {
        return .{
            .mutex = .{},
            .ref_count = 1,
        };
    }

    pub fn lock(self: *PHPMutex) void {
        self.mutex.lock();
    }

    pub fn unlock(self: *PHPMutex) void {
        self.mutex.unlock();
    }

    pub fn tryLock(self: *PHPMutex) bool {
        return self.mutex.tryLock();
    }
};

var global_mutex: ?*PHPMutex = null;

fn getGlobalMutex() *PHPMutex {
    if (global_mutex == null) {
        const allocator = getGlobalAllocator();
        global_mutex = allocator.create(PHPMutex) catch {
            const static = struct {
                var mutex: PHPMutex = PHPMutex.init();
            };
            return &static.mutex;
        };
        global_mutex.?.* = PHPMutex.init();
    }
    return global_mutex.?;
}

pub fn php_mutex_new() *PHPMutex {
    const allocator = getGlobalAllocator();
    const mutex = allocator.create(PHPMutex) catch {
        return getGlobalMutex();
    };
    mutex.* = PHPMutex.init();
    return mutex;
}

pub fn php_mutex_lock() void {
    const mutex = getGlobalMutex();
    mutex.lock();
}

pub fn php_mutex_unlock() void {
    const mutex = getGlobalMutex();
    mutex.unlock();
}

pub fn php_mutex_lock_ptr(mutex: *PHPMutex) void {
    mutex.lock();
}

pub fn php_mutex_unlock_ptr(mutex: *PHPMutex) void {
    mutex.unlock();
}

pub fn php_mutex_trylock_ptr(mutex: *PHPMutex) bool {
    return mutex.tryLock();
}

pub fn php_mutex_retain(mutex: *PHPMutex) void {
    mutex.ref_count += 1;
}

pub fn php_mutex_release(mutex: *PHPMutex) void {
    if (mutex.ref_count == 0) return;
    mutex.ref_count -= 1;
    if (mutex.ref_count == 0) {
        if (mutex == global_mutex) return;
        const allocator = getGlobalAllocator();
        allocator.destroy(mutex);
    }
}

// ============================================================================
// Array Iterator Support for foreach
// ============================================================================

/// Array iterator state
pub const PHPArrayIterator = struct {
    array: *PHPArray,
    current: ?*ArrayEntry,
    is_done: bool,

    pub fn init(array: *PHPArray) PHPArrayIterator {
        return .{
            .array = array,
            .current = array.first,
            .is_done = array.first == null,
        };
    }
};

/// Initialize array iterator
export fn php_array_iter_init(val: Value) Value {
    const allocator = getGlobalAllocator();

    if (!nanbox.isArray(val)) {
        return nanbox.encodeNull();
    }

    const array = getArrayPtr(val);
    const iter = allocator.create(PHPArrayIterator) catch @panic("OOM");
    iter.* = PHPArrayIterator.init(array);

    return nanbox.encodePtr(@intFromPtr(iter), nanbox.TYPE_REF);
}

/// Check if iterator is valid
export fn php_array_iter_valid(iter_val: Value) Value {
    if (nanbox.getPtrType(iter_val) != nanbox.TYPE_REF) {
        return php_value_create_bool(false);
    }
    const iter: *PHPArrayIterator = @ptrFromInt(nanbox.decodePtr(iter_val));
    return php_value_create_bool(!iter.is_done);
}

/// Get current key
export fn php_array_iter_key(iter_val: Value) Value {
    if (nanbox.getPtrType(iter_val) != nanbox.TYPE_REF) {
        return nanbox.encodeNull();
    }
    const iter: *PHPArrayIterator = @ptrFromInt(nanbox.decodePtr(iter_val));

    if (iter.current) |entry| {
        return switch (entry.key) {
            .int => |i| php_value_create_int(i),
            .string => |s| php_value_create_string(s.getData()),
        };
    }

    return nanbox.encodeNull();
}

/// Get current value
export fn php_array_iter_value(iter_val: Value) Value {
    if (nanbox.getPtrType(iter_val) != nanbox.TYPE_REF) {
        return nanbox.encodeNull();
    }
    const iter: *PHPArrayIterator = @ptrFromInt(nanbox.decodePtr(iter_val));

    if (iter.current) |entry| {
        gcRetainValue(entry.value);
        return entry.value;
    }

    return nanbox.encodeNull();
}

/// Get current value by reference
export fn php_array_iter_value_ref(iter_val: Value) Value {
    return php_array_iter_value(iter_val);
}

/// Move to next element
export fn php_array_iter_next(iter_val: Value) Value {
    if (nanbox.getPtrType(iter_val) != nanbox.TYPE_REF) {
        return iter_val;
    }
    const iter: *PHPArrayIterator = @ptrFromInt(nanbox.decodePtr(iter_val));

    if (iter.current) |entry| {
        iter.current = entry.next_order;
        iter.is_done = iter.current == null;
    } else {
        iter.is_done = true;
    }

    return iter_val;
}

/// Free iterator
export fn php_array_iter_free(iter_val: Value) void {
    if (nanbox.getPtrType(iter_val) != nanbox.TYPE_REF) {
        return;
    }
    const allocator = getGlobalAllocator();
    const iter: *PHPArrayIterator = @ptrFromInt(nanbox.decodePtr(iter_val));
    allocator.destroy(iter);
    gcReleaseValue(iter_val);
}

// ============================================================================
// Math Functions (exported)
// ============================================================================

export fn php_round(value: Value, precision: Value) Value {
    const num = php_value_to_float(value);
    const prec = @as(i32, @intCast(php_value_to_int(precision)));
    const multiplier = std.math.pow(f64, 10.0, @as(f64, @floatFromInt(prec)));
    const rounded = @round(num * multiplier) / multiplier;
    return php_value_create_float(rounded);
}

// ============================================================================
// Time Functions
// ============================================================================

export fn php_microtime(get_as_float: Value) Value {
    const as_float = php_value_to_bool(get_as_float);
    const now = std.time.microTimestamp();

    if (as_float) {
        const seconds = @as(f64, @floatFromInt(now)) / 1_000_000.0;
        return php_value_create_float(seconds);
    }

    const sec = @divFloor(now, 1_000_000);
    const usec = @mod(now, 1_000_000);
    const allocator = getGlobalAllocator();
    const str = std.fmt.allocPrint(allocator, "0.{d:0>6} {d}", .{ usec, sec }) catch return nanbox.encodeNull();
    return php_value_create_string(str);
}

export fn php_date(format: Value, timestamp: Value) Value {
    _ = format;
    const ts = if (nanbox.isNull(timestamp)) std.time.timestamp() else php_value_to_int(timestamp);

    const allocator = getGlobalAllocator();
    const epoch_seconds: u64 = @intCast(ts);

    const days_since_epoch = epoch_seconds / 86400;
    const year = 1970 + @divFloor(days_since_epoch, 365);
    const month: u8 = 1;
    const day: u8 = 1;

    const result = std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}", .{ year, month, day }) catch return nanbox.encodeNull();

    return php_value_create_string(result);
}

export fn php_strtotime(time_str: Value, now: Value) Value {
    _ = time_str;
    _ = now;
    return php_value_create_int(std.time.timestamp());
}

// ============================================================================
// Constant Functions
// ============================================================================

pub var constants_map: ?std.StringHashMap(Value) = null;

export fn php_define(name: Value, value: Value) Value {
    const allocator = getGlobalAllocator();

    if (constants_map == null) {
        constants_map = std.StringHashMap(Value).init(allocator);
    }

    if (!nanbox.isString(name)) {
        return php_value_create_bool(false);
    }

    const name_str = getStringPtr(name);
    const name_copy = allocator.dupe(u8, name_str.getData()) catch return php_value_create_bool(false);

    gcRetainValue(value);
    constants_map.?.put(name_copy, value) catch return php_value_create_bool(false);

    return php_value_create_bool(true);
}

export fn php_constant(name: Value) Value {
    if (constants_map == null) {
        return nanbox.encodeNull();
    }

    if (!nanbox.isString(name)) {
        return nanbox.encodeNull();
    }

    const name_str = getStringPtr(name);
    if (constants_map.?.get(name_str.getData())) |val| {
        gcRetainValue(val);
        return val;
    }

    return nanbox.encodeNull();
}

/// count() - count array elements
pub fn php_count(arr: Value, mode: Value) Value {
    const mode_int = if (nanbox.isInt(mode)) nanbox.decodeInt(mode) else 0;

    if (!nanbox.isArray(arr)) {
        return php_value_create_int(0);
    }

    const arr_ptr = getArrayPtr(arr);

    if (mode_int == 1) {
        return php_value_create_int(@intCast(countRecursive(arr_ptr)));
    }

    return php_value_create_int(@intCast(arr_ptr.count()));
}

fn countRecursive(arr: *PHPArray) usize {
    var total: usize = arr.count();

    var entry = arr.first;
    while (entry) |e| {
        if (nanbox.isArray(e.value)) {
            const child = getArrayPtr(e.value);
            total += countRecursive(child);
        }
        entry = e.next_order;
    }

    return total;
}

// ============================================================================
// Unit Tests
// ============================================================================

test "Value creation - null" {
    initRuntime(std.testing.allocator);
    defer deinitRuntime();

    const val = php_value_create_null();
    try std.testing.expect(nanbox.isNull(val));
    try std.testing.expect(!valueIsTruthy(val));
}

test "Value creation - bool" {
    initRuntime(std.testing.allocator);
    defer deinitRuntime();

    const val_true = php_value_create_bool(true);
    const val_false = php_value_create_bool(false);

    try std.testing.expect(nanbox.isBool(val_true));
    try std.testing.expect(nanbox.decodeBool(val_true));
    try std.testing.expect(valueIsTruthy(val_true));

    try std.testing.expect(nanbox.isBool(val_false));
    try std.testing.expect(!nanbox.decodeBool(val_false));
    try std.testing.expect(!valueIsTruthy(val_false));
}

test "Value creation - int" {
    initRuntime(std.testing.allocator);
    defer deinitRuntime();

    const val = php_value_create_int(42);
    try std.testing.expect(nanbox.isInt(val));
    try std.testing.expectEqual(@as(i64, 42), nanbox.decodeInt(val));
    try std.testing.expect(valueIsTruthy(val));

    const zero = php_value_create_int(0);
    try std.testing.expect(!valueIsTruthy(zero));
}

test "Value creation - float" {
    initRuntime(std.testing.allocator);
    defer deinitRuntime();

    const val = php_value_create_float(3.14);
    try std.testing.expect(nanbox.isFloat(val));
    try std.testing.expectApproxEqAbs(@as(f64, 3.14), nanbox.decodeFloat(val), 0.001);
    try std.testing.expect(valueIsTruthy(val));
}

test "Value creation - string" {
    initRuntime(std.testing.allocator);
    defer deinitRuntime();

    const val = php_value_create_string("hello");
    defer gcReleaseValue(val);

    try std.testing.expect(nanbox.isString(val));
    try std.testing.expectEqualStrings("hello", getStringPtr(val).getData());
    try std.testing.expect(valueIsTruthy(val));

    const empty = php_value_create_string("");
    defer gcReleaseValue(empty);
    try std.testing.expect(!valueIsTruthy(empty));

    const zero_str = php_value_create_string("0");
    defer gcReleaseValue(zero_str);
    try std.testing.expect(!valueIsTruthy(zero_str));
}

test "Value creation - array" {
    initRuntime(std.testing.allocator);
    defer deinitRuntime();

    const val = php_value_create_array();
    defer gcReleaseValue(val);

    try std.testing.expect(nanbox.isArray(val));
    try std.testing.expectEqual(@as(usize, 0), getArrayPtr(val).count());
    try std.testing.expect(!valueIsTruthy(val));
}

test "NaN-boxing roundtrip - integer" {
    for ([_]i64{ 0, 1, -1, 42, -42, 0x7FFFFFFFFFFF, -0x800000000000 }) |i| {
        const encoded = nanbox.encodeInt(i);
        try std.testing.expect(nanbox.isInt(encoded));
        try std.testing.expectEqual(i, nanbox.decodeInt(encoded));
        // Verify it's NOT a float
        try std.testing.expect(!nanbox.isFloat(encoded));
    }
}

test "NaN-boxing roundtrip - float" {
    const test_values = [_]f64{ 0.0, -0.0, 1.0, -1.0, 3.14159, std.math.inf(f64), -std.math.inf(f64), 1e308, 1e-308 };
    for (test_values) |f| {
        const encoded = nanbox.encodeFloat(f);
        try std.testing.expect(nanbox.isFloat(encoded));
        const decoded = nanbox.decodeFloat(encoded);
        if (std.math.isNan(f)) {
            try std.testing.expect(std.math.isNan(decoded));
        } else {
            try std.testing.expectEqual(f, decoded);
        }
    }
    // NaN canonicalization
    const nan_val = nanbox.encodeFloat(std.math.nan(f64));
    try std.testing.expect(nanbox.isFloat(nan_val));
    try std.testing.expect(std.math.isNan(nanbox.decodeFloat(nan_val)));
}

test "NaN-boxing roundtrip - null/bool" {
    const null_val = nanbox.encodeNull();
    try std.testing.expect(nanbox.isNull(null_val));
    try std.testing.expect(!nanbox.isBool(null_val));

    const true_val = nanbox.encodeBool(true);
    try std.testing.expect(nanbox.isBool(true_val));
    try std.testing.expect(nanbox.decodeBool(true_val));

    const false_val = nanbox.encodeBool(false);
    try std.testing.expect(nanbox.isBool(false_val));
    try std.testing.expect(!nanbox.decodeBool(false_val));
}

test "NaN-boxing roundtrip - pointer types" {
    // Verify pointer encoding/decoding
    const test_addr: usize = 0x7FFFFFFFFFFF;
    const encoded_str = nanbox.encodePtr(test_addr, nanbox.TYPE_STRING);
    try std.testing.expect(nanbox.isString(encoded_str));
    try std.testing.expectEqual(test_addr, nanbox.decodePtr(encoded_str));

    const encoded_arr = nanbox.encodePtr(test_addr, nanbox.TYPE_ARRAY);
    try std.testing.expect(nanbox.isArray(encoded_arr));
    try std.testing.expectEqual(test_addr, nanbox.decodePtr(encoded_arr));

    const encoded_obj = nanbox.encodePtr(test_addr, nanbox.TYPE_OBJECT);
    try std.testing.expect(nanbox.isObject(encoded_obj));
    try std.testing.expectEqual(test_addr, nanbox.decodePtr(encoded_obj));
}

test "Type conversion - toInt" {
    initRuntime(std.testing.allocator);
    defer deinitRuntime();

    try std.testing.expectEqual(@as(i64, 0), php_value_to_int(php_value_create_null()));

    try std.testing.expectEqual(@as(i64, 1), php_value_to_int(php_value_create_bool(true)));

    try std.testing.expectEqual(@as(i64, 3), php_value_to_int(php_value_create_float(3.7)));

    const str_val = php_value_create_string("42");
    defer gcReleaseValue(str_val);
    try std.testing.expectEqual(@as(i64, 42), php_value_to_int(str_val));
}

test "Type conversion - toFloat" {
    initRuntime(std.testing.allocator);
    defer deinitRuntime();

    try std.testing.expectApproxEqAbs(@as(f64, 42.0), php_value_to_float(php_value_create_int(42)), 0.001);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), php_value_to_float(php_value_create_bool(true)), 0.001);
}

test "Type conversion - toBool" {
    initRuntime(std.testing.allocator);
    defer deinitRuntime();

    try std.testing.expect(!php_value_to_bool(php_value_create_int(0)));
    try std.testing.expect(php_value_to_bool(php_value_create_int(1)));

    const str_empty = php_value_create_string("");
    defer gcReleaseValue(str_empty);
    try std.testing.expect(!php_value_to_bool(str_empty));

    const str_nonempty = php_value_create_string("hello");
    defer gcReleaseValue(str_nonempty);
    try std.testing.expect(php_value_to_bool(str_nonempty));
}

test "Reference counting" {
    initRuntime(std.testing.allocator);
    defer deinitRuntime();

    const val = php_value_create_string("test");
    try std.testing.expectEqual(@as(u32, 1), php_gc_get_ref_count(val));

    php_gc_retain(val);
    try std.testing.expectEqual(@as(u32, 2), php_gc_get_ref_count(val));

    php_gc_retain(val);
    try std.testing.expectEqual(@as(u32, 3), php_gc_get_ref_count(val));

    php_gc_release(val);
    try std.testing.expectEqual(@as(u32, 2), php_gc_get_ref_count(val));

    php_gc_release(val);
    try std.testing.expectEqual(@as(u32, 1), php_gc_get_ref_count(val));

    php_gc_release(val);
    // Value should be freed now
}

test "Array operations" {
    initRuntime(std.testing.allocator);
    defer deinitRuntime();

    const arr_val = php_value_create_array();
    defer gcReleaseValue(arr_val);
    const arr = getArrayPtr(arr_val);

    const val1 = php_value_create_int(10);
    php_array_push(arr, val1);

    const val2 = php_value_create_int(20);
    php_array_push(arr, val2);

    const val3 = php_value_create_string("hello");
    defer gcReleaseValue(val3);
    php_array_push(arr, val3);

    try std.testing.expectEqual(@as(i64, 3), php_array_count(arr));

    const got1 = php_array_get_int(arr, 0);
    try std.testing.expectEqual(@as(i64, 10), nanbox.decodeInt(got1));

    const got2 = php_array_get_int(arr, 1);
    try std.testing.expectEqual(@as(i64, 20), nanbox.decodeInt(got2));

    try std.testing.expect(php_array_key_exists_int(arr, 0));
    try std.testing.expect(php_array_key_exists_int(arr, 1));
    try std.testing.expect(!php_array_key_exists_int(arr, 10));
}

test "String operations" {
    initRuntime(std.testing.allocator);
    defer deinitRuntime();

    const str1 = php_value_create_string("Hello");
    defer gcReleaseValue(str1);
    const str2 = php_value_create_string(" World");
    defer gcReleaseValue(str2);

    const concat = php_string_concat(str1, str2);
    defer gcReleaseValue(concat);
    try std.testing.expectEqualStrings("Hello World", getStringPtr(concat).getData());

    try std.testing.expectEqual(@as(i64, 5), php_string_length(str1));
    try std.testing.expectEqual(@as(i64, 6), php_string_length(str2));
    try std.testing.expectEqual(@as(i64, 11), php_string_length(concat));
}

test "String substr" {
    initRuntime(std.testing.allocator);
    defer deinitRuntime();

    const str = php_value_create_string("Hello World");
    defer gcReleaseValue(str);

    const sub1 = php_string_substr(str, 0, 5);
    defer gcReleaseValue(sub1);
    try std.testing.expectEqualStrings("Hello", getStringPtr(sub1).getData());

    const sub2 = php_string_substr(str, 6, null);
    defer gcReleaseValue(sub2);
    try std.testing.expectEqualStrings("World", getStringPtr(sub2).getData());

    const sub3 = php_string_substr(str, -5, null);
    defer gcReleaseValue(sub3);
    try std.testing.expectEqualStrings("World", getStringPtr(sub3).getData());
}

test "Built-in functions - strlen" {
    initRuntime(std.testing.allocator);
    defer deinitRuntime();

    const str = php_value_create_string("Hello");
    defer gcReleaseValue(str);

    const len = php_builtin_strlen(str);
    try std.testing.expect(nanbox.isInt(len));
    try std.testing.expectEqual(@as(i64, 5), nanbox.decodeInt(len));
}

test "Built-in functions - count" {
    initRuntime(std.testing.allocator);
    defer deinitRuntime();

    const arr_val = php_value_create_array();
    defer gcReleaseValue(arr_val);
    const arr = getArrayPtr(arr_val);

    php_array_push(arr, php_value_create_int(1));
    php_array_push(arr, php_value_create_int(2));
    php_array_push(arr, php_value_create_int(3));

    const count = php_builtin_count(arr_val);
    try std.testing.expect(nanbox.isInt(count));
    try std.testing.expectEqual(@as(i64, 3), nanbox.decodeInt(count));
}

test "Built-in functions - type checking" {
    initRuntime(std.testing.allocator);
    defer deinitRuntime();

    const null_val = php_value_create_null();
    const int_val = php_value_create_int(42);
    const str_val = php_value_create_string("hello");
    defer gcReleaseValue(str_val);
    const arr_val = php_value_create_array();
    defer gcReleaseValue(arr_val);

    const is_null_result = php_builtin_is_null(null_val);
    try std.testing.expect(nanbox.decodeBool(is_null_result));

    const is_int_result = php_builtin_is_int(int_val);
    try std.testing.expect(nanbox.decodeBool(is_int_result));

    const is_string_result = php_builtin_is_string(str_val);
    try std.testing.expect(nanbox.decodeBool(is_string_result));

    const is_array_result = php_builtin_is_array(arr_val);
    try std.testing.expect(nanbox.decodeBool(is_array_result));
}

test "Exception handling" {
    initRuntime(std.testing.allocator);
    defer deinitRuntime();

    try std.testing.expect(!php_has_exception());

    php_throw_message("Test error");
    try std.testing.expect(php_has_exception());

    const msg = php_get_exception_message();
    try std.testing.expect(msg != null);
    try std.testing.expectEqualStrings("Test error", msg.?);

    const ex = php_catch();
    try std.testing.expect(!nanbox.isNull(ex));
    try std.testing.expect(!php_has_exception());

    gcReleaseValue(ex);
}

test "Value cloning" {
    initRuntime(std.testing.allocator);
    defer deinitRuntime();

    const int_val = php_value_create_int(42);
    const int_clone = php_value_clone(int_val);
    try std.testing.expectEqual(@as(i64, 42), nanbox.decodeInt(int_clone));
    try std.testing.expectEqual(int_val, int_clone);
}

test "Math functions" {
    initRuntime(std.testing.allocator);
    defer deinitRuntime();

    const neg = php_value_create_int(-42);
    const abs_result = php_builtin_abs(neg);
    try std.testing.expectEqual(@as(i64, 42), nanbox.decodeInt(abs_result));

    const float_val = php_value_create_float(3.7);
    const floor_result = php_builtin_floor(float_val);
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), nanbox.decodeFloat(floor_result), 0.001);

    const ceil_result = php_builtin_ceil(float_val);
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), nanbox.decodeFloat(ceil_result), 0.001);
}

test "NaN-boxing identity for simple types" {
    // Simple types should have identity equality (same u64 bits)
    try std.testing.expectEqual(php_value_create_null(), php_value_create_null());
    try std.testing.expectEqual(php_value_create_bool(true), php_value_create_bool(true));
    try std.testing.expectEqual(php_value_create_bool(false), php_value_create_bool(false));
    try std.testing.expectEqual(php_value_create_int(42), php_value_create_int(42));
    try std.testing.expectEqual(php_value_create_float(3.14), php_value_create_float(3.14));
}

test "Int encoding edge cases" {
    // Max positive 48-bit int
    try std.testing.expectEqual(@as(i64, 0x7FFFFFFFFFFF), nanbox.decodeInt(nanbox.encodeInt(0x7FFFFFFFFFFF)));
    // Min negative 48-bit int
    try std.testing.expectEqual(@as(i64, -0x800000000000), nanbox.decodeInt(nanbox.encodeInt(-0x800000000000)));
    // Zero
    try std.testing.expectEqual(@as(i64, 0), nanbox.decodeInt(nanbox.encodeInt(0)));
}