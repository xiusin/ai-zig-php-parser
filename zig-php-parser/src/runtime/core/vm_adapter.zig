//! VM 适配器层
//!
//! 将核心函数适配到 VM 执行模式。
//! 负责 VM Value 类型与核心函数之间的转换。
//!
//! @ownership TRANSFER (返回的 Value 由 VM 管理)
//! @thread-safety ISOLATED

const std = @import("std");
const Allocator = std.mem.Allocator;

const core = @import("root.zig");
const CoreContext = core.CoreContext;

/// VM 适配器
/// 提供从 VM Value 到核心函数调用的桥接
pub fn VMAdapter(comptime Value: type, comptime VM: type) type {
    return struct {
        const Self = @This();

        /// 从 VM 创建核心上下文
        pub fn createContext(vm: *VM) CoreContext {
            return CoreContext.init(vm.allocator);
        }

        // ====================================================================
        // 字符串函数适配
        // ====================================================================

        /// strlen 适配
        pub fn strlen(vm: *VM, args: []const Value) !Value {
            _ = vm;
            if (args.len < 1) return Value.initNull();
            
            const str = args[0].toString() catch return Value.initNull();
            return Value.initInt(core.string.strlen(str));
        }

        /// substr 适配
        pub fn substr(vm: *VM, args: []const Value) !Value {
            if (args.len < 2) return Value.initNull();

            const str = args[0].toString() catch return Value.initNull();
            const start = args[0].toInt();
            const length: ?i64 = if (args.len >= 3) args[2].toInt() else null;

            var ctx = createContext(vm);
            const result = core.string.substr(&ctx, str, start, length) catch {
                return Value.initNull();
            };

            return Value.initStringOwned(result);
        }

        /// strtoupper 适配
        pub fn strtoupper(vm: *VM, args: []const Value) !Value {
            if (args.len < 1) return Value.initNull();

            const str = args[0].toString() catch return Value.initNull();
            var ctx = createContext(vm);
            const result = core.string.strtoupper(&ctx, str) catch {
                return Value.initNull();
            };

            return Value.initStringOwned(result);
        }

        /// strtolower 适配
        pub fn strtolower(vm: *VM, args: []const Value) !Value {
            if (args.len < 1) return Value.initNull();

            const str = args[0].toString() catch return Value.initNull();
            var ctx = createContext(vm);
            const result = core.string.strtolower(&ctx, str) catch {
                return Value.initNull();
            };

            return Value.initStringOwned(result);
        }

        /// strpos 适配
        pub fn strpos(vm: *VM, args: []const Value) !Value {
            _ = vm;
            if (args.len < 2) return Value.initBool(false);

            const haystack = args[0].toString() catch return Value.initBool(false);
            const needle = args[1].toString() catch return Value.initBool(false);
            const offset: usize = if (args.len >= 3)
                @intCast(@max(0, args[2].toInt()))
            else
                0;

            const pos = core.string.strpos(haystack, needle, offset);
            return if (pos >= 0) Value.initInt(pos) else Value.initBool(false);
        }

        /// str_contains 适配
        pub fn str_contains(vm: *VM, args: []const Value) !Value {
            _ = vm;
            if (args.len < 2) return Value.initBool(false);

            const haystack = args[0].toString() catch return Value.initBool(false);
            const needle = args[1].toString() catch return Value.initBool(false);

            return Value.initBool(core.string.str_contains(haystack, needle));
        }

        /// trim 适配
        pub fn trim(vm: *VM, args: []const Value) !Value {
            if (args.len < 1) return Value.initNull();

            const str = args[0].toString() catch return Value.initNull();
            const trimmed = core.string.trim(str);

            const result = vm.allocator.dupe(u8, trimmed) catch {
                return Value.initNull();
            };
            return Value.initStringOwned(result);
        }

        // ====================================================================
        // 数学函数适配
        // ====================================================================

        /// abs 适配
        pub fn abs(vm: *VM, args: []const Value) !Value {
            _ = vm;
            if (args.len < 1) return Value.initInt(0);

            const arg = args[0];
            if (arg.isInt()) {
                const result = core.math.abs(.{ .int = arg.toInt() });
                return Value.initInt(result.int);
            } else {
                const result = core.math.abs(.{ .float = arg.toFloat() });
                return Value.initFloat(result.float);
            }
        }

        /// round 适配
        pub fn round(vm: *VM, args: []const Value) !Value {
            _ = vm;
            if (args.len < 1) return Value.initFloat(0.0);

            const value = args[0].toFloat();
            const precision: i32 = if (args.len >= 2)
                @intCast(args[1].toInt())
            else
                0;

            return Value.initFloat(core.math.round(value, precision));
        }

        /// floor 适配
        pub fn floor(vm: *VM, args: []const Value) !Value {
            _ = vm;
            if (args.len < 1) return Value.initFloat(0.0);
            return Value.initFloat(core.math.floor(args[0].toFloat()));
        }

        /// ceil 适配
        pub fn ceil(vm: *VM, args: []const Value) !Value {
            _ = vm;
            if (args.len < 1) return Value.initFloat(0.0);
            return Value.initFloat(core.math.ceil(args[0].toFloat()));
        }

        /// sqrt 适配
        pub fn sqrt(vm: *VM, args: []const Value) !Value {
            _ = vm;
            if (args.len < 1) return Value.initFloat(0.0);
            return Value.initFloat(core.math.sqrt(args[0].toFloat()));
        }

        /// pow 适配
        pub fn pow(vm: *VM, args: []const Value) !Value {
            _ = vm;
            if (args.len < 2) return Value.initFloat(0.0);
            return Value.initFloat(core.math.pow(
                args[0].toFloat(),
                args[1].toFloat(),
            ));
        }

        /// min 适配
        pub fn min(vm: *VM, args: []const Value) !Value {
            _ = vm;
            if (args.len < 2) return Value.initNull();
            return Value.initFloat(core.math.min(
                args[0].toFloat(),
                args[1].toFloat(),
            ));
        }

        /// max 适配
        pub fn max(vm: *VM, args: []const Value) !Value {
            _ = vm;
            if (args.len < 2) return Value.initNull();
            return Value.initFloat(core.math.max(
                args[0].toFloat(),
                args[1].toFloat(),
            ));
        }

        // ====================================================================
        // 时间函数适配
        // ====================================================================

        /// time 适配
        pub fn time(vm: *VM, args: []const Value) !Value {
            _ = vm;
            _ = args;
            return Value.initInt(core.time.time());
        }

        /// microtime 适配
        pub fn microtime(vm: *VM, args: []const Value) !Value {
            const as_float = if (args.len >= 1) args[0].toBool() else false;

            if (as_float) {
                return Value.initFloat(core.time.microtime_float());
            } else {
                var ctx = createContext(vm);
                const result = core.time.microtime_string(&ctx) catch {
                    return Value.initNull();
                };
                return Value.initStringOwned(result);
            }
        }

        /// date 适配
        pub fn date(vm: *VM, args: []const Value) !Value {
            if (args.len < 1) return Value.initNull();

            const format = args[0].toString() catch return Value.initNull();
            const timestamp: ?i64 = if (args.len >= 2) args[1].toInt() else null;

            var ctx = createContext(vm);
            const result = core.time.date(&ctx, format, timestamp) catch {
                return Value.initNull();
            };
            return Value.initStringOwned(result);
        }

        // ====================================================================
        // 类型函数适配
        // ====================================================================

        /// intval 适配
        pub fn intval(vm: *VM, args: []const Value) !Value {
            _ = vm;
            if (args.len < 1) return Value.initInt(0);

            const arg = args[0];
            if (arg.isInt()) return arg;
            if (arg.isFloat()) return Value.initInt(@intFromFloat(arg.toFloat()));

            const str = arg.toString() catch return Value.initInt(0);
            const base: u8 = if (args.len >= 2)
                @intCast(@max(0, @min(36, args[1].toInt())))
            else
                10;

            return Value.initInt(core.types.intval(str, base));
        }

        /// floatval 适配
        pub fn floatval(vm: *VM, args: []const Value) !Value {
            _ = vm;
            if (args.len < 1) return Value.initFloat(0.0);

            const arg = args[0];
            if (arg.isFloat()) return arg;
            if (arg.isInt()) return Value.initFloat(@floatFromInt(arg.toInt()));

            const str = arg.toString() catch return Value.initFloat(0.0);
            return Value.initFloat(core.types.floatval(str));
        }

        /// is_numeric 适配
        pub fn is_numeric(vm: *VM, args: []const Value) !Value {
            _ = vm;
            if (args.len < 1) return Value.initBool(false);

            const arg = args[0];
            if (arg.isInt() or arg.isFloat()) return Value.initBool(true);

            const str = arg.toString() catch return Value.initBool(false);
            return Value.initBool(core.types.is_numeric(str));
        }

        // ====================================================================
        // 随机数函数适配
        // ====================================================================

        /// rand 适配
        pub fn rand(vm: *VM, args: []const Value) !Value {
            _ = vm;
            const min_val: ?i64 = if (args.len >= 1) args[0].toInt() else null;
            const max_val: ?i64 = if (args.len >= 2) args[1].toInt() else null;
            return Value.initInt(core.random.rand(min_val, max_val));
        }

        /// mt_rand 适配
        pub fn mt_rand(vm: *VM, args: []const Value) !Value {
            return rand(vm, args);
        }

        /// srand 适配
        pub fn srand(vm: *VM, args: []const Value) !Value {
            _ = vm;
            const seed: u64 = if (args.len >= 1)
                @bitCast(args[0].toInt())
            else
                @bitCast(std.time.nanoTimestamp());
            core.random.srand(seed);
            return Value.initNull();
        }

        /// random_int 适配
        pub fn random_int(vm: *VM, args: []const Value) !Value {
            _ = vm;
            if (args.len < 2) return Value.initInt(0);
            const result = core.random.random_int(
                args[0].toInt(),
                args[1].toInt(),
            ) catch return Value.initInt(0);
            return Value.initInt(result);
        }

        /// random_bytes 适配
        pub fn random_bytes(vm: *VM, args: []const Value) !Value {
            if (args.len < 1) return Value.initNull();

            const length: usize = @intCast(@max(0, args[0].toInt()));
            var ctx = createContext(vm);
            const result = core.random.random_bytes(&ctx, length) catch {
                return Value.initNull();
            };
            return Value.initStringOwned(result);
        }

        // ====================================================================
        // JSON 函数适配
        // ====================================================================

        /// json_encode 适配（简化版，仅支持标量类型）
        pub fn json_encode(vm: *VM, args: []const Value) !Value {
            if (args.len < 1) return Value.initNull();

            var ctx = createContext(vm);
            const arg = args[0];

            const result = blk: {
                if (arg.isNull()) {
                    break :blk core.json.json_encode_null(&ctx) catch {
                        return Value.initNull();
                    };
                } else if (arg.isBool()) {
                    break :blk core.json.json_encode_bool(&ctx, arg.toBool()) catch {
                        return Value.initNull();
                    };
                } else if (arg.isInt()) {
                    break :blk core.json.json_encode_int(&ctx, arg.toInt()) catch {
                        return Value.initNull();
                    };
                } else if (arg.isFloat()) {
                    break :blk core.json.json_encode_float(&ctx, arg.toFloat()) catch {
                        return Value.initNull();
                    };
                } else {
                    const str = arg.toString() catch return Value.initNull();
                    break :blk core.json.json_encode_string(&ctx, str, .{}) catch {
                        return Value.initNull();
                    };
                }
            };

            return Value.initStringOwned(result);
        }
    };
}
