# Design Document: PHP AOT Compiler

## Overview

本设计文档描述了为 Zig PHP 解释器添加 AOT (Ahead-of-Time) 编译功能的技术架构。该功能将 PHP 源代码编译为独立的原生二进制可执行文件，无需 PHP 运行时依赖。

### 设计目标

1. **最小侵入性**: 不修改现有解释器核心逻辑，AOT 编译作为独立模块
2. **复用现有基础设施**: 复用 Lexer、Parser、AST 定义
3. **跨平台支持**: 利用 Zig 的 LLVM 后端实现跨平台编译
4. **静态链接**: 生成无外部依赖的独立可执行文件
5. **安全性**: 保留边界检查和类型检查

### 编译流程

```
PHP Source → Lexer → Parser → AST → Type Inference → IR Generation → 
LLVM IR → Machine Code → Linker → Executable
```

## Architecture

### 高层架构图

```
┌─────────────────────────────────────────────────────────────────────┐
│                        AOT Compiler Pipeline                         │
├─────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────────────┐ │
│  │  Lexer   │──▶│  Parser  │──▶│   AST    │──▶│ Type Inferencer  │ │
│  │(existing)│   │(existing)│   │(existing)│   │     (new)        │ │
│  └──────────┘   └──────────┘   └──────────┘   └────────┬─────────┘ │
│                                                         │           │
│                                                         ▼           │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                    IR Generator (new)                         │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐   │  │
│  │  │ SSA Builder │  │ Const Fold  │  │ Dead Code Elim      │   │  │
│  │  └─────────────┘  └─────────────┘  └─────────────────────┘   │  │
│  └────────────────────────────┬─────────────────────────────────┘  │
│                               │                                     │
│                               ▼                                     │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                 Code Generator (new)                          │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐   │  │
│  │  │ LLVM Bridge │  │ ABI Handler │  │ Debug Info Gen      │   │  │
│  │  └─────────────┘  └─────────────┘  └─────────────────────┘   │  │
│  └────────────────────────────┬─────────────────────────────────┘  │
│                               │                                     │
│                               ▼                                     │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                    Static Linker                              │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐   │  │
│  │  │Runtime Lib  │  │ Symbol Res  │  │ Binary Output       │   │  │
│  │  └─────────────┘  └─────────────┘  └─────────────────────┘   │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### 模块依赖关系

```
src/
├── compiler/           # 现有编译器前端 (不修改)
│   ├── lexer.zig
│   ├── parser.zig
│   ├── ast.zig
│   └── token.zig
├── runtime/            # 现有运行时 (部分复用)
│   ├── types.zig       # 复用类型定义
│   ├── stdlib.zig      # 复用内置函数
│   └── gc.zig          # 复用 GC
├── aot/                # 新增 AOT 编译模块
│   ├── compiler.zig    # AOT 编译器主入口
│   ├── type_inference.zig
│   ├── ir.zig          # IR 定义
│   ├── ir_generator.zig
│   ├── codegen.zig     # LLVM 代码生成
│   ├── linker.zig      # 静态链接
│   └── runtime_lib.zig # 运行时库接口
└── main.zig            # 扩展命令行接口
```


## Components and Interfaces

### 1. AOT Compiler 主入口 (`src/aot/compiler.zig`)

```zig
pub const AOTCompiler = struct {
    allocator: std.mem.Allocator,
    options: CompileOptions,
    type_inferencer: *TypeInferencer,
    ir_generator: *IRGenerator,
    codegen: *CodeGenerator,
    linker: *StaticLinker,
    diagnostics: *DiagnosticEngine,

    pub const CompileOptions = struct {
        input_file: []const u8,
        output_file: ?[]const u8,
        target: Target,
        optimize_level: OptimizeLevel,
        static_link: bool,
        debug_info: bool,
        dump_ir: bool,
        dump_ast: bool,
        verbose: bool,
    };

    pub const OptimizeLevel = enum {
        debug,
        release_safe,
        release_fast,
        release_small,
    };

    pub const Target = struct {
        arch: Arch,
        os: OS,
        abi: ABI,

        pub const Arch = enum { x86_64, aarch64, arm };
        pub const OS = enum { linux, macos, windows };
        pub const ABI = enum { gnu, musl, msvc, none };

        pub fn native() Target { ... }
        pub fn fromString(triple: []const u8) !Target { ... }
    };

    pub fn init(allocator: std.mem.Allocator, options: CompileOptions) !*AOTCompiler { ... }
    pub fn deinit(self: *AOTCompiler) void { ... }
    
    /// 主编译入口
    pub fn compile(self: *AOTCompiler) !void {
        // 1. 解析源文件
        const ast = try self.parseSource();
        
        // 2. 类型推断
        const typed_ast = try self.type_inferencer.infer(ast);
        
        // 3. 生成 IR
        const ir = try self.ir_generator.generate(typed_ast);
        
        // 4. 优化 IR
        const optimized_ir = try self.optimizeIR(ir);
        
        // 5. 生成机器码
        const object_file = try self.codegen.generate(optimized_ir);
        
        // 6. 链接
        try self.linker.link(object_file, self.options.output_file);
    }
    
    pub fn compileToIR(self: *AOTCompiler) !*IR.Module { ... }
    pub fn compileToObject(self: *AOTCompiler) ![]const u8 { ... }
};
```

### 2. 类型推断器 (`src/aot/type_inference.zig`)

```zig
pub const TypeInferencer = struct {
    allocator: std.mem.Allocator,
    symbol_table: *SymbolTable,
    type_env: *TypeEnvironment,

    pub const InferredType = union(enum) {
        /// 精确类型 (编译时已知)
        concrete: ConcreteType,
        /// 联合类型
        union_type: []const ConcreteType,
        /// 动态类型 (需要运行时检查)
        dynamic: void,
    };

    pub const ConcreteType = enum {
        void,
        null,
        bool,
        int,
        float,
        string,
        array,
        object,
        callable,
        resource,
    };

    pub fn init(allocator: std.mem.Allocator) !*TypeInferencer { ... }
    pub fn deinit(self: *TypeInferencer) void { ... }

    /// 推断 AST 节点的类型
    pub fn infer(self: *TypeInferencer, ast: *ast.Node) !*TypedAST { ... }
    
    /// 推断表达式类型
    pub fn inferExpr(self: *TypeInferencer, expr: *ast.Node) !InferredType { ... }
    
    /// 推断函数返回类型
    pub fn inferFunctionReturn(self: *TypeInferencer, func: *ast.Node) !InferredType { ... }
};

