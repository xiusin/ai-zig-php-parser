const std = @import("std");
const Value = @import("types.zig").Value;
const PHPString = @import("types.zig").PHPString;
const PHPArray = @import("types.zig").PHPArray;
const PHPObject = @import("types.zig").PHPObject;
const PHPResource = @import("types.zig").PHPResource;
const UserFunction = @import("types.zig").UserFunction;
const Closure = @import("types.zig").Closure;
const ArrowFunction = @import("types.zig").ArrowFunction;

pub fn Box(comptime T: type) type {
    return struct {
        ref_count: u32,
        gc_info: GCInfo,
        data: T,
        
        pub const GCInfo = packed struct {
            color: Color = .white,
            buffered: bool = false,
            
            pub const Color = enum(u2) {
                white = 0,
                gray = 1,
                black = 2,
                purple = 3,
            };
        };
        
        pub fn retain(self: *@This()) *@This() {
            self.ref_count += 1;
            return self;
        }
        
        pub fn release(self: *@This(), allocator: std.mem.Allocator) void {
            if (self.ref_count > 0) {
                self.ref_count -= 1;
                if (self.ref_count == 0) {
                    self.destroy(allocator);
                } else {
                    // Mark as potential cycle root when ref count decreases
                    self.gc_info.color = .purple;
                }
            }
        }
        
        fn destroy(self: *@This(), allocator: std.mem.Allocator) void {
            // Call destructor if this is an object with __destruct method
            switch (T) {
                *PHPString => {
                    self.data.deinit(allocator);
                },
                *PHPArray => {
                    // Decrease reference count for all contained values
                    var iterator = self.data.elements.iterator();
                    while (iterator.next()) |entry| {
                        decrementValueRefCount(entry.value_ptr.*, allocator);
                    }
                    self.data.deinit();
                    allocator.destroy(self.data);
                },
                *PHPObject => {
                    // Call destructor if defined
                    if (self.data.class.methods.get("__destruct")) |_| {
                        // TODO: Call __destruct method
                    }
                    
                    // Decrease reference count for all properties
                    var iterator = self.data.properties.iterator();
                    while (iterator.next()) |entry| {
                        decrementValueRefCount(entry.value_ptr.*, allocator);
                    }
                    self.data.deinit();
                    allocator.destroy(self.data);
                },
                *PHPResource => {
                    self.data.destroy();
                    allocator.destroy(self.data);
                },
                *UserFunction => {
                    allocator.destroy(self.data);
                },
                *Closure => {
                    // Decrease reference count for captured variables
                    var iterator = self.data.captured_vars.iterator();
                    while (iterator.next()) |entry| {
                        decrementValueRefCount(entry.value_ptr.*, allocator);
                    }
                    self.data.deinit();
                    allocator.destroy(self.data);
                },
                *ArrowFunction => {
                    // Decrease reference count for captured variables
                    var iterator = self.data.captured_vars.iterator();
                    while (iterator.next()) |entry| {
                        decrementValueRefCount(entry.value_ptr.*, allocator);
                    }
                    self.data.deinit();
                    allocator.destroy(self.data);
                },
                else => {},
            }
            allocator.destroy(self);
        }
        
        pub fn markGray(self: *@This()) void {
            if (self.gc_info.color != .gray) {
                self.gc_info.color = .gray;
                // Mark children gray recursively
                self.markChildrenGray();
            }
        }
        
        pub fn markChildrenGray(self: *@This()) void {
            switch (T) {
                *PHPArray => {
                    var iterator = self.data.elements.iterator();
                    while (iterator.next()) |entry| {
                        markValueGray(entry.value_ptr.*);
                    }
                },
                *PHPObject => {
                    var iterator = self.data.properties.iterator();
                    while (iterator.next()) |entry| {
                        markValueGray(entry.value_ptr.*);
                    }
                },
                *Closure => {
                    var iterator = self.data.captured_vars.iterator();
                    while (iterator.next()) |entry| {
                        markValueGray(entry.value_ptr.*);
                    }
                },
                *ArrowFunction => {
                    var iterator = self.data.captured_vars.iterator();
                    while (iterator.next()) |entry| {
                        markValueGray(entry.value_ptr.*);
                    }
                },
                else => {},
            }
        }
        
        pub fn scan(self: *@This()) void {
            if (self.gc_info.color == .gray) {
                if (self.ref_count > 0) {
                    self.markBlack();
                } else {
                    self.gc_info.color = .white;
                    self.scanChildren();
                }
            }
        }
        
        pub fn scanChildren(self: *@This()) void {
            switch (T) {
                *PHPArray => {
                    var iterator = self.data.elements.iterator();
                    while (iterator.next()) |entry| {
                        scanValue(entry.value_ptr.*);
                    }
                },
                *PHPObject => {
                    var iterator = self.data.properties.iterator();
                    while (iterator.next()) |entry| {
                        scanValue(entry.value_ptr.*);
                    }
                },
                *Closure => {
                    var iterator = self.data.captured_vars.iterator();
                    while (iterator.next()) |entry| {
                        scanValue(entry.value_ptr.*);
                    }
                },
                *ArrowFunction => {
                    var iterator = self.data.captured_vars.iterator();
                    while (iterator.next()) |entry| {
                        scanValue(entry.value_ptr.*);
                    }
                },
                else => {},
            }
        }
        
        pub fn markBlack(self: *@This()) void {
            self.gc_info.color = .black;
            self.markChildrenBlack();
        }
        
        pub fn markChildrenBlack(self: *@This()) void {
            switch (T) {
                *PHPArray => {
                    var iterator = self.data.elements.iterator();
                    while (iterator.next()) |entry| {
                        markValueBlack(entry.value_ptr.*);
                    }
                },
                *PHPObject => {
                    var iterator = self.data.properties.iterator();
                    while (iterator.next()) |entry| {
                        markValueBlack(entry.value_ptr.*);
                    }
                },
                *Closure => {
                    var iterator = self.data.captured_vars.iterator();
                    while (iterator.next()) |entry| {
                        markValueBlack(entry.value_ptr.*);
                    }
                },
                *ArrowFunction => {
                    var iterator = self.data.captured_vars.iterator();
                    while (iterator.next()) |entry| {
                        markValueBlack(entry.value_ptr.*);
                    }
                },
                else => {},
            }
        }
        
        pub fn collectWhite(self: *@This(), allocator: std.mem.Allocator) void {
            if (self.gc_info.color == .white and !self.gc_info.buffered) {
                self.gc_info.color = .black; // Prevent double collection
                self.collectChildrenWhite(allocator);
                self.destroy(allocator);
            }
        }
        
        pub fn collectChildrenWhite(self: *@This(), allocator: std.mem.Allocator) void {
            switch (T) {
                *PHPArray => {
                    var iterator = self.data.elements.iterator();
                    while (iterator.next()) |entry| {
                        collectValueWhite(entry.value_ptr.*, allocator);
                    }
                },
                *PHPObject => {
                    var iterator = self.data.properties.iterator();
                    while (iterator.next()) |entry| {
                        collectValueWhite(entry.value_ptr.*, allocator);
                    }
                },
                *Closure => {
                    var iterator = self.data.captured_vars.iterator();
                    while (iterator.next()) |entry| {
                        collectValueWhite(entry.value_ptr.*, allocator);
                    }
                },
                *ArrowFunction => {
                    var iterator = self.data.captured_vars.iterator();
                    while (iterator.next()) |entry| {
                        collectValueWhite(entry.value_ptr.*, allocator);
                    }
                },
                else => {},
            }
        }
    };
}

