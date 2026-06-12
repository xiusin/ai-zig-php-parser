//! AOT OOP 运行时完整测试
//!
//! 测试所有 OOP 特性：对象、类、接口、继承、闭包、Union Type、Trait

const std = @import("std");
const testing = std.testing;
const oop = @import("oop_runtime.zig");

const PHPObject = oop.PHPObject;
const ClassMeta = oop.ClassMeta;
const InterfaceMeta = oop.InterfaceMeta;
const TraitMeta = oop.TraitMeta;
const Closure = oop.Closure;
const UnionType = oop.UnionType;
const TypeInfo = oop.TypeInfo;
const Value = oop.Value;
const PropertyMeta = oop.PropertyMeta;
const MethodEntry = oop.MethodEntry;
const MethodSignature = oop.MethodSignature;
const Visibility = oop.Visibility;
const Callable = oop.Callable;

// ============================================================================
// 测试用元数据定义
// ============================================================================

/// 测试接口：Serializable
const SerializableInterface = InterfaceMeta{
    .name = "Serializable",
    .parents = &.{},
    .method_signatures = &[_]MethodSignature{
        .{
            .name = "serialize",
            .param_types = &.{},
            .return_type = TypeInfo.STRING,
            .is_static = false,
        },
        .{
            .name = "unserialize",
            .param_types = &[_]TypeInfo{TypeInfo.STRING},
            .return_type = TypeInfo.VOID,
            .is_static = false,
        },
    },
};

/// 测试接口：JsonSerializable
const JsonSerializableInterface = InterfaceMeta{
    .name = "JsonSerializable",
    .parents = &.{},
    .method_signatures = &[_]MethodSignature{
        .{
            .name = "jsonSerialize",
            .param_types = &.{},
            .return_type = TypeInfo.MIXED,
            .is_static = false,
        },
    },
};

/// 测试 Trait：Loggable
const LoggableTrait = TraitMeta{
    .name = "Loggable",
    .methods = &[_]MethodEntry{
        .{
            .name = "log",
            .func_ptr = @ptrFromInt(0x2000),
            .visibility = .public,
            .is_static = false,
            .is_final = false,
            .param_count = 1,
        },
    },
    .abstract_methods = &.{},
    .required_traits = &.{},
};

/// 基类：BaseEntity
const BaseEntityClass = ClassMeta{
    .name = "BaseEntity",
    .parent = null,
    .interfaces = &.{},
    .traits = &.{},
    .property_count = 1,
    .property_metas = &[_]PropertyMeta{
        .{
            .name = "id",
            .index = 0,
            .type_info = TypeInfo.INT,
            .visibility = .protected,
            .is_static = false,
            .is_readonly = false,
            .default_value = Value.initInt(0),
        },
    },
    .vtable = &[_]MethodEntry{
        .{
            .name = "getId",
            .func_ptr = @ptrFromInt(0x1000),
            .visibility = .public,
            .is_static = false,
            .is_final = false,
            .param_count = 0,
        },
    },
    .is_abstract = false,
    .is_final = false,
};

/// 子类：User（继承 BaseEntity，实现 Serializable）
const UserClass = ClassMeta{
    .name = "User",
    .parent = &BaseEntityClass,
    .interfaces = &[_]*const InterfaceMeta{&SerializableInterface},
    .traits = &[_]*const TraitMeta{&LoggableTrait},
    .property_count = 3,
    .property_metas = &[_]PropertyMeta{
        .{
            .name = "id",
            .index = 0,
            .type_info = TypeInfo.INT,
            .visibility = .protected,
            .is_static = false,
            .is_readonly = false,
            .default_value = Value.initInt(0),
        },
        .{
            .name = "name",
            .index = 1,
            .type_info = TypeInfo.STRING,
            .visibility = .public,
            .is_static = false,
            .is_readonly = false,
            .default_value = null,
        },
        .{
            .name = "email",
            .index = 2,
            .type_info = TypeInfo.STRING,
            .visibility = .private,
            .is_static = false,
            .is_readonly = false,
            .default_value = null,
        },
    },
    .vtable = &[_]MethodEntry{
        .{
            .name = "getId",
            .func_ptr = @ptrFromInt(0x1000),
            .visibility = .public,
            .is_static = false,
            .is_final = false,
            .param_count = 0,
        },
        .{
            .name = "getName",
            .func_ptr = @ptrFromInt(0x1100),
            .visibility = .public,
            .is_static = false,
            .is_final = false,
            .param_count = 0,
        },
        .{
            .name = "serialize",
            .func_ptr = @ptrFromInt(0x1200),
            .visibility = .public,
            .is_static = false,
            .is_final = false,
            .param_count = 0,
        },
        .{
            .name = "unserialize",
            .func_ptr = @ptrFromInt(0x1300),
            .visibility = .public,
            .is_static = false,
            .is_final = false,
            .param_count = 1,
        },
    },
    .is_abstract = false,
    .is_final = false,
};

