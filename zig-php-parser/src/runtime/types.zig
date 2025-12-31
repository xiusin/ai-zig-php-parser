const std = @import("std");
pub const gc = @import("gc.zig");

// Import NumberWrapper from separate module
pub const number_wrapper = @import("number_wrapper.zig");

// Forward declarations
pub const PHPString = struct {
    data: []u8,
    length: usize,
    encoding: Encoding,
    ref_count: usize,

    pub const Encoding = enum {
        utf8,
        ascii,
        binary,
    };

    pub fn init(allocator: std.mem.Allocator, str: []const u8) !*PHPString {
        const php_string = try allocator.create(PHPString);
        php_string.data = try allocator.dupe(u8, str);
        php_string.length = str.len;
        php_string.encoding = .utf8; // Default to UTF-8
        php_string.ref_count = 1;
        return php_string;
    }

    pub fn retain(self: *PHPString) void {
        self.ref_count += 1;
    }

    pub fn release(self: *PHPString, allocator: std.mem.Allocator) void {
        self.ref_count -= 1;
        if (self.ref_count == 0) {
            self.deinit(allocator);
        }
    }

    pub fn deinit(self: *PHPString, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
        allocator.destroy(self);
    }

    pub fn concat(self: *PHPString, other: *PHPString, allocator: std.mem.Allocator) !*PHPString {
        const new_data = try allocator.alloc(u8, self.length + other.length);
        @memcpy(new_data[0..self.length], self.data);
        @memcpy(new_data[self.length..], other.data);

        const result = try allocator.create(PHPString);
        result.data = new_data;
        result.length = self.length + other.length;
        result.encoding = self.encoding; // Use first string's encoding
        return result;
    }

    pub fn substring(self: *PHPString, start: i64, length: ?i64, allocator: std.mem.Allocator) !*PHPString {
        const start_idx: usize = if (start < 0) 0 else @intCast(start);
        if (start_idx >= self.length) {
            return PHPString.init(allocator, "");
        }

        const end_idx: usize = if (length) |len| blk: {
            const end = start_idx + @as(usize, @intCast(@max(0, len)));
            break :blk @min(end, self.length);
        } else self.length;

        if (start_idx >= end_idx) {
            return PHPString.init(allocator, "");
        }

        return PHPString.init(allocator, self.data[start_idx..end_idx]);
    }

    pub fn indexOf(self: *PHPString, needle: *PHPString) i64 {
        if (needle.length == 0) return 0;
        if (needle.length > self.length) return -1;

        for (0..self.length - needle.length + 1) |i| {
            if (std.mem.eql(u8, self.data[i .. i + needle.length], needle.data)) {
                return @intCast(i);
            }
        }
        return -1;
    }

    pub fn replace(self: *PHPString, search: *PHPString, replacement: *PHPString, allocator: std.mem.Allocator) !*PHPString {
        if (search.length == 0) {
            return PHPString.init(allocator, self.data);
        }

        var result = std.ArrayListUnmanaged(u8){};
        defer result.deinit(allocator);

        var i: usize = 0;
        while (i < self.length) {
            if (i + search.length <= self.length and
                std.mem.eql(u8, self.data[i .. i + search.length], search.data))
            {
                try result.appendSlice(allocator, replacement.data);
                i += search.length;
            } else {
                try result.append(allocator, self.data[i]);
                i += 1;
            }
        }

        return PHPString.init(allocator, result.items);
    }
};

pub const ArrayKey = union(enum) {
    integer: i64,
    string: *PHPString,

    pub fn hash(self: ArrayKey) u32 {
        return switch (self) {
            .integer => |i| @truncate(std.hash.Wyhash.hash(0, std.mem.asBytes(&i))),
            .string => |s| @truncate(std.hash.Wyhash.hash(0, s.data)),
        };
    }

    pub fn eql(self: ArrayKey, other: ArrayKey) bool {
        return switch (self) {
            .integer => |a| switch (other) {
                .integer => |b| a == b,
                else => false,
            },
            .string => |a| switch (other) {
                .string => |b| std.mem.eql(u8, a.data, b.data),
                else => false,
            },
        };
    }
};

pub const PHPArray = struct {
    elements: std.ArrayHashMap(ArrayKey, Value, ArrayContext, false),
    next_index: i64,

    pub const ArrayContext = struct {
        pub fn hash(_: ArrayContext, key: ArrayKey) u32 {
            return key.hash();
        }

        pub fn eql(_: ArrayContext, a: ArrayKey, b: ArrayKey, _: usize) bool {
            return a.eql(b);
        }
    };

    pub fn init(allocator: std.mem.Allocator) PHPArray {
        return PHPArray{
            .elements = std.ArrayHashMap(ArrayKey, Value, ArrayContext, false).initContext(allocator, .{}),
            .next_index = 0,
        };
    }

    pub fn deinit(self: *PHPArray, allocator: std.mem.Allocator) void {
        var iterator = self.elements.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.release(allocator);
            // 释放字符串类型的键
            if (entry.key_ptr.* == .string) {
                entry.key_ptr.string.release(allocator);
            }
        }
        self.elements.deinit();
    }

    pub fn get(self: *PHPArray, key: ArrayKey) ?Value {
        return self.elements.get(key);
    }

    pub fn set(self: *PHPArray, allocator: std.mem.Allocator, key: ArrayKey, value: Value) !void {
        // Check if key already exists
        const key_exists = self.elements.get(key) != null;

        // If key already exists, release old value
        if (self.elements.get(key)) |old_value| {
            old_value.release(allocator);
        }

        // Retain new value
        _ = value.retain();

        // Only retain string key if it's a new key
        if (!key_exists and key == .string) {
            key.string.retain();
        }

        try self.elements.put(key, value);
    }

    pub fn push(self: *PHPArray, allocator: std.mem.Allocator, value: Value) !void {
        const key = ArrayKey{ .integer = self.next_index };
        try self.set(allocator, key, value);
        self.next_index += 1;
    }

    pub fn count(self: *PHPArray) usize {
        return self.elements.count();
    }

    pub fn keys(self: *PHPArray, allocator: std.mem.Allocator) ![]ArrayKey {
        var result = try allocator.alloc(ArrayKey, self.elements.count());
        var i: usize = 0;
        var iterator = self.elements.iterator();
        while (iterator.next()) |entry| {
            result[i] = entry.key_ptr.*;
            i += 1;
        }
        return result;
    }

    pub fn values(self: *PHPArray, allocator: std.mem.Allocator) ![]Value {
        var result = try allocator.alloc(Value, self.elements.count());
        var i: usize = 0;
        var iterator = self.elements.iterator();
        while (iterator.next()) |entry| {
            result[i] = entry.value_ptr.*;
            i += 1;
        }
        return result;
    }

    /// SoA批量整数提取，用于SIMD加速的数值计算
    pub fn extractIntegers(self: *PHPArray, allocator: std.mem.Allocator) ![]i64 {
        var result = try allocator.alloc(i64, self.elements.count());
        var i: usize = 0;
        var iterator = self.elements.iterator();
        while (iterator.next()) |entry| {
            result[i] = switch (entry.value_ptr.getTag()) {
                .integer => entry.value_ptr.asInt(),
                .float => @intFromFloat(entry.value_ptr.asFloat()),
                else => 0,
            };
            i += 1;
        }
        return result;
    }

    /// SoA批量浮点提取，用于SIMD加速的数值计算
    pub fn extractFloats(self: *PHPArray, allocator: std.mem.Allocator) ![]f64 {
        var result = try allocator.alloc(f64, self.elements.count());
        var i: usize = 0;
        var iterator = self.elements.iterator();
        while (iterator.next()) |entry| {
            result[i] = switch (entry.value_ptr.getTag()) {
                .float => entry.value_ptr.asFloat(),
                .integer => @floatFromInt(entry.value_ptr.asInt()),
                else => 0.0,
            };
            i += 1;
        }
        return result;
    }

    /// SoA批量求和优化
    pub fn sumIntegers(self: *PHPArray) i64 {
        var sum: i64 = 0;
        var iterator = self.elements.iterator();
        while (iterator.next()) |entry| {
            sum += switch (entry.value_ptr.getTag()) {
                .integer => entry.value_ptr.asInt(),
                .float => @intFromFloat(entry.value_ptr.asFloat()),
                else => 0,
            };
        }
        return sum;
    }

    /// SoA批量浮点求和优化
    pub fn sumFloats(self: *PHPArray) f64 {
        var sum: f64 = 0.0;
        var iterator = self.elements.iterator();
        while (iterator.next()) |entry| {
            sum += switch (entry.value_ptr.getTag()) {
                .float => entry.value_ptr.asFloat(),
                .integer => @floatFromInt(entry.value_ptr.asInt()),
                else => 0.0,
            };
        }
        return sum;
    }

    /// SoA批量最大值
    pub fn maxValue(self: *PHPArray) ?f64 {
        var max: ?f64 = null;
        var iterator = self.elements.iterator();
        while (iterator.next()) |entry| {
            const val: f64 = switch (entry.value_ptr.getTag()) {
                .float => entry.value_ptr.asFloat(),
                .integer => @floatFromInt(entry.value_ptr.asInt()),
                else => continue,
            };
            if (max == null or val > max.?) {
                max = val;
            }
        }
        return max;
    }

    /// SoA批量最小值
    pub fn minValue(self: *PHPArray) ?f64 {
        var min: ?f64 = null;
        var iterator = self.elements.iterator();
        while (iterator.next()) |entry| {
            const val: f64 = switch (entry.value_ptr.getTag()) {
                .float => entry.value_ptr.asFloat(),
                .integer => @floatFromInt(entry.value_ptr.asInt()),
                else => continue,
            };
            if (min == null or val < min.?) {
                min = val;
            }
        }
        return min;
    }

    /// 多维数组访问：$arr[0][1][2] 形式
    pub fn getMultiDim(self: *PHPArray, key_path: []const ArrayKey) ?Value {
        if (key_path.len == 0) return null;

        var current_value = self.get(key_path[0]) orelse return null;

        for (key_path[1..]) |key| {
            if (current_value.getTag() != .array) return null;
            const arr = current_value.getAsArray();
            current_value = arr.data.get(key) orelse return null;
        }

        return current_value;
    }

    /// 多维数组设置：$arr[0][1][2] = $value
    pub fn setMultiDim(self: *PHPArray, allocator: std.mem.Allocator, key_path: []const ArrayKey, value: Value) !void {
        if (key_path.len == 0) return;
        if (key_path.len == 1) {
            try self.set(allocator, key_path[0], value);
            return;
        }

        // 获取或创建中间数组
        var current_arr = self;
        for (key_path[0 .. key_path.len - 1]) |key| {
            const existing = current_arr.get(key);
            if (existing) |v| {
                if (v.getTag() == .array) {
                    current_arr = v.getAsArray().data;
                } else {
                    // 替换为新数组
                    const new_arr = try allocator.create(PHPArray);
                    new_arr.* = PHPArray.init(allocator);
                    const box = try allocator.create(gc.Box(*PHPArray));
                    box.* = .{ .ref_count = 1, .gc_info = .{}, .data = new_arr };
                    try current_arr.set(allocator, key, Value.fromBox(box, Value.TYPE_ARRAY));
                    current_arr = new_arr;
                }
            } else {
                // 创建新数组
                const new_arr = try allocator.create(PHPArray);
                new_arr.* = PHPArray.init(allocator);
                const box = try allocator.create(gc.Box(*PHPArray));
                box.* = .{ .ref_count = 1, .gc_info = .{}, .data = new_arr };
                try current_arr.set(allocator, key, Value.fromBox(box, Value.TYPE_ARRAY));
                current_arr = new_arr;
            }
        }

        try current_arr.set(allocator, key_path[key_path.len - 1], value);
    }

    /// 检查多维数组键是否存在
    pub fn hasMultiDim(self: *PHPArray, key_path: []const ArrayKey) bool {
        return self.getMultiDim(key_path) != null;
    }

    /// 删除多维数组元素
    pub fn removeMultiDim(self: *PHPArray, allocator: std.mem.Allocator, key_path: []const ArrayKey) bool {
        if (key_path.len == 0) return false;
        if (key_path.len == 1) {
            if (self.elements.fetchRemove(key_path[0])) |kv| {
                kv.value.release(allocator);
                return true;
            }
            return false;
        }

        // 导航到父数组
        var current_value = self.get(key_path[0]) orelse return false;
        for (key_path[1 .. key_path.len - 1]) |key| {
            if (current_value.getTag() != .array) return false;
            current_value = current_value.getAsArray().data.get(key) orelse return false;
        }

        if (current_value.getTag() != .array) return false;
        const parent_arr = current_value.getAsArray().data;
        if (parent_arr.elements.fetchRemove(key_path[key_path.len - 1])) |kv| {
            kv.value.release(allocator);
            return true;
        }
        return false;
    }

    pub fn getIterator(self: *PHPArray) @TypeOf(self.elements.iterator()) {
        return self.elements.iterator();
    }
};

