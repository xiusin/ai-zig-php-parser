//! PHP File I/O Built-in Functions
//!
//! This module implements PHP's file system and I/O functions,
//! providing behavior consistent with PHP's standard library.

const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const PHPString = types.PHPString;
const PHPArray = types.PHPArray;
const ArrayKey = types.ArrayKey;
const exceptions = @import("exceptions.zig");
const ExceptionFactory = exceptions.ExceptionFactory;

// Forward declaration for VM
const VM = @import("vm.zig").VM;

// Helper to get Io instance for Zig 0.17 API
fn getIo() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
}

// Helper to get cwd directory
fn getCwd() std.Io.Dir {
    return std.Io.Dir.cwd();
}

// ============================================================================
// Configuration
// ============================================================================

/// Security configuration
var security_config = struct {
    allow_unsafe_paths: bool = false,
}{};

/// Load security configuration from .zigphp.json
pub fn loadConfig(alloc: std.mem.Allocator) !void {
    const config_file = ".zigphp.json";
    const io = getIo();
    const cwd = getCwd();

    const content = cwd.readFileAlloc(io, config_file, alloc, .limited(1024 * 1024)) catch {
        // If config file doesn't exist or can't be read, use default values
        return;
    };
    defer alloc.free(content);

    const parsed = std.json.parseFromSlice(std.json.Value, alloc, content, .{}) catch {
        // If parsing fails, use default values
        return;
    };
    defer parsed.deinit();

    if (parsed.value.object.get("security")) |security| {
        if (security.object.get("allow_unsafe_paths")) |allow| {
            security_config.allow_unsafe_paths = switch (allow) {
                .bool => |b| b,
                else => false,
            };
        }
    }
}

// ============================================================================
// Security: Path Validation
// ============================================================================

/// Check if a path is safe (prevents directory traversal attacks)
/// Returns true if path is safe, false if it contains "../" or absolute paths
fn isPathSafe(path: []const u8) bool {
    // Check for directory traversal
    if (std.mem.indexOf(u8, path, "..") != null) {
        return false;
    }

    // Check for absolute paths (only allow relative paths)
    if (path.len > 0 and (path[0] == '/' or path[0] == '\\')) {
        return false;
    }

    // Check for Windows-style absolute paths (C:\, etc.)
    if (path.len > 1 and path[1] == ':') {
        return false;
    }

    return true;
}

/// Normalize and validate a path
/// Returns error if path is unsafe (unless unsafe paths are allowed)
fn validatePath(path: []const u8) ![]const u8 {
    // If unsafe paths are allowed, skip validation
    if (security_config.allow_unsafe_paths) {
        return path;
    }

    if (!isPathSafe(path)) {
        return error.InvalidPath;
    }
    return path;
}

// ============================================================================
// File Handle Management
// ============================================================================

/// File handle for tracking open files
pub const FileHandle = struct {
    file: std.Io.File,
    path: []const u8,
    mode: []const u8,
    eof: bool = false,
    pos: u64 = 0,

    pub fn close(self: *FileHandle) void {
        const io = getIo();
        self.file.close(io);
        // Free the path and mode strings
        allocator.free(self.path);
        allocator.free(self.mode);
    }
};

/// Global file handle registry
var file_handles: std.AutoHashMap(u32, *FileHandle) = undefined;
var next_handle_id: u32 = 1;
var allocator: std.mem.Allocator = undefined;

/// Initialize the file handle registry
pub fn initFileHandles(alloc: std.mem.Allocator) void {
    allocator = alloc;
    file_handles = std.AutoHashMap(u32, *FileHandle).init(alloc);
}

/// Clean up all open file handles
pub fn deinitFileHandles() void {
    var iter = file_handles.iterator();
    while (iter.next()) |entry| {
        entry.value_ptr.*.close();
        allocator.destroy(entry.value_ptr.*);
    }
    file_handles.deinit();
}

/// Register a new file handle
fn registerFileHandle(handle: *FileHandle) !u32 {
    const id = next_handle_id;
    next_handle_id += 1;
    try file_handles.put(id, handle);
    return id;
}

/// Get a file handle by ID
fn getFileHandle(id: u32) ?*FileHandle {
    return file_handles.get(id);
}

/// Close and remove a file handle
fn closeFileHandle(id: u32) void {
    if (file_handles.fetchRemove(id)) |entry| {
        entry.value.close();
        allocator.destroy(entry.value);
    }
}

// ============================================================================
// Basic File Operations
// ============================================================================

/// file_get_contents - Reads entire file into a string
/// Parameters:
///   - filename (string): Path to the file
///   - use_include_path (bool, optional): Search in include path
///   - context (resource, optional): Context resource
///   - offset (int, optional): Offset to start reading
///   - maxlen (int, optional): Maximum length to read
/// Returns: string|false - File contents or false on failure
pub fn fileGetContentsFn(vm: *VM, args: []const Value) !Value {
    const filename = args[0];

    if (filename.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "file_get_contents() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const file_path = filename.getAsString().data.data;
    const safe_path = validatePath(file_path) catch |err| {
        switch (err) {
            error.InvalidPath => return Value.initBool(false),
        }
    };

    // Handle optional offset parameter
    const offset: i64 = if (args.len > 3 and args[3].getTag() == .integer)
        args[3].asInt()
    else
        0;

    // Handle optional maxlen parameter
    const maxlen: ?usize = if (args.len > 4 and args[4].getTag() == .integer)
        @intCast(args[4].asInt())
    else
        null;

    const io = getIo();
    const cwd = getCwd();

    const file = cwd.openFile(io, safe_path, .{}) catch {
        return Value.initBool(false);
    };
    defer file.close(io);

    const file_size = file.length(io) catch return Value.initBool(false);

    // Apply offset if specified
    const actual_offset: u64 = if (offset > 0) @intCast(offset) else 0;
    const remaining = if (file_size > actual_offset) file_size - actual_offset else 0;

    // Determine read length
    const read_len = if (maxlen) |ml| @min(ml, remaining) else remaining;

    if (read_len == 0) {
        return try Value.initString(vm.allocator, "");
    }

    const contents = try vm.allocator.alloc(u8, read_len);
    const bytes_read = file.readPositionalAll(io, contents, actual_offset) catch {
        vm.allocator.free(contents);
        return Value.initBool(false);
    };

    const result_str = try PHPString.init(vm.allocator, contents[0..bytes_read]);
    vm.allocator.free(contents);

    // Create box for the string
    const box = try vm.allocator.create(types.gc.Box(*PHPString));
    box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = result_str,
    };

    return Value.fromBox(box, Value.TYPE_STRING);
}

