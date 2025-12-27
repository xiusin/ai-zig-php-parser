const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const PHPString = types.PHPString;
const PHPClass = types.PHPClass;
const PHPObject = types.PHPObject;
const PHPArray = types.PHPArray;
const Property = types.Property;
const Method = types.Method;
const gc = types.gc;

/// PHP内置类管理器
/// 提供stdClass、Exception、Iterator等内置类
pub const BuiltinClassManager = struct {
    allocator: std.mem.Allocator,
    classes: std.StringHashMap(*PHPClass),

    pub fn init(allocator: std.mem.Allocator) !BuiltinClassManager {
        var manager = BuiltinClassManager{
            .allocator = allocator,
            .classes = std.StringHashMap(*PHPClass).init(allocator),
        };

        // 注册所有内置类
        try manager.registerBuiltinClasses();

        return manager;
    }

    pub fn deinit(self: *BuiltinClassManager) void {
        var iter = self.classes.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.*.deinit(self.allocator);
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.classes.deinit();
    }

    fn registerBuiltinClasses(self: *BuiltinClassManager) !void {
        // stdClass - PHP的基础动态对象类
        try self.registerStdClass();

        // Exception类层级
        try self.registerExceptionClasses();

        // Iterator接口
        try self.registerIteratorInterfaces();

        // ArrayAccess接口
        try self.registerArrayAccess();

        // Closure类
        try self.registerClosureClass();

        // DateTime类
        try self.registerDateTimeClasses();
    }

    /// 注册stdClass
    fn registerStdClass(self: *BuiltinClassManager) !void {
        const class_name = try PHPString.init(self.allocator, "stdClass");
        const class = try self.allocator.create(PHPClass);
        class.* = PHPClass.init(self.allocator, class_name);

        // stdClass不需要任何预定义属性或方法
        // 它是一个完全动态的类

        try self.classes.put("stdClass", class);
    }

    /// 注册Exception类层级
    fn registerExceptionClasses(self: *BuiltinClassManager) !void {
        // 基础Exception类
        const exception_name = try PHPString.init(self.allocator, "Exception");
        const exception_class = try self.allocator.create(PHPClass);
        exception_class.* = PHPClass.init(self.allocator, exception_name);

        // 添加Exception属性
        try self.addProperty(exception_class, "message", .public, null);
        try self.addProperty(exception_class, "code", .public, null);
        try self.addProperty(exception_class, "file", .protected, null);
        try self.addProperty(exception_class, "line", .protected, null);
        try self.addProperty(exception_class, "previous", .private, null);

        try self.classes.put("Exception", exception_class);

        // Error类
        const error_name = try PHPString.init(self.allocator, "Error");
        const error_class = try self.allocator.create(PHPClass);
        error_class.* = PHPClass.init(self.allocator, error_name);
        try self.addProperty(error_class, "message", .public, null);
        try self.addProperty(error_class, "code", .public, null);
        try self.addProperty(error_class, "file", .protected, null);
        try self.addProperty(error_class, "line", .protected, null);
        try self.classes.put("Error", error_class);

        // TypeError
        const type_error_name = try PHPString.init(self.allocator, "TypeError");
        const type_error_class = try self.allocator.create(PHPClass);
        type_error_class.* = PHPClass.init(self.allocator, type_error_name);
        type_error_class.parent = error_class;
        try self.classes.put("TypeError", type_error_class);

        // ArgumentCountError
        const arg_count_error_name = try PHPString.init(self.allocator, "ArgumentCountError");
        const arg_count_error_class = try self.allocator.create(PHPClass);
        arg_count_error_class.* = PHPClass.init(self.allocator, arg_count_error_name);
        arg_count_error_class.parent = type_error_class;
        try self.classes.put("ArgumentCountError", arg_count_error_class);

        // RuntimeException
        const runtime_exception_name = try PHPString.init(self.allocator, "RuntimeException");
        const runtime_exception_class = try self.allocator.create(PHPClass);
        runtime_exception_class.* = PHPClass.init(self.allocator, runtime_exception_name);
        runtime_exception_class.parent = exception_class;
        try self.classes.put("RuntimeException", runtime_exception_class);

        // InvalidArgumentException
        const invalid_arg_name = try PHPString.init(self.allocator, "InvalidArgumentException");
        const invalid_arg_class = try self.allocator.create(PHPClass);
        invalid_arg_class.* = PHPClass.init(self.allocator, invalid_arg_name);
        invalid_arg_class.parent = exception_class;
        try self.classes.put("InvalidArgumentException", invalid_arg_class);

        // LogicException
        const logic_exception_name = try PHPString.init(self.allocator, "LogicException");
        const logic_exception_class = try self.allocator.create(PHPClass);
        logic_exception_class.* = PHPClass.init(self.allocator, logic_exception_name);
        logic_exception_class.parent = exception_class;
        try self.classes.put("LogicException", logic_exception_class);
    }

    /// 注册Iterator接口
    fn registerIteratorInterfaces(self: *BuiltinClassManager) !void {
        // Traversable接口（标记接口）
        const traversable_name = try PHPString.init(self.allocator, "Traversable");
        const traversable_class = try self.allocator.create(PHPClass);
        traversable_class.* = PHPClass.init(self.allocator, traversable_name);
        traversable_class.modifiers.is_abstract = true;
        try self.classes.put("Traversable", traversable_class);

        // Iterator接口
        const iterator_name = try PHPString.init(self.allocator, "Iterator");
        const iterator_class = try self.allocator.create(PHPClass);
        iterator_class.* = PHPClass.init(self.allocator, iterator_name);
        iterator_class.modifiers.is_abstract = true;
        // Iterator方法: current(), key(), next(), rewind(), valid()
        try self.classes.put("Iterator", iterator_class);

        // IteratorAggregate接口
        const iterator_agg_name = try PHPString.init(self.allocator, "IteratorAggregate");
        const iterator_agg_class = try self.allocator.create(PHPClass);
        iterator_agg_class.* = PHPClass.init(self.allocator, iterator_agg_name);
        iterator_agg_class.modifiers.is_abstract = true;
        try self.classes.put("IteratorAggregate", iterator_agg_class);

        // ArrayIterator类
        const array_iterator_name = try PHPString.init(self.allocator, "ArrayIterator");
        const array_iterator_class = try self.allocator.create(PHPClass);
        array_iterator_class.* = PHPClass.init(self.allocator, array_iterator_name);
        try self.addProperty(array_iterator_class, "storage", .private, null);
        try self.addProperty(array_iterator_class, "position", .private, null);
        try self.classes.put("ArrayIterator", array_iterator_class);
    }

    /// 注册ArrayAccess接口
    fn registerArrayAccess(self: *BuiltinClassManager) !void {
        const array_access_name = try PHPString.init(self.allocator, "ArrayAccess");
        const array_access_class = try self.allocator.create(PHPClass);
        array_access_class.* = PHPClass.init(self.allocator, array_access_name);
        array_access_class.modifiers.is_abstract = true;
        // ArrayAccess方法: offsetExists(), offsetGet(), offsetSet(), offsetUnset()
        try self.classes.put("ArrayAccess", array_access_class);

        // Countable接口
        const countable_name = try PHPString.init(self.allocator, "Countable");
        const countable_class = try self.allocator.create(PHPClass);
        countable_class.* = PHPClass.init(self.allocator, countable_name);
        countable_class.modifiers.is_abstract = true;
        try self.classes.put("Countable", countable_class);

        // ArrayObject类
        const array_object_name = try PHPString.init(self.allocator, "ArrayObject");
        const array_object_class = try self.allocator.create(PHPClass);
        array_object_class.* = PHPClass.init(self.allocator, array_object_name);
        try self.addProperty(array_object_class, "storage", .private, null);
        try self.classes.put("ArrayObject", array_object_class);
    }

    /// 注册Closure类
    fn registerClosureClass(self: *BuiltinClassManager) !void {
        const closure_name = try PHPString.init(self.allocator, "Closure");
        const closure_class = try self.allocator.create(PHPClass);
        closure_class.* = PHPClass.init(self.allocator, closure_name);
        closure_class.modifiers.is_final = true;
        // Closure方法: bind(), bindTo(), call(), fromCallable()
        try self.classes.put("Closure", closure_class);
    }

    /// 注册DateTime类
    fn registerDateTimeClasses(self: *BuiltinClassManager) !void {
        // DateTimeInterface
        const datetime_interface_name = try PHPString.init(self.allocator, "DateTimeInterface");
        const datetime_interface_class = try self.allocator.create(PHPClass);
        datetime_interface_class.* = PHPClass.init(self.allocator, datetime_interface_name);
        datetime_interface_class.modifiers.is_abstract = true;
        try self.classes.put("DateTimeInterface", datetime_interface_class);

        // DateTime类
        const datetime_name = try PHPString.init(self.allocator, "DateTime");
        const datetime_class = try self.allocator.create(PHPClass);
        datetime_class.* = PHPClass.init(self.allocator, datetime_name);
        try self.addProperty(datetime_class, "timestamp", .private, null);
        try self.addProperty(datetime_class, "timezone", .private, null);
        try self.classes.put("DateTime", datetime_class);

        // DateTimeImmutable类
        const datetime_immutable_name = try PHPString.init(self.allocator, "DateTimeImmutable");
        const datetime_immutable_class = try self.allocator.create(PHPClass);
        datetime_immutable_class.* = PHPClass.init(self.allocator, datetime_immutable_name);
        try self.addProperty(datetime_immutable_class, "timestamp", .private, null);
        try self.addProperty(datetime_immutable_class, "timezone", .private, null);
        try self.classes.put("DateTimeImmutable", datetime_immutable_class);

        // DateInterval类
        const date_interval_name = try PHPString.init(self.allocator, "DateInterval");
        const date_interval_class = try self.allocator.create(PHPClass);
        date_interval_class.* = PHPClass.init(self.allocator, date_interval_name);
        try self.addProperty(date_interval_class, "y", .public, null);
        try self.addProperty(date_interval_class, "m", .public, null);
        try self.addProperty(date_interval_class, "d", .public, null);
        try self.addProperty(date_interval_class, "h", .public, null);
        try self.addProperty(date_interval_class, "i", .public, null);
        try self.addProperty(date_interval_class, "s", .public, null);
        try self.classes.put("DateInterval", date_interval_class);

        // DateTimeZone类
        const datetime_zone_name = try PHPString.init(self.allocator, "DateTimeZone");
        const datetime_zone_class = try self.allocator.create(PHPClass);
        datetime_zone_class.* = PHPClass.init(self.allocator, datetime_zone_name);
        try self.addProperty(datetime_zone_class, "name", .private, null);
        try self.classes.put("DateTimeZone", datetime_zone_class);
    }

    /// 辅助函数：添加属性
    fn addProperty(self: *BuiltinClassManager, class: *PHPClass, name: []const u8, visibility: Property.Visibility, default_value: ?Value) !void {
        const prop_name = try PHPString.init(self.allocator, name);
        var property = Property.init(prop_name);
        property.modifiers.visibility = visibility;
        property.default_value = default_value;
        try class.properties.put(name, property);
    }

    /// 获取内置类
    pub fn getClass(self: *BuiltinClassManager, name: []const u8) ?*PHPClass {
        return self.classes.get(name);
    }

    /// 检查类是否是内置类
    pub fn isBuiltinClass(self: *BuiltinClassManager, name: []const u8) bool {
        return self.classes.contains(name);
    }

    /// 创建stdClass实例
    pub fn createStdClass(self: *BuiltinClassManager) !Value {
        const std_class = self.classes.get("stdClass") orelse return error.StdClassNotFound;

        const php_object = try self.allocator.create(PHPObject);
        php_object.* = PHPObject.init(self.allocator, std_class);

        const box = try self.allocator.create(gc.Box(*PHPObject));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = php_object,
        };

        return Value{ .tag = .object, .data = .{ .object = box } };
    }

    /// 创建Exception实例
    pub fn createException(self: *BuiltinClassManager, message: []const u8, code: i64) !Value {
        const exception_class = self.classes.get("Exception") orelse return error.ExceptionClassNotFound;

        const php_object = try self.allocator.create(PHPObject);
        php_object.* = PHPObject.init(self.allocator, exception_class);

        // 设置message属性
        const msg_value = try Value.initString(self.allocator, message);
        try php_object.setProperty(self.allocator, "message", msg_value);

        // 设置code属性
        const code_value = Value.initInt(code);
        try php_object.setProperty(self.allocator, "code", code_value);

        const box = try self.allocator.create(gc.Box(*PHPObject));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = php_object,
        };

        return Value{ .tag = .object, .data = .{ .object = box } };
    }
};