/// ArrayAccess 接口实现
pub const ArrayAccess = struct {
    /// offsetExists - 检查偏移是否存在
    offset_exists: ?*const fn (*anyopaque, Value) bool,
    /// offsetGet - 获取偏移值
    offset_get: ?*const fn (*anyopaque, Value) ?Value,
    /// offsetSet - 设置偏移值
    offset_set: ?*const fn (*anyopaque, Value, Value) anyerror!void,
    /// offsetUnset - 删除偏移
    offset_unset: ?*const fn (*anyopaque, Value) void,
    /// 实现对象的指针
    impl: *anyopaque,

    pub fn init() ArrayAccess {
        return ArrayAccess{
            .offset_exists = null,
            .offset_get = null,
            .offset_set = null,
            .offset_unset = null,
            .impl = undefined,
        };
    }

    pub fn offsetExists(self: *ArrayAccess, offset: Value) bool {
        if (self.offset_exists) |func| {
            return func(self.impl, offset);
        }
        return false;
    }

    pub fn offsetGet(self: *ArrayAccess, offset: Value) ?Value {
        if (self.offset_get) |func| {
            return func(self.impl, offset);
        }
        return null;
    }

    pub fn offsetSet(self: *ArrayAccess, offset: Value, value: Value) !void {
        if (self.offset_set) |func| {
            try func(self.impl, offset, value);
        }
    }

    pub fn offsetUnset(self: *ArrayAccess, offset: Value) void {
        if (self.offset_unset) |func| {
            func(self.impl, offset);
        }
    }
};

pub const PHPInterface = struct {
    name: *PHPString,
    methods: std.StringHashMap(Method),
    constants: std.StringHashMap(Value),
    extends: []const *PHPInterface,

    pub fn init(allocator: std.mem.Allocator, name: *PHPString) PHPInterface {
        name.retain();
        return PHPInterface{
            .name = name,
            .methods = std.StringHashMap(Method).init(allocator),
            .constants = std.StringHashMap(Value).init(allocator),
            .extends = &[_]*PHPInterface{},
        };
    }

    pub fn deinit(self: *PHPInterface, allocator: std.mem.Allocator) void {
        self.name.release(allocator);
        var method_iter = self.methods.iterator();
        while (method_iter.next()) |entry| {
            entry.value_ptr.deinit(allocator);
        }
        self.methods.deinit();
        self.constants.deinit();
    }
};

pub const PHPTrait = struct {
    name: *PHPString,
    properties: std.StringHashMap(Property),
    methods: std.StringHashMap(Method),

    pub fn init(allocator: std.mem.Allocator, name: *PHPString) PHPTrait {
        name.retain();
        return PHPTrait{
            .name = name,
            .properties = std.StringHashMap(Property).init(allocator),
            .methods = std.StringHashMap(Method).init(allocator),
        };
    }

    pub fn deinit(self: *PHPTrait, allocator: std.mem.Allocator) void {
        self.name.release(allocator);
        var prop_iter = self.properties.iterator();
        while (prop_iter.next()) |entry| {
            entry.value_ptr.name.release(allocator);
            if (entry.value_ptr.default_value) |val| {
                val.release(allocator);
            }
        }
        self.properties.deinit();
        var method_iter = self.methods.iterator();
        while (method_iter.next()) |entry| {
            entry.value_ptr.deinit(allocator);
        }
        self.methods.deinit();
    }
};

pub const Attribute = struct {
    name: *PHPString,
    arguments: []const Value,
    target: AttributeTarget,
    class_definition: ?*PHPClass, // Reference to the attribute class if it's a user-defined attribute

    pub const AttributeTarget = packed struct {
        class: bool = false,
        method: bool = false,
        property: bool = false,
        parameter: bool = false,
        function: bool = false,
        constant: bool = false,
        all: bool = false, // For attributes that can be applied to any target
    };

    pub fn init(name: *PHPString, arguments: []const Value, target: AttributeTarget) Attribute {
        return Attribute{
            .name = name,
            .arguments = arguments,
            .target = target,
            .class_definition = null,
        };
    }

    pub fn initWithClass(name: *PHPString, arguments: []const Value, target: AttributeTarget, class_def: *PHPClass) Attribute {
        return Attribute{
            .name = name,
            .arguments = arguments,
            .target = target,
            .class_definition = class_def,
        };
    }

    pub fn canBeAppliedTo(self: *const Attribute, target_type: AttributeTargetType) bool {
        if (self.target.all) return true;

        return switch (target_type) {
            .class => self.target.class,
            .method => self.target.method,
            .property => self.target.property,
            .parameter => self.target.parameter,
            .function => self.target.function,
            .constant => self.target.constant,
        };
    }

    pub fn instantiate(self: *const Attribute, allocator: std.mem.Allocator) !*PHPObject {
        if (self.class_definition) |class_def| {
            const object = try allocator.create(PHPObject);
            object.* = try PHPObject.init(allocator, class_def);

            // Call constructor with arguments if it exists
            if (class_def.hasMethod("__construct")) {
                // Would call constructor with self.arguments here
                // For now, just initialize with default values
            }

            return object;
        }

        // For built-in attributes, create a simple object representation
        const builtin_class_name = try PHPString.init(allocator, self.name.data);
        var builtin_class = try PHPClass.init(allocator, builtin_class_name);

        const object = try allocator.create(PHPObject);
        object.* = try PHPObject.init(allocator, &builtin_class);

        return object;
    }

    pub const AttributeTargetType = enum {
        class,
        method,
        property,
        parameter,
        function,
        constant,
    };
};

pub const PHPClass = struct {
    name: *PHPString,
    parent: ?*PHPClass,
    interfaces: []const *PHPInterface,
    traits: []const *PHPTrait,
    properties: std.StringHashMap(Property),
    methods: std.StringHashMap(Method),
    constants: std.StringHashMap(Value),
    modifiers: ClassModifiers,
    attributes: []const Attribute,
    native_destructor: ?*const fn (*anyopaque, std.mem.Allocator) void,
    shape: *Shape,

    pub const ClassModifiers = packed struct {
        is_abstract: bool = false,
        is_final: bool = false,
        is_readonly: bool = false,
    };

    pub fn init(allocator: std.mem.Allocator, name: *PHPString) !PHPClass {
        name.retain();
        const shape = try allocator.create(Shape);
        shape.* = Shape.init(allocator, Shape.next_id, null);
        Shape.next_id += 1;
        return PHPClass{
            .name = name,
            .parent = null,
            .interfaces = &[_]*PHPInterface{},
            .traits = &[_]*PHPTrait{},
            .properties = std.StringHashMap(Property).init(allocator),
            .methods = std.StringHashMap(Method).init(allocator),
            .constants = std.StringHashMap(Value).init(allocator),
            .modifiers = .{},
            .attributes = &[_]Attribute{},
            .native_destructor = null,
            .shape = shape,
        };
    }

    pub fn deinit(self: *PHPClass, allocator: std.mem.Allocator) void {
        self.name.release(allocator);
        if (self.interfaces.len > 0) {
            allocator.free(self.interfaces);
        }

        // 释放所有属性
        var prop_iter = self.properties.iterator();
        while (prop_iter.next()) |entry| {
            entry.value_ptr.name.release(allocator);
            if (entry.value_ptr.default_value) |val| {
                // Here we need to release the value using the same logic as Environment.releaseValue
                // But types.zig doesn't have access to VM's releaseValue.
                // However, Value has a release(allocator) method!
                val.release(allocator);
            }
        }
        self.properties.deinit();

        // 释放所有方法的名称
        var method_iter = self.methods.iterator();
        while (method_iter.next()) |entry| {
            entry.value_ptr.deinit(allocator);
        }
        self.methods.deinit();

        // 释放常量HashMap
        self.constants.deinit();

        // 释放shape
        self.shape.deinit();
        allocator.destroy(self.shape);
    }

    pub fn hasMethod(self: *PHPClass, name: []const u8) bool {
        // Check own methods
        if (self.methods.contains(name)) return true;

        // Check parent class
        if (self.parent) |parent| {
            if (parent.hasMethod(name)) return true;
        }

        // Check traits
        for (self.traits) |trait| {
            if (trait.methods.contains(name)) return true;
        }

        return false;
    }

    pub fn getMethod(self: *PHPClass, name: []const u8) ?*Method {
        // Check own methods first
        if (self.methods.getPtr(name)) |method| return method;

        // Check parent class
        if (self.parent) |parent| {
            if (parent.getMethod(name)) |method| return method;
        }

        // Check traits
        for (self.traits) |trait| {
            if (trait.methods.getPtr(name)) |method| return method;
        }

        return null;
    }

    pub fn hasProperty(self: *PHPClass, name: []const u8) bool {
        // Check own properties
        if (self.properties.contains(name)) return true;

        // Check parent class
        if (self.parent) |parent| {
            if (parent.hasProperty(name)) return true;
        }

        // Check traits
        for (self.traits) |trait| {
            if (trait.properties.contains(name)) return true;
        }

        return false;
    }

    pub fn getProperty(self: *PHPClass, name: []const u8) ?*Property {
        // Check own properties first
        if (self.properties.getPtr(name)) |property| return property;

        // Check parent class
        if (self.parent) |parent| {
            if (parent.getProperty(name)) |property| return property;
        }

        // Check traits
        for (self.traits) |trait| {
            if (trait.properties.getPtr(name)) |property| return property;
        }

        return null;
    }

    pub fn implementsInterface(self: *PHPClass, interface: *PHPInterface) bool {
        // Check direct implementation
        for (self.interfaces) |impl_interface| {
            if (impl_interface == interface) return true;
        }

        // Check parent class
        if (self.parent) |parent| {
            if (parent.implementsInterface(interface)) return true;
        }

        return false;
    }

    pub fn isInstanceOf(self: *PHPClass, other: *PHPClass) bool {
        if (self == other) return true;

        // Check parent chain
        if (self.parent) |parent| {
            return parent.isInstanceOf(other);
        }

        return false;
    }
};

