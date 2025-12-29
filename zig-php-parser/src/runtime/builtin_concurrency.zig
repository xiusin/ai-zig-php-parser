const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const concurrency = @import("concurrency.zig");

/// 注册并发安全类到 VM
pub fn registerConcurrencyClasses(vm: anytype) !void {
    try registerMutexClass(vm);
    try registerAtomicClass(vm);
    try registerRWLockClass(vm);
    try registerSharedDataClass(vm);
    try registerChannelClass(vm);
}

/// 注册 Mutex 类
fn registerMutexClass(vm: anytype) !void {
    const name_str = try types.PHPString.init(vm.allocator, "Mutex");
    const mutex_class = try vm.allocator.create(types.PHPClass);
    mutex_class.* = types.PHPClass.init(vm.allocator, name_str);

    try vm.classes.put("Mutex", mutex_class);
    try vm.defineBuiltin("Mutex", mutexConstructor);
}

pub fn mutexConstructor(vm: anytype, args: []Value) !Value {
    _ = args;

    const mutex = try vm.allocator.create(concurrency.PHPMutex);
    mutex.* = concurrency.PHPMutex.init(vm.allocator);

    const class = vm.classes.get("Mutex").?;
    const box = try vm.memory_manager.allocObject(class);
    const obj = box.data;
    obj.native_data = @ptrCast(mutex);

    return Value{
        .tag = .object,
        .data = .{ .object = box },
    };
}

/// 注册 Atomic 类
fn registerAtomicClass(vm: anytype) !void {
    const name_str = try types.PHPString.init(vm.allocator, "Atomic");
    const atomic_class = try vm.allocator.create(types.PHPClass);
    atomic_class.* = types.PHPClass.init(vm.allocator, name_str);

    try vm.classes.put("Atomic", atomic_class);
    try vm.defineBuiltin("Atomic", atomicConstructor);
}

pub fn atomicConstructor(vm: anytype, args: []Value) !Value {
    const initial_value: i64 = if (args.len > 0 and args[0].tag == .integer)
        args[0].data.integer
    else
        0;

    const atomic = try vm.allocator.create(concurrency.PHPAtomic);
    atomic.* = concurrency.PHPAtomic.init(vm.allocator, initial_value);

    const class = vm.classes.get("Atomic").?;
    const box = try vm.memory_manager.allocObject(class);
    const obj = box.data;
    obj.native_data = @ptrCast(atomic);

    return Value{
        .tag = .object,
        .data = .{ .object = box },
    };
}

/// 注册 RWLock 类
fn registerRWLockClass(vm: anytype) !void {
    const name_str = try types.PHPString.init(vm.allocator, "RWLock");
    const rwlock_class = try vm.allocator.create(types.PHPClass);
    rwlock_class.* = types.PHPClass.init(vm.allocator, name_str);

    try vm.classes.put("RWLock", rwlock_class);
    try vm.defineBuiltin("RWLock", rwlockConstructor);
}

pub fn rwlockConstructor(vm: anytype, args: []Value) !Value {
    _ = args;

    const rwlock = try vm.allocator.create(concurrency.PHPRWLock);
    rwlock.* = concurrency.PHPRWLock.init(vm.allocator);

    const class = vm.classes.get("RWLock").?;
    const box = try vm.memory_manager.allocObject(class);
    const obj = box.data;
    obj.native_data = @ptrCast(rwlock);

    return Value{
        .tag = .object,
        .data = .{ .object = box },
    };
}

/// 注册 SharedData 类
fn registerSharedDataClass(vm: anytype) !void {
    const name_str = try types.PHPString.init(vm.allocator, "SharedData");
    const shared_class = try vm.allocator.create(types.PHPClass);
    shared_class.* = types.PHPClass.init(vm.allocator, name_str);

    try vm.classes.put("SharedData", shared_class);
    try vm.defineBuiltin("SharedData", sharedDataConstructor);
}

pub fn sharedDataConstructor(vm: anytype, args: []Value) !Value {
    _ = args;

    const shared = try vm.allocator.create(concurrency.PHPSharedData);
    shared.* = concurrency.PHPSharedData.init(vm.allocator);

    const class = vm.classes.get("SharedData").?;
    const box = try vm.memory_manager.allocObject(class);
    const obj = box.data;
    obj.native_data = @ptrCast(shared);

    return Value{
        .tag = .object,
        .data = .{ .object = box },
    };
}