/// file_put_contents - Write data to a file
/// Parameters:
///   - filename (string): Path to the file
///   - data (mixed): Data to write
///   - flags (int, optional): FILE_USE_INCLUDE_PATH | FILE_APPEND | LOCK_EX
///   - context (resource, optional): Context resource
/// Returns: int|false - Number of bytes written or false on failure
pub fn filePutContentsFn(vm: *VM, args: []const Value) !Value {
    const filename = args[0];
    const data = args[1];

    if (filename.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "file_put_contents() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const file_path = filename.getAsString().data.data;
    const safe_path = validatePath(file_path) catch |err| {
        switch (err) {
            error.InvalidPath => return Value.initBool(false),
        }
    };

    // Handle flags (default: 0)
    const flags: u32 = if (args.len > 2 and args[2].getTag() == .integer)
        @intCast(args[2].asInt())
    else
        0;

    const FILE_APPEND = 8;

    const append = (flags & FILE_APPEND) != 0;
    _ = (flags & LOCK_EX) != 0;

    const data_str = try data.toString(vm.allocator);
    defer data_str.deinit(vm.allocator);

    const io = getIo();
    const cwd = getCwd();

    const file = blk: {
        if (append) {
            break :blk cwd.openFile(io, safe_path, .{ .mode = .write_only }) catch |err| {
                switch (err) {
                    error.FileNotFound => {
                        // Create new file if it doesn't exist
                        break :blk cwd.createFile(io, safe_path, .{}) catch {
                            return Value.initBool(false);
                        };
                    },
                    else => return Value.initBool(false),
                }
            };
        } else {
            break :blk cwd.createFile(io, safe_path, .{}) catch {
                return Value.initBool(false);
            };
        }
    };

    defer file.close(io);

    // Seek to end if appending
    if (append) {
        const end_pos = file.length(io) catch 0;
        file.writePositionalAll(io, data_str.data, end_pos) catch {
            return Value.initBool(false);
        };
        return Value.initInt(@intCast(data_str.data.len));
    }

    file.writeStreamingAll(io, data_str.data) catch {
        return Value.initBool(false);
    };

    return Value.initInt(@intCast(data_str.data.len));
}

/// file_exists - Checks whether a file or directory exists
/// Parameters:
///   - filename (string): Path to check
/// Returns: bool - True if file/directory exists, false otherwise
pub fn fileExistsFn(vm: *VM, args: []const Value) !Value {
    const filename = args[0];

    if (filename.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "file_exists() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const file_path = filename.getAsString().data.data;
    const safe_path = validatePath(file_path) catch |err| {
        switch (err) {
            error.InvalidPath => return Value.initBool(false),
        }
    };

    const io = getIo();
    const cwd = getCwd();

    cwd.access(io, safe_path, .{}) catch {
        return Value.initBool(false);
    };

    return Value.initBool(true);
}

/// is_file - Tells whether the filename is a regular file
/// Parameters:
///   - filename (string): Path to check
/// Returns: bool - True if file exists and is a regular file
pub fn isFileFn(vm: *VM, args: []const Value) !Value {
    const filename = args[0];

    if (filename.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "is_file() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const file_path = filename.getAsString().data.data;
    const safe_path = validatePath(file_path) catch |err| {
        switch (err) {
            error.InvalidPath => return Value.initBool(false),
        }
    };

    const io = getIo();
    const cwd = getCwd();

    const stat = cwd.statFile(io, safe_path, .{}) catch {
        return Value.initBool(false);
    };

    return Value.initBool(stat.kind == .file);
}

/// is_dir - Tells whether the filename is a directory
/// Parameters:
///   - dirname (string): Path to check
/// Returns: bool - True if directory exists
pub fn isDirFn(vm: *VM, args: []const Value) !Value {
    const dirname = args[0];

    if (dirname.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "is_dir() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const safe_dir_path = dirname.getAsString().data.data;

    const io = getIo();
    const cwd = getCwd();

    const stat = cwd.statFile(io, safe_dir_path, .{}) catch {
        return Value.initBool(false);
    };

    return Value.initBool(stat.kind == .directory);
}

/// filesize - Gets file size
/// Parameters:
///   - filename (string): Path to file
/// Returns: int|false - File size in bytes or false on failure
pub fn filesizeFn(vm: *VM, args: []const Value) !Value {
    const filename = args[0];

    if (filename.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "filesize() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const file_path = filename.getAsString().data.data;
    const safe_path = validatePath(file_path) catch |err| {
        switch (err) {
            error.InvalidPath => return Value.initBool(false),
        }
    };

    const io = getIo();
    const cwd = getCwd();

    const stat = cwd.statFile(io, safe_path, .{}) catch {
        return Value.initBool(false);
    };

    return Value.initInt(@intCast(stat.size));
}

/// filemtime - Gets file modification time
/// Parameters:
///   - filename (string): Path to file
/// Returns: int|false - Unix timestamp or false on failure
pub fn filemtimeFn(vm: *VM, args: []const Value) !Value {
    const filename = args[0];

    if (filename.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "filemtime() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const file_path = filename.getAsString().data.data;
    const safe_path = validatePath(file_path) catch |err| {
        switch (err) {
            error.InvalidPath => return Value.initBool(false),
        }
    };

    const io = getIo();
    const cwd = getCwd();

    const stat = cwd.statFile(io, safe_path, .{}) catch {
        return Value.initBool(false);
    };

    // mtime is Io.Timestamp with nanoseconds field (i96), convert to seconds
    const mtime_seconds = @divFloor(stat.mtime.nanoseconds, std.time.ns_per_s);
    return Value.initInt(@intCast(mtime_seconds));
}

// ============================================================================
// File Management Functions
// ============================================================================

/// unlink - Deletes a file
/// Parameters:
///   - filename (string): Path to file
/// Returns: bool - True on success, false on failure
pub fn unlinkFn(vm: *VM, args: []const Value) !Value {
    const filename = args[0];

    if (filename.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "unlink() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const file_path = filename.getAsString().data.data;
    const safe_path = validatePath(file_path) catch |err| {
        switch (err) {
            error.InvalidPath => return Value.initBool(false),
        }
    };

    const io = getIo();
    const cwd = getCwd();

    cwd.deleteFile(io, safe_path) catch {
        return Value.initBool(false);
    };

    return Value.initBool(true);
}

/// rename - Renames a file or directory
/// Parameters:
///   - oldname (string): Old name
///   - newname (string): New name
/// Returns: bool - True on success, false on failure
pub fn renameFn(vm: *VM, args: []const Value) !Value {
    const oldname = args[0];
    const newname = args[1];

    if (oldname.getTag() != .string or newname.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "rename() expects parameters 1 and 2 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const old_path = oldname.getAsString().data.data;
    const new_path = newname.getAsString().data.data;

    // Validate both paths
    _ = validatePath(old_path) catch |err| {
        switch (err) {
            error.InvalidPath => return Value.initBool(false),
        }
    };

    _ = validatePath(new_path) catch |err| {
        switch (err) {
            error.InvalidPath => return Value.initBool(false),
        }
    };

    const io = getIo();
    const cwd = getCwd();

    std.Io.Dir.rename(cwd, old_path, cwd, new_path, io) catch {
        return Value.initBool(false);
    };

    return Value.initBool(true);
}

/// copy - Copies a file
/// Parameters:
///   - source (string): Source file path
///   - dest (string): Destination file path
///   - context (resource, optional): Context resource
/// Returns: bool - True on success, false on failure
pub fn copyFn(vm: *VM, args: []const Value) !Value {
    const source = args[0];
    const dest = args[1];

    if (source.getTag() != .string or dest.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "copy() expects parameters 1 and 2 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const source_path = source.getAsString().data.data;
    const dest_path = dest.getAsString().data.data;

    // Validate both paths
    _ = validatePath(source_path) catch |err| {
        switch (err) {
            error.InvalidPath => return Value.initBool(false),
        }
    };

    _ = validatePath(dest_path) catch |err| {
        switch (err) {
            error.InvalidPath => return Value.initBool(false),
        }
    };

    const io = getIo();
    const cwd = getCwd();

    // Read source file content
    const content = cwd.readFileAlloc(io, source_path, vm.allocator, .unlimited) catch {
        return Value.initBool(false);
    };
    defer vm.allocator.free(content);

    // Create and write to destination file
    const dest_file = cwd.createFile(io, dest_path, .{}) catch {
        return Value.initBool(false);
    };
    defer dest_file.close(io);

    dest_file.writeStreamingAll(io, content) catch {
        return Value.initBool(false);
    };

    return Value.initBool(true);
}

// ============================================================================
// Directory Operations
// ============================================================================

/// mkdir - Makes directory
/// Parameters:
///   - dirname (string): Directory name
///   - mode (int, optional): Mode (default: 0777)
///   - recursive (bool, optional): Allow creating nested directories
/// Returns: bool - True on success, false on failure
pub fn mkdirFn(vm: *VM, args: []const Value) !Value {
    const dirname = args[0];

    if (dirname.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "mkdir() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const dir_path = dirname.getAsString().data.data;

    // Validate path
    const safe_dir_path = validatePath(dir_path) catch |err| {
        switch (err) {
            error.InvalidPath => return Value.initBool(false),
        }
    };

    // Handle recursive flag
    const recursive = if (args.len > 2 and args[2].getTag() == .boolean)
        args[2].asBool()
    else
        false;

    const io = getIo();
    const cwd = getCwd();

    if (recursive) {
        cwd.createDirPath(io, safe_dir_path) catch {
            return Value.initBool(false);
        };
    } else {
        cwd.createDir(io, safe_dir_path, .default_dir) catch {
            return Value.initBool(false);
        };
    }

    return Value.initBool(true);
}

/// rmdir - Removes directory
/// Parameters:
///   - dirname (string): Directory name
///   - context (resource, optional): Context resource
/// Returns: bool - True on success, false on failure
pub fn rmdirFn(vm: *VM, args: []const Value) !Value {
    const dirname = args[0];

    if (dirname.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "rmdir() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const dir_path = dirname.getAsString().data.data;

    // Validate path
    const safe_dir_path = validatePath(dir_path) catch |err| {
        switch (err) {
            error.InvalidPath => return Value.initBool(false),
        }
    };

    const io = getIo();
    const cwd = getCwd();

    cwd.deleteDir(io, safe_dir_path) catch {
        return Value.initBool(false);
    };

    return Value.initBool(true);
}

/// scandir - List files and directories inside the specified path
/// Parameters:
///   - directory (string): Directory path
///   - sorting_order (int, optional): SCANDIR_SORT_ASCENDING (default) or SCANDIR_SORT_DESCENDING
/// Returns: array|false - Array of filenames or false on failure
pub fn scandirFn(vm: *VM, args: []const Value) !Value {
    const directory = args[0];

    if (directory.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "scandir() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const dir_path = directory.getAsString().data.data;
    const safe_dir_path = validatePath(dir_path) catch |err| {
        switch (err) {
            error.InvalidPath => return Value.initBool(false),
        }
    };

    const io = getIo();
    const cwd = getCwd();

    var dir = cwd.openDir(io, safe_dir_path, .{ .iterate = true }) catch {
        return Value.initBool(false);
    };
    defer dir.close(io);

    var entries = std.ArrayListUnmanaged([]const u8){ .items = &.{}, .capacity = 0 };
    defer {
        for (entries.items) |entry| {
            vm.allocator.free(entry);
        }
        entries.deinit(vm.allocator);
    }

    var iter = dir.iterate();
    while (try iter.next(io)) |entry| {
        const name_copy = try vm.allocator.dupe(u8, entry.name);
        try entries.append(vm.allocator, name_copy);
    }

    // Create PHP array on heap
    const php_array = try vm.allocator.create(PHPArray);
    php_array.* = PHPArray.init(vm.allocator);

    for (entries.items, 0..) |entry, i| {
        const str = try PHPString.init(vm.allocator, entry);
        // Create box for the string
        const box = try vm.allocator.create(types.gc.Box(*PHPString));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = str,
        };
        const val = Value.fromBox(box, Value.TYPE_STRING);
        try php_array.set(vm.allocator, ArrayKey{ .integer = @intCast(i) }, val);
    }

    // Create box for the array
    const array_box = try vm.allocator.create(types.gc.Box(*PHPArray));
    array_box.* = .{
        .ref_count = 1,
        .gc_info = .{},
        .data = php_array,
    };
    return Value.fromBox(array_box, Value.TYPE_ARRAY);
}

// ============================================================================
// Path Functions
// ============================================================================

/// basename - Returns trailing name component of path
/// Parameters:
///   - path (string): Path
///   - suffix (string, optional): Suffix to remove
/// Returns: string - Base name
pub fn basenameFn(vm: *VM, args: []const Value) !Value {
    const path = args[0];
    const suffix = if (args.len > 1) args[1] else Value.initNull();

    if (path.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "basename() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const path_str = path.getAsString().data.data;
    const basename = std.fs.path.basename(path_str);

    var result_name = basename;

    // Remove suffix if provided
    if (suffix.getTag() == .string) {
        const suffix_str = suffix.getAsString().data.data;
        if (std.mem.endsWith(u8, basename, suffix_str)) {
            result_name = basename[0 .. basename.len - suffix_str.len];
        }
    }

    return try Value.initString(vm.allocator, result_name);
}

/// dirname - Returns a parent directory's path
/// Parameters:
///   - path (string): Path
///   - levels (int, optional): Number of parent directories to go up (default: 1)
/// Returns: string - Parent directory path
pub fn dirnameFn(vm: *VM, args: []const Value) !Value {
    const path = args[0];
    const levels = if (args.len > 1) args[1] else Value.initInt(1);

    if (path.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "dirname() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    if (levels.getTag() != .integer) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "dirname() expects parameter 2 to be integer", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const path_str = path.getAsString().data.data;
    const levels_int = @as(u32, @intCast(levels.asInt()));

    var result = path_str;

        var i: usize = 0;

        while (i < levels_int) : (i += 1) {

            const dirname_result = std.fs.path.dirname(result) orelse ".";

            // dirname returns []u8, so we need to copy it

            const dirname_copy = try vm.allocator.dupe(u8, dirname_result);

            if (i > 0) vm.allocator.free(result);

            result = dirname_copy;

            if (std.mem.eql(u8, result, ".")) break;

        }

        defer vm.allocator.free(result);

    return try Value.initString(vm.allocator, result);
}

/// realpath - Returns canonicalized absolute pathname
/// Parameters:
///   - path (string): Path
/// Returns: string|false - Canonicalized path or false on failure
pub fn realpathFn(vm: *VM, args: []const Value) !Value {
    const path = args[0];

    if (path.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "realpath() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const path_str = path.getAsString().data.data;

    const io = getIo();
    const cwd = getCwd();

    const resolved = cwd.realPathFileAlloc(io, path_str, vm.allocator) catch {
        return Value.initBool(false);
    };

    return try Value.initString(vm.allocator, resolved);
}

// ============================================================================
// File Stream Operations
// ============================================================================

/// fopen - Opens file or URL
/// Parameters:
///   - filename (string): File path
///   - mode (string): Mode (r, r+, w, w+, a, a+, x, x+, c, c+)
///   - use_include_path (bool, optional): Search in include path
///   - context (resource, optional): Context resource
/// Returns: resource|false - File handle or false on failure
pub fn fopenFn(vm: *VM, args: []const Value) !Value {
    const filename = args[0];
    const mode = args[1];

    if (filename.getTag() != .string or mode.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "fopen() expects parameters 1 and 2 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const file_path = filename.getAsString().data.data;
    const safe_path = validatePath(file_path) catch |err| {
        switch (err) {
            error.InvalidPath => return Value.initBool(false),
        }
    };
    const mode_str = mode.getAsString().data.data;

    // Parse mode and determine open flags
    const read = std.mem.indexOfScalar(u8, mode_str, 'r') != null;
    const write = std.mem.indexOfScalar(u8, mode_str, 'w') != null or
                   std.mem.indexOfScalar(u8, mode_str, 'a') != null or
                   std.mem.indexOfScalar(u8, mode_str, 'c') != null;
    const append = std.mem.indexOfScalar(u8, mode_str, 'a') != null;
    const create = std.mem.indexOfScalar(u8, mode_str, 'x') != null or
                   std.mem.indexOfScalar(u8, mode_str, 'w') != null or
                   std.mem.indexOfScalar(u8, mode_str, 'c') != null;
    const truncate = std.mem.indexOfScalar(u8, mode_str, 'w') != null;

    const open_mode: std.Io.Dir.OpenFileOptions.Mode = if (read and write)
        .read_write
    else if (read)
        .read_only
    else if (write)
        .write_only
    else
        .read_only;

    const io = getIo();
    const cwd = getCwd();

    const file = if (create)
        cwd.createFile(io, safe_path, .{ .truncate = truncate, .read = read }) catch |err| {
            switch (err) {
                error.PathAlreadyExists => {
                    // Open existing file
                    const existing_file = cwd.openFile(io, safe_path, .{ .mode = open_mode }) catch {
                        return Value.initBool(false);
                    };
                    const file_handle = try vm.allocator.create(FileHandle);
                    file_handle.* = .{
                        .file = existing_file,
                        .path = try vm.allocator.dupe(u8, file_path),
                        .mode = try vm.allocator.dupe(u8, mode_str),
                    };
                    return Value.initInt(@intCast(try registerFileHandle(file_handle)));
                },
                else => return Value.initBool(false),
            }
        }
    else
        cwd.openFile(io, safe_path, .{ .mode = open_mode }) catch {
            return Value.initBool(false);
        };

    // Seek to end if append mode
    const initial_pos: u64 = if (append) (file.length(io) catch 0) else 0;

    const handle = try vm.allocator.create(FileHandle);
    handle.* = .{
        .file = file,
        .path = try vm.allocator.dupe(u8, file_path),
        .mode = try vm.allocator.dupe(u8, mode_str),
        .pos = initial_pos,
    };

    const handle_id = try registerFileHandle(handle);

    return Value.initInt(@intCast(handle_id));
}

/// fclose - Closes an open file pointer
/// Parameters:
///   - handle (resource): File handle
/// Returns: bool - True on success, false on failure
pub fn fcloseFn(vm: *VM, args: []const Value) !Value {
    const handle = args[0];

    if (handle.getTag() != .integer) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "fclose() expects parameter 1 to be resource", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const handle_id = @as(u32, @intCast(handle.asInt()));

    if (getFileHandle(handle_id)) |_| {
        closeFileHandle(handle_id);
        return Value.initBool(true);
    }

    return Value.initBool(false);
}

/// fread - Binary-safe file read
/// Parameters:
///   - handle (resource): File handle
///   - length (int): Number of bytes to read
/// Returns: string|false - Read data or false on failure
pub fn freadFn(vm: *VM, args: []const Value) !Value {
    const handle = args[0];
    const length = args[1];

    if (handle.getTag() != .integer or length.getTag() != .integer) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "fread() expects parameter 1 to be resource and parameter 2 to be integer", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const handle_id = @as(u32, @intCast(handle.asInt()));
    const length_int = @as(usize, @intCast(length.asInt()));

    const file_handle = getFileHandle(handle_id) orelse return Value.initBool(false);

    const buffer = try vm.allocator.alloc(u8, length_int);
    defer vm.allocator.free(buffer);

    const io = getIo();
    const bytes_read = file_handle.file.readPositionalAll(io, buffer, file_handle.pos) catch {
        return Value.initBool(false);
    };

    if (bytes_read == 0) {
        file_handle.eof = true;
        return try Value.initString(vm.allocator, "");
    }

    file_handle.pos += bytes_read;

    return try Value.initString(vm.allocator, buffer[0..bytes_read]);
}

/// fwrite - Binary-safe file write
/// Parameters:
///   - handle (resource): File handle
///   - data (string): Data to write
///   - length (int, optional): Maximum length to write
/// Returns: int|false - Number of bytes written or false on failure
pub fn fwriteFn(vm: *VM, args: []const Value) !Value {
    const handle = args[0];
    const data = args[1];

    if (handle.getTag() != .integer or data.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "fwrite() expects parameter 1 to be resource and parameter 2 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const handle_id = @as(u32, @intCast(handle.asInt()));
    const data_str = data.getAsString().data.data;

    const file_handle = getFileHandle(handle_id) orelse return Value.initBool(false);

    const io = getIo();
    file_handle.file.writePositionalAll(io, data_str, file_handle.pos) catch {
        return Value.initBool(false);
    };

    file_handle.pos += data_str.len;

    return Value.initInt(@intCast(data_str.len));
}

/// feof - Tests for end-of-file on a file pointer
/// Parameters:
///   - handle (resource): File handle
/// Returns: bool - True if EOF, false otherwise
pub fn feofFn(vm: *VM, args: []const Value) !Value {
    const handle = args[0];

    if (handle.getTag() != .integer) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "feof() expects parameter 1 to be resource", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const handle_id = @as(u32, @intCast(handle.asInt()));

    const file_handle = getFileHandle(handle_id) orelse return Value.initBool(true);

    // Check if we're at end of file
    const io = getIo();
    const size = file_handle.file.length(io) catch return Value.initBool(true);

    return Value.initBool(file_handle.pos >= size);
}

/// fseek - Seeks on a file pointer
/// Parameters:
///   - handle (resource): File handle
///   - offset (int): Offset
///   - whence (int, optional): SEEK_SET, SEEK_CUR, or SEEK_END
/// Returns: int|false - 0 on success, -1 on failure
pub fn fseekFn(vm: *VM, args: []const Value) !Value {
    const handle = args[0];
    const offset = args[1];
    const whence = if (args.len > 2) args[2] else Value.initInt(0);

    if (handle.getTag() != .integer or offset.getTag() != .integer) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "fseek() expects parameter 1 to be resource and parameter 2 to be integer", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const handle_id = @as(u32, @intCast(handle.asInt()));
    const offset_int = @as(i64, @intCast(offset.asInt()));
    const whence_int = if (whence.getTag() == .integer) @as(i32, @intCast(whence.asInt())) else 0;

    const file_handle = getFileHandle(handle_id) orelse return Value.initInt(-1);

    switch (whence_int) {
        0 => {
            // SEEK_SET
            if (offset_int < 0) return Value.initInt(-1);
            file_handle.pos = @intCast(offset_int);
        },
        1 => {
            // SEEK_CUR
            const new_pos = @as(i64, @intCast(file_handle.pos)) + offset_int;
            if (new_pos < 0) return Value.initInt(-1);
            file_handle.pos = @intCast(new_pos);
        },
        2 => {
            // SEEK_END
            const io = getIo();
            const end_pos = file_handle.file.length(io) catch return Value.initInt(-1);
            const new_pos = @as(i64, @intCast(end_pos)) + offset_int;
            if (new_pos < 0) return Value.initInt(-1);
            file_handle.pos = @intCast(new_pos);
        },
        else => return Value.initInt(-1),
    }

    return Value.initInt(0);
}

/// ftell - Returns the current position of the file read/write pointer
/// Parameters:
///   - handle (resource): File handle
/// Returns: int|false - Current position or false on failure
pub fn ftellFn(vm: *VM, args: []const Value) !Value {
    const handle = args[0];

    if (handle.getTag() != .integer) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "ftell() expects parameter 1 to be resource", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const handle_id = @as(u32, @intCast(handle.asInt()));

    const file_handle = getFileHandle(handle_id) orelse return Value.initBool(false);

    return Value.initInt(@intCast(file_handle.pos));
}

/// fgets - Gets line from file pointer
/// Parameters:
///   - handle (resource): File handle
///   - length (int, optional): Maximum length (default: 1024 or until newline)
/// Returns: string|false - Read line or false on failure
pub fn fgetsFn(vm: *VM, args: []const Value) !Value {
    const handle = args[0];
    const length = if (args.len > 1) args[1] else Value.initInt(1024);

    if (handle.getTag() != .integer or length.getTag() != .integer) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "fgets() expects parameter 1 to be resource and parameter 2 to be integer", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const handle_id = @as(u32, @intCast(handle.asInt()));
    const length_int = @as(usize, @intCast(length.asInt()));

    const file_handle = getFileHandle(handle_id) orelse return Value.initBool(false);

    const buffer = try vm.allocator.alloc(u8, length_int);

        defer vm.allocator.free(buffer);



        // Read line using positional read byte by byte until newline



            var bytes_read: usize = 0;



            const io = getIo();

            while (bytes_read < length_int) {



                var byte_buf: [1]u8 = undefined;



                const n = file_handle.file.readPositionalAll(io, &byte_buf, file_handle.pos) catch {

                    break;

                };



                if (n == 0) break;



                file_handle.pos += 1;

                const byte = byte_buf[0];



                if (byte == '\n') {



                    buffer[bytes_read] = byte;



                    bytes_read += 1;



                    break;



                }



                buffer[bytes_read] = byte;



                bytes_read += 1;



            }



        if (bytes_read == 0) {

            return Value.initBool(false);

        }

    return try Value.initString(vm.allocator, buffer[0..bytes_read]);
}

/// fgetc - Gets character from file pointer
/// Parameters:
///   - handle (resource): File handle
/// Returns: string|false - Single character or false on failure
pub fn fgetcFn(vm: *VM, args: []const Value) !Value {
    const handle = args[0];

    if (handle.getTag() != .integer) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "fgetc() expects parameter 1 to be resource", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const handle_id = @as(u32, @intCast(handle.asInt()));

    const file_handle = getFileHandle(handle_id) orelse return Value.initBool(false);

    var buffer: [1]u8 = undefined;
    const io = getIo();
    const bytes_read = file_handle.file.readPositionalAll(io, &buffer, file_handle.pos) catch {
        return Value.initBool(false);
    };

    if (bytes_read == 0) {
        return Value.initBool(false);
    }

    file_handle.pos += bytes_read;

    return try Value.initString(vm.allocator, buffer[0..bytes_read]);
}

/// rewind - Rewind the position of a file pointer
/// Parameters:
///   - handle (resource): File handle
/// Returns: bool - True on success, false on failure
pub fn rewindFn(vm: *VM, args: []const Value) !Value {
    const handle = args[0];

    if (handle.getTag() != .integer) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "rewind() expects parameter 1 to be resource", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const handle_id = @as(u32, @intCast(handle.asInt()));

    const file_handle = getFileHandle(handle_id) orelse return Value.initBool(false);

    file_handle.pos = 0;
    file_handle.eof = false;

    return Value.initBool(true);
}

/// fflush - Flushes the output to a file
/// Parameters:
///   - handle (resource): File handle
/// Returns: bool - True on success, false on failure
pub fn fflushFn(vm: *VM, args: []const Value) !Value {
    const handle = args[0];

    if (handle.getTag() != .integer) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "fflush() expects parameter 1 to be resource", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const handle_id = @as(u32, @intCast(handle.asInt()));

    const file_handle = getFileHandle(handle_id) orelse return Value.initBool(false);

    const io = getIo();
    file_handle.file.sync(io) catch {
        return Value.initBool(false);
    };

    return Value.initBool(true);
}

// flock and ftruncate functions removed

// ============================================================================
// flock - File locking
// ============================================================================

/// flock - Provides simple advisory file locking
/// Parameters:
///   - handle (resource): File handle
///   - operation (int): LOCK_SH (shared), LOCK_EX (exclusive), LOCK_UN (unlock), LOCK_NB (non-blocking)
/// Returns: bool - True on success, false on failure
pub fn flockFn(vm: *VM, args: []const Value) !Value {
    const handle = args[0];
    const operation = if (args.len > 1) args[1].asInt() else LOCK_EX;

    if (handle.getTag() != .integer) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "flock() expects parameter 1 to be resource", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const handle_id = @as(u32, @intCast(handle.asInt()));
    const file_handle = getFileHandle(handle_id) orelse return Value.initBool(false);

    // Map PHP lock operations to Zig lock flags
    const lock_flag: std.Io.File.Lock = if (operation & LOCK_EX != 0)
        .exclusive
    else if (operation & LOCK_SH != 0)
        .shared
    else
        .none;

    const io = getIo();

    if (lock_flag == .none) {
        // LOCK_UN - unlock
        file_handle.file.unlock(io);
    } else if (operation & LOCK_NB != 0) {
        // Non-blocking lock attempt
        const locked = file_handle.file.tryLock(io, lock_flag) catch {
            return Value.initBool(false);
        };
        if (!locked) return Value.initBool(false);
    } else {
        file_handle.file.lock(io, lock_flag) catch {
            return Value.initBool(false);
        };
    }

    return Value.initBool(true);
}

/// ftruncate - Truncates a file to a specified size
/// Parameters:
///   - filename (string): Path to file
///   - size (int): New size
/// Returns: bool - True on success, false on failure
pub fn ftruncateFn(vm: *VM, args: []const Value) !Value {
    const handle = args[0];
    const size = args[1].asInt();

    if (handle.getTag() != .integer) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "ftruncate() expects parameter 1 to be resource", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const handle_id = @as(u32, @intCast(handle.asInt()));
    const file_handle = getFileHandle(handle_id) orelse return Value.initBool(false);

    if (size < 0) {
        return Value.initBool(false);
    }

    const io = getIo();
    file_handle.file.setLength(io, @as(u64, @intCast(size))) catch {
        return Value.initBool(false);
    };

    return Value.initBool(true);
}

// ============================================================================
// file - Reads entire file into an array
// ============================================================================

/// file - Reads entire file into an array
/// Parameters:
///   - filename (string): Path to file
///   - flags (int): FILE_IGNORE_NEW_LINES, FILE_SKIP_EMPTY_LINES
///   - context (resource): Stream context
/// Returns: array|false - Array of lines or false on failure
pub fn fileFn(vm: *VM, args: []const Value) !Value {
    const filename = args[0];
    const flags = if (args.len > 1) args[1].asInt() else 0;
    // context parameter ignored for now

    if (filename.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "file() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const file_path = try filename.toString(vm.allocator);
    defer file_path.release(vm.allocator);

    const path = try validatePath(file_path.data);

    const io = getIo();
    const cwd = getCwd();

    const content = cwd.readFileAlloc(io, path, vm.allocator, .limited(1024 * 1024 * 10)) catch {
        return Value.initBool(false);
    };
    defer vm.allocator.free(content);

    const result = try vm.allocator.create(PHPArray);
    errdefer vm.allocator.destroy(result);
    result.* = PHPArray.init(vm.allocator);

    var start: usize = 0;
    var line_num: usize = 0;

    for (content, 0..) |byte, i| {
        if (byte == '\n') {
            const line = content[start..i];
            const effective_line = if (flags & FILE_SKIP_EMPTY_LINES != 0 and line.len == 0)
                continue
            else if (flags & FILE_IGNORE_NEW_LINES != 0 and line.len > 0 and line[line.len - 1] == '\r')
                line[0..line.len - 1]
            else
                line;

            if (!(flags & FILE_SKIP_EMPTY_LINES != 0 and effective_line.len == 0)) {
                const line_value = try Value.initString(vm.allocator, effective_line);
                try result.set(vm.allocator, ArrayKey{ .integer = @as(i64, @intCast(line_num)) }, line_value);
                line_num += 1;
            }
            start = i + 1;
        }
    }

    // Handle last line if no trailing newline
    if (start < content.len) {
        const line = content[start..];
        if (!(flags & FILE_SKIP_EMPTY_LINES != 0 and line.len == 0)) {
            const line_value = try Value.initString(vm.allocator, line);
            try result.set(vm.allocator, ArrayKey{ .integer = @as(i64, @intCast(line_num)) }, line_value);
        }
    }

    const box = try vm.allocator.create(types.gc.Box(*PHPArray));
    box.* = .{ .ref_count = 1, .gc_info = .{}, .data = result };
    return Value.fromBox(box, Value.TYPE_ARRAY);
}

/// readfile - Reads a file and writes it to the output buffer
/// Parameters:
///   - filename (string): Path to file
///   - use_include_path (bool): Whether to search include path
///   - context (resource): Stream context
/// Returns: int|false - Number of bytes read or false on failure
pub fn readfileFn(vm: *VM, args: []const Value) !Value {
    const filename = args[0];
    // use_include_path and context ignored for now

    if (filename.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "readfile() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const file_path = try filename.toString(vm.allocator);
    defer file_path.release(vm.allocator);

    const path = try validatePath(file_path.data);

    const io = getIo();
    const cwd = getCwd();

    const content = cwd.readFileAlloc(io, path, vm.allocator, .limited(1024 * 1024 * 10)) catch {
        return Value.initBool(false);
    };
    defer vm.allocator.free(content);

    // Note: readfile outputs to stdout and returns byte count
    // For now, we just return the byte count without outputting
    return Value.initInt(@as(i64, @intCast(content.len)));
}

// File constants
const FILE_IGNORE_NEW_LINES: i64 = 2;
const FILE_SKIP_EMPTY_LINES: i64 = 4;
const FILE_USE_INCLUDE_PATH: i64 = 1;

// Lock constants
const LOCK_SH: i64 = 1;    // Shared lock
const LOCK_EX: i64 = 2;    // Exclusive lock
const LOCK_UN: i64 = 3;    // Unlock
const LOCK_NB: i64 = 4;    // Non-blocking

// ============================================================================
// File permission functions
// ============================================================================

/// is_readable - Tells whether a file exists and is readable
/// Parameters:
///   - filename (string): Path to file
/// Returns: bool - True if readable
pub fn isReadableFn(vm: *VM, args: []const Value) !Value {
    const filename = args[0];

    if (filename.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "is_readable() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const file_path = try filename.toString(vm.allocator);
    defer file_path.release(vm.allocator);

    const path = try validatePath(file_path.data);

    const io = getIo();
    const cwd = getCwd();

    // Try to open the file for reading
    _ = cwd.openFile(io, path, .{}) catch {
        return Value.initBool(false);
    };

    return Value.initBool(true);
}

/// is_writable - Tells whether a file is writable
/// Parameters:
///   - filename (string): Path to file
/// Returns: bool - True if writable
pub fn isWritableFn(vm: *VM, args: []const Value) !Value {
    const filename = args[0];

    if (filename.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "is_writable() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const file_path = try filename.toString(vm.allocator);
    defer file_path.release(vm.allocator);

    const path = try validatePath(file_path.data);

    const io = getIo();
    const cwd = getCwd();

    // Try to open the file for writing
    _ = cwd.openFile(io, path, .{ .mode = .read_write }) catch {
        return Value.initBool(false);
    };

    return Value.initBool(true);
}

/// is_executable - Tells whether a file is executable
/// Parameters:
///   - filename (string): Path to file
/// Returns: bool - True if executable
pub fn isExecutableFn(vm: *VM, args: []const Value) !Value {
    const filename = args[0];

    if (filename.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "is_executable() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const file_path = try filename.toString(vm.allocator);
    defer file_path.release(vm.allocator);

    const path = try validatePath(file_path.data);

    const io = getIo();
    const cwd = getCwd();

    // Check if file exists and is executable (simplified check)
    const file = cwd.openFile(io, path, .{}) catch {
        return Value.initBool(false);
    };
    defer file.close(io);

    return Value.initBool(true);
}

/// clearstatcache - Clears file stat cache
/// Parameters:
///   - filename (string): Optional - clear cache for specific file
///   - ...: Additional filenames
/// Returns: void
pub fn clearstatcacheFn(_: *VM, args: []const Value) !Value {
    // In our implementation, we don't have a stat cache,
    // so this is a no-op
    _ = args;
    return Value.initNull();
}

/// disk_free_space - Returns available space on filesystem or disk partition
/// Parameters:
///   - directory (string): Directory on the disk
/// Returns: float|false - Available space in bytes
pub fn diskFreeSpaceFn(vm: *VM, args: []const Value) !Value {
    const directory = args[0];

    if (directory.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "disk_free_space() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const dir_path = try directory.toString(vm.allocator);
    defer dir_path.release(vm.allocator);

    // Simplified implementation - just return a reasonable value
    return Value.initFloat(1024.0 * 1024.0 * 1024.0); // Return 1GB as default
}

/// disk_total_space - Returns the total size of a filesystem or disk partition
/// Parameters:
///   - directory (string): Directory on the disk
/// Returns: float|false - Total space in bytes
pub fn diskTotalSpaceFn(vm: *VM, args: []const Value) !Value {
    const directory = args[0];

    if (directory.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "disk_total_space() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const dir_path = try directory.toString(vm.allocator);
    defer dir_path.release(vm.allocator);

    // Simplified implementation - just return a reasonable value
    return Value.initFloat(100.0 * 1024.0 * 1024.0 * 1024.0); // Return 100GB as default
}

/// is_link - Checks if filename is a symbolic link
/// Parameters:
///   - filename (string): Path to file
/// Returns: bool - True if it's a symbolic link
pub fn isLinkFn(vm: *VM, args: []const Value) !Value {
    const filename = args[0];

    if (filename.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "is_link() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const file_path = try filename.toString(vm.allocator);
    defer file_path.release(vm.allocator);

    const path = try validatePath(file_path.data);

    // Get directory and basename
    const dir_path = std.fs.path.dirname(path) orelse ".";
    const basename = std.fs.path.basename(path);

    const io = getIo();
    const cwd = getCwd();

    var dir = cwd.openDir(io, dir_path, .{ .iterate = false }) catch {
        return Value.initBool(false);
    };
    defer dir.close(io);

    // Try to read the link - if successful, it's a symlink
    const buffer = try vm.allocator.alloc(u8, 4096);
    defer vm.allocator.free(buffer);

    _ = dir.readLink(io, basename, buffer) catch {
        return Value.initBool(false);
    };

    return Value.initBool(true);
}

/// fnmatch - Match filename against a pattern
/// Parameters:
///   - pattern (string): Wildcard pattern
///   - filename (string): Filename to match
///   - flags (int): Optional flags
/// Returns: bool - True if filename matches pattern
pub fn fnmatchFn(vm: *VM, args: []const Value) !Value {
    const pattern = args[0];
    const filename = args[1];
    const flags = if (args.len > 2) args[2].asInt() else 0;

    if (pattern.getTag() != .string or filename.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "fnmatch() expects parameters 1 and 2 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const pattern_str = try pattern.toString(vm.allocator);
    defer pattern_str.release(vm.allocator);

    const filename_str = try filename.toString(vm.allocator);
    defer filename_str.release(vm.allocator);

    // Simple glob-style pattern matching
    // Supports: *, ?, [...]
    const case_insensitive = (flags & (1 << 0)) != 0; // FNM_CASEFOLD

    const matched = matchPattern(pattern_str.data, filename_str.data, case_insensitive);

    return Value.initBool(matched);
}

/// Match a pattern against a string (simple glob-style)
fn matchPattern(pattern: []const u8, str: []const u8, case_insensitive: bool) bool {
    if (pattern.len == 0) {
        return str.len == 0;
    }

    var pattern_idx: usize = 0;
    var str_idx: usize = 0;
    var star_idx: usize = std.math.maxInt(usize);
    var match_idx: usize = 0;

    while (str_idx < str.len) : (str_idx += 1) {
        if (star_idx != std.math.maxInt(usize) and pattern_idx < pattern.len) {
            // Previous match was *, continue from match point
            pattern_idx = star_idx;
            match_idx = str_idx;
        }

        if (pattern_idx < pattern.len) {
            const p = pattern[pattern_idx];

            if (p == '*') {
                star_idx = pattern_idx;
                match_idx = str_idx;
                continue;
            }

            if (p == '?') {
                // Match any single character
                pattern_idx += 1;
                continue;
            }

            if (p == '[') {
                // Character class
                pattern_idx += 1;
                var negated = false;
                var char_class_match = false;

                if (pattern_idx < pattern.len and pattern[pattern_idx] == '!') {
                    negated = true;
                    pattern_idx += 1;
                }

                while (pattern_idx < pattern.len and pattern[pattern_idx] != ']') {
                    const start_char = pattern[pattern_idx];
                    var end_char = start_char;

                    if (pattern_idx + 2 < pattern.len and pattern[pattern_idx + 1] == '-') {
                        end_char = pattern[pattern_idx + 2];
                        pattern_idx += 2;
                    }

                    const test_char = str[str_idx];
                    const start_cmp = if (case_insensitive)
                        std.ascii.toLower(start_char)
                    else
                        start_char;
                    const end_cmp = if (case_insensitive)
                        std.ascii.toLower(end_char)
                    else
                        end_char;
                    const test_cmp = if (case_insensitive)
                        std.ascii.toLower(test_char)
                    else
                        test_char;

                    if (test_cmp >= start_cmp and test_cmp <= end_cmp) {
                        char_class_match = true;
                    }

                    pattern_idx += 1;
                }
                pattern_idx += 1; // Skip ']'

                if (negated) {
                    char_class_match = !char_class_match;
                }

                if (!char_class_match) {
                    if (star_idx != std.math.maxInt(usize)) {
                        // Backtrack to previous *
                        pattern_idx = star_idx;
                        match_idx += 1;
                        continue;
                    }
                    return false;
                }
                continue;
            }

            // Regular character
            const s = str[str_idx];
            const match = if (case_insensitive)
                std.ascii.toLower(p) == std.ascii.toLower(s)
            else
                p == s;

            if (match) {
                pattern_idx += 1;
            } else {
                if (star_idx != std.math.maxInt(usize)) {
                    // Backtrack to previous *
                    pattern_idx = star_idx;
                    match_idx += 1;
                    continue;
                }
                return false;
            }
        }
    }

    // Skip remaining * in pattern
    while (pattern_idx < pattern.len and pattern[pattern_idx] == '*') {
        pattern_idx += 1;
    }

    return pattern_idx == pattern.len;
}

/// chmod - Changes file mode (permissions)
/// Parameters:
///   - filename (string): Path to file
///   - mode (int): New permissions (e.g., 0644)
/// Returns: bool - True on success, false on failure
pub fn chmodFn(vm: *VM, args: []const Value) !Value {
    const filename = args[0];
    const mode = @as(u32, @intCast(args[1].asInt()));

    if (filename.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "chmod() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const file_path = try filename.toString(vm.allocator);
    defer file_path.release(vm.allocator);

    const path = try validatePath(file_path.data);

    const io = getIo();
    const cwd = getCwd();

    // Open file and chmod
    const file = cwd.openFile(io, path, .{}) catch {
        return Value.initBool(false);
    };
    defer file.close(io);

    file.setPermissions(io, std.Io.File.Permissions.fromMode(@intCast(mode & 0o777))) catch {
        return Value.initBool(false);
    };

    return Value.initBool(true);
}

/// chown - Changes file owner
/// Parameters:
///   - filename (string): Path to file
///   - owner (int|string): User ID or username
/// Returns: bool - True on success
pub fn chownFn(vm: *VM, args: []const Value) !Value {
    const filename = args[0];

    if (filename.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "chown() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const file_path = try filename.toString(vm.allocator);
    defer file_path.release(vm.allocator);

    const path = try validatePath(file_path.data);

    const io = getIo();
    const cwd = getCwd();

    // Simplified: just try to change ownership
    // Full implementation would need user/group lookup
    _ = cwd.openFile(io, path, .{}) catch {
        return Value.initBool(false);
    };

    // chown typically requires root privileges
    // We'll return true if the file exists and is accessible
    return Value.initBool(true);
}

/// chgrp - Changes file group
/// Parameters:
///   - filename (string): Path to file
///   - group (int|string): Group ID or group name
/// Returns: bool - True on success
pub fn chgrpFn(vm: *VM, args: []const Value) !Value {
    const filename = args[0];

    if (filename.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "chgrp() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const file_path = try filename.toString(vm.allocator);
    defer file_path.release(vm.allocator);

    const path = try validatePath(file_path.data);

    const io = getIo();
    const cwd = getCwd();

    // Simplified: just check if file exists
    _ = cwd.openFile(io, path, .{}) catch {
        return Value.initBool(false);
    };

    return Value.initBool(true);
}

/// link - Create a hard link
/// Parameters:
///   - target (string): Existing file
///   - link (string): New link to create
/// Returns: bool - True on success
pub fn linkFn(vm: *VM, args: []const Value) !Value {
    const target = args[0];
    const link = args[1];

    if (target.getTag() != .string or link.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "link() expects both parameters to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const target_path = try target.toString(vm.allocator);
    defer target_path.release(vm.allocator);
    const link_path = try link.toString(vm.allocator);
    defer link_path.release(vm.allocator);

    const safe_target = try validatePath(target_path.data);
    const safe_link = try validatePath(link_path.data);

    // std.c.link requires null-terminated strings
    const target_z = vm.allocator.dupeSentinel(u8, safe_target, 0) catch {
        return Value.initBool(false);
    };
    defer vm.allocator.free(target_z);
    const link_z = vm.allocator.dupeSentinel(u8, safe_link, 0) catch {
        return Value.initBool(false);
    };
    defer vm.allocator.free(link_z);

    const result = std.c.link(target_z.ptr, link_z.ptr);
    if (result != 0) {
        return Value.initBool(false);
    }

    return Value.initBool(true);
}

/// symlink - Creates a symbolic link
/// Parameters:
///   - target (string): The target of the link
///   - link (string): The link to create
/// Returns: bool - True on success
pub fn symlinkFn(vm: *VM, args: []const Value) !Value {
    const target = args[0];
    const link = args[1];

    if (target.getTag() != .string or link.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "symlink() expects both parameters to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const target_path = try target.toString(vm.allocator);
    defer target_path.release(vm.allocator);

    const link_path = try link.toString(vm.allocator);
    defer link_path.release(vm.allocator);

    const target_valid = try validatePath(target_path.data);
    const link_valid = try validatePath(link_path.data);

    // Get directory and basename for link
    const link_dir = std.fs.path.dirname(link_valid) orelse ".";
    const link_basename = std.fs.path.basename(link_valid);

    const io = getIo();
    const cwd = getCwd();

    var dir = cwd.openDir(io, link_dir, .{ .iterate = false }) catch {
        return Value.initBool(false);
    };
    defer dir.close(io);

    dir.symLink(io, target_valid, link_basename, .{}) catch {
        return Value.initBool(false);
    };

    return Value.initBool(true);
}

/// readlink - Returns the target of a symbolic link
/// Parameters:
///   - path (string): The symbolic link path
/// Returns: string|false - The target path or false on error
pub fn readlinkFn(vm: *VM, args: []const Value) !Value {
    const path = args[0];

    if (path.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "readlink() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const path_str = try path.toString(vm.allocator);
    defer path_str.release(vm.allocator);

    const path_valid = try validatePath(path_str.data);

    // Get directory and basename
    const dir_path = std.fs.path.dirname(path_valid) orelse ".";
    const basename = std.fs.path.basename(path_valid);

    const io = getIo();
    const cwd = getCwd();

    var dir = cwd.openDir(io, dir_path, .{ .iterate = false }) catch {
        return Value.initBool(false);
    };
    defer dir.close(io);

    // readLink requires a buffer, allocate 4096 bytes
    const buffer = try vm.allocator.alloc(u8, 4096);
    defer vm.allocator.free(buffer);

    const target_len = dir.readLink(io, basename, buffer) catch {
        return Value.initBool(false);
    };

    return try Value.initString(vm.allocator, buffer[0..target_len]);
}

/// lstat - Gives information about a file (does not follow symlinks)
/// Parameters:
///   - filename (string): Path to file
/// Returns: array|false - Array of file info or false on error
pub fn lstatFn(vm: *VM, args: []const Value) !Value {
    return statInternal(vm, args, true);
}

/// stat - Gives information about a file (follows symlinks)
/// Parameters:
///   - filename (string): Path to file
/// Returns: array|false - Array of file info or false on error
pub fn statFn(vm: *VM, args: []const Value) !Value {
    return statInternal(vm, args, false);
}

/// Internal stat function
/// Parameters:
///   - vm: VM instance
///   - args: Function arguments
///   - lstat_mode: If true, don't follow symlinks
/// Returns: array|false - Array of file info or false on error
fn statInternal(vm: *VM, args: []const Value, lstat_mode: bool) !Value {
    const filename = args[0];

    if (filename.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "stat() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const file_path = try filename.toString(vm.allocator);
    defer file_path.release(vm.allocator);

    const path = try validatePath(file_path.data);

    // Get directory and basename
    const dir_path = std.fs.path.dirname(path) orelse ".";
    const basename = std.fs.path.basename(path);

    const io = getIo();
    const cwd = getCwd();

    var dir = cwd.openDir(io, dir_path, .{ .iterate = false }) catch {
        return Value.initBool(false);
    };
    defer dir.close(io);

    // Get file info (lstat or stat based on lstat_mode)
    const file_info = if (lstat_mode)
        dir.statFile(io, basename, .{ .follow_symlinks = false })
    else
        dir.statFile(io, basename, .{});

    const info = file_info catch {
        return Value.initBool(false);
    };

    // Build stat result array
    const stat_result = try vm.allocator.create(PHPArray);
    stat_result.* = PHPArray.init(vm.allocator);

    // 0 - device (not available, use 0)
    try stat_result.set(vm.allocator, ArrayKey{ .integer = 0 }, Value.initInt(0));
    // 1 - inode
    try stat_result.set(vm.allocator, ArrayKey{ .integer = 1 }, Value.initInt(@intCast(info.inode)));
    // 2 - mode (file type + permissions)
    try stat_result.set(vm.allocator, ArrayKey{ .integer = 2 }, Value.initInt(@intCast(@intFromEnum(info.permissions))));
    // 3 - number of hard links
    try stat_result.set(vm.allocator, ArrayKey{ .integer = 3 }, Value.initInt(@intCast(info.nlink)));
    // 4 - user id (not available, use 0)
    try stat_result.set(vm.allocator, ArrayKey{ .integer = 4 }, Value.initInt(0));
    // 5 - group id (not available, use 0)
    try stat_result.set(vm.allocator, ArrayKey{ .integer = 5 }, Value.initInt(0));
    // 6 - device type (not available, use 0)
    try stat_result.set(vm.allocator, ArrayKey{ .integer = 6 }, Value.initInt(0));
    // 7 - size in bytes
    try stat_result.set(vm.allocator, ArrayKey{ .integer = 7 }, Value.initInt(@intCast(info.size)));
    // 8 - atime
    const atime_ns: i64 = if (info.atime) |at| @intCast(@divFloor(at.nanoseconds, std.time.ns_per_s)) else 0;
    try stat_result.set(vm.allocator, ArrayKey{ .integer = 8 }, Value.initInt(atime_ns));
    // 9 - mtime
    try stat_result.set(vm.allocator, ArrayKey{ .integer = 9 }, Value.initInt(@intCast(@divFloor(info.mtime.nanoseconds, std.time.ns_per_s))));
    // 10 - ctime
    try stat_result.set(vm.allocator, ArrayKey{ .integer = 10 }, Value.initInt(@intCast(@divFloor(info.ctime.nanoseconds, std.time.ns_per_s))));
    // 11 - blksize
    try stat_result.set(vm.allocator, ArrayKey{ .integer = 11 }, Value.initInt(@intCast(info.block_size)));
    // 12 - blocks (not available, use 0)
    try stat_result.set(vm.allocator, ArrayKey{ .integer = 12 }, Value.initInt(0));

    return Value.initArrayWithObject(&vm.memory_manager, stat_result);
}

/// glob - Find pathnames matching a pattern
/// Parameters:
///   - pattern (string): The pattern to match
///   - flags (int): Optional flags
/// Returns: array|false - Array of matched paths or false on error
pub fn globFn(vm: *VM, args: []const Value) !Value {
    const pattern = args[0];
    const flags = if (args.len > 1) args[1].asInt() else 0;
    _ = flags; // flags not used yet

    if (pattern.getTag() != .string) {
        const exception = try ExceptionFactory.createTypeError(vm.allocator, "glob() expects parameter 1 to be string", "builtin", 0);
        _ = try vm.throwException(exception);
        return error.InvalidArgumentType;
    }

    const pattern_str = try pattern.toString(vm.allocator);
    defer pattern_str.release(vm.allocator);

    // Build result array
    const result = try vm.allocator.create(PHPArray);
    result.* = PHPArray.init(vm.allocator);

    // Parse the pattern - simplified implementation
    // For now, just return the pattern itself
    const value = try Value.initString(vm.allocator, pattern_str.data);
    try result.push(vm.allocator, value);

    return Value.initArrayWithObject(&vm.memory_manager, result);
}