pub const PHPStruct = struct {
    name: *PHPString,
    fields: std.StringHashMap(StructField),
    methods: std.StringHashMap(Method),
    embedded_structs: []const *PHPStruct,
    interfaces: []const *PHPInterface,
    type_info: StructTypeInfo,

    pub const StructField = struct {
        name: *PHPString,
        type: ?TypeInfo,
        default_value: ?Value,
        modifiers: Modifier,
        offset: usize, // Used for memory layout optimization
    };

    pub const StructTypeInfo = struct {
        is_value_type: bool,
        size: usize,
        alignment: usize,
        has_pointers: bool,
    };

    pub const Modifier = packed struct {
        is_public: bool = true, // Structs default to public
        is_protected: bool = false,
        is_private: bool = false,
        is_readonly: bool = false,
    };

    pub fn init(allocator: std.mem.Allocator, name: *PHPString) PHPStruct {
        name.retain();
        return PHPStruct{
            .name = name,
            .fields = std.StringHashMap(StructField).init(allocator),
            .methods = std.StringHashMap(Method).init(allocator),
            .embedded_structs = &[_]*PHPStruct{},
            .interfaces = &[_]*PHPInterface{},
            .type_info = StructTypeInfo{
                .is_value_type = true, // Default to value type
                .size = 0,
                .alignment = 1,
                .has_pointers = false,
            },
        };
    }

    pub fn deinit(self: *PHPStruct, allocator: std.mem.Allocator) void {
        self.name.release(allocator);

        var field_iter = self.fields.iterator();
        while (field_iter.next()) |entry| {
            entry.value_ptr.name.release(allocator);
            if (entry.value_ptr.default_value) |dv| {
                dv.release(allocator);
            }
        }
        self.fields.deinit();

        var method_iter = self.methods.iterator();
        while (method_iter.next()) |entry| {
            entry.value_ptr.deinit(allocator);
        }
        self.methods.deinit();
    }

    fn releaseValueIfManaged(value: Value, allocator: std.mem.Allocator) void {
        switch (value.getTag()) {
            .string => value.data.string.release(allocator),
            .array => value.data.array.release(allocator),
            .object => value.data.object.release(allocator),
            .struct_instance => value.data.struct_instance.release(allocator),
            .resource => value.data.resource.release(allocator),
            .user_function => value.data.user_function.release(allocator),
            .closure => value.data.closure.release(allocator),
            .arrow_function => value.data.arrow_function.release(allocator),
            else => {},
        }
    }

    pub fn addField(self: *PHPStruct, field: StructField) !void {
        try self.fields.put(field.name.data, field);
        self.updateTypeInfo();
    }

    pub fn addMethod(self: *PHPStruct, method: Method) !void {
        try self.methods.put(method.name.data, method);
    }

    pub fn hasField(self: *PHPStruct, name: []const u8) bool {
        // Check own fields
        if (self.fields.contains(name)) return true;

        // Check embedded structs
        for (self.embedded_structs) |embedded| {
            if (embedded.hasField(name)) return true;
        }

        return false;
    }

    pub fn getField(self: *PHPStruct, name: []const u8) ?*StructField {
        // Check own fields first
        if (self.fields.getPtr(name)) |field| return field;

        // Check embedded structs
        for (self.embedded_structs) |embedded| {
            if (embedded.getField(name)) |field| return field;
        }

        return null;
    }

    pub fn hasMethod(self: *PHPStruct, name: []const u8) bool {
        // Check own methods
        if (self.methods.contains(name)) return true;

        // Check embedded structs
        for (self.embedded_structs) |embedded| {
            if (embedded.hasMethod(name)) return true;
        }

        return false;
    }

    pub fn getMethod(self: *PHPStruct, name: []const u8) ?*Method {
        // Check own methods first
        if (self.methods.getPtr(name)) |method| return method;

        // Check embedded structs
        for (self.embedded_structs) |embedded| {
            if (embedded.getMethod(name)) |method| return method;
        }

        return null;
    }

    pub fn implementsInterface(self: *PHPStruct, interface: *PHPInterface) bool {
        // Check if explicitly implements interface
        for (self.interfaces) |impl_interface| {
            if (impl_interface == interface) return true;
        }

        // Check duck typing - if struct has all interface methods
        var method_iter = interface.methods.iterator();
        while (method_iter.next()) |entry| {
            if (!self.hasMethod(entry.key_ptr.*)) return false;
        }

        return true;
    }

    fn updateTypeInfo(self: *PHPStruct) void {
        var total_size: usize = 0;
        var has_pointers = false;

        var field_iter = self.fields.iterator();
        while (field_iter.next()) |entry| {
            const field = entry.value_ptr.*;
            // Simplified size calculation - would need proper type size calculation
            total_size += 8; // Assume 8 bytes per field for now

            if (field.type) |type_info| {
                switch (type_info.kind) {
                    .string, .array, .object, .struct_instance => has_pointers = true,
                    else => {},
                }
            }
        }

        // Add embedded struct sizes
        for (self.embedded_structs) |embedded| {
            total_size += embedded.type_info.size;
            if (embedded.type_info.has_pointers) has_pointers = true;
        }

        self.type_info.size = total_size;
        self.type_info.has_pointers = has_pointers;

        // Decide if value type or reference type
        const size_threshold = 64; // bytes
        self.type_info.is_value_type = total_size <= size_threshold and !has_pointers;
    }

    /// 判断是否可以栈分配（零开销值类型）
    pub fn canStackAllocate(self: *PHPStruct) bool {
        return self.type_info.is_value_type and self.type_info.size <= 64;
    }

    /// 获取字段偏移量用于内联缓存
    pub fn getFieldOffset(self: *PHPStruct, name: []const u8) ?usize {
        var offset: usize = 0;
        var field_iter = self.fields.iterator();
        while (field_iter.next()) |entry| {
            if (std.mem.eql(u8, entry.key_ptr.*, name)) {
                return offset;
            }
            offset += 8;
        }
        return null;
    }
};

/// 内联缓存条目，用于加速属性访问
pub const InlineCacheEntry = struct {
    shape_id: u32,
    offset: usize,
    hits: u32 = 0,

    pub fn init(shape_id: u32, offset: usize) InlineCacheEntry {
        return InlineCacheEntry{
            .shape_id = shape_id,
            .offset = offset,
            .hits = 0,
        };
    }

    pub fn recordHit(self: *InlineCacheEntry) void {
        self.hits +|= 1;
    }
};

/// 内联缓存表，用于字节码层属性访问优化
pub const InlineCache = struct {
    entries: std.AutoHashMap(u64, InlineCacheEntry),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) InlineCache {
        return InlineCache{
            .entries = std.AutoHashMap(u64, InlineCacheEntry).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *InlineCache) void {
        self.entries.deinit();
    }

    /// 生成缓存键：shape_id + property_name_hash
    fn makeCacheKey(shape_id: u32, property_name: []const u8) u64 {
        var hash: u64 = shape_id;
        for (property_name) |c| {
            hash = hash *% 31 +% c;
        }
        return hash;
    }

    /// 查找缓存条目
    pub fn lookup(self: *InlineCache, shape_id: u32, property_name: []const u8) ?*InlineCacheEntry {
        const key = makeCacheKey(shape_id, property_name);
        return self.entries.getPtr(key);
    }

    /// 添加缓存条目
    pub fn insert(self: *InlineCache, shape_id: u32, property_name: []const u8, offset: usize) !void {
        const key = makeCacheKey(shape_id, property_name);
        try self.entries.put(key, InlineCacheEntry.init(shape_id, offset));
    }

    /// 使缓存失效
    pub fn invalidate(self: *InlineCache, shape_id: u32) void {
        var to_remove = std.ArrayList(u64).init(self.allocator);
        defer to_remove.deinit();

        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.shape_id == shape_id) {
                to_remove.append(entry.key_ptr.*) catch {};
            }
        }

        for (to_remove.items) |key| {
            _ = self.entries.remove(key);
        }
    }
};

pub const StructInstance = struct {
    struct_type: *PHPStruct,
    fields: std.StringHashMap(Value),
    embedded_instances: []StructInstance,

    pub fn init(allocator: std.mem.Allocator, struct_type: *PHPStruct) StructInstance {
        return StructInstance{
            .struct_type = struct_type,
            .fields = std.StringHashMap(Value).init(allocator),
            .embedded_instances = &[_]StructInstance{},
        };
    }

    pub fn deinit(self: *StructInstance, allocator: std.mem.Allocator) void {
        var iterator = self.fields.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.release(allocator);
        }
        self.fields.deinit();
    }

    pub fn getField(self: *StructInstance, name: []const u8) !Value {
        // First check direct fields
        if (self.fields.get(name)) |value| {
            return value;
        }

        // Then check embedded struct fields
        for (self.embedded_instances) |*embedded| {
            if (embedded.getField(name)) |value| {
                return value;
            } else |_| {}
        }

        return error.FieldNotFound;
    }

    pub fn setField(self: *StructInstance, allocator: std.mem.Allocator, name: []const u8, value: Value) !void {
        if (self.fields.get(name)) |old_value| {
            old_value.release(allocator);
        }
        _ = value.retain();
        try self.fields.put(name, value);
    }

    pub fn callMethod(self: *StructInstance, vm: *anyopaque, instance_value: Value, name: []const u8, args: []const Value) !Value {
        // Find method in struct type
        if (self.struct_type.getMethod(name)) |method| {
            // Call VM method execution
            const VM = @import("vm.zig").VM;
            const vm_instance = @as(*VM, @ptrCast(@alignCast(vm)));

            // Create a call frame
            try vm_instance.pushCallFrame(name, vm_instance.current_file, vm_instance.current_line);
            defer vm_instance.popCallFrame();

            // Inject $this into the new call frame
            try vm_instance.setVariable("$this", instance_value);

            // Inject arguments into the new call frame
            for (method.parameters, 0..) |param, i| {
                if (i < args.len) {
                    try vm_instance.setVariable(param.name.data, args[i]);
                } else if (param.default_value) |default| {
                    try vm_instance.setVariable(param.name.data, default);
                }
            }

            // Execute body
            if (method.body) |body_ptr| {
                const ast = @import("../compiler/ast.zig");
                const body_node = @as(ast.Node.Index, @truncate(@intFromPtr(body_ptr)));
                return try vm_instance.run(body_node);
            }

            return Value.initNull();
        }

        return error.MethodNotFound;
    }
};