// ==================== Mutex 方法实现 ====================

pub fn callMutexMethod(vm: anytype, obj: *types.PHPObject, method_name: []const u8, args: []Value) !Value {
    const mutex = @as(*concurrency.PHPMutex, @ptrCast(@alignCast(obj.native_data.?)));

    if (std.mem.eql(u8, method_name, "lock")) {
        mutex.lock();
        return Value.initNull();
    } else if (std.mem.eql(u8, method_name, "unlock")) {
        mutex.unlock();
        return Value.initNull();
    } else if (std.mem.eql(u8, method_name, "tryLock")) {
        const result = mutex.tryLock();
        return Value.initBool(result);
    } else if (std.mem.eql(u8, method_name, "getLockCount")) {
        const count = mutex.getLockCount();
        return Value.initInt(@intCast(count));
    }

    _ = vm;
    _ = args;
    return error.MethodNotFound;
}

// ==================== Atomic 方法实现 ====================

pub fn callAtomicMethod(vm: anytype, obj: *types.PHPObject, method_name: []const u8, args: []Value) !Value {
    const atomic = @as(*concurrency.PHPAtomic, @ptrCast(@alignCast(obj.native_data.?)));

    if (std.mem.eql(u8, method_name, "load")) {
        const value = atomic.load();
        return Value.initInt(value);
    } else if (std.mem.eql(u8, method_name, "store")) {
        if (args.len < 1 or args[0].tag != .integer) return error.InvalidArgument;
        atomic.store(args[0].data.integer);
        return Value.initNull();
    } else if (std.mem.eql(u8, method_name, "increment")) {
        const result = atomic.increment();
        return Value.initInt(result);
    } else if (std.mem.eql(u8, method_name, "decrement")) {
        const result = atomic.decrement();
        return Value.initInt(result);
    } else if (std.mem.eql(u8, method_name, "add")) {
        if (args.len < 1 or args[0].tag != .integer) return error.InvalidArgument;
        const result = atomic.add(args[0].data.integer);
        return Value.initInt(result);
    } else if (std.mem.eql(u8, method_name, "sub")) {
        if (args.len < 1 or args[0].tag != .integer) return error.InvalidArgument;
        const result = atomic.sub(args[0].data.integer);
        return Value.initInt(result);
    } else if (std.mem.eql(u8, method_name, "swap")) {
        if (args.len < 1 or args[0].tag != .integer) return error.InvalidArgument;
        const old_value = atomic.swap(args[0].data.integer);
        return Value.initInt(old_value);
    } else if (std.mem.eql(u8, method_name, "compareAndSwap")) {
        if (args.len < 2 or args[0].tag != .integer or args[1].tag != .integer) return error.InvalidArgument;
        const success = atomic.compareAndSwap(args[0].data.integer, args[1].data.integer);
        return Value.initBool(success);
    }

    _ = vm;
    return error.MethodNotFound;
}

// ==================== RWLock 方法实现 ====================

pub fn callRWLockMethod(vm: anytype, obj: *types.PHPObject, method_name: []const u8, args: []Value) !Value {
    const rwlock = @as(*concurrency.PHPRWLock, @ptrCast(@alignCast(obj.native_data.?)));

    if (std.mem.eql(u8, method_name, "lockRead")) {
        rwlock.lockRead();
        return Value.initNull();
    } else if (std.mem.eql(u8, method_name, "unlockRead")) {
        rwlock.unlockRead();
        return Value.initNull();
    } else if (std.mem.eql(u8, method_name, "lockWrite")) {
        rwlock.lockWrite();
        return Value.initNull();
    } else if (std.mem.eql(u8, method_name, "unlockWrite")) {
        rwlock.unlockWrite();
        return Value.initNull();
    } else if (std.mem.eql(u8, method_name, "getReaderCount")) {
        const count = rwlock.getReaderCount();
        return Value.initInt(@intCast(count));
    } else if (std.mem.eql(u8, method_name, "getWriterCount")) {
        const count = rwlock.getWriterCount();
        return Value.initInt(@intCast(count));
    }

    _ = vm;
    _ = args;
    return error.MethodNotFound;
}

// ==================== SharedData 方法实现 ====================

