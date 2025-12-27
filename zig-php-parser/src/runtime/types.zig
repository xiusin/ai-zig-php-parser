const std = @import("std");
pub const gc = @import("gc.zig");

// Forward declarations
pub const PHPString = struct {
    data: []u8,
    length: usize,
    encoding: Encoding,
    
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
        return php_string;
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
            if (std.mem.eql(u8, self.data[i..i + needle.length], needle.data)) {
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
                std.mem.eql(u8, self.data[i..i + search.length], search.data)) {
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
    
    pub fn deinit(self: *PHPArray) void {
        self.elements.deinit();
    }
    
    pub fn get(self: *PHPArray, key: ArrayKey) ?Value {
        return self.elements.get(key);
    }
    
    pub fn set(self: *PHPArray, key: ArrayKey, value: Value) !void {
        try self.elements.put(key, value);
    }
    
    pub fn push(self: *PHPArray, value: Value) !void {
        const key = ArrayKey{ .integer = self.next_index };
        try self.elements.put(key, value);
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
};

pub const PHPInterface = struct {
    name: *PHPString,
    methods: std.StringHashMap(Method),
    constants: std.StringHashMap(Value),
    extends: []const *PHPInterface,
    
    pub fn init(allocator: std.mem.Allocator, name: *PHPString) PHPInterface {
        return PHPInterface{
            .name = name,
            .methods = std.StringHashMap(Method).init(allocator),
            .constants = std.StringHashMap(Value).init(allocator),
            .extends = &[_]*PHPInterface{},
        };
    }
    
    pub fn deinit(self: *PHPInterface) void {
        self.methods.deinit();
        self.constants.deinit();
    }
};

pub const PHPTrait = struct {
    name: *PHPString,
    properties: std.StringHashMap(Property),
    methods: std.StringHashMap(Method),
    
    pub fn init(allocator: std.mem.Allocator, name: *PHPString) PHPTrait {
        return PHPTrait{
            .name = name,
            .properties = std.StringHashMap(Property).init(allocator),
            .methods = std.StringHashMap(Method).init(allocator),
        };
    }
    
    pub fn deinit(self: *PHPTrait) void {
        self.properties.deinit();
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
            object.* = PHPObject.init(allocator, class_def);
            
            // Call constructor with arguments if it exists
            if (class_def.hasMethod("__construct")) {
                // Would call constructor with self.arguments here
                // For now, just initialize with default values
            }
            
            return object;
        }
        
        // For built-in attributes, create a simple object representation
        const builtin_class_name = try PHPString.init(allocator, self.name.data);
        var builtin_class = PHPClass.init(allocator, builtin_class_name);
        
        const object = try allocator.create(PHPObject);
        object.* = PHPObject.init(allocator, &builtin_class);
        
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
    
    pub const ClassModifiers = packed struct {
        is_abstract: bool = false,
        is_final: bool = false,
        is_readonly: bool = false,
    };
    
    pub fn init(allocator: std.mem.Allocator, name: *PHPString) PHPClass {
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
        };
    }
    
    pub fn deinit(self: *PHPClass) void {
        self.properties.deinit();
        self.methods.deinit();
        self.constants.deinit();
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
        
        pub fn validateType(self: *const Parameter, value: Value) !void {
            if (self.type == null) return; // No type constraint
            
            const type_info = self.type.?;
            const type_name = type_info.name.data;
            
            // Basic type checking
            const is_valid = switch (value.tag) {
                .null => type_info.is_nullable,
                .boolean => std.mem.eql(u8, type_name, "bool") or std.mem.eql(u8, type_name, "boolean"),
                .integer => std.mem.eql(u8, type_name, "int") or std.mem.eql(u8, type_name, "integer"),
                .float => std.mem.eql(u8, type_name, "float") or std.mem.eql(u8, type_name, "double"),
                .string => std.mem.eql(u8, type_name, "string"),
                .array => std.mem.eql(u8, type_name, "array"),
                .object => std.mem.eql(u8, type_name, "object") or 
                          std.mem.eql(u8, type_name, value.data.object.data.class.name.data),
                .resource => std.mem.eql(u8, type_name, "resource"),
                .builtin_function, .user_function, .closure, .arrow_function => std.mem.eql(u8, type_name, "callable"),
            };
            
            if (!is_valid) {
                return error.TypeError;
            }
        }
    };
    
    pub fn init(name: *PHPString) Method {
        return Method{
            .name = name,
            .parameters = &[_]Parameter{},
            .return_type = null,
            .modifiers = .{},
            .attributes = &[_]Attribute{},
            .body = null,
        };
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
    properties: std.StringHashMap(Value),
    
    pub fn init(allocator: std.mem.Allocator, class: *PHPClass) PHPObject {
        return PHPObject{
            .class = class,
            .properties = std.StringHashMap(Value).init(allocator),
        };
    }
    
    pub fn deinit(self: *PHPObject) void {
        // Release all property values
        var iterator = self.properties.iterator();
        while (iterator.next()) |_| {
            // TODO: Properly release Value memory based on its type
            // For now, we'll let the GC handle it
        }
        self.properties.deinit();
    }
    
    pub fn getProperty(self: *PHPObject, name: []const u8) !Value {
        // First check if we have the property value directly
        if (self.properties.get(name)) |value| {
            return value;
        }
        
        // Check if property exists in class definition
        const prop_def = self.class.getProperty(name);
        if (prop_def) |property| {
            // Check if property has get hook
            if (property.hasGetHook()) {
                // Would execute get hook here
                return property.default_value orelse Value.initNull();
            }
            
            return property.default_value orelse Value.initNull();
        }
        
        // Try magic __get method
        if (self.class.hasMethod("__get")) {
            // Would call __get magic method here
            return error.UndefinedProperty;
        }
        
        return error.UndefinedProperty;
    }
    
    pub fn setProperty(self: *PHPObject, name: []const u8, value: Value) !void {
        // Check if property exists in class definition
        const prop_def = self.class.getProperty(name);
        if (prop_def == null) {
            // Try magic __set method
            if (self.class.hasMethod("__set")) {
                // Would call __set magic method here
                return;
            }
            // For dynamic properties, just set it
            try self.properties.put(name, value);
            return;
        }
        
        const property = prop_def.?;
        
        // Check if readonly
        if (property.modifiers.is_readonly) {
            // Check if already set
            if (self.properties.contains(name)) {
                return error.ReadonlyPropertyModification;
            }
        }
        
        // Check if property has set hook
        if (property.hasSetHook()) {
            // Would execute set hook here
            try self.properties.put(name, value);
            return;
        }
        
        try self.properties.put(name, value);
    }
    
    pub fn hasMethod(self: *PHPObject, name: []const u8) bool {
        return self.class.hasMethod(name);
    }
    
    pub fn callMethod(self: *PHPObject, vm: *anyopaque, name: []const u8, args: []const Value) !Value {
        const method = self.class.getMethod(name);
        if (method == null) {
            // Try magic __call method
            if (self.class.hasMethod("__call")) {
                // Would call __call magic method here
                return error.UndefinedMethod;
            }
            return error.UndefinedMethod;
        }
        
        // For now, return null - actual method execution would happen here
        _ = vm;
        _ = args;
        return Value.initNull();
    }
    
    pub fn clone(self: *PHPObject, allocator: std.mem.Allocator) !*PHPObject {
        const new_object = try allocator.create(PHPObject);
        new_object.* = PHPObject.init(allocator, self.class);
        
        // Copy properties
        var iterator = self.properties.iterator();
        while (iterator.next()) |entry| {
            try new_object.properties.put(entry.key_ptr.*, entry.value_ptr.*);
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
            // Would call __toString magic method here
            return PHPString.init(allocator, "Object");
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
    destructor: ?*const fn(*anyopaque) void,
    
    pub fn init(type_name: *PHPString, data: *anyopaque, destructor: ?*const fn(*anyopaque) void) PHPResource {
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
    is_nullable: bool = false,
    is_union: bool = false,
    union_types: []const *TypeInfo = &[_]*TypeInfo{},
    
    pub fn init(name: *PHPString) TypeInfo {
        return TypeInfo{
            .name = name,
        };
    }
};

pub const Value = struct {
    tag: Tag,
    data: Data,

    const Self = @This();

    pub fn initNull() Self {
        return .{ .tag = .null, .data = .{ .null = {} } };
    }
    
    pub fn initBool(value: bool) Self {
        return .{ .tag = .boolean, .data = .{ .boolean = value } };
    }
    
    pub fn initInt(value: i64) Self {
        return .{ .tag = .integer, .data = .{ .integer = value } };
    }
    
    pub fn initFloat(value: f64) Self {
        return .{ .tag = .float, .data = .{ .float = value } };
    }

    pub fn initString(allocator: std.mem.Allocator, str: []const u8) !Self {
        const php_string = try PHPString.init(allocator, str);
        const box = try allocator.create(gc.Box(*PHPString));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = php_string,
        };
        return .{ .tag = .string, .data = .{ .string = box } };
    }
    
    pub fn initStringWithManager(memory_manager: *gc.MemoryManager, str: []const u8) !Self {
        const box = try memory_manager.allocString(str);
        return .{ .tag = .string, .data = .{ .string = box } };
    }
    
    pub fn initArray(allocator: std.mem.Allocator) !Self {
        const php_array = try allocator.create(PHPArray);
        php_array.* = PHPArray.init(allocator);
        const box = try allocator.create(gc.Box(*PHPArray));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = php_array,
        };
        return .{ .tag = .array, .data = .{ .array = box } };
    }
    
    pub fn initArrayWithManager(memory_manager: *gc.MemoryManager) !Self {
        const box = try memory_manager.allocArray();
        return .{ .tag = .array, .data = .{ .array = box } };
    }
    
    pub fn initObject(allocator: std.mem.Allocator, class: *PHPClass) !Self {
        const php_object = try allocator.create(PHPObject);
        php_object.* = PHPObject.init(allocator, class);
        const box = try allocator.create(gc.Box(*PHPObject));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = php_object,
        };
        return .{ .tag = .object, .data = .{ .object = box } };
    }
    
    pub fn initObjectWithManager(memory_manager: *gc.MemoryManager, class: *PHPClass) !Self {
        const box = try memory_manager.allocObject(class);
        return .{ .tag = .object, .data = .{ .object = box } };
    }
    
    pub fn initResource(allocator: std.mem.Allocator, resource: PHPResource) !Self {
        const php_resource = try allocator.create(PHPResource);
        php_resource.* = resource;
        const box = try allocator.create(gc.Box(*PHPResource));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = php_resource,
        };
        return .{ .tag = .resource, .data = .{ .resource = box } };
    }
    
    pub fn initResourceWithManager(memory_manager: *gc.MemoryManager, resource: PHPResource) !Self {
        const box = try memory_manager.allocResource(resource);
        return .{ .tag = .resource, .data = .{ .resource = box } };
    }

    pub fn print(self: Self) !void {
        switch (self.tag) {
            .null => std.debug.print("null", .{}),
            .boolean => std.debug.print("{any}", .{self.data.boolean}),
            .integer => std.debug.print("{any}", .{self.data.integer}),
            .float => std.debug.print("{any}", .{self.data.float}),
            .string => std.debug.print("{s}", .{self.data.string.data.data}),
            .array => std.debug.print("Array({d})", .{self.data.array.data.count()}),
            .object => std.debug.print("Object({s})", .{self.data.object.data.class.name.data}),
            .resource => std.debug.print("Resource({s})", .{self.data.resource.data.type_name.data}),
            .builtin_function => std.debug.print("builtin_function", .{}),
            .user_function => std.debug.print("user_function", .{}),
            .closure => std.debug.print("closure", .{}),
            .arrow_function => std.debug.print("arrow_function", .{}),
        }
    }
    
    // Type conversion functions
    pub fn toBool(self: Self) bool {
        return switch (self.tag) {
            .null => false,
            .boolean => self.data.boolean,
            .integer => self.data.integer != 0,
            .float => self.data.float != 0.0,
            .string => self.data.string.data.length > 0 and !std.mem.eql(u8, self.data.string.data.data, "0"),
            .array => self.data.array.data.count() > 0,
            .object, .resource => true,
            else => true,
        };
    }
    
    pub fn toInt(self: Self) !i64 {
        return switch (self.tag) {
            .null => 0,
            .boolean => if (self.data.boolean) @as(i64, 1) else @as(i64, 0),
            .integer => self.data.integer,
            .float => @intFromFloat(self.data.float),
            .string => std.fmt.parseInt(i64, self.data.string.data.data, 10) catch 0,
            else => error.InvalidConversion,
        };
    }
    
    pub fn toFloat(self: Self) !f64 {
        return switch (self.tag) {
            .null => 0.0,
            .boolean => if (self.data.boolean) @as(f64, 1.0) else @as(f64, 0.0),
            .integer => @floatFromInt(self.data.integer),
            .float => self.data.float,
            .string => std.fmt.parseFloat(f64, self.data.string.data.data) catch 0.0,
            else => error.InvalidConversion,
        };
    }
    
    pub fn toString(self: Self, allocator: std.mem.Allocator) !*PHPString {
        return switch (self.tag) {
            .null => PHPString.init(allocator, ""),
            .boolean => PHPString.init(allocator, if (self.data.boolean) "1" else ""),
            .integer => {
                const str = try std.fmt.allocPrint(allocator, "{d}", .{self.data.integer});
                defer allocator.free(str);
                return PHPString.init(allocator, str);
            },
            .float => {
                const str = try std.fmt.allocPrint(allocator, "{d}", .{self.data.float});
                defer allocator.free(str);
                return PHPString.init(allocator, str);
            },
            .string => PHPString.init(allocator, self.data.string.data.data),
            .array => PHPString.init(allocator, "Array"),
            .object => PHPString.init(allocator, "Object"),
            .resource => PHPString.init(allocator, "Resource"),
            else => error.InvalidConversion,
        };
    }
    
    // Type checking functions
    pub fn isNull(self: Self) bool {
        return self.tag == .null;
    }
    
    pub fn isBool(self: Self) bool {
        return self.tag == .boolean;
    }
    
    pub fn isInt(self: Self) bool {
        return self.tag == .integer;
    }
    
    pub fn isFloat(self: Self) bool {
        return self.tag == .float;
    }
    
    pub fn isString(self: Self) bool {
        return self.tag == .string;
    }
    
    pub fn isArray(self: Self) bool {
        return self.tag == .array;
    }
    
    pub fn isObject(self: Self) bool {
        return self.tag == .object;
    }
    
    pub fn isResource(self: Self) bool {
        return self.tag == .resource;
    }
    
    pub fn isCallable(self: Self) bool {
        return switch (self.tag) {
            .builtin_function, .user_function, .closure, .arrow_function => true,
            else => false,
        };
    }

    pub const Tag = enum {
        // Basic types
        null,
        boolean,
        integer,
        float,
        string,
        
        // Composite types
        array,
        object,
        resource,
        
        // Callable types
        builtin_function,
        user_function,
        closure,
        arrow_function,
    };

    pub const Data = union {
        null: void,
        boolean: bool,
        integer: i64,
        float: f64,
        string: *gc.Box(*PHPString),
        array: *gc.Box(*PHPArray),
        object: *gc.Box(*PHPObject),
        resource: *gc.Box(*PHPResource),
        builtin_function: *const anyopaque,
        user_function: *gc.Box(*UserFunction),
        closure: *gc.Box(*Closure),
        arrow_function: *gc.Box(*ArrowFunction),
    };
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
                try bound_args.put(param.name.data, args[i]);
            } else if (param.default_value) |default| {
                // Use default value
                try bound_args.put(param.name.data, default);
            } else if (!param.is_variadic) {
                // Required parameter missing
                return error.MissingRequiredParameter;
            }
        }
        
        // Handle variadic parameters
        if (self.is_variadic and args.len > self.parameters.len - 1) {
            const variadic_param = self.parameters[self.parameters.len - 1];
            var variadic_array = PHPArray.init(allocator);
            
            for (args[self.parameters.len - 1..]) |arg| {
                try variadic_array.push(arg);
            }
            
            const array_box = try allocator.create(gc.Box(*PHPArray));
            array_box.* = .{
                .ref_count = 1,
                .gc_info = .{},
                .data = try allocator.create(PHPArray),
            };
            array_box.data.* = variadic_array;
            
            const array_value = Value{ .tag = .array, .data = .{ .array = array_box } };
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
    
    pub fn deinit(self: *Closure) void {
        self.captured_vars.deinit();
    }
    
    pub fn call(self: *Closure, vm: *anyopaque, args: []const Value) !Value {
        // Validate arguments
        try self.function.validateArguments(args);
        
        // Bind arguments to parameters
        const VM = @import("vm.zig").VM;
        var bound_args = try self.function.bindArguments(args, @as(*VM, @ptrCast(@alignCast(vm))).allocator);
        defer bound_args.deinit();
        
        // Create new environment with captured variables and arguments
        // This would execute the function body in a real implementation
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
            const this_value = Value{ .tag = .object, .data = .{ .object = undefined } }; // Simplified
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
    
    pub fn deinit(self: *ArrowFunction) void {
        self.captured_vars.deinit();
    }
    
    pub fn call(self: *ArrowFunction, vm: *anyopaque, args: []const Value) !Value {
        // Validate arguments
        if (args.len != self.parameters.len) {
            return error.ArgumentCountMismatch;
        }
        
        // Type check arguments
        for (self.parameters, args) |param, arg| {
            try param.validateType(arg);
        }
        
        // Execute arrow function body (simplified)
        _ = vm;
        return Value.initNull();
    }
    
    pub fn autoCaptureVariable(self: *ArrowFunction, name: []const u8, value: Value) !void {
        try self.captured_vars.put(name, value);
    }
};

pub const BuiltinFn = *const fn (*anyopaque, []const Value) anyerror!Value;
