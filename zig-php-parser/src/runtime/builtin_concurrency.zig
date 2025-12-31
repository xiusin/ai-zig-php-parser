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
    defer name_str.release(vm.allocator);
    const mutex_class = try vm.allocator.create(types.PHPClass);
    mutex_class.* = try types.PHPClass.init(vm.allocator, name_str);
    mutex_class.native_destructor = mutexDestructor;

    try vm.classes.put("Mutex", mutex_class);
    try vm.defineBuiltin("Mutex", mutexConstructor);
}

fn mutexDestructor(ptr: *anyopaque, allocator: std.mem.Allocator) void {
    const mutex = @as(*concurrency.PHPMutex, @ptrCast(@alignCast(ptr)));
    mutex.deinit();
    allocator.destroy(mutex);
}

pub fn mutexConstructor(vm: anytype, args: []Value) !Value {
    _ = args;

    const mutex = try vm.allocator.create(concurrency.PHPMutex);
    mutex.* = concurrency.PHPMutex.init(vm.allocator);

    const class = vm.classes.get("Mutex").?;
    const box = try vm.memory_manager.allocObject(class);
    const obj = box.data;
    obj.native_data = @ptrCast(mutex);

    return Value.fromBox(box, Value.TYPE_OBJECT);
}

/// 注册 Atomic 类
fn registerAtomicClass(vm: anytype) !void {
    const name_str = try types.PHPString.init(vm.allocator, "Atomic");
    defer name_str.release(vm.allocator);
    const atomic_class = try vm.allocator.create(types.PHPClass);
    atomic_class.* = try types.PHPClass.init(vm.allocator, name_str);
    atomic_class.native_destructor = atomicDestructor;

    try vm.classes.put("Atomic", atomic_class);
    try vm.defineBuiltin("Atomic", atomicConstructor);
}

fn atomicDestructor(ptr: *anyopaque, allocator: std.mem.Allocator) void {
    const atomic = @as(*concurrency.PHPAtomic, @ptrCast(@alignCast(ptr)));
    atomic.deinit();
    allocator.destroy(atomic);
}

pub fn atomicConstructor(vm: anytype, args: []Value) !Value {
    const initial_value: i64 = if (args.len > 0 and args[0].getTag() == .integer)
        args[0].asInt()
    else
        0;

    const atomic = try vm.allocator.create(concurrency.PHPAtomic);
    atomic.* = concurrency.PHPAtomic.init(vm.allocator, initial_value);

    const class = vm.classes.get("Atomic").?;
    const box = try vm.memory_manager.allocObject(class);
    const obj = box.data;
    obj.native_data = @ptrCast(atomic);

    return Value.fromBox(box, Value.TYPE_OBJECT);
}

/// 注册 RWLock 类
fn registerRWLockClass(vm: anytype) !void {
    const name_str = try types.PHPString.init(vm.allocator, "RWLock");
    defer name_str.release(vm.allocator);
    const rwlock_class = try vm.allocator.create(types.PHPClass);
    rwlock_class.* = try types.PHPClass.init(vm.allocator, name_str);
    rwlock_class.native_destructor = rwlockDestructor;

    try vm.classes.put("RWLock", rwlock_class);
    try vm.defineBuiltin("RWLock", rwlockConstructor);
}

fn rwlockDestructor(ptr: *anyopaque, allocator: std.mem.Allocator) void {
    const rwlock = @as(*concurrency.PHPRWLock, @ptrCast(@alignCast(ptr)));
    rwlock.deinit();
    allocator.destroy(rwlock);
}

pub fn rwlockConstructor(vm: anytype, args: []Value) !Value {
    _ = args;

    const rwlock = try vm.allocator.create(concurrency.PHPRWLock);
    rwlock.* = concurrency.PHPRWLock.init(vm.allocator);

    const class = vm.classes.get("RWLock").?;
    const box = try vm.memory_manager.allocObject(class);
    const obj = box.data;
    obj.native_data = @ptrCast(rwlock);

    return Value.fromBox(box, Value.TYPE_OBJECT);
}

/// 注册 SharedData 类
fn registerSharedDataClass(vm: anytype) !void {
    const name_str = try types.PHPString.init(vm.allocator, "SharedData");
    defer name_str.release(vm.allocator);
    const shared_class = try vm.allocator.create(types.PHPClass);
    shared_class.* = try types.PHPClass.init(vm.allocator, name_str);
    shared_class.native_destructor = sharedDataDestructor;

    try vm.classes.put("SharedData", shared_class);
    try vm.defineBuiltin("SharedData", sharedDataConstructor);
}