pub const SymbolTable = struct {
    scopes: std.ArrayList(Scope),
    
    pub const Scope = struct {
        symbols: std.StringHashMap(Symbol),
        parent: ?*Scope,
    };
    
    pub const Symbol = struct {
        name: []const u8,
        kind: SymbolKind,
        inferred_type: InferredType,
        is_mutable: bool,
        source_location: SourceLocation,
    };
    
    pub const SymbolKind = enum {
        variable,
        function,
        class,
        constant,
        parameter,
    };
};
```

### 3. 中间表示 (IR) (`src/aot/ir.zig`)

```zig
pub const IR = struct {
    pub const Module = struct {
        name: []const u8,
        functions: std.ArrayList(*Function),
        globals: std.ArrayList(*Global),
        types: std.ArrayList(*TypeDef),
        source_file: []const u8,
    };

    pub const Function = struct {
        name: []const u8,
        params: []const Parameter,
        return_type: Type,
        blocks: std.ArrayList(*BasicBlock),
        is_exported: bool,
        source_location: SourceLocation,
    };

    pub const BasicBlock = struct {
        label: []const u8,
        instructions: std.ArrayList(*Instruction),
        terminator: *Terminator,
    };

    /// SSA 形式的指令
    pub const Instruction = struct {
        result: ?Register,
        op: Op,
        source_location: SourceLocation,

        pub const Op = union(enum) {
            // 算术运算
            add: BinaryOp,
            sub: BinaryOp,
            mul: BinaryOp,
            div: BinaryOp,
            mod: BinaryOp,
            neg: UnaryOp,
            
            // 比较运算
            eq: BinaryOp,
            ne: BinaryOp,
            lt: BinaryOp,
            le: BinaryOp,
            gt: BinaryOp,
            ge: BinaryOp,
            
            // 逻辑运算
            and_: BinaryOp,
            or_: BinaryOp,
            not: UnaryOp,
            
            // 内存操作
            alloca: AllocaOp,
            load: LoadOp,
            store: StoreOp,
            
            // 函数调用
            call: CallOp,
            
            // 类型操作
            cast: CastOp,
            type_check: TypeCheckOp,
            
            // PHP 特定操作
            array_get: ArrayGetOp,
            array_set: ArraySetOp,
            property_get: PropertyGetOp,
            property_set: PropertySetOp,
            method_call: MethodCallOp,
            new_object: NewObjectOp,
            new_array: NewArrayOp,
            concat: BinaryOp,
            
            // Phi 节点 (SSA)
            phi: PhiOp,
        };
    };

    pub const Terminator = union(enum) {
        ret: ?Register,
        br: *BasicBlock,
        cond_br: struct {
            cond: Register,
            then_block: *BasicBlock,
            else_block: *BasicBlock,
        },
        switch_: struct {
            value: Register,
            cases: []const SwitchCase,
            default: *BasicBlock,
        },
        unreachable: void,
    };

    pub const Register = struct {
        id: u32,
        type_: Type,
    };

    pub const Type = union(enum) {
        void: void,
        bool: void,
        i64: void,
        f64: void,
        ptr: *Type,
        php_value: void,  // 动态类型的 PHP 值
        php_string: void,
        php_array: void,
        php_object: []const u8,  // 类名
        function: FunctionType,
    };
};
```


### 4. IR 生成器 (`src/aot/ir_generator.zig`)

```zig
pub const IRGenerator = struct {
    allocator: std.mem.Allocator,
    module: *IR.Module,
    current_function: ?*IR.Function,
    current_block: ?*IR.BasicBlock,
    register_counter: u32,
    symbol_table: *SymbolTable,

    pub fn init(allocator: std.mem.Allocator) !*IRGenerator { ... }
    pub fn deinit(self: *IRGenerator) void { ... }

    /// 从类型注解的 AST 生成 IR
    pub fn generate(self: *IRGenerator, typed_ast: *TypedAST) !*IR.Module {
        self.module = try IR.Module.init(self.allocator);
        
        for (typed_ast.root.stmts) |stmt| {
            try self.generateStmt(stmt);
        }
        
        return self.module;
    }

    fn generateStmt(self: *IRGenerator, node: *ast.Node) !void {
        switch (node.tag) {
            .function_decl => try self.generateFunction(node),
            .class_decl => try self.generateClass(node),
            .if_stmt => try self.generateIf(node),
            .while_stmt => try self.generateWhile(node),
            .for_stmt => try self.generateFor(node),
            .foreach_stmt => try self.generateForeach(node),
            .try_stmt => try self.generateTry(node),
            .return_stmt => try self.generateReturn(node),
            .echo_stmt => try self.generateEcho(node),
            .expression_stmt => _ = try self.generateExpr(node.data.expression_stmt.expr),
            else => {},
        }
    }

    fn generateExpr(self: *IRGenerator, node: *ast.Node) !IR.Register {
        switch (node.tag) {
            .literal_int => return self.emitConstInt(node.data.literal_int.value),
            .literal_float => return self.emitConstFloat(node.data.literal_float.value),
            .literal_string => return self.emitConstString(node.data.literal_string.value),
            .variable => return self.emitLoad(node.data.variable.name),
            .binary_expr => return self.generateBinaryExpr(node),
            .unary_expr => return self.generateUnaryExpr(node),
            .function_call => return self.generateCall(node),
            .method_call => return self.generateMethodCall(node),
            .array_access => return self.generateArrayAccess(node),
            .property_access => return self.generatePropertyAccess(node),
            .closure => return self.generateClosure(node),
            .array_init => return self.generateArrayInit(node),
            .object_instantiation => return self.generateNewObject(node),
            else => return self.emitConstNull(),
        }
    }

    /// 分配新的 SSA 寄存器
    fn newRegister(self: *IRGenerator, type_: IR.Type) IR.Register {
        const reg = IR.Register{
            .id = self.register_counter,
            .type_ = type_,
        };
        self.register_counter += 1;
        return reg;
    }

    /// 发射指令
    fn emit(self: *IRGenerator, op: IR.Instruction.Op, result_type: ?IR.Type) !IR.Register {
        const result = if (result_type) |t| self.newRegister(t) else null;
        const inst = try self.allocator.create(IR.Instruction);
        inst.* = .{
            .result = result,
            .op = op,
            .source_location = self.current_source_location,
        };
        try self.current_block.?.instructions.append(inst);
        return result orelse IR.Register{ .id = 0, .type_ = .void };
    }
};
```

### 5. 代码生成器 (`src/aot/codegen.zig`)

```zig
const llvm = @cImport({
    @cInclude("llvm-c/Core.h");
    @cInclude("llvm-c/Target.h");
    @cInclude("llvm-c/TargetMachine.h");
    @cInclude("llvm-c/Analysis.h");
});