pub fn callSharedDataMethod(vm: anytype, obj: *types.PHPObject, method_name: []const u8, args: []Value) !Value {
    const shared = @as(*concurrency.PHPSharedData, @ptrCast(@alignCast(obj.native_data.?)));

    if (std.mem.eql(u8, method_name, "set")) {
        if (args.len < 2 or args[0].tag != .string) return error.InvalidArgument;

        const key = args[0].data.string.data.data;
        try shared.set(key, args[1]);
        return Value.initNull();
    } else if (std.mem.eql(u8, method_name, "get")) {
        if (args.len < 1 or args[0].tag != .string) return error.InvalidArgument;

        const key = args[0].data.string.data.data;
        if (shared.get(key)) |value| {
            return value;
        }
        return Value.initNull();
    } else if (std.mem.eql(u8, method_name, "remove")) {
        if (args.len < 1 or args[0].tag != .string) return error.InvalidArgument;

        const key = args[0].data.string.data.data;
        const result = shared.remove(key);
        return Value.initBool(result);
    } else if (std.mem.eql(u8, method_name, "has")) {
        if (args.len < 1 or args[0].tag != .string) return error.InvalidArgument;

        const key = args[0].data.string.data.data;
        const result = shared.has(key);
        return Value.initBool(result);
    } else if (std.mem.eql(u8, method_name, "size")) {
        const result = shared.size();
        return Value.initInt(@intCast(result));
    } else if (std.mem.eql(u8, method_name, "clear")) {
        shared.clear();
        return Value.initNull();
    } else if (std.mem.eql(u8, method_name, "getAccessCount")) {
        const count = shared.getAccessCount();
        return Value.initInt(@intCast(count));
    }

    _ = vm;
    return error.MethodNotFound;
}

// ==================== Channel 类注册和实现 ====================

fn registerChannelClass(vm: anytype) !void {
    const name_str = try types.PHPString.init(vm.allocator, "Channel");
    const channel_class = try vm.allocator.create(types.PHPClass);
    channel_class.* = types.PHPClass.init(vm.allocator, name_str);

    try vm.classes.put("Channel", channel_class);
    try vm.defineBuiltin("Channel", channelConstructor);
}

pub fn channelConstructor(vm: anytype, args: []Value) !Value {
    const capacity: usize = if (args.len > 0 and args[0].tag == .integer)
        @intCast(@max(0, args[0].data.integer))
    else
        0;

    const channel = try vm.allocator.create(concurrency.PHPChannel);
    channel.* = concurrency.PHPChannel.init(vm.allocator, capacity);

    const class = vm.classes.get("Channel").?;
    const box = try vm.memory_manager.allocObject(class);
    const obj = box.data;
    obj.native_data = @ptrCast(channel);

    return Value{
        .tag = .object,
        .data = .{ .object = box },
    };
}

pub fn callChannelMethod(vm: anytype, obj: *types.PHPObject, method_name: []const u8, args: []Value) !Value {
    const channel = @as(*concurrency.PHPChannel, @ptrCast(@alignCast(obj.native_data.?)));

    if (std.mem.eql(u8, method_name, "send")) {
        if (args.len < 1) return error.InvalidArgument;
        try channel.send(args[0]);
        return Value.initNull();
    } else if (std.mem.eql(u8, method_name, "recv")) {
        if (channel.recv()) |value| {
            return value;
        }
        return Value.initNull();
    } else if (std.mem.eql(u8, method_name, "trySend")) {
        if (args.len < 1) return error.InvalidArgument;
        const result = channel.trySend(args[0]);
        return Value.initBool(result);
    } else if (std.mem.eql(u8, method_name, "tryRecv")) {
        if (channel.tryRecv()) |value| {
            return value;
        }
        return Value.initNull();
    } else if (std.mem.eql(u8, method_name, "close")) {
        channel.close();
        return Value.initNull();
    } else if (std.mem.eql(u8, method_name, "isClosed")) {
        return Value.initBool(channel.isClosed());
    } else if (std.mem.eql(u8, method_name, "len") or std.mem.eql(u8, method_name, "size")) {
        return Value.initInt(@intCast(channel.len()));
    } else if (std.mem.eql(u8, method_name, "capacity") or std.mem.eql(u8, method_name, "getCapacity")) {
        return Value.initInt(@intCast(channel.getCapacity()));
    } else if (std.mem.eql(u8, method_name, "getSendCount")) {
        return Value.initInt(@intCast(channel.getSendCount()));
    } else if (std.mem.eql(u8, method_name, "getRecvCount")) {
        return Value.initInt(@intCast(channel.getRecvCount()));
    }

    _ = vm;
    return error.MethodNotFound;
}
