/// PHP运行时模块根文件
/// 导出所有运行时组件

// 核心类型系统
pub const types = @import("types.zig");
pub const Value = types.Value;
pub const PHPString = types.PHPString;
pub const PHPArray = types.PHPArray;
pub const PHPObject = types.PHPObject;
pub const PHPClass = types.PHPClass;
pub const PHPInterface = types.PHPInterface;
pub const PHPTrait = types.PHPTrait;
pub const PHPStruct = types.PHPStruct;
pub const PHPResource = types.PHPResource;

// 垃圾回收
pub const gc = @import("gc.zig");

// 高性能内存管理系统
pub const memory = @import("memory.zig");
pub const MemoryManager = memory.MemoryManager;
pub const ArenaAllocator = memory.ArenaAllocator;
pub const StringInterner = memory.StringInterner;
pub const GenerationalGC = memory.GenerationalGC;
pub const LeakDetector = memory.LeakDetector;

// 虚拟机
pub const vm = @import("vm.zig");
pub const VM = vm.VM;

// 标准库
pub const stdlib = @import("stdlib.zig");
pub const StandardLibrary = stdlib.StandardLibrary;

// 异常处理
pub const exceptions = @import("exceptions.zig");
pub const PHPException = exceptions.PHPException;
pub const ErrorHandler = exceptions.ErrorHandler;
pub const ExceptionFactory = exceptions.ExceptionFactory;

// 反射系统
pub const reflection = @import("reflection.zig");
pub const ReflectionSystem = reflection.ReflectionSystem;

// PHP 8.5特性
pub const php85_features = @import("php85_features.zig");

// 环境
pub const environment = @import("environment.zig");
pub const Environment = environment.Environment;

// 新增模块

// 命名空间系统
pub const namespace = @import("namespace.zig");
pub const NamespaceManager = namespace.NamespaceManager;
pub const FileLoader = namespace.FileLoader;

// 内置类
pub const builtin_classes = @import("builtin_classes.zig");
pub const BuiltinClassManager = builtin_classes.BuiltinClassManager;

// HTTP服务器
pub const http_server = @import("http_server.zig");
pub const HttpServer = http_server.HttpServer;
pub const HttpRequest = http_server.HttpRequest;
pub const HttpResponse = http_server.HttpResponse;
pub const Router = http_server.Router;

// 协程系统
pub const coroutine = @import("coroutine.zig");
pub const CoroutineManager = coroutine.CoroutineManager;
pub const Coroutine = coroutine.Coroutine;
pub const Channel = coroutine.Channel;
pub const WaitGroup = coroutine.WaitGroup;

// 数据库
pub const database = @import("database.zig");
pub const PDO = database.PDO;
pub const PDOStatement = database.PDOStatement;
pub const MySQLi = database.MySQLi;

// cURL
pub const curl = @import("curl.zig");
pub const CurlHandle = curl.CurlHandle;
pub const CurlMulti = curl.CurlMulti;

// 高级GC系统
pub const concurrent_gc = @import("concurrent_gc.zig");
pub const ConcurrentGC = concurrent_gc.ConcurrentGC;

pub const compacting_gc = @import("compacting_gc.zig");
pub const CompactingGC = compacting_gc.CompactingGC;

// 性能监控
pub const performance_monitor = @import("performance_monitor.zig");
pub const RealTimeProfiler = performance_monitor.RealTimeProfiler;

// 插件系统
pub const plugin_system = @import("plugin_system.zig");

// ============================================================================
// 高性能优化模块
// ============================================================================

// 高性能内存池
pub const fast_pool = @import("fast_pool.zig");
pub const SlabAllocator = fast_pool.SlabAllocator;
pub const BumpAllocator = fast_pool.BumpAllocator;
pub const MultiPool = fast_pool.MultiPool;
pub const PoolManager = fast_pool.PoolManager;

// 高性能字符串
pub const fast_string = @import("fast_string.zig");
pub const StringPool = fast_string.StringPool;
pub const SSOString = fast_string.SSOString;
pub const fnv1a = fast_string.fnv1a;

// 高性能值类型
pub const fast_value = @import("fast_value.zig");
pub const FastValue = fast_value.FastValue;
pub const FastOps = fast_value.FastOps;
pub const ValueStack = fast_value.ValueStack;

// SIMD 优化
pub const simd_ops = @import("simd_ops.zig");
pub const SimdString = simd_ops.SimdString;
pub const SimdArray = simd_ops.SimdArray;
pub const FastMem = simd_ops.FastMem;

// 优化运行时
pub const fast_runtime = @import("fast_runtime.zig");
pub const OptRuntime = fast_runtime.OptRuntime;
pub const OptConfig = fast_runtime.OptConfig;
pub const Benchmark = fast_runtime.Benchmark;
pub const PerfStats = fast_runtime.PerfStats;
pub const PluginSystem = plugin_system.PluginSystem;

// 调试器
pub const debugger = @import("debugger.zig");
pub const Debugger = debugger.Debugger;

test {
    // 运行所有子模块测试
    @import("std").testing.refAllDecls(@This());
}
