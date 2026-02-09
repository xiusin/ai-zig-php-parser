const std = @import("std");
const Allocator = std.mem.Allocator;

/// 模块表示
pub const Module = struct {
    name: []const u8,
    functions: std.StringHashMap(*Function),
    globals: std.StringHashMap(*Global),
    dependencies: std.ArrayList([]const u8),
    allocator: Allocator,

    pub fn init(allocator: Allocator, name: []const u8) !Module {
        return Module{
            .name = name,
            .functions = std.StringHashMap(*Function).init(allocator),
            .globals = std.StringHashMap(*Global).init(allocator),
            .dependencies = try std.ArrayList([]const u8).initCapacity(allocator, 0),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Module) void {
        var func_it = self.functions.valueIterator();
        while (func_it.next()) |func| {
            func.*.deinit();
            self.allocator.destroy(func.*);
        }
        self.functions.deinit();

        var global_it = self.globals.valueIterator();
        while (global_it.next()) |global| {
            global.*.deinit();
            self.allocator.destroy(global.*);
        }
        self.globals.deinit();

        self.dependencies.deinit(self.allocator);
    }

    pub fn addFunction(self: *Module, func: *Function) !void {
        try self.functions.put(func.name, func);
    }

    pub fn addGlobal(self: *Module, global: *Global) !void {
        try self.globals.put(global.name, global);
    }

    pub fn addDependency(self: *Module, dep: []const u8) !void {
        try self.dependencies.append(self.allocator, dep);
    }
};

/// 函数表示
pub const Function = struct {
    name: []const u8,
    module: []const u8,
    is_external: bool,
    call_count: u64,
    size: usize,
    allocator: Allocator,

    pub fn init(allocator: Allocator, name: []const u8, module: []const u8) Function {
        return Function{
            .name = name,
            .module = module,
            .is_external = false,
            .call_count = 0,
            .size = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Function) void {
        _ = self;
    }
};

/// 全局变量表示
pub const Global = struct {
    name: []const u8,
    module: []const u8,
    is_constant: bool,
    allocator: Allocator,

    pub fn init(allocator: Allocator, name: []const u8, module: []const u8) Global {
        return Global{
            .name = name,
            .module = module,
            .is_constant = false,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Global) void {
        _ = self;
    }
};

/// 符号表
pub const SymbolTable = struct {
    symbols: std.StringHashMap(Symbol),
    allocator: Allocator,

    pub const Symbol = struct {
        name: []const u8,
        module: []const u8,
        kind: SymbolKind,
    };

    pub const SymbolKind = enum {
        function,
        global,
    };

    pub fn init(allocator: Allocator) SymbolTable {
        return SymbolTable{
            .symbols = std.StringHashMap(Symbol).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SymbolTable) void {
        self.symbols.deinit();
    }

    pub fn addSymbol(self: *SymbolTable, name: []const u8, module: []const u8, kind: SymbolKind) !void {
        try self.symbols.put(name, Symbol{
            .name = name,
            .module = module,
            .kind = kind,
        });
    }

    pub fn getSymbol(self: *SymbolTable, name: []const u8) ?Symbol {
        return self.symbols.get(name);
    }
};

/// 链接时优化器
pub const LinkTimeOptimizer = struct {
    modules: std.ArrayList(*Module),
    symbol_table: SymbolTable,
    allocator: Allocator,

    pub fn init(allocator: Allocator) LinkTimeOptimizer {
        return LinkTimeOptimizer{
            .modules = std.ArrayList(*Module).initCapacity(allocator, 0) catch unreachable,
            .symbol_table = SymbolTable.init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *LinkTimeOptimizer) void {
        for (self.modules.items) |module| {
            module.deinit();
            self.allocator.destroy(module);
        }
        self.modules.deinit(self.allocator);
        self.symbol_table.deinit();
    }

    /// 添加模块
    pub fn addModule(self: *LinkTimeOptimizer, module: *Module) !void {
        try self.modules.append(self.allocator, module);

        // 添加符号到符号表
        var func_it = module.functions.iterator();
        while (func_it.next()) |entry| {
            try self.symbol_table.addSymbol(entry.key_ptr.*, module.name, .function);
        }

        var global_it = module.globals.iterator();
        while (global_it.next()) |entry| {
            try self.symbol_table.addSymbol(entry.key_ptr.*, module.name, .global);
        }
    }

    /// 合并模块
    pub fn mergeModules(self: *LinkTimeOptimizer) !*MergedModule {
        const merged = try self.allocator.create(MergedModule);
        merged.* = try MergedModule.init(self.allocator);

        for (self.modules.items) |module| {
            try merged.merge(module);
        }

        return merged;
    }

    /// 解析依赖
    pub fn resolveDependencies(self: *LinkTimeOptimizer) !std.ArrayList([]const u8) {
        var resolved = try std.ArrayList([]const u8).initCapacity(self.allocator, 0);
        var visited = std.StringHashMap(void).init(self.allocator);
        defer visited.deinit();

        for (self.modules.items) |module| {
            try self.visitModule(module, &resolved, &visited);
        }

        return resolved;
    }

    fn visitModule(
        self: *LinkTimeOptimizer,
        module: *Module,
        resolved: *std.ArrayList([]const u8),
        visited: *std.StringHashMap(void),
    ) !void {
        if (visited.contains(module.name)) return;

        try visited.put(module.name, {});

        for (module.dependencies.items) |dep| {
            for (self.modules.items) |dep_module| {
                if (std.mem.eql(u8, dep_module.name, dep)) {
                    try self.visitModule(dep_module, resolved, visited);
                    break;
                }
            }
        }

        try resolved.append(self.allocator, module.name);
    }

    /// 跨模块内联
    pub fn crossModuleInlining(self: *LinkTimeOptimizer) !void {
        for (self.modules.items) |module| {
            var func_it = module.functions.iterator();
            while (func_it.next()) |entry| {
                const func = entry.value_ptr.*;
                if (func.size < 100 and func.call_count > 10) {
                    // 标记为可内联
                    func.is_external = false;
                }
            }
        }
    }

    /// 全局死代码消除
    pub fn globalDeadCodeElimination(self: *LinkTimeOptimizer) !void {
        var reachable = std.StringHashMap(void).init(self.allocator);
        defer reachable.deinit();

        // 从入口函数开始标记可达函数
        for (self.modules.items) |module| {
            if (module.functions.get("main")) |main_func| {
                try self.markReachable(main_func, &reachable);
            }
        }

        // 移除不可达函数
        for (self.modules.items) |module| {
            var func_it = module.functions.iterator();
            var to_remove = try std.ArrayList([]const u8).initCapacity(self.allocator, 0);
            defer to_remove.deinit(self.allocator);

            while (func_it.next()) |entry| {
                if (!reachable.contains(entry.key_ptr.*)) {
                    try to_remove.append(self.allocator, entry.key_ptr.*);
                }
            }

            for (to_remove.items) |name| {
                if (module.functions.fetchRemove(name)) |kv| {
                    kv.value.deinit();
                    self.allocator.destroy(kv.value);
                }
            }
        }
    }

    fn markReachable(self: *LinkTimeOptimizer, func: *Function, reachable: *std.StringHashMap(void)) !void {
        _ = self;
        if (reachable.contains(func.name)) return;
        try reachable.put(func.name, {});
    }

    /// 常量合并
    pub fn constantMerging(self: *LinkTimeOptimizer) !void {
        var constants = std.StringHashMap(*Global).init(self.allocator);
        defer constants.deinit();

        for (self.modules.items) |module| {
            var global_it = module.globals.iterator();
            while (global_it.next()) |entry| {
                const global = entry.value_ptr.*;
                if (global.is_constant) {
                    if (constants.get(global.name)) |existing| {
                        // 合并常量
                        _ = existing;
                    } else {
                        try constants.put(global.name, global);
                    }
                }
            }
        }
    }
};

/// 合并后的模块
pub const MergedModule = struct {
    functions: std.StringHashMap(*Function),
    globals: std.StringHashMap(*Global),
    allocator: Allocator,

    pub fn init(allocator: Allocator) !MergedModule {
        return MergedModule{
            .functions = std.StringHashMap(*Function).init(allocator),
            .globals = std.StringHashMap(*Global).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *MergedModule) void {
        self.functions.deinit();
        self.globals.deinit();
    }

    pub fn merge(self: *MergedModule, module: *Module) !void {
        var func_it = module.functions.iterator();
        while (func_it.next()) |entry| {
            try self.functions.put(entry.key_ptr.*, entry.value_ptr.*);
        }

        var global_it = module.globals.iterator();
        while (global_it.next()) |entry| {
            try self.globals.put(entry.key_ptr.*, entry.value_ptr.*);
        }
    }
};
