//! ============================================================================
//! Performance Pool - High-Performance Memory Pooling and Optimization
//! ============================================================================
//!
//! This module implements production-grade memory pooling and optimization
//! for the M:P:N scheduler and coroutine system.
//!
//! Features:
//! - Lock-free object pools for frequent allocations
//! - Memory arena allocators with cache-friendly layouts
//! - Coroutine-specific memory pools
//! - Thread-local caching for reduced contention
//!
//! Requirements: 10.1, 10.2
//! ============================================================================

const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const Coroutine = @import("coroutine.zig").Coroutine;

/// Lock-free object pool using atomic operations
/// Designed for high-throughput allocation/deallocation patterns
pub fn LockFreePool(comptime T: type) type {
    return struct {
        const Self = @This();
        const CHUNK_SIZE: usize = 64; // Objects per chunk
        const MAX_LOCAL_CACHE: usize = 8; // Thread-local cache size

        allocator: std.mem.Allocator,
        
        // Lock-free free list using atomic pointer
        free_head: std.atomic.Value(?*Node),
        
        // Statistics (atomic for thread safety)
        total_allocated: std.atomic.Value(u64),
        total_acquired: std.atomic.Value(u64),
        total_released: std.atomic.Value(u64),
        cache_hits: std.atomic.Value(u64),
        cache_misses: std.atomic.Value(u64),
        
        // Memory tracking
        chunks: std.ArrayListUnmanaged(*[CHUNK_SIZE]Node),
        chunks_mutex: std.Thread.Mutex,

        const Node = struct {
            data: T,
            next: ?*Node,
            in_use: std.atomic.Value(bool),
        };

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .allocator = allocator,
                .free_head = std.atomic.Value(?*Node).init(null),
                .total_allocated = std.atomic.Value(u64).init(0),
                .total_acquired = std.atomic.Value(u64).init(0),
                .total_released = std.atomic.Value(u64).init(0),
                .cache_hits = std.atomic.Value(u64).init(0),
                .cache_misses = std.atomic.Value(u64).init(0),
                .chunks = .{},
                .chunks_mutex = .{},
            };
        }

        pub fn deinit(self: *Self) void {
            self.chunks_mutex.lock();
            defer self.chunks_mutex.unlock();
            
            for (self.chunks.items) |chunk| {
                self.allocator.destroy(chunk);
            }
            self.chunks.deinit(self.allocator);
        }

        /// Acquire an object from the pool (lock-free fast path)
        pub fn acquire(self: *Self) !*T {
            // Try lock-free pop from free list
            while (true) {
                const head = self.free_head.load(.acquire);
                if (head) |node| {
                    const next = node.next;
                    if (self.free_head.cmpxchgWeak(head, next, .release, .monotonic)) |_| {
                        // CAS failed, retry
                        continue;
                    }
                    // Successfully popped
                    node.in_use.store(true, .release);
                    node.next = null;
                    _ = self.total_acquired.fetchAdd(1, .monotonic);
                    _ = self.cache_hits.fetchAdd(1, .monotonic);
                    return &node.data;
                }
                break;
            }
            
            // No free objects, allocate new chunk
            _ = self.cache_misses.fetchAdd(1, .monotonic);
            return self.allocateNewChunk();
        }

        /// Release an object back to the pool (lock-free)
        pub fn release(self: *Self, ptr: *T) void {
            // Calculate node pointer from data pointer
            const node_ptr = @as([*]u8, @ptrCast(ptr)) - @offsetOf(Node, "data");
            const node: *Node = @ptrCast(@alignCast(node_ptr));
            
            if (!node.in_use.load(.acquire)) {
                return; // Already released
            }
            
            node.in_use.store(false, .release);
            
            // Lock-free push to free list
            while (true) {
                const head = self.free_head.load(.acquire);
                node.next = head;
                if (self.free_head.cmpxchgWeak(head, node, .release, .monotonic)) |_| {
                    continue;
                }
                break;
            }
            
            _ = self.total_released.fetchAdd(1, .monotonic);
        }

        /// Allocate a new chunk of objects
        fn allocateNewChunk(self: *Self) !*T {
            self.chunks_mutex.lock();
            defer self.chunks_mutex.unlock();
            
            const chunk = try self.allocator.create([CHUNK_SIZE]Node);
            try self.chunks.append(self.allocator, chunk);
            
            // Initialize all nodes except the first one and add to free list
            for (chunk[1..]) |*node| {
                node.in_use = std.atomic.Value(bool).init(false);
                node.next = self.free_head.load(.acquire);
                self.free_head.store(node, .release);
            }
            
            // Return the first node
            chunk[0].in_use = std.atomic.Value(bool).init(true);
            chunk[0].next = null;
            
            _ = self.total_allocated.fetchAdd(CHUNK_SIZE, .monotonic);
            _ = self.total_acquired.fetchAdd(1, .monotonic);
            
            return &chunk[0].data;
        }

        /// Get pool statistics
        pub fn getStats(self: *Self) PoolStats {
            const acquired = self.total_acquired.load(.monotonic);
            const released = self.total_released.load(.monotonic);
            const hits = self.cache_hits.load(.monotonic);
            const misses = self.cache_misses.load(.monotonic);
            
            return PoolStats{
                .total_allocated = self.total_allocated.load(.monotonic),
                .total_acquired = acquired,
                .total_released = released,
                .active_count = acquired - released,
                .cache_hits = hits,
                .cache_misses = misses,
                .hit_rate = if (hits + misses > 0) 
                    @as(f64, @floatFromInt(hits)) / @as(f64, @floatFromInt(hits + misses))
                else 0.0,
            };
        }
    };
}