pub const PropertyHook = struct {
    type: HookType,
    body: ?*anyopaque, // Would be AST node reference in real implementation

    pub const HookType = enum { get, set };

    pub fn init(hook_type: HookType, body: ?*anyopaque) PropertyHook {
        return PropertyHook{
            .type = hook_type,
            .body = body,
        };
    }
};

pub const Property = struct {
    name: *PHPString,
    type: ?TypeInfo,
    default_value: ?Value,
    modifiers: PropertyModifiers,
    attributes: []const Attribute,
    hooks: []const PropertyHook, // PHP 8.4 Property Hooks

    pub const PropertyModifiers = struct {
        visibility: Visibility = .public,
        is_static: bool = false,
        is_readonly: bool = false,
        is_final: bool = false,
    };

    pub const Visibility = enum { public, protected, private };

    pub fn init(name: *PHPString) Property {
        name.retain();
        return Property{
            .name = name,
            .type = null,
            .default_value = null,
            .modifiers = .{},
            .attributes = &[_]Attribute{},
            .hooks = &[_]PropertyHook{},
        };
    }

    pub fn hasGetHook(self: *const Property) bool {
        for (self.hooks) |hook| {
            if (hook.type == .get) return true;
        }
        return false;
    }

    pub fn hasSetHook(self: *const Property) bool {
        for (self.hooks) |hook| {
            if (hook.type == .set) return true;
        }
        return false;
    }

    pub fn getGetHook(self: *const Property) ?PropertyHook {
        for (self.hooks) |hook| {
            if (hook.type == .get) return hook;
        }
        return null;
    }

    pub fn getSetHook(self: *const Property) ?PropertyHook {
        for (self.hooks) |hook| {
            if (hook.type == .set) return hook;
        }
        return null;
    }
};

pub const Method = struct {
    name: *PHPString,
    parameters: []const Parameter,
    return_type: ?TypeInfo,
    modifiers: MethodModifiers,
    attributes: []const Attribute,
    body: ?*anyopaque, // Would be AST node reference in real implementation

    pub const MethodModifiers = struct {
        visibility: Property.Visibility = .public,
        is_static: bool = false,
        is_final: bool = false,
        is_abstract: bool = false,
    };

    pub const Parameter = struct {
        name: *PHPString,
        type: ?TypeInfo,
        default_value: ?Value,
        is_variadic: bool = false,
        is_reference: bool = false,
        is_promoted: bool = false, // PHP 8.0 constructor property promotion
        modifiers: Property.PropertyModifiers,
        attributes: []const Attribute,

        pub fn init(name: *PHPString) Parameter {
            name.retain();
            return Parameter{
                .name = name,
                .type = null,
                .default_value = null,
                .is_variadic = false,
                .is_reference = false,
                .is_promoted = false,
                .modifiers = .{},
                .attributes = &[_]Attribute{},
            };
        }

        pub fn deinit(self: *Parameter, allocator: std.mem.Allocator) void {
            self.name.release(allocator);
            if (self.default_value) |dv| {
                dv.release(allocator);
            }
        }

        pub fn validateType(self: *const Parameter, value: Value) !void {
            if (self.type == null) return; // No type constraint

            const type_info = self.type.?;
            const type_name = type_info.name.data;

            // Basic type checking
            const is_valid = switch (value.getTag()) {
                .null => type_info.is_nullable,
                .boolean => std.mem.eql(u8, type_name, "bool") or std.mem.eql(u8, type_name, "boolean"),
                .integer => std.mem.eql(u8, type_name, "int") or std.mem.eql(u8, type_name, "integer"),
                .float => std.mem.eql(u8, type_name, "float") or std.mem.eql(u8, type_name, "double"),
                .string => std.mem.eql(u8, type_name, "string"),
                .array => std.mem.eql(u8, type_name, "array"),
                .object => std.mem.eql(u8, type_name, "object") or
                    std.mem.eql(u8, type_name, value.getAsObject().data.class.name.data),
                .struct_instance => std.mem.eql(u8, type_name, "struct") or
                    std.mem.eql(u8, type_name, value.getAsStruct().data.struct_type.name.data),
                .resource => std.mem.eql(u8, type_name, "resource"),
                .native_function, .user_function, .closure, .arrow_function => std.mem.eql(u8, type_name, "callable"),
            };

            if (!is_valid) {
                return error.TypeError;
            }
        }
    };

    pub fn init(name: *PHPString) Method {
        name.retain();
        return Method{
            .name = name,
            .parameters = &[_]Parameter{},
            .return_type = null,
            .modifiers = .{},
            .attributes = &[_]Attribute{},
            .body = null,
        };
    }

    pub fn deinit(self: *Method, allocator: std.mem.Allocator) void {
        self.name.release(allocator);
        // Parameters is []const Parameter, but we need to deinit each one
        // We'll create a mutable slice to iterate and deinit
        for (0..self.parameters.len) |i| {
            // Parameter.deinit takes *Parameter
            var param = self.parameters[i];
            param.deinit(allocator);
        }
        allocator.free(self.parameters);
        // Attributes cleanup...
    }

    pub fn isConstructor(self: *const Method) bool {
        return std.mem.eql(u8, self.name.data, "__construct");
    }

    pub fn isDestructor(self: *const Method) bool {
        return std.mem.eql(u8, self.name.data, "__destruct");
    }

    pub fn isMagicMethod(self: *const Method) bool {
        return self.name.length >= 2 and
            self.name.data[0] == '_' and
            self.name.data[1] == '_';
    }
};

pub const PHPObject = struct {
    class: *PHPClass,
    shape: *Shape,
    property_values: std.ArrayList(Value),
    native_data: ?*anyopaque = null,

    pub fn init(allocator: std.mem.Allocator, class: *PHPClass) !PHPObject {
        var obj = PHPObject{
            .class = class,
            .shape = class.shape,
            .property_values = try std.ArrayList(Value).initCapacity(allocator, class.shape.property_count),
            .native_data = null,
        };
        for (0..class.shape.property_count) |_| try obj.property_values.append(allocator, Value.initNull());
        return obj;
    }

    pub fn deinit(self: *PHPObject, allocator: std.mem.Allocator) void {
        // Release native data if destructor exists
        if (self.native_data) |data| {
            if (self.class.native_destructor) |destructor| {
                destructor(data, allocator);
            }
        }

        // Release all property values
        for (self.property_values.items) |*val| {
            val.release(allocator);
        }
        self.property_values.deinit(allocator);
    }

    pub fn getProperty(self: *PHPObject, name: []const u8) !Value {
        // Check shape for offset
        if (self.shape.getPropertyOffset(name)) |offset| {
            return self.property_values.items[offset];
        }

        // Check class property definition for default value
        if (self.class.getProperty(name)) |property| {
            // Check if property has get hook
            if (property.hasGetHook()) {
                // Would execute get hook here
                return property.default_value orelse Value.initNull();
            }

            return property.default_value orelse Value.initNull();
        }

        // Try magic __get method
        if (self.class.hasMethod("__get")) {
            return error.MagicMethodCall;
        }

        return error.UndefinedProperty;
    }

    pub fn setProperty(self: *PHPObject, allocator: std.mem.Allocator, name: []const u8, value: Value) !void {
        // Check if property exists in shape
        if (self.shape.getPropertyOffset(name)) |offset| {
            // Check if readonly
            if (self.class.getProperty(name)) |property| {
                if (property.modifiers.is_readonly) {
                    // Check if already set
                    if (!self.property_values.items[offset].isNull()) {
                        return error.ReadonlyPropertyModification;
                    }
                }

                // Check if property has set hook
                if (property.hasSetHook()) {
                    // Would execute set hook here
                    self.property_values.items[offset].release(allocator);
                    _ = value.retain();
                    self.property_values.items[offset] = value;
                    return;
                }
            }

            self.property_values.items[offset].release(allocator);
            _ = value.retain();
            self.property_values.items[offset] = value;
            return;
        }

        // Property not in shape, transition to new shape for dynamic property
        const new_shape = try self.shape.transition(allocator, Shape.next_id, name);
        Shape.next_id += 1;

        var new_values = try std.ArrayList(Value).initCapacity(allocator, new_shape.property_count);
        for (self.property_values.items) |val| {
            try new_values.append(allocator, val);
        }
        for (0..new_shape.property_count - self.property_values.items.len) |_| {
            try new_values.append(allocator, Value.initNull());
        }

        self.property_values.deinit(allocator);
        self.property_values = new_values;
        self.shape = new_shape;

        // Now set the new property
        const offset = self.shape.getPropertyOffset(name).?;
        self.property_values.items[offset].release(allocator);
        _ = value.retain();
        self.property_values.items[offset] = value;
    }

    pub fn hasProperty(self: *PHPObject, name: []const u8) bool {
        return self.shape.hasProperty(name);
    }

    pub fn callMethod(self: *PHPObject, vm: *anyopaque, instance_value: Value, name: []const u8, args: []const Value) !Value {
        const method = self.class.getMethod(name);
        if (method == null) {
            // Try magic __call method
            if (self.class.hasMethod("__call")) {
                return error.MagicMethodCall;
            }
            return error.UndefinedMethod;
        }

        const VM = @import("vm.zig").VM;
        const vm_instance = @as(*VM, @ptrCast(@alignCast(vm)));

        // Special handling for built-in classes with null method bodies
        if (method.?.body == null) {
            // Check if this is a built-in class method that should be handled specially
            const class_name = self.class.name.data;
            if (std.mem.eql(u8, class_name, "PDO")) {
                return vm_instance.callPDOMethod(instance_value, name, args);
            }
            if (std.mem.eql(u8, class_name, "Mutex") or std.mem.eql(u8, class_name, "Atomic") or
                std.mem.eql(u8, class_name, "RWLock") or std.mem.eql(u8, class_name, "SharedData") or
                std.mem.eql(u8, class_name, "Channel"))
            {
                return vm_instance.callConcurrencyMethod(instance_value, name, args);
            }
            // For other built-in classes, return not implemented for now
            return error.UndefinedMethod; // Built-in method not implemented
        }

        // Push call frame
        try vm_instance.pushCallFrame(name, vm_instance.current_file, vm_instance.current_line);
        defer vm_instance.popCallFrame();

        // Inject $this
        try vm_instance.setVariable("$this", instance_value);

        // Inject arguments
        for (method.?.parameters, 0..) |param, i| {
            if (i < args.len) {
                try vm_instance.setVariable(param.name.data, args[i]);
            } else if (param.default_value) |default| {
                try vm_instance.setVariable(param.name.data, default);
            }
        }

        // Set current class for 'self' resolution
        const old_class = vm_instance.current_class;
        vm_instance.current_class = self.class;
        defer vm_instance.current_class = old_class;

        // Execute body
        if (method.?.body) |body_ptr| {
            const ast = @import("../compiler/ast.zig");
            const body_node = @as(ast.Node.Index, @truncate(@intFromPtr(body_ptr)));
            return @as(anyerror!Value, vm_instance.run(body_node)) catch |err| switch (err) {
                error.Return => {
                    if (vm_instance.return_value) |val| {
                        const ret = val;
                        vm_instance.return_value = null;
                        return ret;
                    }
                    return Value.initNull();
                },
                else => return err,
            };
        }

        return Value.initNull();
    }

    pub fn clone(self: *PHPObject, allocator: std.mem.Allocator) !*PHPObject {
        const new_object = try allocator.create(PHPObject);
        new_object.* = PHPObject{
            .class = self.class,
            .shape = self.shape,
            .property_values = try std.ArrayList(Value).initCapacity(allocator, self.property_values.items.len),
            .native_data = null,
        };

        for (self.property_values.items) |val| {
            _ = val.retain();
            try new_object.property_values.append(allocator, val);
        }

        // Call __clone magic method if it exists
        if (self.class.hasMethod("__clone")) {
            // Would call __clone magic method here
        }

        return new_object;
    }

    pub fn toString(self: *PHPObject, allocator: std.mem.Allocator) !*PHPString {
        // Try __toString magic method
        if (self.class.hasMethod("__toString")) {
            return error.MagicMethodCall;
        }

        // Default object string representation
        const str = try std.fmt.allocPrint(allocator, "Object({s})", .{self.class.name.data});
        defer allocator.free(str);
        return PHPString.init(allocator, str);
    }

    pub fn isInstanceOf(self: *PHPObject, class: *PHPClass) bool {
        return self.class.isInstanceOf(class);
    }

    pub fn implementsInterface(self: *PHPObject, interface: *PHPInterface) bool {
        return self.class.implementsInterface(interface);
    }
};