// Helper functions for cycle detection algorithm
fn decrementValueRefCount(value: Value, allocator: std.mem.Allocator) void {
    switch (value.tag) {
        .string => value.data.string.release(allocator),
        .array => value.data.array.release(allocator),
        .object => value.data.object.release(allocator),
        .resource => value.data.resource.release(allocator),
        .user_function => value.data.user_function.release(allocator),
        .closure => value.data.closure.release(allocator),
        .arrow_function => value.data.arrow_function.release(allocator),
        else => {},
    }
}

fn markValueGray(value: Value) void {
    switch (value.tag) {
        .string => value.data.string.markGray(),
        .array => value.data.array.markGray(),
        .object => value.data.object.markGray(),
        .resource => value.data.resource.markGray(),
        .user_function => value.data.user_function.markGray(),
        .closure => value.data.closure.markGray(),
        .arrow_function => value.data.arrow_function.markGray(),
        else => {},
    }
}

fn scanValue(value: Value) void {
    switch (value.tag) {
        .string => value.data.string.scan(),
        .array => value.data.array.scan(),
        .object => value.data.object.scan(),
        .resource => value.data.resource.scan(),
        .user_function => value.data.user_function.scan(),
        .closure => value.data.closure.scan(),
        .arrow_function => value.data.arrow_function.scan(),
        else => {},
    }
}