pub const CodeGenerator = struct {
    allocator: std.mem.Allocator,
    context: llvm.LLVMContextRef,
    module: llvm.LLVMModuleRef,
    builder: llvm.LLVMBuilderRef,
    target_machine: llvm.LLVMTargetMachineRef,
    target: AOTCompiler.Target,
    optimize_level: AOTCompiler.OptimizeLevel,
    
    // 类型映射
    php_value_type: llvm.LLVMTypeRef,
    php_string_type: llvm.LLVMTypeRef,
    php_array_type: llvm.LLVMTypeRef,
    
    // 运行时函数引用
    runtime_functions: std.StringHashMap(llvm.LLVMValueRef),

    pub fn init(
        allocator: std.mem.Allocator,
        target: AOTCompiler.Target,
        optimize_level: AOTCompiler.OptimizeLevel,
    ) !*CodeGenerator { ... }
    
    pub fn deinit(self: *CodeGenerator) void { ... }

    /// 从 IR 生成 LLVM IR 并编译为目标代码
    pub fn generate(self: *CodeGenerator, ir: *IR.Module) ![]const u8 {
        // 1. 声明运行时函数
        try self.declareRuntimeFunctions();
        
        // 2. 生成类型定义
        for (ir.types.items) |type_def| {
            try self.generateTypeDef(type_def);
        }
        
        // 3. 生成全局变量
        for (ir.globals.items) |global| {
            try self.generateGlobal(global);
        }
        
        // 4. 生成函数
        for (ir.functions.items) |func| {
            try self.generateFunction(func);
        }
        
        // 5. 验证模块
        try self.verifyModule();
        
        // 6. 优化
        try self.optimize();
        
        // 7. 生成目标代码
        return try self.emitObjectCode();
    }

    fn generateFunction(self: *CodeGenerator, func: *IR.Function) !void {
        // 创建 LLVM 函数
        const func_type = self.getLLVMFunctionType(func);
        const llvm_func = llvm.LLVMAddFunction(
            self.module,
            func.name.ptr,
            func_type,
        );
        
        // 生成基本块
        for (func.blocks.items) |block| {
            try self.generateBasicBlock(llvm_func, block);
        }
    }

    fn generateInstruction(self: *CodeGenerator, inst: *IR.Instruction) !llvm.LLVMValueRef {
        return switch (inst.op) {
            .add => |op| self.buildAdd(op),
            .sub => |op| self.buildSub(op),
            .mul => |op| self.buildMul(op),
            .div => |op| self.buildDiv(op),
            .call => |op| self.buildCall(op),
            .load => |op| self.buildLoad(op),
            .store => |op| self.buildStore(op),
            .array_get => |op| self.buildArrayGet(op),
            .array_set => |op| self.buildArraySet(op),
            .type_check => |op| self.buildTypeCheck(op),
            .cast => |op| self.buildCast(op),
            .phi => |op| self.buildPhi(op),
            else => unreachable,
        };
    }

    /// 声明运行时库函数
    fn declareRuntimeFunctions(self: *CodeGenerator) !void {
        // PHP 值操作
        try self.declareRuntimeFunc("php_value_create_int", ...);
        try self.declareRuntimeFunc("php_value_create_float", ...);
        try self.declareRuntimeFunc("php_value_create_string", ...);
        try self.declareRuntimeFunc("php_value_create_array", ...);
        try self.declareRuntimeFunc("php_value_get_type", ...);
        try self.declareRuntimeFunc("php_value_to_int", ...);
        try self.declareRuntimeFunc("php_value_to_float", ...);
        try self.declareRuntimeFunc("php_value_to_string", ...);
        try self.declareRuntimeFunc("php_value_to_bool", ...);
        
        // 数组操作
        try self.declareRuntimeFunc("php_array_create", ...);
        try self.declareRuntimeFunc("php_array_get", ...);
        try self.declareRuntimeFunc("php_array_set", ...);
        try self.declareRuntimeFunc("php_array_push", ...);
        try self.declareRuntimeFunc("php_array_count", ...);
        
        // 字符串操作
        try self.declareRuntimeFunc("php_string_concat", ...);
        try self.declareRuntimeFunc("php_string_length", ...);
        
        // 对象操作
        try self.declareRuntimeFunc("php_object_create", ...);
        try self.declareRuntimeFunc("php_object_get_property", ...);
        try self.declareRuntimeFunc("php_object_set_property", ...);
        try self.declareRuntimeFunc("php_object_call_method", ...);
        
        // 内存管理
        try self.declareRuntimeFunc("php_gc_alloc", ...);
        try self.declareRuntimeFunc("php_gc_retain", ...);
        try self.declareRuntimeFunc("php_gc_release", ...);
        
        // 异常处理
        try self.declareRuntimeFunc("php_throw", ...);
        try self.declareRuntimeFunc("php_catch", ...);
        
        // I/O
        try self.declareRuntimeFunc("php_echo", ...);
        try self.declareRuntimeFunc("php_print", ...);
    }

    fn emitObjectCode(self: *CodeGenerator) ![]const u8 {
        var error_msg: [*c]u8 = null;
        var output_buffer: llvm.LLVMMemoryBufferRef = null;
        
        if (llvm.LLVMTargetMachineEmitToMemoryBuffer(
            self.target_machine,
            self.module,
            llvm.LLVMObjectFile,
            &error_msg,
            &output_buffer,
        ) != 0) {
            return error.CodeGenFailed;
        }
        
        const data = llvm.LLVMGetBufferStart(output_buffer);
        const size = llvm.LLVMGetBufferSize(output_buffer);
        
        return data[0..size];
    }
};
```


### 6. 运行时库 (`src/aot/runtime_lib.zig`)

```zig
/// AOT 编译后程序使用的运行时库
/// 这些函数会被静态链接到最终的可执行文件中
pub const RuntimeLib = struct {
    
    // ============ PHP Value 类型 ============
    
    pub const PHPValue = extern struct {
        tag: ValueTag,
        data: ValueData,
        ref_count: u32,
        
        pub const ValueTag = enum(u8) {
            null = 0,
            bool = 1,
            int = 2,
            float = 3,
            string = 4,
            array = 5,
            object = 6,
            resource = 7,
        };
        
        pub const ValueData = extern union {
            bool_val: bool,
            int_val: i64,
            float_val: f64,
            string_ptr: *PHPString,
            array_ptr: *PHPArray,
            object_ptr: *PHPObject,
            resource_ptr: *anyopaque,
        };
    };

    // ============ 导出的运行时函数 ============
    
    /// 创建整数值
    export fn php_value_create_int(val: i64) *PHPValue {
        const v = global_allocator.create(PHPValue) catch return null;
        v.* = .{
            .tag = .int,
            .data = .{ .int_val = val },
            .ref_count = 1,
        };
        return v;
    }
    
    /// 创建浮点值
    export fn php_value_create_float(val: f64) *PHPValue {
        const v = global_allocator.create(PHPValue) catch return null;
        v.* = .{
            .tag = .float,
            .data = .{ .float_val = val },
            .ref_count = 1,
        };
        return v;
    }
    
    /// 创建字符串值
    export fn php_value_create_string(data: [*]const u8, len: usize) *PHPValue {
        const str = PHPString.init(global_allocator, data[0..len]) catch return null;
        const v = global_allocator.create(PHPValue) catch return null;
        v.* = .{
            .tag = .string,
            .data = .{ .string_ptr = str },
            .ref_count = 1,
        };
        return v;
    }
    
    /// 获取值类型
    export fn php_value_get_type(val: *PHPValue) u8 {
        return @intFromEnum(val.tag);
    }
    
    /// 转换为整数
    export fn php_value_to_int(val: *PHPValue) i64 {
        return switch (val.tag) {
            .null => 0,
            .bool => if (val.data.bool_val) 1 else 0,
            .int => val.data.int_val,
            .float => @intFromFloat(val.data.float_val),
            .string => std.fmt.parseInt(i64, val.data.string_ptr.data, 10) catch 0,
            else => 0,
        };
    }
    
    /// 转换为布尔值
    export fn php_value_to_bool(val: *PHPValue) bool {
        return switch (val.tag) {
            .null => false,
            .bool => val.data.bool_val,
            .int => val.data.int_val != 0,
            .float => val.data.float_val != 0.0,
            .string => val.data.string_ptr.length > 0 and 
                       !std.mem.eql(u8, val.data.string_ptr.data, "0"),
            .array => val.data.array_ptr.count() > 0,
            else => true,
        };
    }
    
    /// 引用计数增加
    export fn php_gc_retain(val: *PHPValue) void {
        val.ref_count += 1;
    }
    
    /// 引用计数减少
    export fn php_gc_release(val: *PHPValue) void {
        val.ref_count -= 1;
        if (val.ref_count == 0) {
            // 释放内部数据
            switch (val.tag) {
                .string => val.data.string_ptr.deinit(global_allocator),
                .array => val.data.array_ptr.deinit(global_allocator),
                .object => val.data.object_ptr.deinit(global_allocator),
                else => {},
            }
            global_allocator.destroy(val);
        }
    }
    
    // ============ 数组操作 ============
    
    export fn php_array_create() *PHPArray {
        return PHPArray.init(global_allocator) catch return null;
    }
    
    export fn php_array_get(arr: *PHPArray, key: *PHPValue) *PHPValue {
        const array_key = valueToArrayKey(key);
        return arr.get(array_key) orelse php_value_create_null();
    }
    
    export fn php_array_set(arr: *PHPArray, key: *PHPValue, val: *PHPValue) void {
        const array_key = valueToArrayKey(key);
        arr.set(global_allocator, array_key, val) catch {};
    }
    
    export fn php_array_push(arr: *PHPArray, val: *PHPValue) void {
        arr.push(global_allocator, val) catch {};
    }
    
    export fn php_array_count(arr: *PHPArray) i64 {
        return @intCast(arr.count());
    }
    
    // ============ 字符串操作 ============
    
    export fn php_string_concat(a: *PHPValue, b: *PHPValue) *PHPValue {
        const str_a = valueToString(a);
        const str_b = valueToString(b);
        const result = str_a.concat(str_b, global_allocator) catch return null;
        return php_value_create_string(result.data.ptr, result.length);
    }
    
    export fn php_string_length(val: *PHPValue) i64 {
        if (val.tag != .string) return 0;
        return @intCast(val.data.string_ptr.length);
    }
    
    // ============ I/O 操作 ============
    
    export fn php_echo(val: *PHPValue) void {
        const str = valueToString(val);
        const stdout = std.io.getStdOut().writer();
        stdout.writeAll(str.data) catch {};
    }
    
    export fn php_print(val: *PHPValue) i64 {
        php_echo(val);
        return 1;
    }
    
    // ============ 异常处理 ============
    
    var current_exception: ?*PHPValue = null;
    
    export fn php_throw(exception: *PHPValue) void {
        current_exception = exception;
    }
    
    export fn php_catch() ?*PHPValue {
        const ex = current_exception;
        current_exception = null;
        return ex;
    }
    
    export fn php_has_exception() bool {
        return current_exception != null;
    }
    
    // ============ 内置函数 ============
    
    export fn php_builtin_strlen(val: *PHPValue) *PHPValue {
        return php_value_create_int(php_string_length(val));
    }
    
    export fn php_builtin_count(val: *PHPValue) *PHPValue {
        if (val.tag != .array) return php_value_create_int(0);
        return php_value_create_int(php_array_count(val.data.array_ptr));
    }
    
    export fn php_builtin_var_dump(val: *PHPValue) void {
        const stdout = std.io.getStdOut().writer();
        dumpValue(stdout, val, 0) catch {};
    }
    
    // ... 更多内置函数
};
```

### 7. 静态链接器 (`src/aot/linker.zig`)

```zig
pub const StaticLinker = struct {
    allocator: std.mem.Allocator,
    target: AOTCompiler.Target,
    runtime_lib_path: []const u8,

    pub fn init(allocator: std.mem.Allocator, target: AOTCompiler.Target) !*StaticLinker { ... }
    pub fn deinit(self: *StaticLinker) void { ... }

    /// 链接目标文件和运行时库生成最终可执行文件
    pub fn link(
        self: *StaticLinker,
        object_code: []const u8,
        output_path: []const u8,
    ) !void {
        // 1. 写入临时目标文件
        const obj_path = try self.writeTempObject(object_code);
        defer std.fs.deleteFile(obj_path) catch {};
        
        // 2. 获取运行时库路径
        const runtime_lib = try self.getRuntimeLibPath();
        
        // 3. 调用系统链接器
        try self.invokeLinker(obj_path, runtime_lib, output_path);
    }

    fn invokeLinker(
        self: *StaticLinker,
        obj_path: []const u8,
        runtime_lib: []const u8,
        output_path: []const u8,
    ) !void {
        var args = std.ArrayList([]const u8).init(self.allocator);
        defer args.deinit();
        
        // 根据目标平台选择链接器和参数
        switch (self.target.os) {
            .linux => {
                try args.appendSlice(&.{
                    "ld",
                    "-o", output_path,
                    obj_path,
                    runtime_lib,
                    "-static",
                    "-lc",
                });
            },
            .macos => {
                try args.appendSlice(&.{
                    "ld",
                    "-o", output_path,
                    obj_path,
                    runtime_lib,
                    "-lSystem",
                    "-syslibroot", "/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk",
                });
            },
            .windows => {
                try args.appendSlice(&.{
                    "lld-link",
                    "/OUT:" ++ output_path,
                    obj_path,
                    runtime_lib,
                    "/SUBSYSTEM:CONSOLE",
                });
            },
        }
        
        var child = std.process.Child.init(args.items, self.allocator);
        _ = try child.spawnAndWait();
    }
};
```


## Data Models

### PHP Value 内存布局

```
┌─────────────────────────────────────────────────────────────┐
│                      PHPValue (24 bytes)                     │
├─────────────┬─────────────┬─────────────────────────────────┤
│   tag (1B)  │ padding(3B) │        ref_count (4B)           │
├─────────────┴─────────────┴─────────────────────────────────┤
│                      data (16 bytes)                         │
│  ┌─────────────────────────────────────────────────────────┐│
│  │ bool_val (1B) | int_val (8B) | float_val (8B) |         ││
│  │ string_ptr (8B) | array_ptr (8B) | object_ptr (8B)      ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