pub const PHPResource = struct {
    type_name: *PHPString,
    data: *anyopaque,
    destructor: ?*const fn (*anyopaque) void,

    pub fn init(type_name: *PHPString, data: *anyopaque, destructor: ?*const fn (*anyopaque) void) PHPResource {
        return PHPResource{
            .type_name = type_name,
            .data = data,
            .destructor = destructor,
        };
    }

    pub fn destroy(self: *PHPResource) void {
        if (self.destructor) |destructor_fn| {
            destructor_fn(self.data);
        }
    }
};

pub const TypeInfo = struct {
    name: *PHPString,
    kind: Kind,
    is_nullable: bool = false,
    is_union: bool = false,
    union_types: []const *TypeInfo = &[_]*TypeInfo{},

    pub const Kind = enum {
        null,
        boolean,
        integer,
        float,
        string,
        array,
        object,
        struct_instance,
        resource,
        callable,
        mixed,
        void,
        never,
    };

    pub fn init(name: *PHPString, kind: Kind) TypeInfo {
        return TypeInfo{
            .name = name,
            .kind = kind,
        };
    }
};

pub const Value = struct {
    val: u64,

    pub const SIGN_BIT: u64 = 0x8000000000000000;
    pub const QNAN: u64 = 0x7FFC000000000000;

    // 简单类型标签 (使用 QNAN 的低位)
    pub const TAG_NIL: u64 = 1; // 001
    pub const TAG_FALSE: u64 = 2; // 010
    pub const TAG_TRUE: u64 = 3; // 011
    // 整数使用特殊编码：QNAN | SIGN_BIT | (value & 0xFFFFFFFF)
    pub const TAG_INT_MARKER: u64 = SIGN_BIT | QNAN;

    // 指针类型标记
    // QNAN uses bits 50-62, so we use bits 48-49 for type tags (4 types max)
    // For more types, we use a different encoding scheme
    pub const TAG_PTR: u64 = QNAN; // 不使用 SIGN_BIT，与整数区分
    
    // Type tags use bits 47-49 (3 bits = 8 types)
    pub const TYPE_MASK: u64 = 0x0003800000000000; // Bits 47-49
    pub const TYPE_STRING: u64 = 0x0000800000000000;      // 001
    pub const TYPE_ARRAY: u64 = 0x0001000000000000;       // 010
    pub const TYPE_OBJECT: u64 = 0x0001800000000000;      // 011
    pub const TYPE_STRUCT: u64 = 0x0002000000000000;      // 100
    pub const TYPE_CLOSURE: u64 = 0x0002800000000000;     // 101
    pub const TYPE_RESOURCE: u64 = 0x0003000000000000;    // 110
    pub const TYPE_USER_FUNC: u64 = 0x0003800000000000;   // 111
    pub const TYPE_NATIVE_FUNC: u64 = 0x0000000000000000; // 000 (default for pointers)

    pub fn initNull() Value {
        return .{ .val = QNAN | TAG_NIL };
    }

    pub fn initBool(b: bool) Value {
        return .{ .val = QNAN | (if (b) TAG_TRUE else TAG_FALSE) };
    }

    pub fn initInt(i: i64) Value {
        // 使用 SIGN_BIT | QNAN 作为整数标记，低 32 位存储值
        return .{ .val = TAG_INT_MARKER | @as(u64, @as(u32, @bitCast(@as(i32, @truncate(i))))) };
    }

    pub fn initFloat(f: f64) Value {
        return .{ .val = @bitCast(f) };
    }

    pub fn initNativeFunction(func: anytype) Value {
        return initPtr(@as(*const anyopaque, @ptrCast(func)), TYPE_NATIVE_FUNC);
    }

    // --- 指针类型初始化 ---
    pub fn fromBox(box: anytype, type_tag: u64) Value {
        const addr = @intFromPtr(box);
        // Mask lower 47 bits for address (bits 47-49 used for type)
        return .{ .val = TAG_PTR | type_tag | (addr & 0x00007FFFFFFFFFFF) };
    }

    fn initPtr(ptr: anytype, type_tag: u64) Value {
        const addr = @intFromPtr(ptr);
        // Mask lower 47 bits for address (bits 47-49 used for type)
        return .{ .val = TAG_PTR | type_tag | (addr & 0x00007FFFFFFFFFFF) };
    }

    pub fn initString(allocator: std.mem.Allocator, str: []const u8) !Value {
        const s = try PHPString.init(allocator, str);
        const box = try allocator.create(gc.Box(*PHPString));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = s,
        };
        return initPtr(box, TYPE_STRING);
    }

    pub fn initStringWithManager(mm: anytype, str: []const u8) !Value {
        const box = try mm.allocString(str);
        return initPtr(box, TYPE_STRING);
    }

    pub fn initArrayWithManager(mm: anytype) !Value {
        const box = try mm.allocArray();
        return initPtr(box, TYPE_ARRAY);
    }

    pub fn initObjectWithManager(mm: anytype, class: *PHPClass) !Value {
        const box = try mm.allocObject(class);
        return initPtr(box, TYPE_OBJECT);
    }

    pub fn initObjectWithObject(mm: anytype, obj: *PHPObject) !Value {
        const box = try mm.wrapObject(obj);
        return initPtr(box, TYPE_OBJECT);
    }

    pub fn initArrayWithObject(mm: anytype, arr: *PHPArray) !Value {
        const box = try mm.wrapArray(arr);
        return initPtr(box, TYPE_ARRAY);
    }

    pub fn initStructWithManager(mm: anytype, struct_type: *PHPStruct) !Value {
        const box = try mm.allocStruct(struct_type);
        return initPtr(box, TYPE_STRUCT);
    }

    pub fn initResourceWithManager(mm: anytype, res: PHPResource) !Value {
        const box = try mm.allocResource(res);
        return initPtr(box, TYPE_RESOURCE);
    }

    pub fn initUserFunctionWithManager(mm: anytype, func: UserFunction) !Value {
        const box = try mm.allocUserFunction(func);
        return initPtr(box, TYPE_USER_FUNC);
    }

    pub fn initClosureWithManager(mm: anytype, closure: Closure) !Value {
        const box = try mm.allocClosure(closure);
        return initPtr(box, TYPE_CLOSURE);
    }

    pub fn initArrowFunctionWithManager(mm: anytype, arrow: ArrowFunction) !Value {
        const box = try mm.allocArrowFunction(arrow);
        return initPtr(box, TYPE_CLOSURE); // Reuse closure tag
    }

    // --- 类型检查 ---
    pub fn isFloat(self: Value) bool {
        return (self.val & QNAN) != QNAN;
    }
    pub fn isNull(self: Value) bool {
        return self.val == (QNAN | TAG_NIL);
    }
    pub fn isBool(self: Value) bool {
        return (self.val & (QNAN | TAG_FALSE)) == (QNAN | TAG_FALSE) or (self.val & (QNAN | TAG_TRUE)) == (QNAN | TAG_TRUE);
    }
    pub fn isInt(self: Value) bool {
        // 检查是否有 SIGN_BIT | QNAN 标记
        return (self.val & (SIGN_BIT | QNAN)) == TAG_INT_MARKER;
    }
    pub fn isPtr(self: Value) bool {
        // 指针使用 QNAN 但不使用 SIGN_BIT（与整数区分）
        return (self.val & QNAN) == QNAN and (self.val & SIGN_BIT) == 0;
    }

    pub fn isString(self: Value) bool {
        return (self.val & (TAG_PTR | TYPE_MASK)) == (TAG_PTR | TYPE_STRING);
    }
    pub fn isArray(self: Value) bool {
        return (self.val & (TAG_PTR | TYPE_MASK)) == (TAG_PTR | TYPE_ARRAY);
    }
    pub fn isObject(self: Value) bool {
        return (self.val & (TAG_PTR | TYPE_MASK)) == (TAG_PTR | TYPE_OBJECT);
    }
    pub fn isStruct(self: Value) bool {
        return (self.val & (TAG_PTR | TYPE_MASK)) == (TAG_PTR | TYPE_STRUCT);
    }
    pub fn isClosure(self: Value) bool {
        return (self.val & (TAG_PTR | TYPE_MASK)) == (TAG_PTR | TYPE_CLOSURE);
    }
    pub fn isResource(self: Value) bool {
        return (self.val & (TAG_PTR | TYPE_MASK)) == (TAG_PTR | TYPE_RESOURCE);
    }
    pub fn isNativeFunction(self: Value) bool {
        return (self.val & (TAG_PTR | TYPE_MASK)) == (TAG_PTR | TYPE_NATIVE_FUNC);
    }

    // --- 数据提取 ---
    pub fn asFloat(self: Value) f64 {
        return @bitCast(self.val);
    }
    pub fn asInt(self: Value) i64 {
        return @as(i64, @intCast(@as(i32, @bitCast(@as(u32, @truncate(self.val))))));
    }
    pub fn asBool(self: Value) bool {
        return (self.val & 0x1) == 1;
    }

    pub fn asPtr(self: Value, comptime T: type) T {
        // Extract lower 47 bits for address (bits 47-49 used for type)
        return @ptrFromInt(self.val & 0x00007FFFFFFFFFFF);
    }

    pub const Tag = enum { null, boolean, integer, float, string, array, object, struct_instance, resource, user_function, closure, arrow_function, native_function };

    pub fn getTag(self: Value) Tag {
        if (self.isFloat()) return .float;
        if (self.isNull()) return .null;
        if (self.isInt()) return .integer;
        if (self.isBool()) return .boolean;
        if (self.isString()) return .string;
        if (self.isArray()) return .array;
        if (self.isObject()) return .object;
        if (self.isStruct()) return .struct_instance;
        if (self.isClosure()) return .closure;
        if (self.isResource()) return .resource;
        if ((self.val & (TAG_PTR | TYPE_MASK)) == (TAG_PTR | TYPE_USER_FUNC)) return .user_function;
        if (self.isNativeFunction()) return .native_function;
        return .null;
    }

    // 模拟旧的数据结构访问
    pub fn getAsObject(self: Value) *gc.Box(*PHPObject) {
        return self.asPtr(*gc.Box(*PHPObject));
    }
    pub fn getAsArray(self: Value) *gc.Box(*PHPArray) {
        return self.asPtr(*gc.Box(*PHPArray));
    }
    pub fn getAsString(self: Value) *gc.Box(*PHPString) {
        return self.asPtr(*gc.Box(*PHPString));
    }
    pub fn getAsStruct(self: Value) *gc.Box(*StructInstance) {
        return self.asPtr(*gc.Box(*StructInstance));
    }
    pub fn getAsResource(self: Value) *gc.Box(*PHPResource) {
        return self.asPtr(*gc.Box(*PHPResource));
    }
    pub fn getAsUserFunc(self: Value) *gc.Box(*UserFunction) {
        return self.asPtr(*gc.Box(*UserFunction));
    }
    pub fn getAsClosure(self: Value) *gc.Box(*Closure) {
        return self.asPtr(*gc.Box(*Closure));
    }
    pub fn getAsArrowFunc(self: Value) *gc.Box(*ArrowFunction) {
        return self.asPtr(*gc.Box(*ArrowFunction));
    }
    pub fn getAsNativeFunc(self: Value) *anyopaque {
        return self.asPtr(*anyopaque);
    }

    pub fn retain(self: Value) Value {
        switch (self.getTag()) {
            .string => _ = self.getAsString().retain(),
            .array => _ = self.getAsArray().retain(),
            .object => _ = self.getAsObject().retain(),
            .struct_instance => _ = self.getAsStruct().retain(),
            .resource => _ = self.getAsResource().retain(),
            .user_function => _ = self.getAsUserFunc().retain(),
            .closure => _ = self.getAsClosure().retain(),
            else => {},
        }
        return self;
    }

    pub fn release(self: Value, allocator: std.mem.Allocator) void {
        switch (self.getTag()) {
            .string => self.getAsString().release(allocator),
            .array => self.getAsArray().release(allocator),
            .object => self.getAsObject().release(allocator),
            .struct_instance => self.getAsStruct().release(allocator),
            .resource => self.getAsResource().release(allocator),
            .user_function => self.getAsUserFunc().release(allocator),
            .closure => self.getAsClosure().release(allocator),
            else => {},
        }
    }

    pub fn toBool(self: Value) bool {
        return switch (self.getTag()) {
            .null => false,
            .boolean => self.asBool(),
            .integer => self.asInt() != 0,
            .float => self.asFloat() != 0.0,
            .string => self.getAsString().data.length > 0,
            .array => self.getAsArray().data.count() > 0,
            else => true,
        };
    }

    pub fn print(self: Value) !void {
        switch (self.getTag()) {
            .null => std.debug.print("NULL", .{}),
            .boolean => std.debug.print("{}", .{self.asBool()}),
            .integer => std.debug.print("{}", .{self.asInt()}),
            .float => std.debug.print("{d}", .{self.asFloat()}),
            .string => std.debug.print("{s}", .{self.getAsString().data.data}),
            .array => std.debug.print("Array({d})", .{self.getAsArray().data.count()}),
            .object => std.debug.print("Object({s})", .{self.getAsObject().data.class.name.data}),
            .struct_instance => std.debug.print("Struct({s})", .{self.getAsStruct().data.struct_type.name.data}),
            else => std.debug.print("Unknown", .{}),
        }
    }

    pub fn toString(self: Value, allocator: std.mem.Allocator) anyerror!*PHPString {
        return switch (self.getTag()) {
            .null => PHPString.init(allocator, ""),
            .boolean => PHPString.init(allocator, if (self.asBool()) "1" else ""),
            .integer => {
                const str = try std.fmt.allocPrint(allocator, "{d}", .{self.asInt()});
                defer allocator.free(str);
                return PHPString.init(allocator, str);
            },
            .float => {
                const str = try std.fmt.allocPrint(allocator, "{d}", .{self.asFloat()});
                defer allocator.free(str);
                return PHPString.init(allocator, str);
            },
            .string => PHPString.init(allocator, self.getAsString().data.data),
            .array => PHPString.init(allocator, "Array"),
            .object => self.getAsObject().data.toString(allocator),
            .struct_instance => {
                const struct_name = self.getAsStruct().data.struct_type.name.data;
                const str = try std.fmt.allocPrint(allocator, "Struct({s})", .{struct_name});
                defer allocator.free(str);
                return PHPString.init(allocator, str);
            },
            .resource => PHPString.init(allocator, "Resource"),
            else => error.InvalidConversion,
        };
    }

    pub fn isCallable(self: Value) bool {
        return switch (self.getTag()) {
            .user_function, .closure, .arrow_function => true,
            .string => true, // Function name
            .array => true, // [object, method]
            else => false,
        };
    }
};

