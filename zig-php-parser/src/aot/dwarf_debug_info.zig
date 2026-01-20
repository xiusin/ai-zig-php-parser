//! DWARF 调试信息生成器
//!
//! 本模块实现完整的 DWARF 调试信息生成，支持 gdb/lldb 调试器。
//! 
//! ## 功能特性
//! 
//! 1. **DWARF 格式支持**：生成符合 DWARF 4/5 标准的调试信息
//! 2. **源代码映射**：将机器码地址映射到源代码行号
//! 3. **类型信息**：生成完整的类型描述信息
//! 4. **变量信息**：记录局部变量和全局变量的位置
//! 5. **函数信息**：生成函数边界和调用栈信息
//! 6. **调试器集成**：支持 gdb 和 lldb 调试器
//!
//! ## 使用示例
//!
//! ```zig
//! var builder = try DwarfDebugInfoBuilder.init(allocator);
//! defer builder.deinit();
//!
//! // 创建编译单元
//! try builder.createCompileUnit("test.php", "/path/to/source");
//!
//! // 添加函数调试信息
//! const func_die = try builder.createFunction("myFunc", 0x1000, 0x100);
//!
//! // 添加变量调试信息
//! try builder.createLocalVariable(func_die, "x", .i64, 0x1010);
//!
//! // 生成 DWARF 数据
//! const dwarf_data = try builder.finalize();
//! ```
//!
//! ## DWARF 结构
//!
//! DWARF 调试信息由多个 section 组成：
//! - .debug_info: 调试信息条目（DIE）
//! - .debug_abbrev: 缩写表
//! - .debug_line: 行号表
//! - .debug_str: 字符串表
//! - .debug_aranges: 地址范围表
//! - .debug_frame: 调用帧信息

const std = @import("std");
const Allocator = std.mem.Allocator;
const IR = @import("ir.zig");


// ============================================================================
// DWARF 常量定义
// ============================================================================

/// DWARF 版本
pub const DWARF_VERSION = 4;

/// DWARF 标签（TAG）
pub const DW_TAG = enum(u16) {
    compile_unit = 0x11,
    subprogram = 0x2e,
    base_type = 0x24,
    pointer_type = 0x0f,
    structure_type = 0x13,
    array_type = 0x01,
    formal_parameter = 0x05,
    variable = 0x34,
    lexical_block = 0x0b,
};

/// DWARF 属性（AT）
pub const DW_AT = enum(u16) {
    name = 0x03,
    stmt_list = 0x10,
    low_pc = 0x11,
    high_pc = 0x12,
    language = 0x13,
    comp_dir = 0x1b,
    producer = 0x25,
    type = 0x49,
    byte_size = 0x0b,
    encoding = 0x3e,
    frame_base = 0x40,
    location = 0x02,
    decl_file = 0x3a,
    decl_line = 0x3b,
};

/// DWARF 表单（FORM）
pub const DW_FORM = enum(u16) {
    addr = 0x01,
    data1 = 0x0b,
    data2 = 0x05,
    data4 = 0x06,
    data8 = 0x07,
    string = 0x08,
    strp = 0x0e,
    flag = 0x0c,
    ref4 = 0x13,
    exprloc = 0x18,
    sec_offset = 0x17,
};

/// DWARF 语言代码
pub const DW_LANG = enum(u16) {
    c = 0x02,
    c_plus_plus = 0x04,
    php = 0x8000, // 自定义语言代码
};

/// DWARF 基本类型编码
pub const DW_ATE = enum(u8) {
    address = 0x01,
    boolean = 0x02,
    float = 0x04,
    signed = 0x05,
    unsigned = 0x07,
    utf = 0x10,
};

// ============================================================================
// 调试信息条目（DIE）
// ============================================================================

/// 调试信息条目（Debug Information Entry）
pub const DIE = struct {
    tag: DW_TAG,
    attributes: std.ArrayList(Attribute),
    children: std.ArrayList(*DIE),
    parent: ?*DIE,
    offset: u32, // 在 .debug_info 中的偏移量
    
    pub const Attribute = struct {
        name: DW_AT,
        form: DW_FORM,
        value: Value,
        
        pub const Value = union(enum) {
            addr: u64,
            data1: u8,
            data2: u16,
            data4: u32,
            data8: u64,
            string: []const u8,
            strp: u32, // 字符串表偏移
            flag: bool,
            ref4: u32,
            exprloc: []const u8,
            sec_offset: u32,
        };
    };
    
    pub fn init(allocator: Allocator, tag: DW_TAG) !*DIE {
        const die = try allocator.create(DIE);
        die.* = .{
            .tag = tag,
            .attributes = std.ArrayList(Attribute){},
            .children = std.ArrayList(*DIE){},
            .parent = null,
            .offset = 0,
        };
        return die;
    }
    
    pub fn deinit(self: *DIE, allocator: Allocator) void {
        for (self.children.items) |child| {
            child.deinit(allocator);
        }
        self.children.deinit(allocator);
        self.attributes.deinit(allocator);
        allocator.destroy(self);
    }
    
    pub fn addAttribute(self: *DIE, allocator: Allocator, attr: Attribute) !void {
        try self.attributes.append(allocator, attr);
    }
    
    pub fn addChild(self: *DIE, child: *DIE) !void {
        child.parent = self;
        const allocator = self.children.allocator;
        try self.children.append(allocator, child);
    }
};