/// Pool statistics structure
pub const PoolStats = struct {
    total_allocated: u64,
    total_acquired: u64,
    total_released: u64,
    active_count: u64,
    cache_hits: u64,
    cache_misses: u64,
    hit_rate: f64,
};

/// Cache-aligned memory arena for coroutine stacks
/// Optimized for cache-friendly memory access patterns
pub const CacheAlignedArena = struct {
    allocator: std.mem.Allocator,
    chunks: std.ArrayListUnmanaged(*Chunk),
    current_chunk: ?*Chunk,
    
    // Configuration
    chunk_size: usize,
    alignment: usize,
    
    // Statistics
    total_allocated: usize,
    total_used: usize,
    allocation_count: u64,
    
    const CACHE_LINE_SIZE: usize = 64;
    const DEFAULT_CHUNK_SIZE: usize = 256 * 1024; // 256KB chunks

    const Chunk = struct {
        data: []align(CACHE_LINE_SIZE) u8,
        offset: usize,
        allocation_count: u32,
        
        pub fn create(backing: std.mem.Allocator, size: usize) !*Chunk {
            const chunk = try backing.create(Chunk);
            chunk.data = try backing.alignedAlloc(u8, .@"64", size);
            chunk.offset = 0;
            chunk.allocation_count = 0;
            return chunk;
        }
        
        pub fn destroy(self: *Chunk, backing: std.mem.Allocator) void {
            backing.free(self.data);
            backing.destroy(self);
        }
        
        pub fn tryAlloc(self: *Chunk, size: usize, alignment: usize) ?[]u8 {
            // Align to cache line for better performance
            const effective_alignment = @max(alignment, CACHE_LINE_SIZE);
            const aligned = std.mem.alignForward(usize, self.offset, effective_alignment);
            
            if (aligned + size > self.data.len) return null;
            
            const result = self.data[aligned .. aligned + size];
            self.offset = aligned + size;
            self.allocation_count += 1;
            return result;
        }
        
        pub fn reset(self: *Chunk) void {
            self.offset = 0;
            self.allocation_count = 0;
        }
        
        pub fn getUtilization(self: *Chunk) f64 {
            if (self.data.len == 0) return 0.0;
            return @as(f64, @floatFromInt(self.offset)) / @as(f64, @floatFromInt(self.data.len));
        }
    };

    pub fn init(allocator: std.mem.Allocator) CacheAlignedArena {
        return initWithSize(allocator, DEFAULT_CHUNK_SIZE);
    }
    
    pub fn initWithSize(allocator: std.mem.Allocator, chunk_size: usize) CacheAlignedArena {
        return CacheAlignedArena{
            .allocator = allocator,
            .chunks = .{},
            .current_chunk = null,
            .chunk_size = chunk_size,
            .alignment = CACHE_LINE_SIZE,
            .total_allocated = 0,
            .total_used = 0,
            .allocation_count = 0,
        };
    }

    pub fn deinit(self: *CacheAlignedArena) void {
        for (self.chunks.items) |chunk| {
            chunk.destroy(self.allocator);
        }
        self.chunks.deinit(self.allocator);
    }

    /// Allocate memory with cache-line alignment
    pub fn alloc(self: *CacheAlignedArena, comptime T: type, n: usize) ![]T {
        const size = @sizeOf(T) * n;
        const alignment = @max(@alignOf(T), CACHE_LINE_SIZE);
        
        // Try current chunk first
        if (self.current_chunk) |chunk| {
            if (chunk.tryAlloc(size, alignment)) |bytes| {
                self.total_used += size;
                self.allocation_count += 1;
                return @as([*]T, @ptrCast(@alignCast(bytes.ptr)))[0..n];
            }
        }
        
        // Allocate new chunk
        const new_chunk_size = @max(self.chunk_size, size + alignment);
        const new_chunk = try Chunk.create(self.allocator, new_chunk_size);
        try self.chunks.append(self.allocator, new_chunk);
        self.current_chunk = new_chunk;
        self.total_allocated += new_chunk_size;
        
        if (new_chunk.tryAlloc(size, alignment)) |bytes| {
            self.total_used += size;
            self.allocation_count += 1;
            return @as([*]T, @ptrCast(@alignCast(bytes.ptr)))[0..n];
        }
        
        return error.OutOfMemory;
    }

    /// Reset arena for reuse (keeps allocated memory)
    pub fn reset(self: *CacheAlignedArena) void {
        for (self.chunks.items) |chunk| {
            chunk.reset();
        }
        self.current_chunk = if (self.chunks.items.len > 0) self.chunks.items[0] else null;
        self.total_used = 0;
        self.allocation_count = 0;
    }

    /// Free all memory
    pub fn freeAll(self: *CacheAlignedArena) void {
        for (self.chunks.items) |chunk| {
            chunk.destroy(self.allocator);
        }
        self.chunks.clearRetainingCapacity();
        self.current_chunk = null;
        self.total_allocated = 0;
        self.total_used = 0;
        self.allocation_count = 0;
    }

    /// Get arena statistics
    pub fn getStats(self: *CacheAlignedArena) ArenaStats {
        return ArenaStats{
            .total_allocated = self.total_allocated,
            .total_used = self.total_used,
            .chunk_count = self.chunks.items.len,
            .allocation_count = self.allocation_count,
            .utilization = if (self.total_allocated > 0)
                @as(f64, @floatFromInt(self.total_used)) / @as(f64, @floatFromInt(self.total_allocated))
            else 0.0,
        };
    }
};