/// Final 类：Admin（继承 User，不可再继承）
const AdminClass = ClassMeta{
    .name = "Admin",
    .parent = &UserClass,
    .interfaces = &[_]*const InterfaceMeta{
        &SerializableInterface,
        &JsonSerializableInterface,
    },
    .traits = &.{},
    .property_count = 4,
    .property_metas = &[_]PropertyMeta{
        .{
            .name = "id",
            .index = 0,
            .type_info = TypeInfo.INT,
            .visibility = .protected,
            .is_static = false,
            .is_readonly = false,
            .default_value = Value.initInt(0),
        },
        .{
            .name = "name",
            .index = 1,
            .type_info = TypeInfo.STRING,
            .visibility = .public,
            .is_static = false,
            .is_readonly = false,
            .default_value = null,
        },
        .{
            .name = "email",
            .index = 2,
            .type_info = TypeInfo.STRING,
            .visibility = .private,
            .is_static = false,
            .is_readonly = false,
            .default_value = null,
        },
        .{
            .name = "role",
            .index = 3,
            .type_info = TypeInfo.STRING,
            .visibility = .public,
            .is_static = false,
            .is_readonly = true,
            .default_value = Value.initString("admin"),
        },
    },
    .vtable = &[_]MethodEntry{
        .{
            .name = "getId",
            .func_ptr = @ptrFromInt(0x1000),
            .visibility = .public,
            .is_static = false,
            .is_final = false,
            .param_count = 0,
        },
        .{
            .name = "jsonSerialize",
            .func_ptr = @ptrFromInt(0x1400),
            .visibility = .public,
            .is_static = false,
            .is_final = false,
            .param_count = 0,
        },
    },
    .is_abstract = false,
    .is_final = true,
};

// ============================================================================
// PHPObject 测试
// ============================================================================

test "PHPObject.create and release" {
    const allocator = testing.allocator;

    const obj = try PHPObject.create(allocator, &UserClass);
    try testing.expectEqual(@as(u32, 1), obj.ref_count);
    try testing.expectEqual(@as(usize, 3), obj.properties.len);

    obj.release();
}

test "PHPObject.retain and release" {
    const allocator = testing.allocator;

    const obj = try PHPObject.create(allocator, &UserClass);
    try testing.expectEqual(@as(u32, 1), obj.ref_count);

    obj.retain();
    try testing.expectEqual(@as(u32, 2), obj.ref_count);

    obj.retain();
    try testing.expectEqual(@as(u32, 3), obj.ref_count);

    obj.release();
    try testing.expectEqual(@as(u32, 2), obj.ref_count);

    obj.release();
    obj.release();
}

test "PHPObject.getProperty and setProperty" {
    const allocator = testing.allocator;

    const obj = try PHPObject.create(allocator, &UserClass);
    defer obj.release();

    // 设置属性
    try testing.expect(obj.setProperty(0, Value.initInt(42)));
    try testing.expect(obj.setProperty(1, Value.initString("John")));
    try testing.expect(obj.setProperty(2, Value.initString("john@example.com")));

    // 获取属性
    const id = obj.getProperty(0).?;
    try testing.expectEqual(@as(i64, 42), id.int);

    const name = obj.getProperty(1).?;
    try testing.expectEqualStrings("John", name.string);

    // 越界访问
    try testing.expect(obj.getProperty(99) == null);
    try testing.expect(!obj.setProperty(99, Value.initNull()));
}