fn sharedDataDestructor(ptr: *anyopaque, allocator: std.mem.Allocator) void {
    const shared = @as(*concurrency.PHPSharedData, @ptrCast(@alignCast(ptr)));
    shared.deinit();
    allocator.destroy(shared);
}

pub fn sharedDataConstructor(vm: anytype, args: []Value) !Value {
    _ = args;

    const shared = try vm.allocator.create(concurrency.PHPSharedData);
    shared.* = concurrency.PHPSharedData.init(vm.allocator);

    const class = vm.classes.get("SharedData").?;
    const box = try vm.memory_manager.allocObject(class);
    const obj = box.data;
    obj.native_data = @ptrCast(shared);

    return Value.fromBox(box, Value.TYPE_OBJECT);
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
        if (args.len < 1 or args[0].getTag() != .integer) return error.InvalidArgument;
        atomic.store(args[0].asInt());
        return Value.initNull();
    } else if (std.mem.eql(u8, method_name, "increment")) {
        const result = atomic.increment();
        return Value.initInt(result);
    } else if (std.mem.eql(u8, method_name, "decrement")) {
        const result = atomic.decrement();
        return Value.initInt(result);
    } else if (std.mem.eql(u8, method_name, "add")) {
        if (args.len < 1 or args[0].getTag() != .integer) return error.InvalidArgument;
        const result = atomic.add(args[0].asInt());
        return Value.initInt(result);
    } else if (std.mem.eql(u8, method_name, "sub")) {
        if (args.len < 1 or args[0].getTag() != .integer) return error.InvalidArgument;
        const result = atomic.sub(args[0].asInt());
        return Value.initInt(result);
    } else if (std.mem.eql(u8, method_name, "swap")) {
        if (args.len < 1 or args[0].getTag() != .integer) return error.InvalidArgument;
        const old_value = atomic.swap(args[0].asInt());
        return Value.initInt(old_value);
    } else if (std.mem.eql(u8, method_name, "compareAndSwap")) {
        if (args.len < 2 or args[0].getTag() != .integer or args[1].getTag() != .integer) return error.InvalidArgument;
        const success = atomic.compareAndSwap(args[0].asInt(), args[1].asInt());
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
        if (args.len < 2 or args[0].getTag() != .string) return error.InvalidArgument;

        const key = args[0].getAsString().data.data;
        try shared.set(key, args[1]);
        return Value.initNull();
    } else if (std.mem.eql(u8, method_name, "get")) {
        if (args.len < 1 or args[0].getTag() != .string) return error.InvalidArgument;

        const key = args[0].getAsString().data.data;
        if (shared.get(key)) |value| {
            return value;
        }
        return Value.initNull();
    } else if (std.mem.eql(u8, method_name, "remove")) {
        if (args.len < 1 or args[0].getTag() != .string) return error.InvalidArgument;

        const key = args[0].getAsString().data.data;
        const result = shared.remove(key);
        return Value.initBool(result);
    } else if (std.mem.eql(u8, method_name, "has")) {
        if (args.len < 1 or args[0].getTag() != .string) return error.InvalidArgument;

        const key = args[0].getAsString().data.data;
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
    defer name_str.release(vm.allocator);
    const channel_class = try vm.allocator.create(types.PHPClass);
    channel_class.* = try types.PHPClass.init(vm.allocator, name_str);
    channel_class.native_destructor = channelDestructor;

    try vm.classes.put("Channel", channel_class);
    try vm.defineBuiltin("Channel", channelConstructor);
}

fn channelDestructor(ptr: *anyopaque, allocator: std.mem.Allocator) void {
    const channel = @as(*concurrency.PHPChannel, @ptrCast(@alignCast(ptr)));
    channel.deinit();
    allocator.destroy(channel);
}

pub fn channelConstructor(vm: anytype, args: []Value) !Value {
    const capacity: usize = if (args.len > 0 and args[0].getTag() == .integer)
        @intCast(@max(0, args[0].asInt()))
    else
        0;

    const channel = try vm.allocator.create(concurrency.PHPChannel);
    channel.* = concurrency.PHPChannel.init(vm.allocator, capacity);

    const class = vm.classes.get("Channel").?;
    const box = try vm.memory_manager.allocObject(class);
    const obj = box.data;
    obj.native_data = @ptrCast(channel);

    return Value.fromBox(box, Value.TYPE_OBJECT);
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
