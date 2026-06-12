//! AOT OOP 运行时支持
//!
//! 提供 PHP 面向对象特性的 AOT 编译支持：
//! - 对象/类实例化
//! - 接口实现
//! - 高阶函数（闭包/回调）
//! - Union Type
//! - Trait 特性
//! - 继承与多态
//!
//! @ownership TRANSFER (对象实例由调用者管理)
//! @thread-safety ISOLATED

const std = @import("std");
const Allocator = std.mem.Allocator;

/// PHP 对象实例运行时表示
/// @ownership TRANSFER
pub const PHPObject = struct {
    /// 类元信息引用
    class_meta: *const ClassMeta,
    /// 属性值存储（按属性索引访问）
    properties: []Value,
    /// 引用计数
    ref_count: u32,
    /// 分配器
    allocator: Allocator,

    const Self = @This();

    /// 创建新对象实例
    pub fn create(allocator: Allocator, class_meta: *const ClassMeta) !*Self {
        const obj = try allocator.create(Self);
        errdefer allocator.destroy(obj);

        const props = try allocator.alloc(Value, class_meta.property_count);
        errdefer allocator.free(props);

        // 初始化属性为 null
        for (props) |*p| {
            p.* = Value.initNull();
        }

        obj.* = .{
            .class_meta = class_meta,
            .properties = props,
            .ref_count = 1,
            .allocator = allocator,
        };

        return obj;
    }

    /// 增加引用计数
    pub fn retain(self: *Self) void {
        self.ref_count += 1;
    }

    /// 减少引用计数，归零时释放
    pub fn release(self: *Self) void {
        if (self.ref_count <= 1) {
            self.deinit();
        } else {
            self.ref_count -= 1;
        }
    }

    /// 释放对象
    fn deinit(self: *Self) void {
        self.allocator.free(self.properties);
        self.allocator.destroy(self);
    }

    /// 获取属性值
    pub fn getProperty(self: *const Self, index: u32) ?Value {
        if (index < self.properties.len) {
            return self.properties[index];
        }
        return null;
    }

    /// 设置属性值
    pub fn setProperty(self: *Self, index: u32, value: Value) bool {
        if (index < self.properties.len) {
            self.properties[index] = value;
            return true;
        }
        return false;
    }

    /// 检查是否实现接口
    pub fn implementsInterface(self: *const Self, iface_name: []const u8) bool {
        return self.class_meta.implementsInterface(iface_name);
    }

    /// 检查是否是指定类或其子类
    pub fn isInstanceOf(self: *const Self, class_name: []const u8) bool {
        return self.class_meta.isOrExtendsClass(class_name);
    }
};

/// 类元信息（编译时生成）
pub const ClassMeta = struct {
    /// 类名
    name: []const u8,
    /// 父类（null 表示无继承）
    parent: ?*const ClassMeta,
    /// 实现的接口列表
    interfaces: []const *const InterfaceMeta,
    /// 使用的 Trait 列表
    traits: []const *const TraitMeta,
    /// 属性数量
    property_count: u32,
    /// 属性元信息
    property_metas: []const PropertyMeta,
    /// 方法虚表（用于多态调用）
    vtable: []const MethodEntry,
    /// 是否为抽象类
    is_abstract: bool,
    /// 是否为 final 类
    is_final: bool,

    const Self = @This();

    /// 检查是否实现指定接口
    pub fn implementsInterface(self: *const Self, iface_name: []const u8) bool {
        for (self.interfaces) |iface| {
            if (std.mem.eql(u8, iface.name, iface_name)) {
                return true;
            }
        }
        // 检查父类
        if (self.parent) |parent| {
            return parent.implementsInterface(iface_name);
        }
        return false;
    }

    /// 检查是否是指定类或其子类
    pub fn isOrExtendsClass(self: *const Self, class_name: []const u8) bool {
        if (std.mem.eql(u8, self.name, class_name)) {
            return true;
        }
        if (self.parent) |parent| {
            return parent.isOrExtendsClass(class_name);
        }
        return false;
    }

    /// 查找方法
    pub fn findMethod(self: *const Self, name: []const u8) ?MethodEntry {
        for (self.vtable) |entry| {
            if (std.mem.eql(u8, entry.name, name)) {
                return entry;
            }
        }
        // 查找父类
        if (self.parent) |parent| {
            return parent.findMethod(name);
        }
        return null;
    }
};

/// 接口元信息
pub const InterfaceMeta = struct {
    /// 接口名
    name: []const u8,
    /// 父接口列表
    parents: []const *const InterfaceMeta,
    /// 必须实现的方法签名
    method_signatures: []const MethodSignature,
};

/// Trait 元信息
pub const TraitMeta = struct {
    /// Trait 名称
    name: []const u8,
    /// 提供的方法
    methods: []const MethodEntry,
    /// 抽象方法（使用者必须实现）
    abstract_methods: []const MethodSignature,
    /// 依赖的其他 Trait
    required_traits: []const *const TraitMeta,
};