test "PHPObject.isInstanceOf" {
    const allocator = testing.allocator;

    const user = try PHPObject.create(allocator, &UserClass);
    defer user.release();

    const admin = try PHPObject.create(allocator, &AdminClass);
    defer admin.release();

    // User instanceof 检查
    try testing.expect(user.isInstanceOf("User"));
    try testing.expect(user.isInstanceOf("BaseEntity"));
    try testing.expect(!user.isInstanceOf("Admin"));
    try testing.expect(!user.isInstanceOf("NonExistent"));

    // Admin instanceof 检查（继承链）
    try testing.expect(admin.isInstanceOf("Admin"));
    try testing.expect(admin.isInstanceOf("User"));
    try testing.expect(admin.isInstanceOf("BaseEntity"));
}

test "PHPObject.implementsInterface" {
    const allocator = testing.allocator;

    const user = try PHPObject.create(allocator, &UserClass);
    defer user.release();

    const admin = try PHPObject.create(allocator, &AdminClass);
    defer admin.release();

    // User 实现 Serializable
    try testing.expect(user.implementsInterface("Serializable"));
    try testing.expect(!user.implementsInterface("JsonSerializable"));

    // Admin 实现 Serializable 和 JsonSerializable
    try testing.expect(admin.implementsInterface("Serializable"));
    try testing.expect(admin.implementsInterface("JsonSerializable"));
}

// ============================================================================
// ClassMeta 测试
// ============================================================================

test "ClassMeta.isOrExtendsClass" {
    // 直接类名匹配
    try testing.expect(UserClass.isOrExtendsClass("User"));
    try testing.expect(AdminClass.isOrExtendsClass("Admin"));

    // 继承链检查
    try testing.expect(UserClass.isOrExtendsClass("BaseEntity"));
    try testing.expect(AdminClass.isOrExtendsClass("User"));
    try testing.expect(AdminClass.isOrExtendsClass("BaseEntity"));

    // 不匹配
    try testing.expect(!BaseEntityClass.isOrExtendsClass("User"));
    try testing.expect(!UserClass.isOrExtendsClass("Admin"));
}

test "ClassMeta.implementsInterface" {
    try testing.expect(UserClass.implementsInterface("Serializable"));
    try testing.expect(!UserClass.implementsInterface("JsonSerializable"));

    try testing.expect(AdminClass.implementsInterface("Serializable"));
    try testing.expect(AdminClass.implementsInterface("JsonSerializable"));

    try testing.expect(!BaseEntityClass.implementsInterface("Serializable"));
}

test "ClassMeta.findMethod" {
    // 直接方法
    const getName = UserClass.findMethod("getName");
    try testing.expect(getName != null);
    try testing.expectEqualStrings("getName", getName.?.name);

    // 继承的方法
    const getId = AdminClass.findMethod("getId");
    try testing.expect(getId != null);

    // 不存在的方法
    try testing.expect(UserClass.findMethod("nonExistent") == null);
}

// ============================================================================
// Closure 测试
// ============================================================================

test "Closure.create and release" {
    const allocator = testing.allocator;

    const dummy_fn: *const anyopaque = @ptrFromInt(0x3000);
    const captures = [_]Value{
        Value.initInt(10),
        Value.initString("captured"),
    };

    const closure = try Closure.create(allocator, dummy_fn, &captures, 2);
    defer closure.release();

    try testing.expectEqual(@as(u32, 1), closure.ref_count);
    try testing.expectEqual(@as(u8, 2), closure.param_count);
    try testing.expectEqual(@as(usize, 2), closure.captures.len);
    try testing.expectEqual(@as(i64, 10), closure.captures[0].int);
}