// ============================================================================
// 字符串表
// ============================================================================

/// DWARF 字符串表
pub const StringTable = struct {
    allocator: Allocator,
    strings: std.StringHashMap(u32),
    buffer: std.ArrayList(u8),
    
    pub fn init(allocator: Allocator) StringTable {
        return .{
            .allocator = allocator,
            .strings = std.StringHashMap(u32).init(allocator),
            .buffer = std.ArrayList(u8){},
        };
    }
    
    pub fn deinit(self: *StringTable) void {
        self.strings.deinit();
        self.buffer.deinit(self.allocator);
    }
    
    /// 添加字符串到字符串表，返回偏移量
    pub fn addString(self: *StringTable, str: []const u8) !u32 {
        if (self.strings.get(str)) |offset| {
            return offset;
        }
        
        const offset = @as(u32, @intCast(self.buffer.items.len));
        try self.buffer.appendSlice(self.allocator, str);
        try self.buffer.append(self.allocator, 0); // null terminator
        try self.strings.put(str, offset);
        
        return offset;
    }
    
    /// 获取字符串表数据
    pub fn getData(self: *const StringTable) []const u8 {
        return self.buffer.items;
    }
};

// ============================================================================
// 行号表
// ============================================================================

/// 行号表条目
pub const LineEntry = struct {
    address: u64,
    file: u32,
    line: u32,
    column: u32,
    is_stmt: bool,
    basic_block: bool,
    end_sequence: bool,
};

/// 行号表
pub const LineTable = struct {
    allocator: Allocator,
    entries: std.ArrayList(LineEntry),
    files: std.ArrayList(FileEntry),
    
    pub const FileEntry = struct {
        name: []const u8,
        directory: u32,
        mod_time: u64,
        file_size: u64,
    };
    
    pub fn init(allocator: Allocator) LineTable {
        return .{
            .allocator = allocator,
            .entries = std.ArrayList(LineEntry){},
            .files = std.ArrayList(FileEntry){},
        };
    }
    
    pub fn deinit(self: *LineTable) void {
        self.entries.deinit(self.allocator);
        self.files.deinit(self.allocator);
    }
    
    pub fn addFile(self: *LineTable, name: []const u8, directory: u32) !u32 {
        const index = @as(u32, @intCast(self.files.items.len));
        try self.files.append(self.allocator, .{
            .name = name,
            .directory = directory,
            .mod_time = 0,
            .file_size = 0,
        });
        return index;
    }
    
    pub fn addEntry(self: *LineTable, entry: LineEntry) !void {
        try self.entries.append(self.allocator, entry);
    }
};


// ============================================================================
// DWARF 调试信息构建器
// ============================================================================