fn markValueBlack(value: Value) void {
    switch (value.tag) {
        .string => value.data.string.markBlack(),
        .array => value.data.array.markBlack(),
        .object => value.data.object.markBlack(),
        .resource => value.data.resource.markBlack(),
        .user_function => value.data.user_function.markBlack(),
        .closure => value.data.closure.markBlack(),
        .arrow_function => value.data.arrow_function.markBlack(),
        else => {},
    }
}

fn collectValueWhite(value: Value, allocator: std.mem.Allocator) void {
    switch (value.tag) {
        .string => value.data.string.collectWhite(allocator),
        .array => value.data.array.collectWhite(allocator),
        .object => value.data.object.collectWhite(allocator),
        .resource => value.data.resource.collectWhite(allocator),
        .user_function => value.data.user_function.collectWhite(allocator),
        .closure => value.data.closure.collectWhite(allocator),
        .arrow_function => value.data.arrow_function.collectWhite(allocator),
        else => {},
    }
}

pub const GarbageCollector = struct {
    allocator: std.mem.Allocator,
    memory_threshold: usize,
    allocated_memory: usize,
    
    pub fn init(allocator: std.mem.Allocator, memory_threshold: usize) !GarbageCollector {
        return GarbageCollector{
            .allocator = allocator,
            .memory_threshold = memory_threshold,
            .allocated_memory = 0,
        };
    }
    
    pub fn deinit(self: *GarbageCollector) void {
        _ = self;
    }
    
    pub fn collect(self: *GarbageCollector) u32 {
        // Simplified collection for now
        _ = self;
        return 0;
    }
    
    pub fn addRoot(self: *GarbageCollector, root: *anyopaque) !void {
        _ = self;
        _ = root;
    }
    
    pub fn removeRoot(self: *GarbageCollector, root: *anyopaque) void {
        _ = self;
        _ = root;
    }
    
    pub fn shouldCollect(self: *GarbageCollector) bool {
        return self.allocated_memory >= self.memory_threshold;
    }
    
    pub fn trackAllocation(self: *GarbageCollector, size: usize) void {
        self.allocated_memory += size;
    }
    
    pub fn trackDeallocation(self: *GarbageCollector, size: usize) void {
        if (self.allocated_memory >= size) {
            self.allocated_memory -= size;
        } else {
            self.allocated_memory = 0;
        }
    }
};

pub const Header = struct {
    ref_count: u32,
};

pub fn incRef(comptime T: type) fn (ptr: T) void {
    return struct {
        fn anon(ptr: T) void {
            ptr.ref_count += 1;
        }
    }.anon;
}

pub fn decRef(mm: *MemoryManager, val: Value) void {
    switch (val.tag) {
        .string => {
            val.data.string.release(mm.allocator);
        },
        .array => {
            val.data.array.release(mm.allocator);
        },
        .object => {
            val.data.object.release(mm.allocator);
        },
        .resource => {
            val.data.resource.release(mm.allocator);
        },
        .user_function => {
            val.data.user_function.release(mm.allocator);
        },
        .closure => {
            val.data.closure.release(mm.allocator);
        },
        .arrow_function => {
            val.data.arrow_function.release(mm.allocator);
        },
        else => {},
    }
}