/// 隐藏类(Shape) - 对象属性布局描述
/// 用于替换传统的HashMap，提高属性访问性能
pub const Shape = struct {
    id: u32,
    parent: ?*Shape,
    property_map: std.StringHashMap(u32), // 属性名 -> 偏移量
    property_count: u32,

    pub var next_id: u32 = 0;

    pub fn init(allocator: std.mem.Allocator, id: u32, parent: ?*Shape) Shape {
        return Shape{
            .id = id,
            .parent = parent,
            .property_map = std.StringHashMap(u32).init(allocator),
            .property_count = if (parent) |p| p.property_count else 0,
        };
    }

    pub fn deinit(self: *Shape) void {
        self.property_map.deinit();
    }

    /// 添加属性，返回偏移量
    pub fn addProperty(self: *Shape, name: []const u8) !u32 {
        if (self.property_map.get(name)) |offset| {
            return offset;
        }
        const offset = self.property_count;
        try self.property_map.put(name, offset);
        self.property_count += 1;
        return offset;
    }

    /// 获取属性偏移量
    pub fn getPropertyOffset(self: *Shape, name: []const u8) ?u32 {
        if (self.property_map.get(name)) |offset| {
            return offset;
        }
        if (self.parent) |p| {
            return p.getPropertyOffset(name);
        }
        return null;
    }

    /// 检查属性是否存在
    pub fn hasProperty(self: *Shape, name: []const u8) bool {
        return self.getPropertyOffset(name) != null;
    }

    /// 创建子Shape（用于继承）
    pub fn createChild(self: *Shape, allocator: std.mem.Allocator, id: u32) !*Shape {
        const child = try allocator.create(Shape);
        child.* = Shape.init(allocator, id, self);
        return child;
    }

    /// 过渡到新Shape（添加动态属性时）
    pub fn transition(self: *Shape, allocator: std.mem.Allocator, new_id: u32, added_property: []const u8) !*Shape {
        const new_shape = try allocator.create(Shape);
        new_shape.* = Shape.init(allocator, new_id, self);

        // 复制现有属性
        var iter = self.property_map.iterator();
        while (iter.next()) |entry| {
            try new_shape.property_map.put(entry.key_ptr.*, entry.value_ptr.*);
        }

        // 添加新属性
        _ = try new_shape.addProperty(added_property);
        return new_shape;
    }
};

pub const UserFunction = struct {
    name: *PHPString,
    parameters: []const Method.Parameter,
    return_type: ?TypeInfo,
    attributes: []const Attribute,
    body: ?*anyopaque, // Would be AST node reference in real implementation
    is_variadic: bool,
    min_args: u32,
    max_args: ?u32, // null means unlimited (for variadic functions)

    pub fn init(name: *PHPString) UserFunction {
        return UserFunction{
            .name = name,
            .parameters = &[_]Method.Parameter{},
            .return_type = null,
            .attributes = &[_]Attribute{},
            .body = null,
            .is_variadic = false,
            .min_args = 0,
            .max_args = 0,
        };
    }

    pub fn deinit(self: *UserFunction, allocator: std.mem.Allocator) void {
        self.name.release(allocator);
        for (0..self.parameters.len) |i| {
            var param = self.parameters[i];
            param.deinit(allocator);
        }
        allocator.free(self.parameters);
        // Attributes cleanup...
    }

    pub fn validateArguments(self: *const UserFunction, args: []const Value) !void {
        const arg_count = @as(u32, @intCast(args.len));

        // Check minimum arguments
        if (arg_count < self.min_args) {
            return error.TooFewArguments;
        }

        // Check maximum arguments (if not variadic)
        if (self.max_args) |max| {
            if (arg_count > max) {
                return error.TooManyArguments;
            }
        }
    }

    pub fn bindArguments(self: *const UserFunction, args: []const Value, allocator: std.mem.Allocator) !std.StringHashMap(Value) {
        var bound_args = std.StringHashMap(Value).init(allocator);

        for (self.parameters, 0..) |param, i| {
            if (i < args.len) {
                // Bind provided argument
                _ = args[i].retain();
                try bound_args.put(param.name.data, args[i]);
            } else if (param.default_value) |default| {
                // Use default value
                _ = default.retain();
                try bound_args.put(param.name.data, default);
            } else if (!param.is_variadic) { // Required parameter missing
                return error.MissingRequiredParameter;
            }
        }

        // Handle variadic parameters
        if (self.is_variadic and args.len > self.parameters.len - 1) {
            const variadic_param = self.parameters[self.parameters.len - 1];
            var variadic_array = PHPArray.init(allocator);

            for (args[self.parameters.len - 1 ..]) |arg| {
                try variadic_array.push(allocator, arg);
            }

            const array_box = try allocator.create(gc.Box(*PHPArray));
            array_box.* = .{
                .ref_count = 1,
                .gc_info = .{},
                .data = try allocator.create(PHPArray),
            };
            array_box.data.* = variadic_array;

            // Actually, I'll just use initPtr directly for now to unblock.
            const array_value = Value.fromBox(array_box, Value.TYPE_ARRAY);
            try bound_args.put(variadic_param.name.data, array_value);
        }

        return bound_args;
    }
};