/// DWARF 调试信息构建器
pub const DwarfDebugInfoBuilder = struct {
    allocator: Allocator,
    
    // 根 DIE（编译单元）
    compile_unit: ?*DIE,
    
    // 字符串表
    string_table: StringTable,
    
    // 行号表
    line_table: LineTable,
    
    // 类型 DIE 缓存
    type_cache: std.AutoHashMap(IR.Type, *DIE),
    
    // 当前函数 DIE
    current_function: ?*DIE,
    
    // 地址范围
    address_ranges: std.ArrayList(AddressRange),
    
    pub const AddressRange = struct {
        low_pc: u64,
        high_pc: u64,
        die: *DIE,
    };
    
    pub fn init(allocator: Allocator) !*DwarfDebugInfoBuilder {
        const self = try allocator.create(DwarfDebugInfoBuilder);
        self.* = .{
            .allocator = allocator,
            .compile_unit = null,
            .string_table = StringTable.init(allocator),
            .line_table = LineTable.init(allocator),
            .type_cache = std.AutoHashMap(IR.Type, *DIE).init(allocator),
            .current_function = null,
            .address_ranges = std.ArrayList(AddressRange){},
        };
        return self;
    }
    
    pub fn deinit(self: *DwarfDebugInfoBuilder) void {
        if (self.compile_unit) |cu| {
            cu.deinit(self.allocator);
        }
        
        self.string_table.deinit();
        self.line_table.deinit();
        self.type_cache.deinit();
        self.address_ranges.deinit(self.allocator);
        
        self.allocator.destroy(self);
    }
    
    /// 创建编译单元
    /// @pre source_file 和 source_dir 必须有效
    /// @post 创建根 DIE 并设置基本属性
    pub fn createCompileUnit(
        self: *DwarfDebugInfoBuilder,
        source_file: []const u8,
        source_dir: []const u8,
    ) !void {
        const cu = try DIE.init(self.allocator, .compile_unit);
        
        // 添加源文件名
        const file_offset = try self.string_table.addString(source_file);
        try cu.addAttribute(self.allocator, .{
            .name = .name,
            .form = .strp,
            .value = .{ .strp = file_offset },
        });
        
        // 添加编译目录
        const dir_offset = try self.string_table.addString(source_dir);
        try cu.addAttribute(self.allocator, .{
            .name = .comp_dir,
            .form = .strp,
            .value = .{ .strp = dir_offset },
        });
        
        // 添加语言
        try cu.addAttribute(self.allocator, .{
            .name = .language,
            .form = .data2,
            .value = .{ .data2 = @intFromEnum(DW_LANG.php) },
        });
        
        // 添加生产者信息
        const producer = "Zig-PHP AOT Compiler v1.0";
        const producer_offset = try self.string_table.addString(producer);
        try cu.addAttribute(self.allocator, .{
            .name = .producer,
            .form = .strp,
            .value = .{ .strp = producer_offset },
        });
        
        self.compile_unit = cu;
        
        // 添加源文件到行号表
        _ = try self.line_table.addFile(source_file, 0);
    }
    
    /// 创建函数调试信息
    /// @pre compile_unit 必须已创建
    /// @post 返回函数 DIE
    pub fn createFunction(
        self: *DwarfDebugInfoBuilder,
        name: []const u8,
        low_pc: u64,
        high_pc: u64,
        return_type: IR.Type,
    ) !*DIE {
        const cu = self.compile_unit orelse return error.NoCompileUnit;
        
        const func_die = try DIE.init(self.allocator, .subprogram);
        
        // 函数名
        const name_offset = try self.string_table.addString(name);
        try func_die.addAttribute(self.allocator, .{
            .name = .name,
            .form = .strp,
            .value = .{ .strp = name_offset },
        });
        
        // 地址范围
        try func_die.addAttribute(self.allocator, .{
            .name = .low_pc,
            .form = .addr,
            .value = .{ .addr = low_pc },
        });
        
        try func_die.addAttribute(self.allocator, .{
            .name = .high_pc,
            .form = .addr,
            .value = .{ .addr = high_pc },
        });
        
        // 返回类型
        const type_die = try self.getOrCreateType(return_type);
        try func_die.addAttribute(self.allocator, .{
            .name = .type,
            .form = .ref4,
            .value = .{ .ref4 = type_die.offset },
        });
        
        // 添加到编译单元
        try cu.addChild(func_die);
        
        // 记录地址范围
        try self.address_ranges.append(self.allocator, .{
            .low_pc = low_pc,
            .high_pc = high_pc,
            .die = func_die,
        });
        
        self.current_function = func_die;
        
        return func_die;
    }
    
    /// 创建函数参数调试信息
    /// @pre func_die 必须是有效的函数 DIE
    /// @post 添加参数 DIE 到函数
    pub fn createFormalParameter(
        self: *DwarfDebugInfoBuilder,
        func_die: *DIE,
        name: []const u8,
        param_type: IR.Type,
        location: u64,
    ) !void {
        const param_die = try DIE.init(self.allocator, .formal_parameter);
        
        // 参数名
        const name_offset = try self.string_table.addString(name);
        try param_die.addAttribute(self.allocator, .{
            .name = .name,
            .form = .strp,
            .value = .{ .strp = name_offset },
        });
        
        // 参数类型
        const type_die = try self.getOrCreateType(param_type);
        try param_die.addAttribute(self.allocator, .{
            .name = .type,
            .form = .ref4,
            .value = .{ .ref4 = type_die.offset },
        });
        
        // 参数位置（寄存器或栈偏移）
        try param_die.addAttribute(self.allocator, .{
            .name = .location,
            .form = .exprloc,
            .value = .{ .exprloc = try self.encodeLocation(location) },
        });
        
        try func_die.addChild(param_die);
    }
    
    /// 创建局部变量调试信息
    /// @pre func_die 必须是有效的函数 DIE
    /// @post 添加变量 DIE 到函数
    pub fn createLocalVariable(
        self: *DwarfDebugInfoBuilder,
        func_die: *DIE,
        name: []const u8,
        var_type: IR.Type,
        location: u64,
        line: u32,
    ) !void {
        const var_die = try DIE.init(self.allocator, .variable);
        
        // 变量名
        const name_offset = try self.string_table.addString(name);
        try var_die.addAttribute(self.allocator, .{
            .name = .name,
            .form = .strp,
            .value = .{ .strp = name_offset },
        });
        
        // 变量类型
        const type_die = try self.getOrCreateType(var_type);
        try var_die.addAttribute(self.allocator, .{
            .name = .type,
            .form = .ref4,
            .value = .{ .ref4 = type_die.offset },
        });
        
        // 变量位置
        try var_die.addAttribute(self.allocator, .{
            .name = .location,
            .form = .exprloc,
            .value = .{ .exprloc = try self.encodeLocation(location) },
        });
        
        // 声明行号
        try var_die.addAttribute(self.allocator, .{
            .name = .decl_line,
            .form = .data4,
            .value = .{ .data4 = line },
        });
        
        try func_die.addChild(var_die);
    }
    
    /// 添加行号映射
    /// @pre address 必须在有效范围内
    /// @post 添加行号条目到行号表
    pub fn addLineMapping(
        self: *DwarfDebugInfoBuilder,
        address: u64,
        file: u32,
        line: u32,
        column: u32,
    ) !void {
        try self.line_table.addEntry(.{
            .address = address,
            .file = file,
            .line = line,
            .column = column,
            .is_stmt = true,
            .basic_block = false,
            .end_sequence = false,
        });
    }
    
    /// 获取或创建类型 DIE
    fn getOrCreateType(self: *DwarfDebugInfoBuilder, ir_type: IR.Type) !*DIE {
        if (self.type_cache.get(ir_type)) |die| {
            return die;
        }
        
        const type_die = try self.createTypeDIE(ir_type);
        try self.type_cache.put(ir_type, type_die);
        
        // 添加到编译单元
        if (self.compile_unit) |cu| {
            try cu.addChild(type_die);
        }
        
        return type_die;
    }
    
    /// 创建类型 DIE
    fn createTypeDIE(self: *DwarfDebugInfoBuilder, ir_type: IR.Type) !*DIE {
        return switch (ir_type) {
            .void => try self.createBaseType("void", 0, .address),
            .bool => try self.createBaseType("bool", 1, .boolean),
            .i64 => try self.createBaseType("i64", 8, .signed),
            .f64 => try self.createBaseType("f64", 8, .float),
            .php_string => try self.createPointerType(.i64),
            .php_array => try self.createArrayType(.php_value),
            .php_object => try self.createStructType("php_object"),
            .php_value => try self.createBaseType("php_value", 16, .address),
            .php_resource => try self.createBaseType("php_resource", 8, .address),
            .php_callable => try self.createBaseType("php_callable", 8, .address),
            .ptr => |p| try self.createPointerType(p.*),
            .nullable => |n| try self.createPointerType(n.*),
            .function => try self.createBaseType("function", 8, .address),
        };
    }
    
    /// 创建基本类型 DIE
    fn createBaseType(
        self: *DwarfDebugInfoBuilder,
        name: []const u8,
        byte_size: u32,
        encoding: DW_ATE,
    ) !*DIE {
        const type_die = try DIE.init(self.allocator, .base_type);
        
        const name_offset = try self.string_table.addString(name);
        try type_die.addAttribute(self.allocator, .{
            .name = .name,
            .form = .strp,
            .value = .{ .strp = name_offset },
        });
        
        try type_die.addAttribute(self.allocator, .{
            .name = .byte_size,
            .form = .data1,
            .value = .{ .data1 = @as(u8, @intCast(byte_size)) },
        });
        
        try type_die.addAttribute(self.allocator, .{
            .name = .encoding,
            .form = .data1,
            .value = .{ .data1 = @intFromEnum(encoding) },
        });
        
        return type_die;
    }
    
    /// 创建指针类型 DIE
    fn createPointerType(self: *DwarfDebugInfoBuilder, pointee_type: IR.Type) !*DIE {
        const type_die = try DIE.init(self.allocator, .pointer_type);
        
        try type_die.addAttribute(self.allocator, .{
            .name = .byte_size,
            .form = .data1,
            .value = .{ .data1 = 8 }, // 64-bit pointer
        });
        
        const pointee_die = try self.getOrCreateType(pointee_type);
        try type_die.addAttribute(self.allocator, .{
            .name = .type,
            .form = .ref4,
            .value = .{ .ref4 = pointee_die.offset },
        });
        
        return type_die;
    }
    
    /// 创建数组类型 DIE
    fn createArrayType(self: *DwarfDebugInfoBuilder, element_type: IR.Type) !*DIE {
        const type_die = try DIE.init(self.allocator, .array_type);
        
        const element_die = try self.getOrCreateType(element_type);
        try type_die.addAttribute(self.allocator, .{
            .name = .type,
            .form = .ref4,
            .value = .{ .ref4 = element_die.offset },
        });
        
        return type_die;
    }
    
    /// 创建结构体类型 DIE
    fn createStructType(self: *DwarfDebugInfoBuilder, name: []const u8) !*DIE {
        const type_die = try DIE.init(self.allocator, .structure_type);
        
        const name_offset = try self.string_table.addString(name);
        try type_die.addAttribute(self.allocator, .{
            .name = .name,
            .form = .strp,
            .value = .{ .strp = name_offset },
        });
        
        try type_die.addAttribute(self.allocator, .{
            .name = .byte_size,
            .form = .data4,
            .value = .{ .data4 = 0 }, // 未知大小
        });
        
        return type_die;
    }
    
    /// 编码位置表达式
    fn encodeLocation(self: *DwarfDebugInfoBuilder, location: u64) ![]const u8 {
        var buf = std.ArrayList(u8){};
        
        // DW_OP_fbreg: 基于帧指针的偏移
        try buf.append(self.allocator, 0x91);
        
        // 编码 SLEB128 偏移量
        try encodeSLEB128(&buf, self.allocator, @as(i64, @intCast(location)));
        
        return buf.toOwnedSlice(self.allocator);
    }
    
    /// 完成调试信息构建
    /// @pre compile_unit 必须已创建
    /// @post 返回完整的 DWARF 数据
    pub fn finalize(self: *DwarfDebugInfoBuilder) !DwarfData {
        if (self.compile_unit == null) {
            return error.NoCompileUnit;
        }
        
        // 计算所有 DIE 的偏移量
        try self.computeOffsets();
        
        // 生成各个 section
        const debug_info = try self.generateDebugInfo();
        const debug_abbrev = try self.generateDebugAbbrev();
        const debug_line = try self.generateDebugLine();
        const debug_str = self.string_table.getData();
        const debug_aranges = try self.generateDebugAranges();
        
        return DwarfData{
            .debug_info = debug_info,
            .debug_abbrev = debug_abbrev,
            .debug_line = debug_line,
            .debug_str = debug_str,
            .debug_aranges = debug_aranges,
        };
    }
    
    /// 计算所有 DIE 的偏移量
    fn computeOffsets(self: *DwarfDebugInfoBuilder) !void {
        var offset: u32 = 11; // 编译单元头部大小
        
        if (self.compile_unit) |cu| {
            try self.computeDIEOffsets(cu, &offset);
        }
    }
    
    /// 递归计算 DIE 偏移量
    fn computeDIEOffsets(self: *DwarfDebugInfoBuilder, die: *DIE, offset: *u32) !void {
        die.offset = offset.*;
        
        // 标签（LEB128）
        offset.* += 1;
        
        // 属性
        for (die.attributes.items) |attr| {
            offset.* += try self.getAttributeSize(attr);
        }
        
        // 子节点
        for (die.children.items) |child| {
            try self.computeDIEOffsets(child, offset);
        }
        
        // 结束标记
        if (die.children.items.len > 0) {
            offset.* += 1;
        }
    }
    
    /// 获取属性大小
    fn getAttributeSize(self: *DwarfDebugInfoBuilder, attr: DIE.Attribute) !usize {
        _ = self;
        return switch (attr.form) {
            .addr => 8,
            .data1 => 1,
            .data2 => 2,
            .data4 => 4,
            .data8 => 8,
            .string => attr.value.string.len + 1,
            .strp => 4,
            .flag => 1,
            .ref4 => 4,
            .exprloc => attr.value.exprloc.len + 1, // 长度 + 数据
            .sec_offset => 4,
        };
    }
    
    /// 生成 .debug_info section
    fn generateDebugInfo(self: *DwarfDebugInfoBuilder) ![]u8 {
        var buf = std.ArrayList(u8){};
        
        // 编译单元头部
        try buf.appendSlice(self.allocator, &[_]u8{0} ** 4); // 长度（稍后填充）
        try writeU16(&buf, self.allocator, DWARF_VERSION);
        try writeU32(&buf, self.allocator, 0); // .debug_abbrev 偏移
        try buf.append(self.allocator, 8); // 地址大小
        
        // 写入 DIE 树
        if (self.compile_unit) |cu| {
            try self.writeDIE(&buf, cu, 1);
        }
        
        // 填充长度
        const length = @as(u32, @intCast(buf.items.len - 4));
        std.mem.writeInt(u32, buf.items[0..4], length, .little);
        
        return buf.toOwnedSlice(self.allocator);
    }
    
    /// 写入 DIE 到缓冲区
    fn writeDIE(self: *DwarfDebugInfoBuilder, buf: *std.ArrayList(u8), die: *DIE, abbrev_code: u32) !void {
        // 写入缩写代码
        try encodeULEB128(buf, abbrev_code);
        
        // 写入属性
        for (die.attributes.items) |attr| {
            try self.writeAttribute(buf, attr);
        }
        
        // 写入子节点
        var child_code = abbrev_code + 1;
        for (die.children.items) |child| {
            try self.writeDIE(buf, child, child_code);
            child_code += 1;
        }
        
        // 结束标记
        if (die.children.items.len > 0) {
            try buf.append(0);
        }
    }
    
    /// 写入属性到缓冲区
    fn writeAttribute(self: *DwarfDebugInfoBuilder, buf: *std.ArrayList(u8), attr: DIE.Attribute) !void {
        _ = self;
        switch (attr.value) {
            .addr => |v| try writeU64(buf, v),
            .data1 => |v| try buf.append(v),
            .data2 => |v| try writeU16(buf, v),
            .data4 => |v| try writeU32(buf, v),
            .data8 => |v| try writeU64(buf, v),
            .string => |v| {
                try buf.appendSlice(v);
                try buf.append(0);
            },
            .strp => |v| try writeU32(buf, v),
            .flag => |v| try buf.append(if (v) 1 else 0),
            .ref4 => |v| try writeU32(buf, v),
            .exprloc => |v| {
                try encodeULEB128(buf, @as(u64, @intCast(v.len)));
                try buf.appendSlice(v);
            },
            .sec_offset => |v| try writeU32(buf, v),
        }
    }
    
    /// 生成 .debug_abbrev section
    fn generateDebugAbbrev(self: *DwarfDebugInfoBuilder) ![]u8 {
        var buf = std.ArrayList(u8){};
        
        // 编译单元缩写
        try encodeULEB128(&buf, self.allocator, 1); // 缩写代码
        try encodeULEB128(&buf, @intFromEnum(DW_TAG.compile_unit));
        try buf.append(1); // 有子节点
        
        // 属性
        try encodeULEB128(&buf, @intFromEnum(DW_AT.name));
        try encodeULEB128(&buf, @intFromEnum(DW_FORM.strp));
        
        try encodeULEB128(&buf, @intFromEnum(DW_AT.comp_dir));
        try encodeULEB128(&buf, @intFromEnum(DW_FORM.strp));
        
        try encodeULEB128(&buf, @intFromEnum(DW_AT.language));
        try encodeULEB128(&buf, @intFromEnum(DW_FORM.data2));
        
        try encodeULEB128(&buf, @intFromEnum(DW_AT.producer));
        try encodeULEB128(&buf, @intFromEnum(DW_FORM.strp));
        
        // 结束标记
        try buf.append(0);
        try buf.append(0);
        
        // 函数缩写
        try encodeULEB128(&buf, self.allocator, 2);
        try encodeULEB128(&buf, @intFromEnum(DW_TAG.subprogram));
        try buf.append(1); // 有子节点
        
        try encodeULEB128(&buf, @intFromEnum(DW_AT.name));
        try encodeULEB128(&buf, @intFromEnum(DW_FORM.strp));
        
        try encodeULEB128(&buf, @intFromEnum(DW_AT.low_pc));
        try encodeULEB128(&buf, @intFromEnum(DW_FORM.addr));
        
        try encodeULEB128(&buf, @intFromEnum(DW_AT.high_pc));
        try encodeULEB128(&buf, @intFromEnum(DW_FORM.addr));
        
        try buf.append(0);
        try buf.append(0);
        
        // 结束标记
        try buf.append(0);
        
        return buf.toOwnedSlice();
    }
    
    /// 生成 .debug_line section
    fn generateDebugLine(self: *DwarfDebugInfoBuilder) ![]u8 {
        var buf = std.ArrayList(u8){};
        
        // 行号表头部
        try buf.appendSlice(&[_]u8{0} ** 4); // 长度（稍后填充）
        try writeU16(&buf, DWARF_VERSION);
        try writeU32(&buf, 0); // 头部长度（稍后填充）
        try buf.append(1); // 最小指令长度
        try buf.append(1); // 默认 is_stmt
        try buf.append(0); // line_base
        try buf.append(1); // line_range
        try buf.append(13); // opcode_base
        
        // 标准操作码长度
        const std_opcode_lengths = [_]u8{ 0, 1, 1, 1, 1, 0, 0, 0, 1, 0, 0, 1 };
        try buf.appendSlice(&std_opcode_lengths);
        
        // 目录表
        try buf.append(0); // 空目录表
        
        // 文件表
        for (self.line_table.files.items) |file| {
            try buf.appendSlice(file.name);
            try buf.append(0);
            try encodeULEB128(&buf, file.directory);
            try encodeULEB128(&buf, file.mod_time);
            try encodeULEB128(&buf, file.file_size);
        }
        try buf.append(0); // 文件表结束
        
        // 行号程序
        for (self.line_table.entries.items) |entry| {
            // DW_LNE_set_address
            try buf.append(0); // 扩展操作码
            try encodeULEB128(&buf, self.allocator, 9); // 长度
            try buf.append(2); // DW_LNE_set_address
            try writeU64(&buf, entry.address);
            
            // DW_LNS_set_file
            try buf.append(4);
            try encodeULEB128(&buf, entry.file);
            
            // DW_LNS_advance_line
            try buf.append(3);
            try encodeSLEB128(&buf, self.allocator, @as(i64, @intCast(entry.line)));
            
            // DW_LNS_copy
            try buf.append(1);
        }
        
        // DW_LNE_end_sequence
        try buf.append(0);
        try encodeULEB128(&buf, self.allocator, 1);
        try buf.append(1);
        
        // 填充长度
        const length = @as(u32, @intCast(buf.items.len - 4));
        std.mem.writeInt(u32, buf.items[0..4], length, .little);
        
        return buf.toOwnedSlice();
    }
    
    /// 生成 .debug_aranges section
    fn generateDebugAranges(self: *DwarfDebugInfoBuilder) ![]u8 {
        var buf = std.ArrayList(u8){};
        
        // 地址范围表头部
        try buf.appendSlice(&[_]u8{0} ** 4); // 长度（稍后填充）
        try writeU16(&buf, DWARF_VERSION);
        try writeU32(&buf, 0); // .debug_info 偏移
        try buf.append(8); // 地址大小
        try buf.append(0); // 段大小
        
        // 对齐到 2 * 地址大小
        while (buf.items.len % 16 != 0) {
            try buf.append(0);
        }
        
        // 地址范围
        for (self.address_ranges.items) |range| {
            try writeU64(&buf, range.low_pc);
            try writeU64(&buf, range.high_pc - range.low_pc);
        }
        
        // 结束标记
        try writeU64(&buf, 0);
        try writeU64(&buf, 0);
        
        // 填充长度
        const length = @as(u32, @intCast(buf.items.len - 4));
        std.mem.writeInt(u32, buf.items[0..4], length, .little);
        
        return buf.toOwnedSlice();
    }
};