test "Closure.retain and release" {
    const allocator = testing.allocator;

    const dummy_fn: *const anyopaque = @ptrFromInt(0x3000);
    const closure = try Closure.create(allocator, dummy_fn, &.{}, 0);

    closure.retain();
    try testing.expectEqual(@as(u32, 2), closure.ref_count);

    closure.release();
    closure.release();
}

test "Closure.bindTo" {
    const allocator = testing.allocator;

    const obj = try PHPObject.create(allocator, &UserClass);
    defer obj.release();

    const dummy_fn: *const anyopaque = @ptrFromInt(0x3000);
    const closure = try Closure.create(allocator, dummy_fn, &.{}, 0);
    defer closure.release();

    // 绑定 $this
    _ = closure.bindTo(obj);
    try testing.expect(closure.bound_this != null);
    try testing.expectEqual(@as(u32, 2), obj.ref_count);

    // 重新绑定会释放旧的
    const obj2 = try PHPObject.create(allocator, &AdminClass);
    defer obj2.release();

    _ = closure.bindTo(obj2);
    try testing.expectEqual(@as(u32, 1), obj.ref_count);
    try testing.expectEqual(@as(u32, 2), obj2.ref_count);
}

// ============================================================================
// UnionType 测试
// ============================================================================

test "UnionType.accepts basic types" {
    const int_or_string = UnionType.of2(TypeInfo.INT, TypeInfo.STRING);

    try testing.expect(int_or_string.accepts(Value.initInt(42)));
    try testing.expect(int_or_string.accepts(Value.initString("hello")));
    try testing.expect(!int_or_string.accepts(Value.initBool(true)));
    try testing.expect(!int_or_string.accepts(Value.initFloat(3.14)));
    try testing.expect(!int_or_string.accepts(Value.initNull()));
}

test "UnionType.of3" {
    const mixed = UnionType.of3(TypeInfo.INT, TypeInfo.STRING, TypeInfo.BOOL);

    try testing.expect(mixed.accepts(Value.initInt(1)));
    try testing.expect(mixed.accepts(Value.initString("yes")));
    try testing.expect(mixed.accepts(Value.initBool(false)));
    try testing.expect(!mixed.accepts(Value.initFloat(1.0)));
}

test "UnionType with null" {
    const nullable_int = UnionType.of2(TypeInfo.INT, TypeInfo.NULL);

    try testing.expect(nullable_int.accepts(Value.initInt(100)));
    try testing.expect(nullable_int.accepts(Value.initNull()));
    try testing.expect(!nullable_int.accepts(Value.initString("nope")));
}

// ============================================================================
// TypeInfo 测试
// ============================================================================

test "TypeInfo.isCompatibleWith" {
    // 相同类型
    try testing.expect(TypeInfo.INT.isCompatibleWith(TypeInfo.INT));
    try testing.expect(TypeInfo.STRING.isCompatibleWith(TypeInfo.STRING));

    // mixed 接受任何类型
    try testing.expect(TypeInfo.MIXED.isCompatibleWith(TypeInfo.INT));
    try testing.expect(TypeInfo.MIXED.isCompatibleWith(TypeInfo.STRING));
    try testing.expect(TypeInfo.MIXED.isCompatibleWith(TypeInfo.NULL));

    // 不同类型不兼容
    try testing.expect(!TypeInfo.INT.isCompatibleWith(TypeInfo.STRING));
    try testing.expect(!TypeInfo.BOOL.isCompatibleWith(TypeInfo.FLOAT));
}

// ============================================================================
// Value 测试
// ============================================================================

test "Value.toBool" {
    // false 值
    try testing.expect(!Value.initNull().toBool());
    try testing.expect(!Value.initBool(false).toBool());
    try testing.expect(!Value.initInt(0).toBool());
    try testing.expect(!Value.initFloat(0.0).toBool());
    try testing.expect(!Value.initString("").toBool());
    try testing.expect(!Value.initString("0").toBool());

    // true 值
    try testing.expect(Value.initBool(true).toBool());
    try testing.expect(Value.initInt(1).toBool());
    try testing.expect(Value.initInt(-1).toBool());
    try testing.expect(Value.initFloat(0.1).toBool());
    try testing.expect(Value.initString("hello").toBool());
    try testing.expect(Value.initString("1").toBool());
}

