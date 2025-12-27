const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const PHPString = types.PHPString;
const PHPClass = types.PHPClass;
const PHPInterface = types.PHPInterface;
const PHPTrait = types.PHPTrait;

/// PHP命名空间系统实现
/// 支持完整的命名空间导入、别名和自动加载
pub const NamespaceManager = struct {
    allocator: std.mem.Allocator,

    /// 当前命名空间
    current_namespace: []const u8,

    /// 命名空间中定义的类 namespace -> class_name -> class
    namespace_classes: std.StringHashMap(std.StringHashMap(*PHPClass)),

    /// 命名空间中定义的接口
    namespace_interfaces: std.StringHashMap(std.StringHashMap(*PHPInterface)),

    /// 命名空间中定义的函数
    namespace_functions: std.StringHashMap(std.StringHashMap(Value)),

    /// 命名空间中定义的常量
    namespace_constants: std.StringHashMap(std.StringHashMap(Value)),

    /// use导入的类别名 alias -> fully_qualified_name
    class_imports: std.StringHashMap([]const u8),

    /// use导入的函数别名
    function_imports: std.StringHashMap([]const u8),

    /// use导入的常量别名
    constant_imports: std.StringHashMap([]const u8),

    /// 自动加载器回调
    autoloaders: std.ArrayList(AutoloadCallback),

    /// 已加载的文件（用于include_once/require_once）
    loaded_files: std.StringHashMap(bool),

    pub const AutoloadCallback = struct {
        callback: Value,
        prepend: bool,
    };

    pub fn init(allocator: std.mem.Allocator) NamespaceManager {
        return NamespaceManager{
            .allocator = allocator,
            .current_namespace = "",
            .namespace_classes = std.StringHashMap(std.StringHashMap(*PHPClass)).init(allocator),
            .namespace_interfaces = std.StringHashMap(std.StringHashMap(*PHPInterface)).init(allocator),
            .namespace_functions = std.StringHashMap(std.StringHashMap(Value)).init(allocator),
            .namespace_constants = std.StringHashMap(std.StringHashMap(Value)).init(allocator),
            .class_imports = std.StringHashMap([]const u8).init(allocator),
            .function_imports = std.StringHashMap([]const u8).init(allocator),
            .constant_imports = std.StringHashMap([]const u8).init(allocator),
            .autoloaders = std.ArrayList(AutoloadCallback).init(allocator),
            .loaded_files = std.StringHashMap(bool).init(allocator),
        };
    }

    pub fn deinit(self: *NamespaceManager) void {
        // 清理命名空间类
        var ns_classes_iter = self.namespace_classes.iterator();
        while (ns_classes_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.namespace_classes.deinit();

        // 清理命名空间接口
        var ns_interfaces_iter = self.namespace_interfaces.iterator();
        while (ns_interfaces_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.namespace_interfaces.deinit();

        // 清理命名空间函数
        var ns_functions_iter = self.namespace_functions.iterator();
        while (ns_functions_iter.next()) |entry| {
            var func_iter = entry.value_ptr.iterator();
            while (func_iter.next()) |func_entry| {
                func_entry.value_ptr.release(self.allocator);
            }
            entry.value_ptr.deinit();
        }
        self.namespace_functions.deinit();

        // 清理命名空间常量
        var ns_constants_iter = self.namespace_constants.iterator();
        while (ns_constants_iter.next()) |entry| {
            var const_iter = entry.value_ptr.iterator();
            while (const_iter.next()) |const_entry| {
                const_entry.value_ptr.release(self.allocator);
            }
            entry.value_ptr.deinit();
        }
        self.namespace_constants.deinit();

        self.class_imports.deinit();
        self.function_imports.deinit();
        self.constant_imports.deinit();
        self.autoloaders.deinit();
        self.loaded_files.deinit();
    }

    /// 设置当前命名空间
    pub fn setNamespace(self: *NamespaceManager, namespace: []const u8) !void {
        self.current_namespace = try self.allocator.dupe(u8, namespace);

        // 确保命名空间存在于各个映射中
        if (!self.namespace_classes.contains(namespace)) {
            try self.namespace_classes.put(namespace, std.StringHashMap(*PHPClass).init(self.allocator));
        }
        if (!self.namespace_interfaces.contains(namespace)) {
            try self.namespace_interfaces.put(namespace, std.StringHashMap(*PHPInterface).init(self.allocator));
        }
        if (!self.namespace_functions.contains(namespace)) {
            try self.namespace_functions.put(namespace, std.StringHashMap(Value).init(self.allocator));
        }
        if (!self.namespace_constants.contains(namespace)) {
            try self.namespace_constants.put(namespace, std.StringHashMap(Value).init(self.allocator));
        }
    }

    /// 处理use语句
    /// use Namespace\ClassName;
    /// use Namespace\ClassName as Alias;
    /// use function Namespace\functionName;
    /// use const Namespace\CONSTANT_NAME;
    pub fn addUse(self: *NamespaceManager, import_type: ImportType, fully_qualified_name: []const u8, alias: ?[]const u8) !void {
        const actual_alias = alias orelse self.getLastPart(fully_qualified_name);
        const fqn_copy = try self.allocator.dupe(u8, fully_qualified_name);

        switch (import_type) {
            .class => try self.class_imports.put(actual_alias, fqn_copy),
            .function => try self.function_imports.put(actual_alias, fqn_copy),
            .constant => try self.constant_imports.put(actual_alias, fqn_copy),
        }
    }

    /// 导入类型
    pub const ImportType = enum {
        class,
        function,
        constant,
    };

    /// 解析类名到完全限定名
    pub fn resolveClassName(self: *NamespaceManager, name: []const u8) []const u8 {
        // 如果已经是完全限定名（以\开头）
        if (name.len > 0 and name[0] == '\\') {
            return name[1..]; // 去掉前导\
        }

        // 检查是否有导入别名
        if (self.class_imports.get(name)) |fqn| {
            return fqn;
        }

        // 否则使用当前命名空间
        if (self.current_namespace.len > 0) {
            const resolved = std.fmt.allocPrint(self.allocator, "{s}\\{s}", .{ self.current_namespace, name }) catch return name;
            return resolved;
        }

        return name;
    }

    /// 解析函数名到完全限定名
    pub fn resolveFunctionName(self: *NamespaceManager, name: []const u8) []const u8 {
        if (name.len > 0 and name[0] == '\\') {
            return name[1..];
        }

        if (self.function_imports.get(name)) |fqn| {
            return fqn;
        }

        // 函数首先在当前命名空间查找，然后在全局命名空间查找
        if (self.current_namespace.len > 0) {
            const resolved = std.fmt.allocPrint(self.allocator, "{s}\\{s}", .{ self.current_namespace, name }) catch return name;
            // 这里应该检查函数是否存在，如果不存在则回退到全局
            return resolved;
        }

        return name;
    }

    /// 解析常量名到完全限定名
    pub fn resolveConstantName(self: *NamespaceManager, name: []const u8) []const u8 {
        if (name.len > 0 and name[0] == '\\') {
            return name[1..];
        }

        if (self.constant_imports.get(name)) |fqn| {
            return fqn;
        }

        if (self.current_namespace.len > 0) {
            const resolved = std.fmt.allocPrint(self.allocator, "{s}\\{s}", .{ self.current_namespace, name }) catch return name;
            return resolved;
        }

        return name;
    }

    /// 在当前命名空间中定义类
    pub fn defineClass(self: *NamespaceManager, name: []const u8, class: *PHPClass) !void {
        const ns = self.current_namespace;
        if (self.namespace_classes.getPtr(ns)) |classes| {
            try classes.put(name, class);
        }
    }

    /// 获取类（支持自动加载）
    pub fn getClass(self: *NamespaceManager, name: []const u8, vm: *anyopaque) ?*PHPClass {
        const resolved_name = self.resolveClassName(name);

        // 解析命名空间和类名
        const ns_and_class = self.splitNamespace(resolved_name);
        const namespace = ns_and_class.namespace;
        const class_name = ns_and_class.name;

        // 在命名空间中查找
        if (self.namespace_classes.get(namespace)) |classes| {
            if (classes.get(class_name)) |class| {
                return class;
            }
        }

        // 尝试自动加载
        if (self.tryAutoload(resolved_name, vm)) {
            // 再次尝试获取
            if (self.namespace_classes.get(namespace)) |classes| {
                if (classes.get(class_name)) |class| {
                    return class;
                }
            }
        }

        return null;
    }

    /// 注册自动加载器
    pub fn registerAutoloader(self: *NamespaceManager, callback: Value, prepend: bool) !void {
        const autoloader = AutoloadCallback{
            .callback = callback,
            .prepend = prepend,
        };

        if (prepend) {
            try self.autoloaders.insert(0, autoloader);
        } else {
            try self.autoloaders.append(autoloader);
        }
    }

    /// 尝试自动加载类
    fn tryAutoload(self: *NamespaceManager, class_name: []const u8, vm: *anyopaque) bool {
        _ = vm;
        for (self.autoloaders.items) |autoloader| {
            _ = autoloader;
            // 调用自动加载器回调
            // 这里需要调用VM来执行回调函数
            // 传入class_name作为参数
            _ = class_name;
            // TODO: 实现回调调用
        }
        return false;
    }

    /// 检查文件是否已加载
    pub fn isFileLoaded(self: *NamespaceManager, filepath: []const u8) bool {
        return self.loaded_files.contains(filepath);
    }

    /// 标记文件为已加载
    pub fn markFileLoaded(self: *NamespaceManager, filepath: []const u8) !void {
        const path_copy = try self.allocator.dupe(u8, filepath);
        try self.loaded_files.put(path_copy, true);
    }

    /// 清除当前命名空间的导入
    pub fn clearImports(self: *NamespaceManager) void {
        self.class_imports.clearRetainingCapacity();
        self.function_imports.clearRetainingCapacity();
        self.constant_imports.clearRetainingCapacity();
    }

    /// 获取名称的最后一部分（用于自动别名）
    fn getLastPart(self: *NamespaceManager, name: []const u8) []const u8 {
        _ = self;
        var last_slash: usize = 0;
        for (name, 0..) |c, i| {
            if (c == '\\') {
                last_slash = i + 1;
            }
        }
        return name[last_slash..];
    }

    /// 分割命名空间和名称
    fn splitNamespace(self: *NamespaceManager, fqn: []const u8) struct { namespace: []const u8, name: []const u8 } {
        _ = self;
        var last_slash: usize = 0;
        var found = false;
        for (fqn, 0..) |c, i| {
            if (c == '\\') {
                last_slash = i;
                found = true;
            }
        }

        if (found) {
            return .{
                .namespace = fqn[0..last_slash],
                .name = fqn[last_slash + 1 ..],
            };
        }

        return .{
            .namespace = "",
            .name = fqn,
        };
    }
};

/// 文件加载器 - 处理include/require/include_once/require_once
pub const FileLoader = struct {
    allocator: std.mem.Allocator,
    namespace_manager: *NamespaceManager,
    include_paths: std.ArrayList([]const u8),
    current_file: []const u8,
    file_stack: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator, namespace_manager: *NamespaceManager) FileLoader {
        return FileLoader{
            .allocator = allocator,
            .namespace_manager = namespace_manager,
            .include_paths = std.ArrayList([]const u8).init(allocator),
            .current_file = "",
            .file_stack = std.ArrayList([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *FileLoader) void {
        self.include_paths.deinit();
        self.file_stack.deinit();
    }

    /// 添加include路径
    pub fn addIncludePath(self: *FileLoader, path: []const u8) !void {
        const path_copy = try self.allocator.dupe(u8, path);
        try self.include_paths.append(path_copy);
    }

    /// 解析文件路径
    pub fn resolvePath(self: *FileLoader, filename: []const u8) !?[]const u8 {
        // 如果是绝对路径
        if (std.fs.path.isAbsolute(filename)) {
            if (self.fileExists(filename)) {
                return try self.allocator.dupe(u8, filename);
            }
            return null;
        }

        // 相对于当前文件的路径
        if (self.current_file.len > 0) {
            const dir = std.fs.path.dirname(self.current_file) orelse ".";
            const full_path = try std.fs.path.join(self.allocator, &[_][]const u8{ dir, filename });
            if (self.fileExists(full_path)) {
                return full_path;
            }
            self.allocator.free(full_path);
        }

        // 搜索include路径
        for (self.include_paths.items) |include_path| {
            const full_path = try std.fs.path.join(self.allocator, &[_][]const u8{ include_path, filename });
            if (self.fileExists(full_path)) {
                return full_path;
            }
            self.allocator.free(full_path);
        }

        // 当前工作目录
        if (self.fileExists(filename)) {
            return try self.allocator.dupe(u8, filename);
        }

        return null;
    }

    /// 加载文件内容
    pub fn loadFile(self: *FileLoader, filepath: []const u8) ![]const u8 {
        const file = try std.fs.cwd().openFile(filepath, .{});
        defer file.close();

        const file_size = try file.getEndPos();
        const contents = try self.allocator.alloc(u8, file_size);
        _ = try file.readAll(contents);

        return contents;
    }

    /// include操作
    pub fn include(self: *FileLoader, filename: []const u8) !?[]const u8 {
        const resolved_path = try self.resolvePath(filename) orelse {
            // include失败只是警告，不是致命错误
            return null;
        };

        try self.pushFile(resolved_path);
        defer self.popFile();

        return try self.loadFile(resolved_path);
    }

    /// require操作
    pub fn require(self: *FileLoader, filename: []const u8) ![]const u8 {
        const resolved_path = try self.resolvePath(filename) orelse {
            return error.FileNotFound;
        };

        try self.pushFile(resolved_path);
        defer self.popFile();

        return try self.loadFile(resolved_path);
    }

    /// include_once操作
    pub fn includeOnce(self: *FileLoader, filename: []const u8) !?[]const u8 {
        const resolved_path = try self.resolvePath(filename) orelse {
            return null;
        };

        // 检查是否已加载
        if (self.namespace_manager.isFileLoaded(resolved_path)) {
            return null;
        }

        try self.namespace_manager.markFileLoaded(resolved_path);
        try self.pushFile(resolved_path);
        defer self.popFile();

        return try self.loadFile(resolved_path);
    }

    /// require_once操作
    pub fn requireOnce(self: *FileLoader, filename: []const u8) !?[]const u8 {
        const resolved_path = try self.resolvePath(filename) orelse {
            return error.FileNotFound;
        };

        // 检查是否已加载
        if (self.namespace_manager.isFileLoaded(resolved_path)) {
            return null;
        }

        try self.namespace_manager.markFileLoaded(resolved_path);
        try self.pushFile(resolved_path);
        defer self.popFile();

        return try self.loadFile(resolved_path);
    }

    fn fileExists(self: *FileLoader, path: []const u8) bool {
        _ = self;
        std.fs.cwd().access(path, .{}) catch return false;
        return true;
    }

    fn pushFile(self: *FileLoader, filepath: []const u8) !void {
        if (self.current_file.len > 0) {
            try self.file_stack.append(self.current_file);
        }
        self.current_file = filepath;
    }

    fn popFile(self: *FileLoader) void {
        if (self.file_stack.items.len > 0) {
            self.current_file = self.file_stack.pop();
        } else {
            self.current_file = "";
        }
    }

    /// 获取当前文件路径
    pub fn getCurrentFile(self: *FileLoader) []const u8 {
        return self.current_file;
    }

    /// 获取当前目录
    pub fn getCurrentDir(self: *FileLoader) []const u8 {
        if (self.current_file.len > 0) {
            return std.fs.path.dirname(self.current_file) orelse ".";
        }
        return ".";
    }
};

test "namespace manager basic operations" {
    const allocator = std.testing.allocator;
    var manager = NamespaceManager.init(allocator);
    defer manager.deinit();

    // 测试设置命名空间
    try manager.setNamespace("App\\Controllers");
    try std.testing.expectEqualStrings("App\\Controllers", manager.current_namespace);

    // 测试添加use
    try manager.addUse(.class, "App\\Models\\User", null);
    try std.testing.expectEqualStrings("App\\Models\\User", manager.class_imports.get("User").?);

    // 测试带别名的use
    try manager.addUse(.class, "App\\Models\\BaseModel", "Model");
    try std.testing.expectEqualStrings("App\\Models\\BaseModel", manager.class_imports.get("Model").?);
}