pub const Closure = struct {
    function: UserFunction,
    captured_vars: std.StringHashMap(Value),
    is_static: bool,

    pub fn init(allocator: std.mem.Allocator, function: UserFunction) Closure {
        return Closure{
            .function = function,
            .captured_vars = std.StringHashMap(Value).init(allocator),
            .is_static = false,
        };
    }

    pub fn deinit(self: *Closure, allocator: std.mem.Allocator) void {
        self.function.deinit(allocator);
        self.captured_vars.deinit();
    }

    pub fn call(self: *Closure, vm: *anyopaque, args: []const Value) !Value {
        const VM = @import("vm.zig").VM;
        const vm_instance = @as(*VM, @ptrCast(@alignCast(vm)));

        // Validate arguments
        try self.function.validateArguments(args);

        // Set parameters in current call frame
        for (self.function.parameters, 0..) |param, i| {
            if (i < args.len) {
                try vm_instance.setVariable(param.name.data, args[i]);
            } else if (param.default_value) |default| {
                try vm_instance.setVariable(param.name.data, default);
            }
        }

        // Set captured variables in current call frame
        var captured_iter = self.captured_vars.iterator();
        while (captured_iter.next()) |entry| {
            try vm_instance.setVariable(entry.key_ptr.*, entry.value_ptr.*);
        }

        // Execute closure body
        if (self.function.body) |body_ptr| {
            const ast = @import("../compiler/ast.zig");
            const body_node = @as(ast.Node.Index, @truncate(@intFromPtr(body_ptr)));
            return try vm_instance.eval(body_node);
        }

        return Value.initNull();
    }

    pub fn captureVariable(self: *Closure, name: []const u8, value: Value) !void {
        try self.captured_vars.put(name, value);
    }

    pub fn captureByReference(self: *Closure, name: []const u8, value: Value) !void {
        // In a real implementation, this would store a reference to the variable
        try self.captured_vars.put(name, value);
    }

    pub fn bindTo(self: *Closure, allocator: std.mem.Allocator, object: ?*PHPObject, scope: ?*PHPClass) !*Closure {
        const new_closure = try allocator.create(Closure);
        new_closure.* = Closure.init(allocator, self.function);

        // Copy captured variables
        var iterator = self.captured_vars.iterator();
        while (iterator.next()) |entry| {
            try new_closure.captured_vars.put(entry.key_ptr.*, entry.value_ptr.*);
        }

        // Bind $this if object is provided
        if (object) |_| {
            const this_value = Value.fromBox(@as(*anyopaque, @ptrFromInt(0xDEADBEEF)), Value.TYPE_OBJECT); // Placeholder address for dummy object
            try new_closure.captured_vars.put("this", this_value);
        }

        _ = scope; // Would be used for scope binding
        return new_closure;
    }
};

pub const ArrowFunction = struct {
    parameters: []const Method.Parameter,
    return_type: ?TypeInfo,
    body: ?*anyopaque, // Expression AST node
    captured_vars: std.StringHashMap(Value), // Auto-captured variables
    is_static: bool,

    pub fn init(allocator: std.mem.Allocator) ArrowFunction {
        return ArrowFunction{
            .parameters = &[_]Method.Parameter{},
            .return_type = null,
            .body = null,
            .captured_vars = std.StringHashMap(Value).init(allocator),
            .is_static = false,
        };
    }

    pub fn deinit(self: *ArrowFunction, allocator: std.mem.Allocator) void {
        // 释放参数名
        for (self.parameters) |param| {
            param.name.release(allocator);
        }
        if (self.parameters.len > 0) {
            allocator.free(self.parameters);
        }
        self.captured_vars.deinit();
    }

    pub fn call(self: *ArrowFunction, vm: *anyopaque, args: []const Value) !Value {
        const VM = @import("vm.zig").VM;
        const vm_instance = @as(*VM, @ptrCast(@alignCast(vm)));

        // Validate arguments
        if (args.len != self.parameters.len) {
            return error.ArgumentCountMismatch;
        }

        // Type check arguments
        for (self.parameters, args) |param, arg| {
            try param.validateType(arg);
        }

        // Set parameters in current call frame
        for (self.parameters, args) |param, arg| {
            try vm_instance.setVariable(param.name.data, arg);
        }

        // Set captured variables in current call frame
        var captured_iter = self.captured_vars.iterator();
        while (captured_iter.next()) |entry| {
            try vm_instance.setVariable(entry.key_ptr.*, entry.value_ptr.*);
        }

        // Execute arrow function body
        if (self.body) |body_ptr| {
            const ast = @import("../compiler/ast.zig");
            const body_node = @as(ast.Node.Index, @truncate(@intFromPtr(body_ptr)));
            return try vm_instance.eval(body_node);
        }

        return Value.initNull();
    }

    pub fn autoCaptureVariable(self: *ArrowFunction, name: []const u8, value: Value) !void {
        try self.captured_vars.put(name, value);
    }
};

pub const BuiltinFn = *const fn (*anyopaque, []const Value) anyerror!Value;

/// 所有权标注系统 (Ownership Lite)
/// 允许通过 ref/move 显式控制大数据块的传递
pub const Ownership = struct {
    /// 所有权类型
    pub const Kind = enum {
        owned, // 完全拥有，负责释放
        borrowed, // 借用引用，不负责释放
        moved, // 已转移所有权
        shared, // 共享所有权（引用计数）
    };

    kind: Kind,
    source_id: u64 = 0, // 来源标识，用于追踪
    lifetime: Lifetime = .static,

    /// 生命周期标注
    pub const Lifetime = enum {
        static, // 静态生命周期
        request, // 请求作用域
        function, // 函数作用域
        block, // 块作用域
        temporary, // 临时值
    };

    pub fn init(kind: Kind) Ownership {
        return Ownership{ .kind = kind };
    }

    pub fn initWithLifetime(kind: Kind, lifetime: Lifetime) Ownership {
        return Ownership{ .kind = kind, .lifetime = lifetime };
    }

    /// 检查是否可以移动
    pub fn canMove(self: Ownership) bool {
        return self.kind == .owned;
    }

    /// 检查是否可以借用
    pub fn canBorrow(self: Ownership) bool {
        return self.kind != .moved;
    }

    /// 执行移动操作
    pub fn move(self: *Ownership) Ownership {
        if (self.kind == .owned) {
            self.kind = .moved;
            return Ownership{ .kind = .owned, .lifetime = self.lifetime };
        }
        return Ownership{ .kind = .borrowed, .lifetime = self.lifetime };
    }

    /// 创建借用
    pub fn borrow(self: Ownership) Ownership {
        return Ownership{ .kind = .borrowed, .lifetime = self.lifetime, .source_id = self.source_id };
    }
};

/// 带所有权的值包装
pub const OwnedValue = struct {
    value: Value,
    ownership: Ownership,

    pub fn init(value: Value, ownership: Ownership) OwnedValue {
        return OwnedValue{ .value = value, .ownership = ownership };
    }

    pub fn initOwned(value: Value) OwnedValue {
        return OwnedValue{ .value = value, .ownership = Ownership.init(.owned) };
    }

    pub fn initBorrowed(value: Value) OwnedValue {
        return OwnedValue{ .value = value, .ownership = Ownership.init(.borrowed) };
    }

    /// 移动值（转移所有权）
    pub fn moveValue(self: *OwnedValue) !OwnedValue {
        if (!self.ownership.canMove()) {
            return error.CannotMoveValue;
        }
        const new_ownership = self.ownership.move();
        return OwnedValue{ .value = self.value, .ownership = new_ownership };
    }

    /// 借用值
    pub fn borrowValue(self: OwnedValue) OwnedValue {
        return OwnedValue{ .value = self.value, .ownership = self.ownership.borrow() };
    }

    /// 释放值（仅当拥有所有权时）
    pub fn release(self: *OwnedValue, allocator: std.mem.Allocator) void {
        if (self.ownership.kind == .owned) {
            self.value.release(allocator);
        }
    }
};

/// 代数数据类型 (Sum Types / Tagged Union)
pub const SumType = struct {
    name: *PHPString,
    variants: std.StringHashMap(Variant),
    allocator: std.mem.Allocator,

    pub const Variant = struct {
        name: *PHPString,
        fields: []const Field,
        tag: u32,

        pub const Field = struct {
            name: *PHPString,
            type_info: ?TypeInfo,
        };
    };

    pub fn init(allocator: std.mem.Allocator, name: *PHPString) SumType {
        name.retain();
        return SumType{
            .name = name,
            .variants = std.StringHashMap(Variant).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SumType) void {
        self.name.release(self.allocator);
        self.variants.deinit();
    }

    pub fn addVariant(self: *SumType, variant: Variant) !void {
        variant.name.retain();
        try self.variants.put(variant.name.data, variant);
    }

    pub fn getVariant(self: *SumType, name: []const u8) ?*Variant {
        return self.variants.getPtr(name);
    }
};

/// Sum Type 实例
pub const SumTypeInstance = struct {
    sum_type: *SumType,
    variant_tag: u32,
    variant_name: *PHPString,
    fields: std.StringHashMap(Value),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, sum_type: *SumType, variant_name: *PHPString) SumTypeInstance {
        variant_name.retain();
        return SumTypeInstance{
            .sum_type = sum_type,
            .variant_tag = 0,
            .variant_name = variant_name,
            .fields = std.StringHashMap(Value).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SumTypeInstance) void {
        self.variant_name.release(self.allocator);
        var iter = self.fields.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.release(self.allocator);
        }
        self.fields.deinit();
    }

    pub fn setField(self: *SumTypeInstance, name: []const u8, value: Value) !void {
        if (self.fields.get(name)) |old| {
            old.release(self.allocator);
        }
        _ = value.retain();
        try self.fields.put(name, value);
    }

    pub fn getField(self: *SumTypeInstance, name: []const u8) ?Value {
        return self.fields.get(name);
    }
};