/// 属性元信息
pub const PropertyMeta = struct {
    /// 属性名
    name: []const u8,
    /// 属性索引
    index: u32,
    /// 类型信息
    type_info: TypeInfo,
    /// 可见性
    visibility: Visibility,
    /// 是否静态
    is_static: bool,
    /// 是否只读
    is_readonly: bool,
    /// 默认值（可选）
    default_value: ?Value,
};

/// 方法条目（虚表项）
pub const MethodEntry = struct {
    /// 方法名
    name: []const u8,
    /// 方法指针
    func_ptr: *const anyopaque,
    /// 可见性
    visibility: Visibility,
    /// 是否静态
    is_static: bool,
    /// 是否 final
    is_final: bool,
    /// 参数数量
    param_count: u8,
};

/// 方法签名
pub const MethodSignature = struct {
    /// 方法名
    name: []const u8,
    /// 参数类型列表
    param_types: []const TypeInfo,
    /// 返回类型
    return_type: TypeInfo,
    /// 是否静态
    is_static: bool,
};

/// 可见性
pub const Visibility = enum {
    public,
    protected,
    private,
};

// ============================================================================
// Union Type 支持
// ============================================================================

/// Union Type 运行时表示
pub const UnionType = struct {
    /// 可能的类型列表
    types: []const TypeInfo,

    const Self = @This();

    /// 检查值是否符合 union type
    pub fn accepts(self: *const Self, value: Value) bool {
        const value_type = value.getTypeInfo();
        for (self.types) |t| {
            if (t.isCompatibleWith(value_type)) {
                return true;
            }
        }
        return false;
    }

    /// 创建包含两个类型的 union
    pub fn of2(comptime T1: TypeInfo, comptime T2: TypeInfo) Self {
        return .{ .types = &[_]TypeInfo{ T1, T2 } };
    }

    /// 创建包含三个类型的 union
    pub fn of3(comptime T1: TypeInfo, comptime T2: TypeInfo, comptime T3: TypeInfo) Self {
        return .{ .types = &[_]TypeInfo{ T1, T2, T3 } };
    }
};

/// 类型信息
pub const TypeInfo = struct {
    kind: Kind,
    class_name: ?[]const u8 = null,
    element_type: ?*const TypeInfo = null,

    pub const Kind = enum {
        null,
        bool,
        int,
        float,
        string,
        array,
        object,
        callable,
        mixed,
        void,
        never,
        iterable,
        self_type,
        parent_type,
        static_type,
    };

    /// 检查类型兼容性
    pub fn isCompatibleWith(self: TypeInfo, other: TypeInfo) bool {
        if (self.kind == .mixed) return true;
        if (self.kind == other.kind) {
            if (self.kind == .object) {
                if (self.class_name == null) return true;
                if (other.class_name) |other_name| {
                    if (self.class_name) |self_name| {
                        return std.mem.eql(u8, self_name, other_name);
                    }
                }
            }
            return true;
        }
        return false;
    }

    /// 预定义类型常量
    pub const NULL = TypeInfo{ .kind = .null };
    pub const BOOL = TypeInfo{ .kind = .bool };
    pub const INT = TypeInfo{ .kind = .int };
    pub const FLOAT = TypeInfo{ .kind = .float };
    pub const STRING = TypeInfo{ .kind = .string };
    pub const ARRAY = TypeInfo{ .kind = .array };
    pub const MIXED = TypeInfo{ .kind = .mixed };
    pub const VOID = TypeInfo{ .kind = .void };
    pub const CALLABLE = TypeInfo{ .kind = .callable };
};

// ============================================================================
// 高阶函数支持（闭包/回调）
// ============================================================================

/// 闭包运行时表示
pub const Closure = struct {
    /// 捕获的变量
    captures: []Value,
    /// 函数指针
    func_ptr: *const anyopaque,
    /// 参数数量
    param_count: u8,
    /// 引用计数
    ref_count: u32,
    /// 分配器
    allocator: Allocator,
    /// 绑定的 $this（如果有）
    bound_this: ?*PHPObject,

    const Self = @This();

    /// 创建闭包
    pub fn create(
        allocator: Allocator,
        func_ptr: *const anyopaque,
        captures: []const Value,
        param_count: u8,
    ) !*Self {
        const closure = try allocator.create(Self);
        errdefer allocator.destroy(closure);

        const captured = try allocator.alloc(Value, captures.len);
        errdefer allocator.free(captured);
        @memcpy(captured, captures);

        closure.* = .{
            .captures = captured,
            .func_ptr = func_ptr,
            .param_count = param_count,
            .ref_count = 1,
            .allocator = allocator,
            .bound_this = null,
        };

        return closure;
    }

    /// 绑定 $this
    pub fn bindTo(self: *Self, obj: *PHPObject) *Self {
        obj.retain();
        if (self.bound_this) |old| {
            old.release();
        }
        self.bound_this = obj;
        return self;
    }

    /// 增加引用计数
    pub fn retain(self: *Self) void {
        self.ref_count += 1;
    }

    /// 减少引用计数
    pub fn release(self: *Self) void {
        if (self.ref_count <= 1) {
            if (self.bound_this) |obj| {
                obj.release();
            }
            self.allocator.free(self.captures);
            self.allocator.destroy(self);
        } else {
            self.ref_count -= 1;
        }
    }
};

