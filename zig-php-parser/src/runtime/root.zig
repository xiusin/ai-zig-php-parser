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

test {
    // 运行所有子模块测试
    @import("std").testing.refAllDecls(@This());
}