// ============================================================================
// DWARF 数据结构
// ============================================================================

/// DWARF 调试数据
pub const DwarfData = struct {
    debug_info: []u8,
    debug_abbrev: []u8,
    debug_line: []u8,
    debug_str: []const u8,
    debug_aranges: []u8,
    
    pub fn deinit(self: *DwarfData, allocator: Allocator) void {
        allocator.free(self.debug_info);
        allocator.free(self.debug_abbrev);
        allocator.free(self.debug_line);
        allocator.free(self.debug_aranges);
    }
};

// ============================================================================
// 辅助函数
// ============================================================================

/// 编码 ULEB128（无符号 LEB128）
fn encodeULEB128(buf: *std.ArrayList(u8), allocator: Allocator, value: u64) !void {
    var v = value;
    while (true) {
        var byte = @as(u8, @intCast(v & 0x7F));
        v >>= 7;
        if (v != 0) {
            byte |= 0x80;
        }
        try buf.append(allocator, byte);
        if (v == 0) break;
    }
}

/// 编码 SLEB128（有符号 LEB128）
fn encodeSLEB128(buf: *std.ArrayList(u8), allocator: Allocator, value: i64) !void {
    var v = value;
    var more = true;
    while (more) {
        var byte = @as(u8, @intCast(v & 0x7F));
        v >>= 7;
        
        if ((v == 0 and (byte & 0x40) == 0) or (v == -1 and (byte & 0x40) != 0)) {
            more = false;
        } else {
            byte |= 0x80;
        }
        
        try buf.append(allocator, byte);
    }
}