/// Arena statistics
pub const ArenaStats = struct {
    total_allocated: usize,
    total_used: usize,
    chunk_count: usize,
    allocation_count: u64,
    utilization: f64,
};

/// Coroutine-specific memory pool
/// Optimized for coroutine stack and context allocation
pub const CoroutineMemoryPool = struct {
    allocator: std.mem.Allocator,
    
    // Stack pools for different sizes
    small_stack_pool: StackPool,  // 16KB stacks
    medium_stack_pool: StackPool, // 64KB stacks
    large_stack_pool: StackPool,  // 256KB stacks
    
    // Context pool
    context_arena: CacheAlignedArena,
    
    // Statistics
    stats: CoroutinePoolStats,
    
    const SMALL_STACK_SIZE: usize = 16 * 1024;
    const MEDIUM_STACK_SIZE: usize = 64 * 1024;
    const LARGE_STACK_SIZE: usize = 256 * 1024;

    const StackPool = struct {
        allocator: std.mem.Allocator,
        stack_size: usize,
        free_stacks: std.ArrayListUnmanaged([]align(64) u8),
        total_created: u64,
        total_reused: u64,
        max_pool_size: usize,
        mutex: std.Thread.Mutex,
        
        pub fn init(alloc: std.mem.Allocator, stack_size: usize, max_pool: usize) StackPool {
            return StackPool{
                .allocator = alloc,
                .stack_size = stack_size,
                .free_stacks = .{},
                .total_created = 0,
                .total_reused = 0,
                .max_pool_size = max_pool,
                .mutex = .{},
            };
        }
        
        pub fn deinit(self: *StackPool) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            
            for (self.free_stacks.items) |stack| {
                self.allocator.free(stack);
            }
            self.free_stacks.deinit(self.allocator);
        }
        
        pub fn acquire(self: *StackPool) ![]align(64) u8 {
            self.mutex.lock();
            defer self.mutex.unlock();
            
            if (self.free_stacks.items.len > 0) {
                self.total_reused += 1;
                return self.free_stacks.pop().?;
            }
            
            // Allocate new stack with cache-line alignment
            const stack = try self.allocator.alignedAlloc(u8, .@"64", self.stack_size);
            self.total_created += 1;
            return stack;
        }
        
        pub fn release(self: *StackPool, stack: []align(64) u8) void {
            self.mutex.lock();
            defer self.mutex.unlock();
            
            if (self.free_stacks.items.len < self.max_pool_size) {
                // Clear stack memory for security
                @memset(stack, 0);
                self.free_stacks.append(self.allocator, stack) catch {
                    self.allocator.free(stack);
                };
            } else {
                self.allocator.free(stack);
            }
        }
        
        pub fn getReuseRate(self: *StackPool) f64 {
            const total = self.total_created + self.total_reused;
            if (total == 0) return 0.0;
            return @as(f64, @floatFromInt(self.total_reused)) / @as(f64, @floatFromInt(total));
        }
    };

    pub const CoroutinePoolStats = struct {
        small_stacks_created: u64 = 0,
        medium_stacks_created: u64 = 0,
        large_stacks_created: u64 = 0,
        small_stacks_reused: u64 = 0,
        medium_stacks_reused: u64 = 0,
        large_stacks_reused: u64 = 0,
        context_allocations: u64 = 0,
        total_memory_bytes: usize = 0,
    };

    pub fn init(allocator: std.mem.Allocator) CoroutineMemoryPool {
        return CoroutineMemoryPool{
            .allocator = allocator,
            .small_stack_pool = StackPool.init(allocator, SMALL_STACK_SIZE, 100),
            .medium_stack_pool = StackPool.init(allocator, MEDIUM_STACK_SIZE, 50),
            .large_stack_pool = StackPool.init(allocator, LARGE_STACK_SIZE, 20),
            .context_arena = CacheAlignedArena.init(allocator),
            .stats = .{},
        };
    }

    pub fn deinit(self: *CoroutineMemoryPool) void {
        self.small_stack_pool.deinit();
        self.medium_stack_pool.deinit();
        self.large_stack_pool.deinit();
        self.context_arena.deinit();
    }

    /// Acquire a stack of appropriate size
    pub fn acquireStack(self: *CoroutineMemoryPool, requested_size: usize) ![]align(64) u8 {
        if (requested_size <= SMALL_STACK_SIZE) {
            self.stats.small_stacks_created += 1;
            return self.small_stack_pool.acquire();
        } else if (requested_size <= MEDIUM_STACK_SIZE) {
            self.stats.medium_stacks_created += 1;
            return self.medium_stack_pool.acquire();
        } else {
            self.stats.large_stacks_created += 1;
            return self.large_stack_pool.acquire();
        }
    }

    /// Release a stack back to the pool
    pub fn releaseStack(self: *CoroutineMemoryPool, stack: []align(64) u8) void {
        if (stack.len <= SMALL_STACK_SIZE) {
            self.small_stack_pool.release(stack);
        } else if (stack.len <= MEDIUM_STACK_SIZE) {
            self.medium_stack_pool.release(stack);
        } else {
            self.large_stack_pool.release(stack);
        }
    }

    /// Allocate context memory from arena
    pub fn allocContext(self: *CoroutineMemoryPool, comptime T: type) !*T {
        const slice = try self.context_arena.alloc(T, 1);
        self.stats.context_allocations += 1;
        return &slice[0];
    }

    /// Reset context arena (call between request cycles)
    pub fn resetContextArena(self: *CoroutineMemoryPool) void {
        self.context_arena.reset();
    }

    /// Get comprehensive statistics
    pub fn getStats(self: *CoroutineMemoryPool) CoroutinePoolStats {
        var stats = self.stats;
        stats.small_stacks_reused = self.small_stack_pool.total_reused;
        stats.medium_stacks_reused = self.medium_stack_pool.total_reused;
        stats.large_stacks_reused = self.large_stack_pool.total_reused;
        
        // Calculate total memory
        stats.total_memory_bytes = 
            self.small_stack_pool.free_stacks.items.len * SMALL_STACK_SIZE +
            self.medium_stack_pool.free_stacks.items.len * MEDIUM_STACK_SIZE +
            self.large_stack_pool.free_stacks.items.len * LARGE_STACK_SIZE +
            self.context_arena.total_allocated;
        
        return stats;
    }
};