### IR 指令格式

```
┌─────────────────────────────────────────────────────────────┐
│                    IR Instruction                            │
├─────────────┬─────────────┬─────────────────────────────────┤
│ result_reg  │   opcode    │         operands                │
│   (4B)      │    (2B)     │        (variable)               │
├─────────────┴─────────────┴─────────────────────────────────┤
│                  source_location (12B)                       │
│  ┌─────────────┬─────────────┬─────────────────────────────┐│
│  │  file_id    │    line     │         column              ││
│  │   (4B)      │    (4B)     │          (4B)               ││
│  └─────────────┴─────────────┴─────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

### 符号表结构

```
SymbolTable
├── global_scope
│   ├── functions: HashMap<name, FunctionSymbol>
│   ├── classes: HashMap<name, ClassSymbol>
│   └── constants: HashMap<name, ConstantSymbol>
└── scopes: Stack<LocalScope>
    └── LocalScope
        ├── variables: HashMap<name, VariableSymbol>
        ├── parent: ?*LocalScope
        └── depth: u32
```

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system-essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: 编译执行往返正确性

*For any* valid PHP source code that does not use dynamic features (eval, variable variables, dynamic function calls), compiling it with the AOT compiler and executing the resulting binary SHALL produce the same output as interpreting the same code with the tree-walking interpreter.

**Validates: Requirements 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 6.7**

### Property 2: IR 生成 SSA 正确性

*For any* generated IR module, each register SHALL be assigned exactly once (Static Single Assignment form), and all uses of a register SHALL be dominated by its definition.

**Validates: Requirements 2.6**

### Property 3: 类型推断正确性

*For any* PHP expression with explicit type declarations, the inferred type SHALL match the declared type. *For any* expression without type declarations, the inferred type SHALL be compatible with all possible runtime values.

**Validates: Requirements 3.1, 3.2, 3.3, 3.4**

### Property 4: 常量折叠正确性

*For any* constant expression (expression composed only of literals and pure operations), the IR generator SHALL replace it with a single constant value, and this value SHALL equal the result of evaluating the expression at runtime.

**Validates: Requirements 2.5, 8.1**

### Property 5: 错误报告完整性

*For any* PHP source code containing syntax errors, type errors, or undefined symbol references, the AOT compiler SHALL report at least one error with a valid source location (file, line, column).

**Validates: Requirements 7.1, 7.2, 7.3**

### Property 6: 安全检查有效性

*For any* array access operation in the generated code, there SHALL be a bounds check that prevents out-of-bounds access. *For any* pointer dereference, there SHALL be a null check that prevents null pointer dereference.

**Validates: Requirements 12.1, 12.2**

### Property 7: 运行时库类型转换正确性

*For any* PHP value, converting it to another type using the runtime library functions SHALL produce the same result as PHP's type juggling rules.

**Validates: Requirements 5.2**

### Property 8: 垃圾回收正确性

*For any* sequence of value allocations and releases, the reference count of each value SHALL accurately reflect the number of live references, and values with zero references SHALL be deallocated.

**Validates: Requirements 5.3**

### Property 9: 源位置信息保留

*For any* IR instruction generated from a PHP statement or expression, the instruction SHALL contain a valid source location that maps back to the original PHP source code.

**Validates: Requirements 2.4, 11.2**

### Property 10: 死代码消除正确性

*For any* code path that is statically determined to be unreachable, the optimized IR SHALL not contain instructions for that path, AND removing this code SHALL not change the observable behavior of the program.

**Validates: Requirements 8.2**

## Error Handling

### 编译时错误

| 错误类型 | 错误码 | 描述 | 处理方式 |
|---------|-------|------|---------|
| SyntaxError | E001 | PHP 语法错误 | 报告位置和建议修复 |
| TypeError | E002 | 类型不匹配 | 报告期望类型和实际类型 |
| UndefinedSymbol | E003 | 未定义的函数/类/变量 | 报告符号名和可能的拼写建议 |
| CircularDependency | E004 | 循环依赖 | 报告依赖链 |
| UnsupportedFeature | E005 | 不支持的动态特性 | 报告特性名和替代方案 |
| CodeGenError | E006 | 代码生成失败 | 报告 LLVM 错误信息 |
| LinkError | E007 | 链接失败 | 报告未解析的符号 |

### 运行时错误

| 错误类型 | 描述 | 处理方式 |
|---------|------|---------|
| NullPointerException | 空指针访问 | 抛出异常，输出堆栈跟踪 |
| ArrayIndexOutOfBounds | 数组越界 | 抛出异常，输出堆栈跟踪 |
| TypeError | 运行时类型错误 | 抛出异常，输出堆栈跟踪 |
| DivisionByZero | 除零错误 | 抛出异常，输出堆栈跟踪 |
| OutOfMemory | 内存不足 | 尝试 GC，失败则终止 |

### 诊断引擎

```zig
pub const DiagnosticEngine = struct {
    errors: std.ArrayList(Diagnostic),
    warnings: std.ArrayList(Diagnostic),
    
    pub const Diagnostic = struct {
        level: Level,
        code: []const u8,
        message: []const u8,
        location: SourceLocation,
        hints: []const []const u8,
        
        pub const Level = enum { error, warning, note };
    };
    
    pub fn emit(self: *DiagnosticEngine, diag: Diagnostic) void { ... }
    pub fn hasErrors(self: *DiagnosticEngine) bool { ... }
    pub fn printAll(self: *DiagnosticEngine, writer: anytype) void { ... }
};
```

## Testing Strategy

### 单元测试

1. **Lexer/Parser 测试** (现有)
   - 验证各种 PHP 语法的正确解析

2. **类型推断测试**
   - 测试字面量类型推断
   - 测试函数参数/返回类型推断
   - 测试联合类型推断
   - 测试动态类型回退

3. **IR 生成测试**
   - 测试各种 AST 节点到 IR 的转换
   - 测试 SSA 形式正确性
   - 测试常量折叠

4. **代码生成测试**
   - 测试 LLVM IR 生成
   - 测试各种目标平台

5. **运行时库测试**
   - 测试类型转换
   - 测试数组操作
   - 测试字符串操作
   - 测试 GC

### 属性测试

使用 Zig 的测试框架实现属性测试：

```zig
const std = @import("std");
const testing = std.testing;
const aot = @import("aot/compiler.zig");