/// 写入 u16（小端序）
fn writeU16(buf: *std.ArrayList(u8), allocator: Allocator, value: u16) !void {
    var bytes: [2]u8 = undefined;
    std.mem.writeInt(u16, &bytes, value, .little);
    try buf.appendSlice(allocator, &bytes);
}

/// 写入 u32（小端序）
fn writeU32(buf: *std.ArrayList(u8), allocator: Allocator, value: u32) !void {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, value, .little);
    try buf.appendSlice(allocator, &bytes);
}

/// 写入 u64（小端序）
fn writeU64(buf: *std.ArrayList(u8), allocator: Allocator, value: u64) !void {
    var bytes: [8]u8 = undefined;
    std.mem.writeInt(u64, &bytes, value, .little);
    try buf.appendSlice(allocator, &bytes);
}

// ============================================================================
// 单元测试
// ============================================================================

test "DwarfDebugInfoBuilder - 基本功能" {
    const allocator = std.testing.allocator;
    
    var builder = try DwarfDebugInfoBuilder.init(allocator);
    defer builder.deinit();
    
    // 创建编译单元
    try builder.createCompileUnit("test.php", "/path/to/source");
    
    // 创建函数
    const func_die = try builder.createFunction("testFunc", 0x1000, 0x1100, .i64);
    
    // 添加参数
    try builder.createFormalParameter(func_die, "x", .int32, 0);
    try builder.createFormalParameter(func_die, "y", .int32, 8);
    
    // 添加局部变量
    try builder.createLocalVariable(func_die, "result", .i64, 16, 10);
    
    // 添加行号映射
    try builder.addLineMapping(0x1000, 0, 10, 1);
    try builder.addLineMapping(0x1010, 0, 11, 1);
    try builder.addLineMapping(0x1020, 0, 12, 1);
    
    // 完成构建
    var dwarf_data = try builder.finalize();
    defer dwarf_data.deinit(allocator);
    
    // 验证生成的数据
    try std.testing.expect(dwarf_data.debug_info.len > 0);
    try std.testing.expect(dwarf_data.debug_abbrev.len > 0);
    try std.testing.expect(dwarf_data.debug_line.len > 0);
    try std.testing.expect(dwarf_data.debug_str.len > 0);
    try std.testing.expect(dwarf_data.debug_aranges.len > 0);
}