/// Thread-local cache for reduced contention
/// Each worker thread gets its own cache to minimize lock contention
pub const ThreadLocalCache = struct {
    allocator: std.mem.Allocator,
    
    // Per-thread caches (indexed by thread ID hash)
    caches: [MAX_THREADS]Cache,
    cache_count: std.atomic.Value(u32),
    
    // Global fallback pool
    global_pool: std.ArrayListUnmanaged(*anyopaque),
    global_mutex: std.Thread.Mutex,
    
    // Statistics
    local_hits: std.atomic.Value(u64),
    local_misses: std.atomic.Value(u64),
    global_hits: std.atomic.Value(u64),
    
    const MAX_THREADS: usize = 64;
    const LOCAL_CACHE_SIZE: usize = 32;

    const Cache = struct {
        items: [LOCAL_CACHE_SIZE]?*anyopaque,
        count: u32,
        thread_id: ?std.Thread.Id,
        
        pub fn init() Cache {
            return Cache{
                .items = [_]?*anyopaque{null} ** LOCAL_CACHE_SIZE,
                .count = 0,
                .thread_id = null,
            };
        }
        
        pub fn push(self: *Cache, item: *anyopaque) bool {
            if (self.count >= LOCAL_CACHE_SIZE) return false;
            self.items[self.count] = item;
            self.count += 1;
            return true;
        }
        
        pub fn pop(self: *Cache) ?*anyopaque {
            if (self.count == 0) return null;
            self.count -= 1;
            const item = self.items[self.count];
            self.items[self.count] = null;
            return item;
        }
    };

    pub fn init(allocator: std.mem.Allocator) ThreadLocalCache {
        var tlc = ThreadLocalCache{
            .allocator = allocator,
            .caches = undefined,
            .cache_count = std.atomic.Value(u32).init(0),
            .global_pool = .{},
            .global_mutex = .{},
            .local_hits = std.atomic.Value(u64).init(0),
            .local_misses = std.atomic.Value(u64).init(0),
            .global_hits = std.atomic.Value(u64).init(0),
        };
        
        for (&tlc.caches) |*cache| {
            cache.* = Cache.init();
        }
        
        return tlc;
    }

    pub fn deinit(self: *ThreadLocalCache) void {
        self.global_mutex.lock();
        defer self.global_mutex.unlock();
        
        self.global_pool.deinit(self.allocator);
    }

    /// Get cache index for current thread
    fn getCacheIndex(self: *ThreadLocalCache) usize {
        const thread_id = std.Thread.getCurrentId();
        const hash = @as(usize, @intCast(thread_id)) % MAX_THREADS;
        
        // Initialize cache for this thread if needed
        if (self.caches[hash].thread_id == null) {
            self.caches[hash].thread_id = thread_id;
            _ = self.cache_count.fetchAdd(1, .monotonic);
        }
        
        return hash;
    }

    /// Try to get an item from thread-local cache
    pub fn tryGet(self: *ThreadLocalCache) ?*anyopaque {
        const idx = self.getCacheIndex();
        
        // Try local cache first
        if (self.caches[idx].pop()) |item| {
            _ = self.local_hits.fetchAdd(1, .monotonic);
            return item;
        }
        
        _ = self.local_misses.fetchAdd(1, .monotonic);
        
        // Try global pool
        self.global_mutex.lock();
        defer self.global_mutex.unlock();
        
        if (self.global_pool.items.len > 0) {
            _ = self.global_hits.fetchAdd(1, .monotonic);
            return self.global_pool.pop();
        }
        
        return null;
    }

    /// Put an item back to thread-local cache
    pub fn put(self: *ThreadLocalCache, item: *anyopaque) void {
        const idx = self.getCacheIndex();
        
        // Try local cache first
        if (self.caches[idx].push(item)) {
            return;
        }
        
        // Local cache full, put in global pool
        self.global_mutex.lock();
        defer self.global_mutex.unlock();
        
        self.global_pool.append(self.allocator, item) catch {
            // Pool full, just discard (caller should handle cleanup)
        };
    }

    /// Get cache statistics
    pub fn getStats(self: *ThreadLocalCache) ThreadLocalCacheStats {
        const local_hits = self.local_hits.load(.monotonic);
        const local_misses = self.local_misses.load(.monotonic);
        const global_hits = self.global_hits.load(.monotonic);
        const total = local_hits + local_misses;
        
        return ThreadLocalCacheStats{
            .active_threads = self.cache_count.load(.monotonic),
            .local_hits = local_hits,
            .local_misses = local_misses,
            .global_hits = global_hits,
            .local_hit_rate = if (total > 0)
                @as(f64, @floatFromInt(local_hits)) / @as(f64, @floatFromInt(total))
            else 0.0,
        };
    }
};

