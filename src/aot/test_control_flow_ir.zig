const std = @import("std");
const testing = std.testing;
const compiler = @import("compiler");
const root = compiler.root;
const IRGenerator = @import("ir_generator.zig").IRGenerator;
const SymbolTable = @import("symbol_table.zig").SymbolTable;
const DiagnosticEngine = @import("diagnostics.zig").DiagnosticEngine;
const TypeInferencer = @import("type_inference.zig").TypeInferencer;
const IR = @import("ir.zig");
const IROptimizer = @import("optimizer.zig").IROptimizer;
const PassConfig = @import("optimizer.zig").PassConfig;

// Helper to compile PHP source to IR
const TestContext = struct {
    arena_ptr: *std.heap.ArenaAllocator,
    allocator: std.mem.Allocator,
    php_ctx: *root.PHPContext, // Allocate on arena
    st_ptr: *SymbolTable,
    diag_ptr: *DiagnosticEngine,
    ti_ptr: *TypeInferencer,
    gen_ptr: *IRGenerator,
    module: ?*IR.Module,

    pub fn init(child_allocator: std.mem.Allocator) !TestContext {
        const arena_ptr = try child_allocator.create(std.heap.ArenaAllocator);
        arena_ptr.* = std.heap.ArenaAllocator.init(child_allocator);
        const allocator = arena_ptr.allocator();

        // Allocate everything in arena
        const ctx_ptr = try allocator.create(root.PHPContext);
        ctx_ptr.* = root.PHPContext.init(allocator);

        const st_ptr = try allocator.create(SymbolTable);
        st_ptr.* = try SymbolTable.init(allocator);
        
        const diag_ptr = try allocator.create(DiagnosticEngine);
        diag_ptr.* = DiagnosticEngine.init(allocator);
        
        const ti_ptr = try allocator.create(TypeInferencer);
        ti_ptr.* = TypeInferencer.init(allocator, st_ptr, diag_ptr);
        
        const gen_ptr = try allocator.create(IRGenerator);
        gen_ptr.* = IRGenerator.init(allocator, st_ptr, ti_ptr, diag_ptr);

        return TestContext{
            .arena_ptr = arena_ptr,
            .allocator = allocator,
            .php_ctx = ctx_ptr,
            .st_ptr = st_ptr,
            .diag_ptr = diag_ptr,
            .ti_ptr = ti_ptr,
            .gen_ptr = gen_ptr,
            .module = null,
        };
    }

    pub fn deinit(self: *TestContext) void {
        const child_alloc = self.arena_ptr.child_allocator;
        self.arena_ptr.deinit();
        child_alloc.destroy(self.arena_ptr);
    }

    pub fn compile(self: *TestContext, source: [:0]const u8) !*IR.Module {
        const root_idx = try self.php_ctx.parseSource(source);
        const keys = self.php_ctx.string_pool.keys();
        
        self.module = try self.gen_ptr.generateFromRoot(
            self.php_ctx.nodes.items,
            keys,
            source,
            root_idx,
            "test_module",
            "test.php"
        );
        return self.module.?;
    }
};

test "IRGenerator: If-Else Control Flow" {
    const allocator = std.testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const source = 
        \\<?php
        \\$cond = true;
        \\if ($cond) {
        \\    $x = 10;
        \\} else {
        \\    $x = 20;
        \\}
        \\$y = $x;
        \\return $y;
    ;

    const module = try ctx.compile(source);
    
    // Verify CFG structure
    const func = module.functions.items[0]; // Main function
    
    try std.testing.expect(func.blocks.items.len >= 4);
    
    // Check for cond_br in one of the blocks
    var found_cond_br = false;
    for (func.blocks.items) |block| {
        if (block.terminator) |term| {
            switch (term) {
                .cond_br => found_cond_br = true,
                else => {},
            }
        }
    }
    try std.testing.expect(found_cond_br);
    
    // Check for PHI nodes (currently disabled/not implemented)
    var found_phi = false;
    for (func.blocks.items) |block| {
        for (block.instructions.items) |inst| {
            if (inst.op == .phi) {
                found_phi = true;
            }
        }
    }
    
    if (!found_phi) {
        // PHI nodes not found. Mem2Reg pass required for SSA.
    }
}

test "IRGenerator: While Loop Control Flow" {
    const allocator = std.testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const source = 
        \\<?php
        \\$i = 0;
        \\while ($i < 10) {
        \\    $i = $i + 1;
        \\}
        \\$y = $i;
    ;

    const module = try ctx.compile(source);
    const func = module.functions.items[0];
    
    try std.testing.expect(func.blocks.items.len >= 3);
    
    var found_cond_br = false;
    var found_br = false;
    
    for (func.blocks.items) |block| {
        if (block.terminator) |term| {
            switch (term) {
                .cond_br => found_cond_br = true,
                .br => found_br = true,
                else => {},
            }
        }
    }
    
    try std.testing.expect(found_cond_br);
    try std.testing.expect(found_br);
}

test "Optimizer: Mem2Reg on If-Else" {
    const allocator = std.testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const source = 
        \\<?php
        \\function test_func($cond) {
        \\    if ($cond) {
        \\        $x = 10;
        \\    } else {
        \\        $x = 20;
        \\    }
        \\    $y = $x; 
        \\    return $y;
        \\}
    ;

    const module = try ctx.compile(source);
    
    // Run optimizer
    var config = PassConfig.releaseSafe();
    config.mem2reg = true;
    config.constant_propagation = false;
    config.sccp = false;
    config.cfg_cleanup = false;
    
    // Use ctx.allocator (Arena) so that we can mix new instructions with old ones
    // and destroy calls will be no-ops (safe for Arena)
    var optimizer = IROptimizer.initWithConfig(ctx.allocator, config, null);
    defer optimizer.deinit();
    
    // Debug: Print IR
    var list = std.ArrayListUnmanaged(u8){};
    defer list.deinit(allocator);
    // var printer = IR.IRPrinter.initUnmanaged(&list, allocator);
    
    // try printer.printModule(module);
    // std.debug.print("--- BEFORE ---\n{s}\n", .{list.items});
    list.clearRetainingCapacity();
    
    try optimizer.optimize(module);
    
    // try printer.printModule(module);
    // std.debug.print("--- AFTER ---\n{s}\n", .{list.items});
    
    // Find test_func (not __main__)
    var func: ?*IR.Function = null;
    for (module.functions.items) |f| {
        if (std.mem.eql(u8, f.name, "test_func")) {
            func = f;
            break;
        }
    }
    
    try std.testing.expect(func != null);
    
    // Check for Phi nodes
    // The variable $x should be converted to a Phi node in the merge block
    var found_phi = false;
    for (func.?.blocks.items) |block| {
        for (block.instructions.items) |inst| {
            if (inst.op == .phi) {
                found_phi = true;
                // Verify phi has 2 incoming values
                try std.testing.expectEqual(@as(usize, 2), inst.op.phi.incoming.len);
            }
        }
    }
    
    try std.testing.expect(found_phi);
}