/// 回调函数类型
pub const Callable = union(enum) {
    /// 普通函数名
    function_name: []const u8,
    /// 闭包
    closure: *Closure,
    /// 对象方法 [object, method_name]
    object_method: struct {
        object: *PHPObject,
        method: []const u8,
    },
    /// 静态方法 [class_name, method_name]
    static_method: struct {
        class: []const u8,
        method: []const u8,
    },

    /// 检查是否可调用
    pub fn isCallable(self: Callable) bool {
        return switch (self) {
            .function_name => true,
            .closure => true,
            .object_method => |om| om.object.class_meta.findMethod(om.method) != null,
            .static_method => true,
        };
    }
};

// ============================================================================
// 值类型（AOT 简化版）
// ============================================================================

/// AOT 运行时值
pub const Value = union(enum) {
    null: void,
    bool: bool,
    int: i64,
    float: f64,
    string: []const u8,
    array: *anyopaque,
    object: *PHPObject,
    closure: *Closure,

    const Self = @This();

    pub fn initNull() Self {
        return .{ .null = {} };
    }

    pub fn initBool(v: bool) Self {
        return .{ .bool = v };
    }

    pub fn initInt(v: i64) Self {
        return .{ .int = v };
    }

    pub fn initFloat(v: f64) Self {
        return .{ .float = v };
    }

    pub fn initString(v: []const u8) Self {
        return .{ .string = v };
    }

    pub fn initObject(obj: *PHPObject) Self {
        return .{ .object = obj };
    }

    pub fn initClosure(c: *Closure) Self {
        return .{ .closure = c };
    }

    /// 获取类型信息
    pub fn getTypeInfo(self: Self) TypeInfo {
        return switch (self) {
            .null => TypeInfo.NULL,
            .bool => TypeInfo.BOOL,
            .int => TypeInfo.INT,
            .float => TypeInfo.FLOAT,
            .string => TypeInfo.STRING,
            .array => TypeInfo.ARRAY,
            .object => TypeInfo{ .kind = .object },
            .closure => TypeInfo.CALLABLE,
        };
    }

    /// 转换为布尔值
    pub fn toBool(self: Self) bool {
        return switch (self) {
            .null => false,
            .bool => |v| v,
            .int => |v| v != 0,
            .float => |v| v != 0.0,
            .string => |v| v.len > 0 and !std.mem.eql(u8, v, "0"),
            .array => true,
            .object => true,
            .closure => true,
        };
    }
};

// ============================================================================
// 继承与多态支持
// ============================================================================

/// 方法调度器（支持虚方法调用）
pub const MethodDispatcher = struct {
    /// 调用实例方法（多态）
    pub fn callMethod(
        obj: *PHPObject,
        method_name: []const u8,
        args: []const Value,
    ) ?Value {
        if (obj.class_meta.findMethod(method_name)) |entry| {
            _ = args;
            // 实际调用需要通过函数指针
            _ = entry.func_ptr;
            return Value.initNull();
        }
        return null;
    }

    /// 调用父类方法
    pub fn callParentMethod(
        obj: *PHPObject,
        method_name: []const u8,
        args: []const Value,
    ) ?Value {
        if (obj.class_meta.parent) |parent| {
            if (parent.findMethod(method_name)) |entry| {
                _ = args;
                _ = entry.func_ptr;
                return Value.initNull();
            }
        }
        return null;
    }
};

// ============================================================================
// 测试
// ============================================================================

test "PHPObject basic operations" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // 创建测试类元信息
    const class_meta = ClassMeta{
        .name = "TestClass",
        .parent = null,
        .interfaces = &.{},
        .traits = &.{},
        .property_count = 2,
        .property_metas = &.{},
        .vtable = &.{},
        .is_abstract = false,
        .is_final = false,
    };

    // 创建对象
    const obj = try PHPObject.create(allocator, &class_meta);
    defer obj.release();

    // 测试属性操作
    try testing.expect(obj.setProperty(0, Value.initInt(42)));
    try testing.expectEqual(@as(i64, 42), obj.getProperty(0).?.int);

    // 测试类型检查
    try testing.expect(obj.isInstanceOf("TestClass"));
    try testing.expect(!obj.isInstanceOf("OtherClass"));
}

test "Closure operations" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const dummy_fn: *const anyopaque = @ptrFromInt(0x1000);
    const captures = [_]Value{ Value.initInt(1), Value.initInt(2) };

    const closure = try Closure.create(allocator, dummy_fn, &captures, 1);
    defer closure.release();

    try testing.expectEqual(@as(u8, 1), closure.param_count);
    try testing.expectEqual(@as(usize, 2), closure.captures.len);
}

test "UnionType accepts" {
    const testing = std.testing;

    const int_or_string = UnionType.of2(TypeInfo.INT, TypeInfo.STRING);

    try testing.expect(int_or_string.accepts(Value.initInt(42)));
    try testing.expect(int_or_string.accepts(Value.initString("hello")));
    try testing.expect(!int_or_string.accepts(Value.initBool(true)));
}