// Property 1: 编译执行往返正确性
test "Property 1: compile-execute roundtrip" {
    // Feature: php-aot-compiler, Property 1: compile-execute roundtrip
    const test_cases = generateRandomPHPCode(100);
    
    for (test_cases) |php_code| {
        const interpreted_output = interpretPHP(php_code);
        const compiled_binary = try compilePHP(php_code);
        const compiled_output = try executeBinary(compiled_binary);
        
        try testing.expectEqualStrings(interpreted_output, compiled_output);
    }
}

// Property 2: IR SSA 正确性
test "Property 2: IR SSA correctness" {
    // Feature: php-aot-compiler, Property 2: IR SSA correctness
    const test_cases = generateRandomPHPCode(100);
    
    for (test_cases) |php_code| {
        const ir = try generateIR(php_code);
        try verifySSAForm(ir);
    }
}

// Property 3: 类型推断正确性
test "Property 3: type inference correctness" {
    // Feature: php-aot-compiler, Property 3: type inference correctness
    const test_cases = generateTypedPHPCode(100);
    
    for (test_cases) |php_code| {
        const inferred_types = try inferTypes(php_code);
        const declared_types = extractDeclaredTypes(php_code);
        
        for (declared_types) |decl| {
            const inferred = inferred_types.get(decl.name);
            try testing.expect(typesCompatible(inferred, decl.type));
        }
    }
}
```

### 集成测试

1. **端到端编译测试**
   - 编译示例 PHP 文件
   - 验证生成的二进制可执行
   - 验证输出正确

2. **跨平台测试**
   - 在 CI 中测试 Linux、macOS、Windows
   - 测试交叉编译

3. **性能测试**
   - 比较编译后二进制与解释执行的性能
   - 测试不同优化级别的效果

### 测试配置

- 每个属性测试运行至少 100 次迭代
- 使用随机生成的 PHP 代码作为输入
- 测试覆盖所有支持的 PHP 语法特性