/// Thread-local cache statistics
pub const ThreadLocalCacheStats = struct {
    active_threads: u32,
    local_hits: u64,
    local_misses: u64,
    global_hits: u64,
    local_hit_rate: f64,
};

/// Unified Performance Manager
/// Coordinates all memory pooling and optimization components
pub const PerformanceManager = struct {
    allocator: std.mem.Allocator,
    
    // Memory pools
    coroutine_pool: CoroutineMemoryPool,
    value_pool: LockFreePool(Value),
    
    // Thread-local caching
    thread_cache: ThreadLocalCache,
    
    // Cache-aligned arena for temporary allocations
    temp_arena: CacheAlignedArena,
    
    // Configuration
    config: PerformanceConfig,
    
    // Global statistics
    stats: PerformanceStats,
    
    pub const PerformanceConfig = struct {
        enable_pooling: bool = true,
        enable_thread_local_cache: bool = true,
        enable_cache_alignment: bool = true,
        max_coroutine_stacks: usize = 1000,
        max_value_pool_size: usize = 10000,
        arena_chunk_size: usize = 256 * 1024,
    };
    
    pub const PerformanceStats = struct {
        total_allocations: u64 = 0,
        total_deallocations: u64 = 0,
        pool_hits: u64 = 0,
        pool_misses: u64 = 0,
        memory_saved_bytes: usize = 0,
        peak_memory_usage: usize = 0,
        current_memory_usage: usize = 0,
    };

    pub fn init(allocator: std.mem.Allocator) PerformanceManager {
        return initWithConfig(allocator, PerformanceConfig{});
    }
    
    pub fn initWithConfig(allocator: std.mem.Allocator, config: PerformanceConfig) PerformanceManager {
        return PerformanceManager{
            .allocator = allocator,
            .coroutine_pool = CoroutineMemoryPool.init(allocator),
            .value_pool = LockFreePool(Value).init(allocator),
            .thread_cache = ThreadLocalCache.init(allocator),
            .temp_arena = CacheAlignedArena.initWithSize(allocator, config.arena_chunk_size),
            .config = config,
            .stats = .{},
        };
    }

    pub fn deinit(self: *PerformanceManager) void {
        self.coroutine_pool.deinit();
        self.value_pool.deinit();
        self.thread_cache.deinit();
        self.temp_arena.deinit();
    }

    /// Acquire a coroutine stack
    pub fn acquireCoroutineStack(self: *PerformanceManager, size: usize) ![]align(64) u8 {
        if (!self.config.enable_pooling) {
            return self.allocator.alignedAlloc(u8, .@"64", size);
        }
        
        const stack = try self.coroutine_pool.acquireStack(size);
        self.stats.total_allocations += 1;
        self.stats.pool_hits += 1;
        return stack;
    }

    /// Release a coroutine stack
    pub fn releaseCoroutineStack(self: *PerformanceManager, stack: []align(64) u8) void {
        if (!self.config.enable_pooling) {
            self.allocator.free(stack);
            return;
        }
        
        self.coroutine_pool.releaseStack(stack);
        self.stats.total_deallocations += 1;
    }

    /// Acquire a Value from pool
    pub fn acquireValue(self: *PerformanceManager) !*Value {
        if (!self.config.enable_pooling) {
            return self.allocator.create(Value);
        }
        
        const value = try self.value_pool.acquire();
        self.stats.total_allocations += 1;
        return value;
    }

    /// Release a Value back to pool
    pub fn releaseValue(self: *PerformanceManager, value: *Value) void {
        if (!self.config.enable_pooling) {
            self.allocator.destroy(value);
            return;
        }
        
        self.value_pool.release(value);
        self.stats.total_deallocations += 1;
    }

    /// Allocate temporary memory (reset between requests)
    pub fn allocTemp(self: *PerformanceManager, comptime T: type, n: usize) ![]T {
        return self.temp_arena.alloc(T, n);
    }

    /// Reset temporary arena
    pub fn resetTemp(self: *PerformanceManager) void {
        self.temp_arena.reset();
    }

    /// Get comprehensive statistics
    pub fn getStats(self: *PerformanceManager) PerformanceReport {
        return PerformanceReport{
            .global_stats = self.stats,
            .coroutine_pool_stats = self.coroutine_pool.getStats(),
            .value_pool_stats = self.value_pool.getStats(),
            .thread_cache_stats = self.thread_cache.getStats(),
            .arena_stats = self.temp_arena.getStats(),
        };
    }

    /// Print performance report
    pub fn printReport(self: *PerformanceManager) void {
        const report = self.getStats();
        
        std.log.info("=== Performance Manager Report ===", .{});
        std.log.info("Global: allocs={}, deallocs={}, pool_hits={}", .{
            report.global_stats.total_allocations,
            report.global_stats.total_deallocations,
            report.global_stats.pool_hits,
        });
        std.log.info("Value Pool: hit_rate={d:.2}%", .{
            report.value_pool_stats.hit_rate * 100.0,
        });
        std.log.info("Thread Cache: local_hit_rate={d:.2}%", .{
            report.thread_cache_stats.local_hit_rate * 100.0,
        });
        std.log.info("Arena: utilization={d:.2}%", .{
            report.arena_stats.utilization * 100.0,
        });
    }
};

