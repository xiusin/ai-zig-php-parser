// 嵌套循环代码生成 - 新实现
// 
// 设计原则：
// 1. 显式累加器识别：通过 PHI 节点模式识别累加器
// 2. 直接值传递：子循环结束后直接生成赋值语句
// 3. 清晰的接口：外层和内层循环通过明确的寄存器传递值
// 4. 可扩展性：支持任意深度的嵌套
//
// 累加器识别规则：
// - PHI 节点有两个 incoming：初始值（常量）和循环内更新值
// - 更新值来自 add/sub 等算术操作
// - 不是循环变量（循环变量的更新是固定步长）
//
// 值传递策略：
// - 子循环结束时，将子循环的所有累加器保存到临时变量
// - 外层循环的 PHI 更新时，从临时变量读取
//
// 示例：
// ```
// for ($i = 0; $i < 10; $i++) {
//     for ($j = 0; $j < 10; $j++) {
//         $sum += $i * $j;  // $sum 是累加器
//     }
// }
// ```
//
// 生成代码：
// ```zig
// while (true) {
//     // 外层 header
//     if (!(i < 10)) break;
//     
//     // 内层循环
//     while (true) {
//         // 内层 header
//         if (!(j < 10)) break;
//         sum = sum + i * j;
//         j = j + 1;
//     }
//     
//     // 关键：内层循环结束后，sum 已经是最新值
//     // 外层 PHI 更新时直接使用 sum
//     i = i + 1;
// }
// ```

const std = @import("std");
const IR = @import("ir.zig");

/// 累加器信息
pub const AccumulatorInfo = struct {
    /// 累加器寄存器 ID
    reg_id: usize,
    /// 累加器类型
    type_: IR.Type,
    /// 初始值寄存器 ID
    init_reg: ?usize,
    /// 是否来自外层循环
    from_outer: bool,
};

/// 循环上下文信息
pub const LoopContext = struct {
    /// 循环变量（归纳变量）
    induction_vars: std.ArrayList(usize),
    /// 累加器
    accumulators: std.ArrayList(AccumulatorInfo),
    /// 父循环上下文
    parent: ?*LoopContext,
    
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) LoopContext {
        return .{
            .induction_vars = std.ArrayList(usize).init(allocator),
            .accumulators = std.ArrayList(AccumulatorInfo).init(allocator),
            .parent = null,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *LoopContext) void {
        self.induction_vars.deinit();
        self.accumulators.deinit();
    }
};

/// 分析循环中的累加器
pub fn analyzeLoopAccumulators(
    allocator: std.mem.Allocator,
    func: *const IR.Function,
    loop_header_idx: usize,
) !std.ArrayList(AccumulatorInfo) {
    var accumulators = std.ArrayList(AccumulatorInfo).init(allocator);
    
    const header_block = func.blocks.items[loop_header_idx];
    
    // 遍历 header 块的 PHI 节点
    for (header_block.instructions.items) |inst| {
        if (inst.op != .phi) continue;
        
        const phi_op = inst.op.phi;
        const result_reg = inst.result orelse continue;
        
        // 检查是否是累加器模式
        if (phi_op.incoming.len != 2) continue;
        
        var init_value: ?usize = null;
        var loop_value: ?usize = null;
        
        for (phi_op.incoming) |incoming| {
            // 初始化块的值是初始值
            if (std.mem.indexOf(u8, incoming.block.label, "init") != null) {
                init_value = incoming.value.id;
            } else {
                loop_value = incoming.value.id;
            }
        }
        
        if (loop_value) |lv| {
            // 检查 loop_value 是否来自算术操作
            const is_accumulator = blk: {
                // 查找定义 loop_value 的指令
                for (func.blocks.items) |block| {
                    for (block.instructions.items) |block_inst| {
                        if (block_inst.result) |res| {
                            if (res.id == lv) {
                                // 检查是否是算术操作
                                switch (block_inst.op) {
                                    .add, .sub, .mul, .div, .mod => {
                                        break :blk true;
                                    },
                                    else => break :blk false,
                                }
                            }
                        }
                    }
                }
                break :blk false;
            };
            
            if (is_accumulator) {
                try accumulators.append(.{
                    .reg_id = result_reg.id,
                    .type_ = result_reg.type_,
                    .init_reg = init_value,
                    .from_outer = false,
                });
            }
        }
    }
    
    return accumulators;
}