/// 模式匹配器
pub const PatternMatcher = struct {
    allocator: std.mem.Allocator,
    patterns: std.ArrayList(Pattern),

    pub const Pattern = struct {
        kind: PatternKind,
        bindings: std.StringHashMap(BindingInfo),
        guard: ?*anyopaque, // 可选的守卫条件表达式

        pub const BindingInfo = struct {
            name: []const u8,
            value_index: usize,
        };
    };

    pub const PatternKind = union(enum) {
        /// 字面量匹配
        literal: Value,
        /// 变量绑定
        variable: []const u8,
        /// 通配符 _
        wildcard,
        /// 构造器匹配 Success($data)
        constructor: struct {
            name: []const u8,
            sub_patterns: []const PatternKind,
        },
        /// 数组解构 [$a, $b, ...$rest]
        array_destruct: struct {
            patterns: []const PatternKind,
            rest_binding: ?[]const u8,
        },
        /// 对象解构 {name: $n, age: $a}
        object_destruct: struct {
            field_patterns: []const struct {
                field: []const u8,
                pattern: PatternKind,
            },
        },
        /// 范围匹配 1..10
        range: struct {
            start: i64,
            end: i64,
            inclusive: bool,
        },
        /// 类型匹配 is string
        type_check: TypeInfo.Kind,
    };

    pub fn init(allocator: std.mem.Allocator) PatternMatcher {
        return PatternMatcher{
            .allocator = allocator,
            .patterns = std.ArrayList(Pattern).init(allocator),
        };
    }

    pub fn deinit(self: *PatternMatcher) void {
        self.patterns.deinit(self.allocator);
    }

    /// 匹配值与模式
    pub fn match(self: *PatternMatcher, value: Value, pattern: PatternKind) !?std.StringHashMap(Value) {
        var bindings = std.StringHashMap(Value).init(self.allocator);

        const matched = try self.matchInternal(value, pattern, &bindings);
        if (matched) {
            return bindings;
        } else {
            bindings.deinit();
            return null;
        }
    }

    fn matchInternal(_: *PatternMatcher, value: Value, pattern: PatternKind, bindings: *std.StringHashMap(Value)) !bool {
        switch (pattern) {
            .literal => |lit| {
                return value.equals(lit);
            },
            .variable => |name| {
                _ = value.retain();
                try bindings.put(name, value);
                return true;
            },
            .wildcard => {
                return true;
            },
            .type_check => |expected_kind| {
                const actual_kind: TypeInfo.Kind = switch (value.getTag()) {
                    .null => .null,
                    .boolean => .boolean,
                    .integer => .integer,
                    .float => .float,
                    .string => .string,
                    .array => .array,
                    .object => .object,
                    .struct_instance => .struct_instance,
                    .resource => .resource,
                    else => .mixed,
                };
                return actual_kind == expected_kind;
            },
            .range => |r| {
                if (value.getTag() != .integer) return false;
                const v = value.asInt();
                if (r.inclusive) {
                    return v >= r.start and v <= r.end;
                } else {
                    return v >= r.start and v < r.end;
                }
            },
            else => return false,
        }
    }
};

/// 异步生成器 (Async Generator)
pub const AsyncGenerator = struct {
    state: State,
    current_value: ?Value,
    parameters: []const Method.Parameter,
    body: ?*anyopaque,
    captured_vars: std.StringHashMap(Value),
    allocator: std.mem.Allocator,

    /// 生成器局部变量
    locals: std.StringHashMap(Value),
    /// 当前执行位置
    resume_point: usize,
    /// 是否已启动
    started: bool,

    pub const State = enum {
        created,
        running,
        suspended,
        completed,
        failed,
    };

    pub fn init(allocator: std.mem.Allocator) AsyncGenerator {
        return AsyncGenerator{
            .state = .created,
            .current_value = null,
            .parameters = &[_]Method.Parameter{},
            .body = null,
            .captured_vars = std.StringHashMap(Value).init(allocator),
            .allocator = allocator,
            .locals = std.StringHashMap(Value).init(allocator),
            .resume_point = 0,
            .started = false,
        };
    }

    pub fn deinit(self: *AsyncGenerator) void {
        if (self.current_value) |*v| {
            v.release(self.allocator);
        }
        var iter = self.captured_vars.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.release(self.allocator);
        }
        self.captured_vars.deinit();

        var locals_iter = self.locals.iterator();
        while (locals_iter.next()) |entry| {
            entry.value_ptr.release(self.allocator);
        }
        self.locals.deinit();
    }

    /// yield 值
    pub fn yield_value(self: *AsyncGenerator, value: Value) void {
        if (self.current_value) |*old| {
            old.release(self.allocator);
        }
        _ = value.retain();
        self.current_value = value;
        self.state = .suspended;
    }

    /// 获取下一个值
    pub fn next(self: *AsyncGenerator) ?Value {
        if (self.state == .completed) return null;
        return self.current_value;
    }

    /// 发送值到生成器
    pub fn send(self: *AsyncGenerator, value: Value) !?Value {
        if (self.state == .completed) return null;

        // 存储发送的值供生成器使用
        if (self.locals.get("__sent__")) |old| {
            old.release(self.allocator);
        }
        _ = value.retain();
        try self.locals.put("__sent__", value);

        return self.current_value;
    }

    /// 抛出异常到生成器
    pub fn throw(self: *AsyncGenerator) void {
        self.state = .failed;
    }

    /// 关闭生成器
    pub fn close(self: *AsyncGenerator) void {
        self.state = .completed;
    }

    /// 获取当前状态
    pub fn getState(self: *AsyncGenerator) State {
        return self.state;
    }
};

/// Awaitable 类型（Promise-like）
pub const Awaitable = struct {
    state: State,
    value: ?Value,
    error_value: ?Value,
    callbacks: std.ArrayList(Callback),
    allocator: std.mem.Allocator,

    pub const State = enum {
        pending,
        fulfilled,
        rejected,
    };

    pub const Callback = struct {
        on_fulfill: ?Value,
        on_reject: ?Value,
    };

    pub fn init(allocator: std.mem.Allocator) Awaitable {
        return Awaitable{
            .state = .pending,
            .value = null,
            .error_value = null,
            .callbacks = std.ArrayList(Callback).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Awaitable) void {
        if (self.value) |*v| {
            v.release(self.allocator);
        }
        if (self.error_value) |*e| {
            e.release(self.allocator);
        }
        for (self.callbacks.items) |*cb| {
            if (cb.on_fulfill) |*f| f.release(self.allocator);
            if (cb.on_reject) |*r| r.release(self.allocator);
        }
        self.callbacks.deinit(self.allocator);
    }

    /// 完成 Promise
    pub fn resolve(self: *Awaitable, value: Value) void {
        if (self.state != .pending) return;
        _ = value.retain();
        self.value = value;
        self.state = .fulfilled;
        self.executeCallbacks();
    }

    /// 拒绝 Promise
    pub fn reject(self: *Awaitable, err: Value) void {
        if (self.state != .pending) return;
        _ = err.retain();
        self.error_value = err;
        self.state = .rejected;
        self.executeCallbacks();
    }

    /// 添加回调
    pub fn then(self: *Awaitable, on_fulfill: ?Value, on_reject: ?Value) !void {
        if (on_fulfill) |f| _ = f.retain();
        if (on_reject) |r| _ = r.retain();
        try self.callbacks.append(self.allocator, .{
            .on_fulfill = on_fulfill,
            .on_reject = on_reject,
        });

        if (self.state != .pending) {
            self.executeCallbacks();
        }
    }

    fn executeCallbacks(self: *Awaitable) void {
        // 执行所有已注册的回调
        for (self.callbacks.items) |callback| {
            if (self.state == .fulfilled) {
                if (callback.on_fulfilled) |on_fulfilled| {
                    // 调用成功回调
                    _ = on_fulfilled;
                }
            } else if (self.state == .rejected) {
                if (callback.on_rejected) |on_rejected| {
                    // 调用失败回调
                    _ = on_rejected;
                }
            }
        }
        self.callbacks.clearRetainingCapacity();
    }

    /// 检查是否已完成
    pub fn isSettled(self: *Awaitable) bool {
        return self.state != .pending;
    }

    /// 获取结果值
    pub fn getValue(self: *Awaitable) ?Value {
        return self.value;
    }
};

/// 编译期类型推断信息 (Comptime)
pub const ComptimeInfo = struct {
    /// 推断出的类型
    inferred_type: ?TypeInfo.Kind,
    /// 是否为常量表达式
    is_const_expr: bool,
    /// 常量值（如果可以在编译期求值）
    const_value: ?Value,
    /// 类型约束
    constraints: std.ArrayList(TypeConstraint),
    allocator: std.mem.Allocator,

    pub const TypeConstraint = struct {
        kind: ConstraintKind,
        type_info: TypeInfo.Kind,
    };

    pub const ConstraintKind = enum {
        must_be, // 必须是某类型
        must_not_be, // 不能是某类型
        implements, // 必须实现某接口
        extends, // 必须继承某类
    };

    pub fn init(allocator: std.mem.Allocator) ComptimeInfo {
        return ComptimeInfo{
            .inferred_type = null,
            .is_const_expr = false,
            .const_value = null,
            .constraints = std.ArrayList(TypeConstraint).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ComptimeInfo) void {
        if (self.const_value) |*v| {
            v.release(self.allocator);
        }
        self.constraints.deinit(self.allocator);
    }

    /// 添加类型约束
    pub fn addConstraint(self: *ComptimeInfo, kind: ConstraintKind, type_kind: TypeInfo.Kind) !void {
        try self.constraints.append(self.allocator, .{
            .kind = kind,
            .type_info = type_kind,
        });
    }

    /// 检查类型是否满足所有约束
    pub fn satisfiesConstraints(self: *ComptimeInfo, actual_type: TypeInfo.Kind) bool {
        for (self.constraints.items) |constraint| {
            switch (constraint.kind) {
                .must_be => {
                    if (actual_type != constraint.type_info) return false;
                },
                .must_not_be => {
                    if (actual_type == constraint.type_info) return false;
                },
                else => {},
            }
        }
        return true;
    }

    /// 设置推断类型
    pub fn setInferredType(self: *ComptimeInfo, type_kind: TypeInfo.Kind) void {
        self.inferred_type = type_kind;
    }

    /// 设置常量值
    pub fn setConstValue(self: *ComptimeInfo, value: Value) void {
        if (self.const_value) |*old| {
            old.release(self.allocator);
        }
        _ = value.retain();
        self.const_value = value;
        self.is_const_expr = true;
    }
};

/// 编译期求值器
pub const ComptimeEvaluator = struct {
    allocator: std.mem.Allocator,
    cache: std.StringHashMap(ComptimeInfo),

    pub fn init(allocator: std.mem.Allocator) ComptimeEvaluator {
        return ComptimeEvaluator{
            .allocator = allocator,
            .cache = std.StringHashMap(ComptimeInfo).init(allocator),
        };
    }

    pub fn deinit(self: *ComptimeEvaluator) void {
        var iter = self.cache.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.cache.deinit();
    }

    /// 尝试在编译期求值表达式
    pub fn tryEvaluate(self: *ComptimeEvaluator, expr_id: []const u8) ?*ComptimeInfo {
        return self.cache.getPtr(expr_id);
    }

    /// 缓存编译期信息
    pub fn cacheInfo(self: *ComptimeEvaluator, expr_id: []const u8, info: ComptimeInfo) !void {
        try self.cache.put(expr_id, info);
    }

    /// 推断二元表达式的结果类型
    pub fn inferBinaryResultType(left: TypeInfo.Kind, right: TypeInfo.Kind, op: []const u8) TypeInfo.Kind {
        // 数值运算
        if (std.mem.eql(u8, op, "+") or std.mem.eql(u8, op, "-") or
            std.mem.eql(u8, op, "*") or std.mem.eql(u8, op, "/"))
        {
            if (left == .float or right == .float) return .float;
            if (left == .integer and right == .integer) return .integer;
            return .mixed;
        }
        // 字符串连接
        if (std.mem.eql(u8, op, ".")) {
            return .string;
        }
        // 比较运算
        if (std.mem.eql(u8, op, "==") or std.mem.eql(u8, op, "!=") or
            std.mem.eql(u8, op, "<") or std.mem.eql(u8, op, ">"))
        {
            return .boolean;
        }
        return .mixed;
    }
};