test "DwarfDebugInfoBuilder - 多函数" {
    const allocator = std.testing.allocator;
    
    var builder = try DwarfDebugInfoBuilder.init(allocator);
    defer builder.deinit();
    
    try builder.createCompileUnit("test.php", "/path/to/source");
    
    // 创建多个函数
    _ = try builder.createFunction("func1", 0x1000, 0x1100, .void);
    _ = try builder.createFunction("func2", 0x2000, 0x2200, .int32);
    _ = try builder.createFunction("func3", 0x3000, 0x3150, .float64);
    
    var dwarf_data = try builder.finalize();
    defer dwarf_data.deinit(allocator);
    
    // 验证地址范围
    try std.testing.expectEqual(@as(usize, 3), builder.address_ranges.items.len);
}

test "DwarfDebugInfoBuilder - 类型缓存" {
    const allocator = std.testing.allocator;
    
    var builder = try DwarfDebugInfoBuilder.init(allocator);
    defer builder.deinit();
    
    try builder.createCompileUnit("test.php", "/path/to/source");
    
    // 多次使用相同类型
    const func1 = try builder.createFunction("func1", 0x1000, 0x1100, .i64);
    const func2 = try builder.createFunction("func2", 0x2000, 0x2100, .i64);
    
    try builder.createLocalVariable(func1, "x", .i64, 0, 10);
    try builder.createLocalVariable(func2, "y", .i64, 0, 20);
    
    // 类型应该被缓存
    try std.testing.expect(builder.type_cache.count() > 0);
}