/// Comprehensive performance report
pub const PerformanceReport = struct {
    global_stats: PerformanceManager.PerformanceStats,
    coroutine_pool_stats: CoroutineMemoryPool.CoroutinePoolStats,
    value_pool_stats: PoolStats,
    thread_cache_stats: ThreadLocalCacheStats,
    arena_stats: ArenaStats,
};

// ============================================================================
// Tests
// ============================================================================

test "lock-free pool basic operations" {
    const TestStruct = struct {
        value: u64,
        data: [56]u8, // Pad to 64 bytes for cache alignment
    };
    
    var pool = LockFreePool(TestStruct).init(std.testing.allocator);
    defer pool.deinit();
    
    // Acquire and release
    const obj1 = try pool.acquire();
    obj1.value = 42;
    
    const obj2 = try pool.acquire();
    obj2.value = 100;
    
    pool.release(obj1);
    pool.release(obj2);
    
    // Verify reuse
    const obj3 = try pool.acquire();
    try std.testing.expect(obj3 == obj2 or obj3 == obj1);
    
    const stats = pool.getStats();
    try std.testing.expect(stats.total_acquired >= 3);
    try std.testing.expect(stats.total_released >= 2);
}

test "cache-aligned arena allocation" {
    var arena = CacheAlignedArena.init(std.testing.allocator);
    defer arena.deinit();
    
    const data1 = try arena.alloc(u64, 10);
    try std.testing.expect(data1.len == 10);
    
    const data2 = try arena.alloc(u8, 100);
    try std.testing.expect(data2.len == 100);
    
    const stats = arena.getStats();
    try std.testing.expect(stats.allocation_count == 2);
    try std.testing.expect(stats.total_used > 0);
    
    // Test reset
    arena.reset();
    const stats_after = arena.getStats();
    try std.testing.expect(stats_after.total_used == 0);
    try std.testing.expect(stats_after.total_allocated > 0); // Memory retained
}

