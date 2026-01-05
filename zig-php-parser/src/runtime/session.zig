const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;

pub const Session = struct {
    id: []const u8,
    data: std.StringHashMap(Value),
    last_access: i64,

    pub fn init(allocator: std.mem.Allocator, id: []const u8) Session {
        return .{
            .id = id,
            .data = std.StringHashMap(Value).init(allocator),
            .last_access = std.time.timestamp(),
        };
    }

    pub fn deinit(self: *Session) void {
        var it = self.data.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.release(self.data.allocator);
        }
        self.data.deinit();
        self.data.allocator.free(self.id);
    }
};

pub const SessionManager = struct {
    allocator: std.mem.Allocator,
    sessions: std.StringHashMap(*Session),
    mutex: std.Thread.Mutex,

    pub fn init(allocator: std.mem.Allocator) SessionManager {
        return .{
            .allocator = allocator,
            .sessions = std.StringHashMap(*Session).init(allocator),
            .mutex = .{},
        };
    }

    pub fn deinit(self: *SessionManager) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var it = self.sessions.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit();
            self.allocator.destroy(entry.value_ptr);
        }
        self.sessions.deinit();
    }

    pub fn createSession(self: *SessionManager) !*Session {
        var random_bytes: [16]u8 = undefined;
        try std.crypto.random.bytes(&random_bytes);

        const id = try std.fmt.allocPrint(self.allocator, "{x}", .{std.fmt.fmtSliceHexLower(&random_bytes)});

        const session = try self.allocator.create(Session);
        session.* = Session.init(self.allocator, id);

        self.mutex.lock();
        defer self.mutex.unlock();
        try self.sessions.put(id, session);

        return session;
    }

    pub fn getSession(self: *SessionManager, id: []const u8) ?*Session {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.sessions.get(id)) |session| {
            session.last_access = std.time.timestamp();
            return session;
        }
        return null;
    }
};
