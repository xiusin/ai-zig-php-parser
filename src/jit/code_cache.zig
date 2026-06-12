const std = @import("std");
const builtin = @import("builtin");

// Alias for compatibility
const os = if (@hasDecl(std, "posix")) std.posix else std.os;

const page_align = if (builtin.os.tag == .macos and builtin.cpu.arch == .aarch64) 16384 else 4096;

extern "c" fn sys_icache_invalidate(start: *const anyopaque, len: usize) void;
extern "c" fn pthread_jit_write_protect_np(enabled: c_int) void;
extern "c" fn __clear_cache(start: ?*anyopaque, end: ?*anyopaque) void;

pub const CodeCache = struct {
    memory: []align(page_align) u8,
    cursor: usize,
    allocator: std.mem.Allocator,

    pub fn protect(self: *CodeCache) void {
        _ = self;
        if (builtin.os.tag == .macos and builtin.cpu.arch == .aarch64) {
            pthread_jit_write_protect_np(1);
        }
    }

    pub fn unprotect(self: *CodeCache) void {
        _ = self;
        if (builtin.os.tag == .macos and builtin.cpu.arch == .aarch64) {
            // std.debug.print("Unprotecting JIT memory\n", .{});
            pthread_jit_write_protect_np(0);
        }
    }

    pub fn init(allocator: std.mem.Allocator, size: usize) !CodeCache {
        // PROT_READ | PROT_WRITE | PROT_EXEC
        const prot = os.PROT.READ | os.PROT.WRITE | os.PROT.EXEC;
        
        // Use struct initialization for MAP flags
        var flags = os.MAP{ .TYPE = .PRIVATE, .ANONYMOUS = true };

        // On macOS with Apple Silicon, we need MAP_JIT to write executable memory
        if (builtin.os.tag == .macos and builtin.cpu.arch == .aarch64) {
            // Check if JIT field exists (it does based on probe)
            if (@hasField(os.MAP, "JIT")) {
                flags.JIT = true;
                std.debug.print("JIT: Using MAP_JIT\n", .{});
            } else {
                std.debug.print("JIT: MAP_JIT not available in std.os.MAP\n", .{});
            }
        }

        const memory = try os.mmap(
            null,
            size,
            prot,
            flags,
            -1,
            0,
        );

        return CodeCache{
            .memory = memory,
            .cursor = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CodeCache) void {
        os.munmap(self.memory);
    }

    pub fn allocate(self: *CodeCache, size: usize) ![]u8 {
        // Align to 4 bytes for ARM64 instructions
        const aligned_cursor = std.mem.alignForward(usize, self.cursor, 4);
        
        if (aligned_cursor + size > self.memory.len) {
            return error.OutOfMemory;
        }
        
        const ptr = self.memory[aligned_cursor .. aligned_cursor + size];
        self.cursor = aligned_cursor + size;
        return ptr;
    }

    pub fn reset(self: *CodeCache) void {
        self.cursor = 0;
    }
    
    pub fn flush(self: *CodeCache, code: []u8) void {
        _ = self;
        if (builtin.os.tag == .macos and builtin.cpu.arch == .aarch64) {
            sys_icache_invalidate(code.ptr, code.len);
            
            // Also try __clear_cache
            const start = @as(?*anyopaque, @ptrCast(@constCast(code.ptr)));
            const end = @as(?*anyopaque, @ptrCast(@constCast(code.ptr + code.len)));
            __clear_cache(start, end);
            
            // Verify content
            if (code.len >= 84) {
                 const first_word = std.mem.readInt(u32, code[0..4], .little);
                 std.debug.print("JIT Code[0]: {x}\n", .{first_word});
                 const word_80 = std.mem.readInt(u32, code[80..84], .little);
                 std.debug.print("JIT Code[80]: {x}\n", .{word_80});
            }
        } else {
            // Generic fallback, maybe __clear_cache for gcc/clang builtins
            // but for now we assume x86_64 TSO usually handles this, 
            // though strict correctness requires fence.
        }
    }
};
