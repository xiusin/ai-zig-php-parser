//! ============================================================================
//! Windows IOCP (I/O Completion Ports) 完整实现
//! ============================================================================
//!
//! 本模块实现了完整的 Windows IOCP 支持，替代简化的占位符实现
//!
//! 功能：
//! - IOCP 句柄管理
//! - 异步文件 I/O
//! - 异步网络 I/O
//! - 完成端口轮询
//! - 重叠 I/O 结构管理
//!
//! 修复问题：src/runtime/async_io.zig:620-650 的占位符实现
//! ============================================================================

const std = @import("std");
const builtin = @import("builtin");
const windows = std.os.windows;

/// Windows IOCP 多路复用器（完整实现）
/// @platform Windows
/// @thread-safety THREAD-SAFE
pub const IOCPMultiplexer = struct {
    allocator: std.mem.Allocator,
    
    /// IOCP 句柄
    iocp_handle: windows.HANDLE,
    
    /// 最大并发线程数
    max_concurrent_threads: u32,
    
    /// 活跃的重叠 I/O 操作
    active_operations: std.AutoHashMap(usize, *OverlappedOperation),
    
    /// 操作 ID 生成器
    next_operation_id: std.atomic.Value(usize),
    
    /// 互斥锁
    mutex: std.Thread.Mutex,
    
    /// 初始化 IOCP 多路复用器
    /// @pre allocator 必须有效
    /// @post 返回初始化的 IOCP 多路复用器
    pub fn init(allocator: std.mem.Allocator) !IOCPMultiplexer {
        // 创建 IOCP 句柄
        // 参数：
        // - INVALID_HANDLE_VALUE: 不关联现有文件句柄
        // - null: 不关联现有 IOCP
        // - 0: 完成键（稍后设置）
        // - 0: 最大并发线程数（0 = CPU 核心数）
        const iocp_handle = try windows.CreateIoCompletionPort(
            windows.INVALID_HANDLE_VALUE,
            null,
            0,
            0,
        );
        errdefer windows.CloseHandle(iocp_handle);
        
        return IOCPMultiplexer{
            .allocator = allocator,
            .iocp_handle = iocp_handle,
            .max_concurrent_threads = 0, // 0 = 使用 CPU 核心数
            .active_operations = std.AutoHashMap(usize, *OverlappedOperation).init(allocator),
            .next_operation_id = std.atomic.Value(usize).init(1),
            .mutex = .{},
        };
    }
    
    /// 释放资源
    /// @pre self 必须已初始化
    /// @post 释放所有资源
    pub fn deinit(self: *IOCPMultiplexer) void {
        // 关闭 IOCP 句柄
        windows.CloseHandle(self.iocp_handle);
        
        // 清理活跃操作
        var iter = self.active_operations.valueIterator();
        while (iter.next()) |op| {
            op.*.deinit(self.allocator);
        }
        self.active_operations.deinit();
    }
    
    /// 轮询 I/O 完成事件
    /// @pre self 必须已初始化
    /// @post 返回已完成的 I/O 事件列表
    pub fn poll(self: *IOCPMultiplexer, timeout_ms: i32) ![]IOEvent {
        var events = std.ArrayList(IOEvent).init(self.allocator);
        errdefer events.deinit();
        
        // 转换超时时间
        const timeout: u32 = if (timeout_ms < 0)
            windows.INFINITE
        else
            @intCast(timeout_ms);
        
        // 批量获取完成事件（最多 64 个）
        const max_events = 64;
        var completion_entries: [max_events]windows.OVERLAPPED_ENTRY = undefined;
        
        var num_entries: u32 = 0;
        const result = windows.kernel32.GetQueuedCompletionStatusEx(
            self.iocp_handle,
            &completion_entries,
            max_events,
            &num_entries,
            timeout,
            0, // 不使用 alertable wait
        );
        
        if (result == 0) {
            const err = windows.kernel32.GetLastError();
            if (err == windows.Win32Error.WAIT_TIMEOUT) {
                // 超时，返回空列表
                return events.toOwnedSlice();
            }
            return windows.unexpectedError(err);
        }
        
        // 处理完成的操作
        for (completion_entries[0..num_entries]) |entry| {
            const overlapped = @as(*OverlappedOperation, @ptrCast(@alignCast(entry.lpOverlapped)));
            
            // 创建 I/O 事件
            const event = IOEvent{
                .fd = overlapped.fd,
                .type = overlapped.operation_type,
                .bytes_transferred = entry.dwNumberOfBytesTransferred,
                .error_code = if (entry.Internal == 0) null else @as(windows.Win32Error, @enumFromInt(entry.Internal)),
            };
            
            try events.append(event);
            
            // 从活跃操作中移除
            self.mutex.lock();
            _ = self.active_operations.remove(overlapped.operation_id);
            self.mutex.unlock();
            
            // 释放重叠结构
            overlapped.deinit(self.allocator);
        }
        
        return events.toOwnedSlice();
    }
    
    /// 关联文件句柄到 IOCP
    /// @pre self 必须已初始化
    /// @post 文件句柄被关联到 IOCP
    pub fn associateHandle(self: *IOCPMultiplexer, handle: windows.HANDLE, completion_key: usize) !void {
        _ = try windows.CreateIoCompletionPort(
            handle,
            self.iocp_handle,
            completion_key,
            0,
        );
    }
    
    /// 提交异步读取操作
    /// @pre self 和 handle 必须有效
    /// @post 异步读取操作被提交
    pub fn submitRead(
        self: *IOCPMultiplexer,
        handle: windows.HANDLE,
        buffer: []u8,
        offset: u64,
    ) !*OverlappedOperation {
        const operation_id = self.next_operation_id.fetchAdd(1, .monotonic);
        
        // 创建重叠结构
        const overlapped = try OverlappedOperation.init(
            self.allocator,
            operation_id,
            @intFromPtr(handle),
            .file_read_ready,
        );
        errdefer overlapped.deinit(self.allocator);
        
        // 设置偏移量
        overlapped.overlapped.DUMMYUNIONNAME.DUMMYSTRUCTNAME.Offset = @truncate(offset);
        overlapped.overlapped.DUMMYUNIONNAME.DUMMYSTRUCTNAME.OffsetHigh = @truncate(offset >> 32);
        
        // 提交读取操作
        var bytes_read: u32 = 0;
        const result = windows.kernel32.ReadFile(
            handle,
            buffer.ptr,
            @intCast(buffer.len),
            &bytes_read,
            &overlapped.overlapped,
        );
        
        if (result == 0) {
            const err = windows.kernel32.GetLastError();
            if (err != windows.Win32Error.IO_PENDING) {
                return windows.unexpectedError(err);
            }
        }
        
        // 添加到活跃操作
        self.mutex.lock();
        try self.active_operations.put(operation_id, overlapped);
        self.mutex.unlock();
        
        return overlapped;
    }
    
    /// 提交异步写入操作
    /// @pre self 和 handle 必须有效
    /// @post 异步写入操作被提交
    pub fn submitWrite(
        self: *IOCPMultiplexer,
        handle: windows.HANDLE,
        buffer: []const u8,
        offset: u64,
    ) !*OverlappedOperation {
        const operation_id = self.next_operation_id.fetchAdd(1, .monotonic);
        
        // 创建重叠结构
        const overlapped = try OverlappedOperation.init(
            self.allocator,
            operation_id,
            @intFromPtr(handle),
            .file_write_ready,
        );
        errdefer overlapped.deinit(self.allocator);
        
        // 设置偏移量
        overlapped.overlapped.DUMMYUNIONNAME.DUMMYSTRUCTNAME.Offset = @truncate(offset);
        overlapped.overlapped.DUMMYUNIONNAME.DUMMYSTRUCTNAME.OffsetHigh = @truncate(offset >> 32);
        
        // 提交写入操作
        var bytes_written: u32 = 0;
        const result = windows.kernel32.WriteFile(
            handle,
            buffer.ptr,
            @intCast(buffer.len),
            &bytes_written,
            &overlapped.overlapped,
        );
        
        if (result == 0) {
            const err = windows.kernel32.GetLastError();
            if (err != windows.Win32Error.IO_PENDING) {
                return windows.unexpectedError(err);
            }
        }
        
        // 添加到活跃操作
        self.mutex.lock();
        try self.active_operations.put(operation_id, overlapped);
        self.mutex.unlock();
        
        return overlapped;
    }
    
    /// 提交异步 socket 接收操作
    /// @pre self 和 socket 必须有效
    /// @post 异步接收操作被提交
    pub fn submitRecv(
        self: *IOCPMultiplexer,
        socket: windows.ws2_32.SOCKET,
        buffer: []u8,
    ) !*OverlappedOperation {
        const operation_id = self.next_operation_id.fetchAdd(1, .monotonic);
        
        // 创建重叠结构
        const overlapped = try OverlappedOperation.init(
            self.allocator,
            operation_id,
            @intCast(socket),
            .socket_read_ready,
        );
        errdefer overlapped.deinit(self.allocator);
        
        // 准备 WSABUF
        var wsabuf = windows.ws2_32.WSABUF{
            .len = @intCast(buffer.len),
            .buf = buffer.ptr,
        };
        
        // 提交接收操作
        var flags: u32 = 0;
        var bytes_received: u32 = 0;
        const result = windows.ws2_32.WSARecv(
            socket,
            @ptrCast(&wsabuf),
            1,
            &bytes_received,
            &flags,
            @ptrCast(&overlapped.overlapped),
            null,
        );
        
        if (result != 0) {
            const err = windows.ws2_32.WSAGetLastError();
            if (err != windows.ws2_32.WinsockError.WSA_IO_PENDING) {
                return error.WSARecvFailed;
            }
        }
        
        // 添加到活跃操作
        self.mutex.lock();
        try self.active_operations.put(operation_id, overlapped);
        self.mutex.unlock();
        
        return overlapped;
    }
    
    /// 提交异步 socket 发送操作
    /// @pre self 和 socket 必须有效
    /// @post 异步发送操作被提交
    pub fn submitSend(
        self: *IOCPMultiplexer,
        socket: windows.ws2_32.SOCKET,
        buffer: []const u8,
    ) !*OverlappedOperation {
        const operation_id = self.next_operation_id.fetchAdd(1, .monotonic);
        
        // 创建重叠结构
        const overlapped = try OverlappedOperation.init(
            self.allocator,
            operation_id,
            @intCast(socket),
            .socket_write_ready,
        );
        errdefer overlapped.deinit(self.allocator);
        
        // 准备 WSABUF
        var wsabuf = windows.ws2_32.WSABUF{
            .len = @intCast(buffer.len),
            .buf = @constCast(buffer.ptr),
        };
        
        // 提交发送操作
        var bytes_sent: u32 = 0;
        const result = windows.ws2_32.WSASend(
            socket,
            @ptrCast(&wsabuf),
            1,
            &bytes_sent,
            0,
            @ptrCast(&overlapped.overlapped),
            null,
        );
        
        if (result != 0) {
            const err = windows.ws2_32.WSAGetLastError();
            if (err != windows.ws2_32.WinsockError.WSA_IO_PENDING) {
                return error.WSASendFailed;
            }
        }
        
        // 添加到活跃操作
        self.mutex.lock();
        try self.active_operations.put(operation_id, overlapped);
        self.mutex.unlock();
        
        return overlapped;
    }
    
    /// 取消操作
    /// @pre self 和 operation 必须有效
    /// @post 操作被取消
    pub fn cancelOperation(self: *IOCPMultiplexer, operation: *OverlappedOperation) !void {
        _ = self;
        
        // 使用 CancelIoEx 取消特定操作
        const result = windows.kernel32.CancelIoEx(
            @ptrFromInt(operation.fd),
            &operation.overlapped,
        );
        
        if (result == 0) {
            const err = windows.kernel32.GetLastError();
            if (err != windows.Win32Error.NOT_FOUND) {
                return windows.unexpectedError(err);
            }
        }
    }
};