/// stdClass动态属性支持
/// 允许在运行时动态添加和访问属性
pub const DynamicObject = struct {
    base_object: *PHPObject,
    dynamic_properties: std.StringHashMap(Value),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, base_object: *PHPObject) DynamicObject {
        return DynamicObject{
            .base_object = base_object,
            .dynamic_properties = std.StringHashMap(Value).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *DynamicObject) void {
        var iter = self.dynamic_properties.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.release(self.allocator);
        }
        self.dynamic_properties.deinit();
    }

    /// 设置动态属性
    pub fn setProperty(self: *DynamicObject, name: []const u8, value: Value) !void {
        // 首先检查是否是类定义的属性
        if (self.base_object.class.hasProperty(name)) {
            try self.base_object.setProperty(self.allocator, name, value);
            return;
        }

        // 否则添加为动态属性
        if (self.dynamic_properties.get(name)) |old_value| {
            old_value.release(self.allocator);
        }
        _ = value.retain();
        try self.dynamic_properties.put(name, value);
    }

    /// 获取动态属性
    pub fn getProperty(self: *DynamicObject, name: []const u8) !Value {
        // 首先检查类定义的属性
        if (self.base_object.getProperty(name)) |value| {
            return value;
        } else |_| {}

        // 然后检查动态属性
        if (self.dynamic_properties.get(name)) |value| {
            return value;
        }

        return error.UndefinedProperty;
    }

    /// 检查属性是否存在
    pub fn hasProperty(self: *DynamicObject, name: []const u8) bool {
        if (self.base_object.class.hasProperty(name)) {
            return true;
        }
        return self.dynamic_properties.contains(name);
    }

    /// 删除动态属性
    pub fn unsetProperty(self: *DynamicObject, name: []const u8) void {
        if (self.dynamic_properties.fetchRemove(name)) |kv| {
            kv.value.release(self.allocator);
        }
    }

    /// 获取所有属性名
    pub fn getPropertyNames(self: *DynamicObject) ![][]const u8 {
        var names = std.ArrayList([]const u8).init(self.allocator);

        // 添加类定义的属性
        var class_props = self.base_object.class.properties.iterator();
        while (class_props.next()) |entry| {
            try names.append(entry.key_ptr.*);
        }

        // 添加动态属性
        var dynamic_props = self.dynamic_properties.iterator();
        while (dynamic_props.next()) |entry| {
            try names.append(entry.key_ptr.*);
        }

        return names.toOwnedSlice();
    }
};

test "builtin class manager" {
    const allocator = std.testing.allocator;
    var manager = try BuiltinClassManager.init(allocator);
    defer manager.deinit();

    // 测试stdClass存在
    try std.testing.expect(manager.getClass("stdClass") != null);

    // 测试Exception类存在
    try std.testing.expect(manager.getClass("Exception") != null);

    // 测试创建stdClass实例
    const std_obj = try manager.createStdClass();
    defer std_obj.release(allocator);
    try std.testing.expect(std_obj.tag == .object);
}
