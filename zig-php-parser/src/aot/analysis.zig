//! Analysis passes for AOT Compiler IR
//!
//! This module implements control flow analysis algorithms:
//! - Dominator Tree construction
//! - Dominance Frontier calculation
//! - Reverse Post-Order (RPO) traversal

const std = @import("std");
const Allocator = std.mem.Allocator;
const IR = @import("ir.zig");
const BasicBlock = IR.BasicBlock;
const Function = IR.Function;
const Terminator = IR.Terminator;

/// Dominator Tree information
pub const DominatorTree = struct {
    allocator: Allocator,
    /// Immediate dominator for each block (indexed by block.index)
    idoms: []?*BasicBlock,
    /// Dominance frontier for each block (indexed by block.index)
    frontiers: []std.ArrayListUnmanaged(*BasicBlock),
    /// Children in dominator tree (indexed by block.index)
    children: []std.ArrayListUnmanaged(*BasicBlock),
    /// Depth in dominator tree (indexed by block.index)
    levels: []u32,

    const Self = @This();

    /// Initialize empty dominator tree
    fn init(allocator: Allocator, size: usize) !Self {
        const idoms = try allocator.alloc(?*BasicBlock, size);
        @memset(idoms, null);

        const frontiers = try allocator.alloc(std.ArrayListUnmanaged(*BasicBlock), size);
        @memset(frontiers, .{});

        const children = try allocator.alloc(std.ArrayListUnmanaged(*BasicBlock), size);
        @memset(children, .{});

        const levels = try allocator.alloc(u32, size);
        @memset(levels, 0);

        return .{
            .allocator = allocator,
            .idoms = idoms,
            .frontiers = frontiers,
            .children = children,
            .levels = levels,
        };
    }

    /// Deinitialize and free resources
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.idoms);
        
        for (self.frontiers) |*list| {
            list.deinit(self.allocator);
        }
        self.allocator.free(self.frontiers);

        for (self.children) |*list| {
            list.deinit(self.allocator);
        }
        self.allocator.free(self.children);
        
        self.allocator.free(self.levels);
    }

    /// Check if block `a` dominates block `b`
    pub fn dominates(self: *const Self, a: *BasicBlock, b: *BasicBlock) bool {
        if (a == b) return true;
        
        // If a is deeper than b, it cannot dominate b
        if (self.levels[a.index] >= self.levels[b.index]) return false;

        // Walk up from b
        var current = b;
        while (self.idoms[current.index]) |idom| {
            if (idom == a) return true;
            if (self.levels[idom.index] < self.levels[a.index]) return false;
            current = idom;
        }
        
        return false;
    }

    /// Check if block `a` strictly dominates block `b`
    pub fn strictlyDominates(self: *const Self, a: *BasicBlock, b: *BasicBlock) bool {
        return a != b and self.dominates(a, b);
    }
};

/// Compute Dominator Tree and Dominance Frontiers for a function
pub fn computeDominators(allocator: Allocator, func: *const Function) !DominatorTree {
    const num_blocks = func.blocks.items.len;
    var dt = try DominatorTree.init(allocator, num_blocks);
    errdefer dt.deinit();

    if (num_blocks == 0) return dt;

    const entry_block = func.blocks.items[0];
    
    // 1. Compute Reverse Post-Order (RPO)
    var rpo = try std.ArrayListUnmanaged(*BasicBlock).initCapacity(allocator, num_blocks);
    defer rpo.deinit(allocator);
    
    var visited = try std.DynamicBitSet.initEmpty(allocator, num_blocks);
    defer visited.deinit();
    
    try computeRPO(allocator, entry_block, &rpo, &visited);
    
    // We need to reverse the result of post-order traversal to get RPO
    std.mem.reverse(*BasicBlock, rpo.items);
    
    // Create map from block to RPO index for fast comparison
    var rpo_indices = try allocator.alloc(usize, num_blocks);
    defer allocator.free(rpo_indices);
    
    for (rpo.items, 0..) |block, i| {
        rpo_indices[block.index] = i;
    }

    // 2. Compute Immediate Dominators (Iterative Algorithm)
    dt.idoms[entry_block.index] = entry_block;
    
    var changed = true;
    while (changed) {
        changed = false;
        
        // Iterate all blocks in RPO, except start node
        for (rpo.items) |block| {
            if (block == entry_block) continue;
            
            var new_idom: ?*BasicBlock = null;
            
            // Find first processed predecessor
            for (block.predecessors.items) |pred| {
                if (dt.idoms[pred.index] != null) {
                    new_idom = pred;
                    break;
                }
            }
            
            if (new_idom) |first_processed| {
                var temp_idom = first_processed;
                
                // Intersect with other processed predecessors
                for (block.predecessors.items) |pred| {
                    if (pred != temp_idom and dt.idoms[pred.index] != null) {
                        temp_idom = intersect(temp_idom, pred, dt.idoms, rpo_indices);
                    }
                }
                
                if (dt.idoms[block.index] != temp_idom) {
                    dt.idoms[block.index] = temp_idom;
                    changed = true;
                }
            }
        }
    }
    
    // Correct entry block's idom to be null (it has no dominator)
    dt.idoms[entry_block.index] = null;

    // 3. Build Dominator Tree Children and Levels
    for (func.blocks.items) |block| {
        if (block == entry_block) {
            dt.levels[block.index] = 0;
            continue;
        }
        
        if (dt.idoms[block.index]) |idom| {
            try dt.children[idom.index].append(allocator, block);
            // We'll compute levels in a separate pass or just assume valid order
            // Since we iterate array order, parents might not be processed.
            // But we can do a BFS/DFS on the tree later.
        }
    }
    
    // Compute levels using BFS on the dominator tree
    var queue = std.ArrayListUnmanaged(*BasicBlock){};
    defer queue.deinit(allocator);
    
    try queue.append(allocator, entry_block);
    dt.levels[entry_block.index] = 0;
    
    var head: usize = 0;
    while (head < queue.items.len) {
        const current = queue.items[head];
        head += 1;
        
        const current_level = dt.levels[current.index];
        for (dt.children[current.index].items) |child| {
            dt.levels[child.index] = current_level + 1;
            try queue.append(allocator, child);
        }
    }

    // 4. Compute Dominance Frontiers
    for (func.blocks.items) |block| {
        if (block.predecessors.items.len >= 2) {
            for (block.predecessors.items) |pred| {
                var runner = pred;
                while (runner != dt.idoms[block.index]) {
                    // Add block to runner's frontier
                    // Avoid duplicates
                    var found = false;
                    for (dt.frontiers[runner.index].items) |f| {
                        if (f == block) {
                            found = true;
                            break;
                        }
                    }
                    if (!found) {
                        try dt.frontiers[runner.index].append(allocator, block);
                    }
                    
                    if (dt.idoms[runner.index]) |next_runner| {
                        runner = next_runner;
                    } else {
                        break; // Should not happen if CFG is valid and connected
                    }
                }
            }
        }
    }

    return dt;
}