test "coroutine memory pool" {
    var pool = CoroutineMemoryPool.init(std.testing.allocator);
    defer pool.deinit();
    
    // Test small stack
    const small_stack = try pool.acquireStack(8 * 1024);
    try std.testing.expect(small_stack.len == 16 * 1024);
    pool.releaseStack(small_stack);
    
    // Test medium stack
    const medium_stack = try pool.acquireStack(32 * 1024);
    try std.testing.expect(medium_stack.len == 64 * 1024);
    pool.releaseStack(medium_stack);
    
    // Test reuse
    const reused_stack = try pool.acquireStack(8 * 1024);
    try std.testing.expect(reused_stack.ptr == small_stack.ptr);
    pool.releaseStack(reused_stack);
}

test "thread-local cache" {
    var cache = ThreadLocalCache.init(std.testing.allocator);
    defer cache.deinit();
    
    // Create some test items
    var items: [5]u64 = .{ 1, 2, 3, 4, 5 };
    
    // Put items
    for (&items) |*item| {
        cache.put(@ptrCast(item));
    }
    
    // Get items back
    var retrieved: usize = 0;
    while (cache.tryGet()) |_| {
        retrieved += 1;
    }
    
    try std.testing.expect(retrieved == 5);
    
    const stats = cache.getStats();
    try std.testing.expect(stats.local_hits >= 5);
}

test "performance manager integration" {
    var manager = PerformanceManager.init(std.testing.allocator);
    defer manager.deinit();
    
    // Test coroutine stack
    const stack = try manager.acquireCoroutineStack(32 * 1024);
    try std.testing.expect(stack.len >= 32 * 1024);
    manager.releaseCoroutineStack(stack);
    
    // Test value pool
    const value = try manager.acquireValue();
    value.* = Value.initNull();
    manager.releaseValue(value);
    
    // Test temp arena
    const temp_data = try manager.allocTemp(u8, 100);
    try std.testing.expect(temp_data.len == 100);
    manager.resetTemp();
    
    // Verify stats
    const report = manager.getStats();
    try std.testing.expect(report.global_stats.total_allocations >= 2);
}
