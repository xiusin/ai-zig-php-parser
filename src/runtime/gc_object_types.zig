const std = @import("std");
const GCObjectHeader = @import("generational_gc.zig").GCObjectHeader;

/// GC 对象类型系统
/// 用于完整的对象图遍历和标记
/// @memory-safety 所有类型都包含完整的引用信息
/// 对象类型标签
pub const ObjectType = enum(u8) {
    /// 基本类型（无引用）
    integer = 0,
    float = 1,
    boolean = 2,
    null_type = 3,

    /// 引用类型（需要扫描）
    string = 4,
    array = 5,
    object = 6,
    closure = 7,
    reference = 8,

    /// 特殊类型
    resource = 9,
    unknown = 255,
};

/// 类型化的 GC 对象头
/// 扩展 GCObjectHeader，添加类型信息
pub const TypedGCObject = struct {
    header: GCObjectHeader,
    type_tag: ObjectType,

    /// 获取数据指针
    pub fn getDataPtr(self: *TypedGCObject) *anyopaque {
        return self.header.getDataPtr();
    }

    /// 从数据指针获取对象头
    pub fn fromDataPtr(data: *anyopaque) *TypedGCObject {
        const header = GCObjectHeader.fromDataPtr(data);
        const header_ptr: [*]u8 = @ptrCast(header);
        return @ptrCast(@alignCast(header_ptr - @sizeOf(ObjectType)));
    }

    /// 检查是否有引用
    pub fn hasReferences(self: *const TypedGCObject) bool {
        return switch (self.type_tag) {
            .array, .object, .closure, .reference => true,
            else => false,
        };
    }
};

/// 数组对象
pub const ArrayObject = struct {
    /// 元素数量
    count: usize,
    /// 容量
    capacity: usize,
    /// 元素数组（紧跟在结构体后面）
    /// 每个元素是一个指向 TypedGCObject 的指针
    /// 获取元素指针数组
    pub fn getElements(self: *ArrayObject) []*TypedGCObject {
        const self_ptr: [*]u8 = @ptrCast(self);
        const elements_ptr: [*]*TypedGCObject = @ptrCast(@alignCast(self_ptr + @sizeOf(ArrayObject)));
        return elements_ptr[0..self.count];
    }

    /// 计算数组对象的总大小
    pub fn calculateSize(capacity: usize) usize {
        return @sizeOf(TypedGCObject) + @sizeOf(ArrayObject) + capacity * @sizeOf(*TypedGCObject);
    }
};

/// 对象属性
pub const ObjectProperty = struct {
    /// 属性名哈希（用于快速查找）
    name_hash: u64,
    /// 属性名长度
    name_len: u32,
    /// 属性值指针
    value: *TypedGCObject,
    /// 属性名（紧跟在结构体后面）
    /// 获取属性名
    pub fn getName(self: *ObjectProperty) []const u8 {
        const self_ptr: [*]u8 = @ptrCast(self);
        const name_ptr = self_ptr + @sizeOf(ObjectProperty);
        return name_ptr[0..self.name_len];
    }
};

/// 对象实例
pub const ObjectInstance = struct {
    /// 类名哈希
    class_hash: u64,
    /// 属性数量
    property_count: usize,
    /// 属性数组（紧跟在结构体后面）
    /// 获取属性数组
    pub fn getProperties(self: *ObjectInstance) []ObjectProperty {
        const self_ptr: [*]u8 = @ptrCast(self);
        const props_ptr: [*]ObjectProperty = @ptrCast(@alignCast(self_ptr + @sizeOf(ObjectInstance)));
        return props_ptr[0..self.property_count];
    }

    /// 计算对象实例的总大小
    pub fn calculateSize(property_count: usize, total_name_len: usize) usize {
        return @sizeOf(TypedGCObject) +
            @sizeOf(ObjectInstance) +
            property_count * @sizeOf(ObjectProperty) +
            total_name_len;
    }
};

/// 闭包捕获的变量
pub const CapturedVar = struct {
    /// 变量名哈希
    name_hash: u64,
    /// 变量值指针
    value: *TypedGCObject,
};

/// 闭包对象
pub const ClosureObject = struct {
    /// 函数指针
    function_ptr: *const anyopaque,
    /// 捕获变量数量
    captured_count: usize,
    /// 捕获变量数组（紧跟在结构体后面）
    /// 获取捕获变量数组
    pub fn getCapturedVars(self: *ClosureObject) []CapturedVar {
        const self_ptr: [*]u8 = @ptrCast(self);
        const vars_ptr: [*]CapturedVar = @ptrCast(@alignCast(self_ptr + @sizeOf(ClosureObject)));
        return vars_ptr[0..self.captured_count];
    }

    /// 计算闭包对象的总大小
    pub fn calculateSize(captured_count: usize) usize {
        return @sizeOf(TypedGCObject) + @sizeOf(ClosureObject) + captured_count * @sizeOf(CapturedVar);
    }
};

/// 引用对象（PHP 引用）
pub const ReferenceObject = struct {
    /// 引用计数
    ref_count: usize,
    /// 指向的对象
    target: *TypedGCObject,
};