/// Helper for RPO traversal (actually computes Post-Order)
fn computeRPO(allocator: Allocator, block: *BasicBlock, list: *std.ArrayListUnmanaged(*BasicBlock), visited: *std.DynamicBitSet) !void {
    visited.set(block.index);
    
    for (block.successors.items) |succ| {
        if (!visited.isSet(succ.index)) {
            try computeRPO(allocator, succ, list, visited);
        }
    }
    
    try list.append(allocator, block);
}

/// Find nearest common dominator
fn intersect(b1: *BasicBlock, b2: *BasicBlock, idoms: []?*BasicBlock, rpo_indices: []usize) *BasicBlock {
    var finger1 = b1;
    var finger2 = b2;
    
    while (finger1 != finger2) {
        while (rpo_indices[finger1.index] > rpo_indices[finger2.index]) {
            if (idoms[finger1.index]) |next| {
                finger1 = next;
            } else {
                return finger2; // Should not happen
            }
        }
        while (rpo_indices[finger2.index] > rpo_indices[finger1.index]) {
            if (idoms[finger2.index]) |next| {
                finger2 = next;
            } else {
                return finger1; // Should not happen
            }
        }
    }
    
    return finger1;
}

/// Rebuild CFG edges based on terminators
pub fn rebuildCFG(func: *Function) !void {
    // Reassign indices to ensure they are compact and match array order
    // This is crucial if blocks were removed (e.g. by DCE)
    for (func.blocks.items, 0..) |block, i| {
        block.index = @intCast(i);
    }

    // Clear existing edges
    for (func.blocks.items) |block| {
        block.predecessors.clearRetainingCapacity();
        block.successors.clearRetainingCapacity();
    }

    // Build edges
    for (func.blocks.items) |block| {
        if (block.terminator) |term| {
            switch (term) {
                .br => |target| try addEdge(block, target),
                .cond_br => |cb| {
                    try addEdge(block, cb.then_block);
                    try addEdge(block, cb.else_block);
                },
                .switch_ => |sw| {
                    for (sw.cases) |case| {
                        try addEdge(block, case.block);
                    }
                    try addEdge(block, sw.default);
                },
                else => {},
            }
        }
    }
}

fn addEdge(from: *BasicBlock, to: *BasicBlock) !void {
    try from.addSuccessor(to);
    try to.addPredecessor(from);
}

// ============================================================================
// Loop Analysis
// ============================================================================

/// Loop information
pub const Loop = struct {
    /// Loop header (entry point)
    header: *BasicBlock,
    /// Blocks contained in the loop
    blocks: std.ArrayListUnmanaged(*BasicBlock),
    /// Sub-loops nested within this loop
    sub_loops: std.ArrayListUnmanaged(*Loop),
    /// Parent loop (null for top-level loops)
    parent: ?*Loop,

    const Self = @This();

    pub fn init(allocator: Allocator, header: *BasicBlock) Self {
        _ = allocator;
        return .{
            .header = header,
            .blocks = .{},
            .sub_loops = .{},
            .parent = null,
        };
    }

    pub fn deinit(self: *Self, allocator: Allocator) void {
        self.blocks.deinit(allocator);
        for (self.sub_loops.items) |sub_loop| {
            sub_loop.deinit(allocator);
            allocator.destroy(sub_loop);
        }
        self.sub_loops.deinit(allocator);
    }

    /// Check if block is in this loop
    pub fn contains(self: *const Self, block: *BasicBlock) bool {
        for (self.blocks.items) |b| {
            if (b == block) return true;
        }
        return false;
    }
};