pub const MemoryManager = struct {
    allocator: std.mem.Allocator,
    gc: GarbageCollector,
    
    pub fn init(allocator: std.mem.Allocator) !MemoryManager {
        const default_threshold = 1024 * 1024; // 1MB default threshold
        return MemoryManager{
            .allocator = allocator,
            .gc = try GarbageCollector.init(allocator, default_threshold),
        };
    }
    
    pub fn initWithThreshold(allocator: std.mem.Allocator, memory_threshold: usize) !MemoryManager {
        return MemoryManager{
            .allocator = allocator,
            .gc = try GarbageCollector.init(allocator, memory_threshold),
        };
    }

    pub fn deinit(self: *MemoryManager) void {
        self.gc.deinit();
    }

    pub fn allocString(self: *MemoryManager, data: []const u8) !*Box(*PHPString) {
        const php_string = try PHPString.init(self.allocator, data);
        const box = try self.allocator.create(Box(*PHPString));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = php_string,
        };
        
        // Track allocation and trigger GC if needed
        self.gc.trackAllocation(@sizeOf(Box(*PHPString)) + data.len);
        if (self.gc.shouldCollect()) {
            _ = self.gc.collect();
        }
        
        return box;
    }

    pub fn allocArray(self: *MemoryManager) !*Box(*PHPArray) {
        const php_array = try self.allocator.create(PHPArray);
        php_array.* = PHPArray.init(self.allocator);
        const box = try self.allocator.create(Box(*PHPArray));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = php_array,
        };
        
        // Track allocation and trigger GC if needed
        self.gc.trackAllocation(@sizeOf(Box(*PHPArray)) + @sizeOf(PHPArray));
        if (self.gc.shouldCollect()) {
            _ = self.gc.collect();
        }
        
        return box;
    }
    
    pub fn allocObject(self: *MemoryManager, class: *@import("types.zig").PHPClass) !*Box(*PHPObject) {
        const php_object = try self.allocator.create(PHPObject);
        php_object.* = PHPObject.init(self.allocator, class);
        const box = try self.allocator.create(Box(*PHPObject));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = php_object,
        };
        
        // Track allocation and trigger GC if needed
        self.gc.trackAllocation(@sizeOf(Box(*PHPObject)) + @sizeOf(PHPObject));
        if (self.gc.shouldCollect()) {
            _ = self.gc.collect();
        }
        
        return box;
    }
    
    pub fn allocResource(self: *MemoryManager, resource: PHPResource) !*Box(*PHPResource) {
        const php_resource = try self.allocator.create(PHPResource);
        php_resource.* = resource;
        const box = try self.allocator.create(Box(*PHPResource));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = php_resource,
        };
        
        // Track allocation and trigger GC if needed
        self.gc.trackAllocation(@sizeOf(Box(*PHPResource)) + @sizeOf(PHPResource));
        if (self.gc.shouldCollect()) {
            _ = self.gc.collect();
        }
        
        return box;
    }
    
    pub fn allocUserFunction(self: *MemoryManager, function: UserFunction) !*Box(*UserFunction) {
        const user_function = try self.allocator.create(UserFunction);
        user_function.* = function;
        const box = try self.allocator.create(Box(*UserFunction));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = user_function,
        };
        
        // Track allocation and trigger GC if needed
        self.gc.trackAllocation(@sizeOf(Box(*UserFunction)) + @sizeOf(UserFunction));
        if (self.gc.shouldCollect()) {
            _ = self.gc.collect();
        }
        
        return box;
    }
    
    pub fn allocClosure(self: *MemoryManager, closure: Closure) !*Box(*Closure) {
        const closure_ptr = try self.allocator.create(Closure);
        closure_ptr.* = closure;
        const box = try self.allocator.create(Box(*Closure));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = closure_ptr,
        };
        
        // Track allocation and trigger GC if needed
        self.gc.trackAllocation(@sizeOf(Box(*Closure)) + @sizeOf(Closure));
        if (self.gc.shouldCollect()) {
            _ = self.gc.collect();
        }
        
        return box;
    }
    
    pub fn allocArrowFunction(self: *MemoryManager, arrow_function: ArrowFunction) !*Box(*ArrowFunction) {
        const arrow_function_ptr = try self.allocator.create(ArrowFunction);
        arrow_function_ptr.* = arrow_function;
        const box = try self.allocator.create(Box(*ArrowFunction));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = arrow_function_ptr,
        };
        
        // Track allocation and trigger GC if needed
        self.gc.trackAllocation(@sizeOf(Box(*ArrowFunction)) + @sizeOf(ArrowFunction));
        if (self.gc.shouldCollect()) {
            _ = self.gc.collect();
        }
        
        return box;
    }
    
    pub fn collect(self: *MemoryManager) u32 {
        return self.gc.collect();
    }
    
    pub fn addRoot(self: *MemoryManager, root: *anyopaque) !void {
        try self.gc.addRoot(root);
    }
    
    pub fn removeRoot(self: *MemoryManager, root: *anyopaque) void {
        self.gc.removeRoot(root);
    }
    
    pub fn forceCollect(self: *MemoryManager) u32 {
        return self.gc.collect();
    }
    
    pub fn getMemoryUsage(self: *MemoryManager) usize {
        return self.gc.allocated_memory;
    }
    
    pub fn setMemoryThreshold(self: *MemoryManager, threshold: usize) void {
        self.gc.memory_threshold = threshold;
    }
};

// Global function to manually trigger garbage collection (gc_collect_cycles equivalent)
pub fn collectCycles(mm: *MemoryManager) u32 {
    return mm.forceCollect();
}