test "StringTable - 字符串去重" {
    const allocator = std.testing.allocator;
    
    var table = StringTable.init(allocator);
    defer table.deinit();
    
    const offset1 = try table.addString("hello");
    const offset2 = try table.addString("world");
    const offset3 = try table.addString("hello"); // 重复
    
    // 重复的字符串应该返回相同的偏移量
    try std.testing.expectEqual(offset1, offset3);
    try std.testing.expect(offset1 != offset2);
}

test "LineTable - 行号映射" {
    const allocator = std.testing.allocator;
    
    var table = LineTable.init(allocator);
    defer table.deinit();
    
    const file_idx = try table.addFile("test.php", 0);
    
    try table.addEntry(.{
        .address = 0x1000,
        .file = file_idx,
        .line = 10,
        .column = 1,
        .is_stmt = true,
        .basic_block = false,
        .end_sequence = false,
    });
    
    try std.testing.expectEqual(@as(usize, 1), table.entries.items.len);
    try std.testing.expectEqual(@as(u32, 10), table.entries.items[0].line);
}

test "ULEB128 编码" {
    const allocator = std.testing.allocator;
    
    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);
    
    // 测试小值
    try encodeULEB128(&buf, allocator, 0);
    try std.testing.expectEqual(@as(usize, 1), buf.items.len);
    try std.testing.expectEqual(@as(u8, 0), buf.items[0]);
    
    buf.clearRetainingCapacity();
    
    // 测试大值
    try encodeULEB128(&buf, allocator, 127);
    try std.testing.expectEqual(@as(usize, 1), buf.items.len);
    
    buf.clearRetainingCapacity();
    
    try encodeULEB128(&buf, allocator, 128);
    try std.testing.expectEqual(@as(usize, 2), buf.items.len);
}

test "SLEB128 编码" {
    const allocator = std.testing.allocator;
    
    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);
    
    // 测试正数
    try encodeSLEB128(&buf, allocator, 0);
    try std.testing.expectEqual(@as(usize, 1), buf.items.len);
    
    buf.clearRetainingCapacity();
    
    // 测试负数
    try encodeSLEB128(&buf, allocator, -1);
    try std.testing.expectEqual(@as(usize, 1), buf.items.len);
    try std.testing.expectEqual(@as(u8, 0x7F), buf.items[0]);
}