/// 重叠 I/O 操作
/// @ownership TRANSFER（由 IOCP 管理）
pub const OverlappedOperation = struct {
    /// Windows OVERLAPPED 结构
    overlapped: windows.OVERLAPPED,
    
    /// 操作 ID
    operation_id: usize,
    
    /// 文件描述符或 socket
    fd: usize,
    
    /// 操作类型
    operation_type: IOEventType,
    
    /// 初始化重叠操作
    /// @pre allocator 必须有效
    /// @post 返回初始化的重叠操作
    pub fn init(
        allocator: std.mem.Allocator,
        operation_id: usize,
        fd: usize,
        operation_type: IOEventType,
    ) !*OverlappedOperation {
        const self = try allocator.create(OverlappedOperation);
        errdefer allocator.destroy(self);
        
        self.* = .{
            .overlapped = std.mem.zeroes(windows.OVERLAPPED),
            .operation_id = operation_id,
            .fd = fd,
            .operation_type = operation_type,
        };
        
        return self;
    }
    
    /// 释放资源
    /// @pre self 必须已初始化
    /// @post 释放所有资源
    pub fn deinit(self: *OverlappedOperation, allocator: std.mem.Allocator) void {
        allocator.destroy(self);
    }
};

/// I/O 事件
pub const IOEvent = struct {
    fd: usize,
    type: IOEventType,
    bytes_transferred: u32,
    error_code: ?windows.Win32Error,
};

/// I/O 事件类型
pub const IOEventType = enum {
    file_read_ready,
    file_write_ready,
    socket_read_ready,
    socket_write_ready,
    socket_accept_ready,
    socket_connect_ready,
};

// ============================================================================
// 测试
// ============================================================================

test "iocp initialization" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    
    const allocator = std.testing.allocator;
    
    var iocp = try IOCPMultiplexer.init(allocator);
    defer iocp.deinit();
    
    try std.testing.expect(iocp.iocp_handle != windows.INVALID_HANDLE_VALUE);
}

test "iocp poll timeout" {
    if (builtin.os.tag != .windows) return error.SkipZigTest;
    
    const allocator = std.testing.allocator;
    
    var iocp = try IOCPMultiplexer.init(allocator);
    defer iocp.deinit();
    
    // 轮询（应该超时）
    const events = try iocp.poll(10); // 10ms
    defer allocator.free(events);
    
    try std.testing.expectEqual(@as(usize, 0), events.len);
}