test "Value.getTypeInfo" {
    try testing.expectEqual(TypeInfo.Kind.null, Value.initNull().getTypeInfo().kind);
    try testing.expectEqual(TypeInfo.Kind.bool, Value.initBool(true).getTypeInfo().kind);
    try testing.expectEqual(TypeInfo.Kind.int, Value.initInt(42).getTypeInfo().kind);
    try testing.expectEqual(TypeInfo.Kind.float, Value.initFloat(3.14).getTypeInfo().kind);
    try testing.expectEqual(TypeInfo.Kind.string, Value.initString("test").getTypeInfo().kind);
}

// ============================================================================
// Callable 测试
// ============================================================================

test "Callable.isCallable" {
    const allocator = testing.allocator;

    // 函数名
    const fn_callable = Callable{ .function_name = "array_map" };
    try testing.expect(fn_callable.isCallable());

    // 闭包
    const dummy_fn: *const anyopaque = @ptrFromInt(0x3000);
    const closure = try Closure.create(allocator, dummy_fn, &.{}, 0);
    defer closure.release();

    const closure_callable = Callable{ .closure = closure };
    try testing.expect(closure_callable.isCallable());

    // 对象方法
    const obj = try PHPObject.create(allocator, &UserClass);
    defer obj.release();

    const method_callable = Callable{
        .object_method = .{
            .object = obj,
            .method = "getName",
        },
    };
    try testing.expect(method_callable.isCallable());

    // 不存在的方法
    const invalid_callable = Callable{
        .object_method = .{
            .object = obj,
            .method = "nonExistent",
        },
    };
    try testing.expect(!invalid_callable.isCallable());

    // 静态方法
    const static_callable = Callable{
        .static_method = .{
            .class = "User",
            .method = "create",
        },
    };
    try testing.expect(static_callable.isCallable());
}

// ============================================================================
// 集成测试：完整 OOP 场景
// ============================================================================

test "integration: create object hierarchy" {
    const allocator = testing.allocator;

    // 创建 Admin 对象（继承 User -> BaseEntity）
    const admin = try PHPObject.create(allocator, &AdminClass);
    defer admin.release();

    // 设置属性
    try testing.expect(admin.setProperty(0, Value.initInt(1)));
    try testing.expect(admin.setProperty(1, Value.initString("Alice")));
    try testing.expect(admin.setProperty(2, Value.initString("alice@admin.com")));
    try testing.expect(admin.setProperty(3, Value.initString("super_admin")));

    // 验证继承链
    try testing.expect(admin.isInstanceOf("Admin"));
    try testing.expect(admin.isInstanceOf("User"));
    try testing.expect(admin.isInstanceOf("BaseEntity"));

    // 验证接口实现
    try testing.expect(admin.implementsInterface("Serializable"));
    try testing.expect(admin.implementsInterface("JsonSerializable"));

    // 验证方法查找
    try testing.expect(admin.class_meta.findMethod("getId") != null);
    try testing.expect(admin.class_meta.findMethod("jsonSerialize") != null);
}

test "integration: closure with bound object" {
    const allocator = testing.allocator;

    // 创建对象
    const user = try PHPObject.create(allocator, &UserClass);
    defer user.release();

    _ = user.setProperty(1, Value.initString("Bob"));

    // 创建闭包并绑定
    const dummy_fn: *const anyopaque = @ptrFromInt(0x4000);
    const captured_name = Value.initString("closure_var");
    const closure = try Closure.create(allocator, dummy_fn, &[_]Value{captured_name}, 1);
    defer closure.release();

    _ = closure.bindTo(user);

    // 验证绑定
    try testing.expect(closure.bound_this != null);
    try testing.expectEqualStrings("User", closure.bound_this.?.class_meta.name);
}