/// Result of loop analysis
pub const LoopInfo = struct {
    allocator: Allocator,
    /// Top-level loops
    loops: std.ArrayListUnmanaged(*Loop),
    /// Map from header block to Loop
    loop_map: std.AutoHashMap(*BasicBlock, *Loop),

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return .{
            .allocator = allocator,
            .loops = .{},
            .loop_map = std.AutoHashMap(*BasicBlock, *Loop).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.loops.items) |loop| {
            loop.deinit(self.allocator);
            self.allocator.destroy(loop);
        }
        self.loops.deinit(self.allocator);
        self.loop_map.deinit();
    }
};

/// Compute loop information for a function
pub fn computeLoops(allocator: Allocator, func: *const Function, dt: *const DominatorTree) !LoopInfo {
    var info = LoopInfo.init(allocator);
    errdefer info.deinit();

    // 1. Identify back edges
    for (func.blocks.items) |block| {
        for (block.successors.items) |succ| {
            // Check if successor dominates predecessor (back edge)
            if (dt.dominates(succ, block)) {
                // Found loop header `succ` and back edge `block -> succ`
                
                // Get or create loop for this header
                var loop_ptr: *Loop = undefined;
                if (info.loop_map.get(succ)) |existing| {
                    loop_ptr = existing;
                } else {
                    const new_loop = try allocator.create(Loop);
                    new_loop.* = Loop.init(allocator, succ);
                    try info.loop_map.put(succ, new_loop);
                    // We'll organize hierarchy later, initially treat all as top-level or collect them
                    // For now, let's just track unique headers
                    loop_ptr = new_loop;
                }

                // Add nodes to loop
                // The natural loop of a back edge A->B consists of B plus
                // the set of nodes that can reach A without going through B.
                try addLoopBlocks(allocator, loop_ptr, block, succ);
            }
        }
    }

    // 2. Build loop hierarchy (nesting)
    // If loop A's header is in loop B, then A is nested in B (unless they share header)
    // If they share header, they are merged or one is part of another. 
    // In our logic above, one header = one loop struct.
    // So we just check if loop A's header is contained in loop B's blocks.
    
    // We need to iterate carefully. Let's collect all loops first.
    var all_loops = std.ArrayListUnmanaged(*Loop){};
    defer all_loops.deinit(allocator);
    
    var it = info.loop_map.iterator();
    while (it.next()) |entry| {
        try all_loops.append(allocator, entry.value_ptr.*);
    }

    // Sort loops by size (number of blocks) - usually inner loops are smaller?
    // Or just strictly check containment.
    
    for (all_loops.items) |loop| {
        var parent_candidate: ?*Loop = null;
        
        // Find the "nearest" enclosing loop
        // A loop L1 is nested in L2 if L1.header is in L2.blocks AND L1.header != L2.header
        
        for (all_loops.items) |potential_parent| {
            if (loop == potential_parent) continue;
            
            if (potential_parent.contains(loop.header)) {
                // Found a container. Is it the tightest one?
                // If we already have a parent, check if potential_parent is nested in current parent
                if (parent_candidate) |curr_parent| {
                    if (curr_parent.contains(potential_parent.header)) {
                        // potential_parent is tighter (nested inside curr_parent)
                        parent_candidate = potential_parent;
                    }
                } else {
                    parent_candidate = potential_parent;
                }
            }
        }
        
        if (parent_candidate) |parent| {
            loop.parent = parent;
            try parent.sub_loops.append(allocator, loop);
        } else {
            // Top-level loop
            try info.loops.append(allocator, loop);
        }
    }

    return info;
}

/// Helper to add blocks to a loop (Reverse DFS from back-edge source)
fn addLoopBlocks(allocator: Allocator, loop: *Loop, back_edge_source: *BasicBlock, header: *BasicBlock) !void {
    // If header is not in loop yet, add it
    if (!loop.contains(header)) {
        try loop.blocks.append(allocator, header);
    }
    
    // If back_edge_source is header (self-loop), we are done
    if (back_edge_source == header) return;

    // Worklist for reverse traversal
    var worklist = std.ArrayListUnmanaged(*BasicBlock){};
    defer worklist.deinit(allocator);

    try worklist.append(allocator, back_edge_source);
    if (!loop.contains(back_edge_source)) {
        try loop.blocks.append(allocator, back_edge_source);
    }

    while (worklist.items.len > 0) {
        const block = worklist.pop().?;
        for (block.predecessors.items) |pred| {
            if (pred == header) continue; // Don't go past header
            
            if (!loop.contains(pred)) {
                try loop.blocks.append(allocator, pred);
                try worklist.append(allocator, pred);
            }
        }
    }
}