/// 字符串对象
pub const StringObject = struct {
    /// 字符串长度
    length: usize,
    /// 字符串哈希（用于快速比较）
    hash: u64,
    /// 字符串数据（紧跟在结构体后面）
    /// 获取字符串数据
    pub fn getData(self: *StringObject) []const u8 {
        const self_ptr: [*]u8 = @ptrCast(self);
        const data_ptr = self_ptr + @sizeOf(StringObject);
        return data_ptr[0..self.length];
    }

    /// 计算字符串对象的总大小
    pub fn calculateSize(length: usize) usize {
        return @sizeOf(TypedGCObject) + @sizeOf(StringObject) + length;
    }
};

// ============================================================================
// 对象遍历器 - 用于 GC 标记
// ============================================================================

/// 对象引用遍历器
/// @concurrency-model ISOLATED
/// @memory-safety 确保所有引用都被正确遍历
pub const ObjectTraverser = struct {
    allocator: std.mem.Allocator,

    /// 遍历对象的所有引用
    /// @pre obj 必须是有效的 TypedGCObject
    /// @post worklist 包含所有被引用的对象
    pub fn traverseReferences(self: *ObjectTraverser, obj: *TypedGCObject, worklist: *std.ArrayListUnmanaged(*GCObjectHeader)) !void {
        switch (obj.type_tag) {
            .array => {
                const data_ptr: *ArrayObject = @ptrCast(@alignCast(obj.getDataPtr()));
                const elements = data_ptr.getElements();

                for (elements) |elem| {
                    try worklist.append(self.allocator, &elem.header);
                }
            },

            .object => {
                const data_ptr: *ObjectInstance = @ptrCast(@alignCast(obj.getDataPtr()));
                const properties = data_ptr.getProperties();

                for (properties) |*prop| {
                    try worklist.append(self.allocator, &prop.value.header);
                }
            },

            .closure => {
                const data_ptr: *ClosureObject = @ptrCast(@alignCast(obj.getDataPtr()));
                const captured_vars = data_ptr.getCapturedVars();

                for (captured_vars) |*var_| {
                    try worklist.append(self.allocator, &var_.value.header);
                }
            },

            .reference => {
                const data_ptr: *ReferenceObject = @ptrCast(@alignCast(obj.getDataPtr()));
                try worklist.append(self.allocator, &data_ptr.target.header);
            },

            // 基本类型和字符串没有引用
            .integer, .float, .boolean, .null_type, .string, .resource, .unknown => {},
        }
    }
};

// ============================================================================
// 测试
// ============================================================================

test "array object traversal" {
    const allocator = std.testing.allocator;

    // 创建一个简单的数组对象用于测试
    const array_size = ArrayObject.calculateSize(3);
    const memory = try allocator.alloc(u8, array_size);
    defer allocator.free(memory);

    const typed_obj: *TypedGCObject = @ptrCast(@alignCast(memory.ptr));
    typed_obj.header = GCObjectHeader.init(@intCast(array_size));
    typed_obj.type_tag = .array;

    const array_obj: *ArrayObject = @ptrCast(@alignCast(typed_obj.getDataPtr()));
    array_obj.count = 3;
    array_obj.capacity = 3;

    // 验证类型检查
    try std.testing.expect(typed_obj.hasReferences());
    try std.testing.expect(typed_obj.type_tag == .array);
}

test "object instance traversal" {
    const allocator = std.testing.allocator;

    // 创建一个对象实例
    const obj_size = ObjectInstance.calculateSize(2, 10); // 2个属性，总名称长度10
    const memory = try allocator.alloc(u8, obj_size);
    defer allocator.free(memory);

    const typed_obj: *TypedGCObject = @ptrCast(@alignCast(memory.ptr));
    typed_obj.header = GCObjectHeader.init(@intCast(obj_size));
    typed_obj.type_tag = .object;

    const obj_inst: *ObjectInstance = @ptrCast(@alignCast(typed_obj.getDataPtr()));
    obj_inst.class_hash = 12345;
    obj_inst.property_count = 2;

    // 验证类型检查
    try std.testing.expect(typed_obj.hasReferences());
    try std.testing.expect(typed_obj.type_tag == .object);
}

test "closure object traversal" {
    const allocator = std.testing.allocator;

    // 创建一个闭包对象
    const closure_size = ClosureObject.calculateSize(2); // 2个捕获变量
    const memory = try allocator.alloc(u8, closure_size);
    defer allocator.free(memory);

    const typed_obj: *TypedGCObject = @ptrCast(@alignCast(memory.ptr));
    typed_obj.header = GCObjectHeader.init(@intCast(closure_size));
    typed_obj.type_tag = .closure;

    const closure_obj: *ClosureObject = @ptrCast(@alignCast(typed_obj.getDataPtr()));
    closure_obj.captured_count = 2;

    // 验证类型检查
    try std.testing.expect(typed_obj.hasReferences());
    try std.testing.expect(typed_obj.type_tag == .closure);
}

test "string object no references" {
    const allocator = std.testing.allocator;

    // 创建一个字符串对象
    const str_size = StringObject.calculateSize(10);
    const memory = try allocator.alloc(u8, str_size);
    defer allocator.free(memory);

    const typed_obj: *TypedGCObject = @ptrCast(@alignCast(memory.ptr));
    typed_obj.header = GCObjectHeader.init(@intCast(str_size));
    typed_obj.type_tag = .string;

    // 字符串没有引用
    try std.testing.expect(!typed_obj.hasReferences());
}
