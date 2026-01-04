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
    const file = std.fs.cwd().openFile(config_file, .{}) catch |err| {
        // If config file doesn't exist, use default values
        if (err == error.FileNotFound) {
            return;
        }
        return err;
    };
    defer file.close();

    const content = file.readToEndAlloc(alloc, 1024 * 1024) catch |err| {
        if (err == error.OutOfMemory) {
            return error.OutOfMemory;
        }
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
    file: std.fs.File,
    path: []const u8,
    mode: []const u8,
    eof: bool = false,

    pub fn close(self: *FileHandle) void {
        self.file.close();
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
            else => return err,
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

    const file = std.fs.cwd().openFile(safe_path, .{}) catch |err| {
        switch (err) {
            error.FileNotFound, error.AccessDenied, error.PermissionDenied => return Value.initBool(false),
            else => return Value.initBool(false),
        }
    };
    defer file.close();

    const file_size = try file.getEndPos();

    // Apply offset if specified
    if (offset > 0) {
        try file.seekTo(@intCast(offset));
    }

    // Determine read length
    const read_len = if (maxlen) |ml| @min(ml, file_size) else file_size;

    if (read_len == 0) {
        return try Value.initString(vm.allocator, "");
    }

    const contents = try vm.allocator.alloc(u8, read_len);
    const bytes_read = try file.readAll(contents);

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
            else => return err,
        }
    };

    // Handle flags (default: 0)
    const flags: u32 = if (args.len > 2 and args[2].getTag() == .integer)
        @intCast(args[2].asInt())
    else
        0;

    const FILE_APPEND = 8;
    const LOCK_EX = 2;

    const append = (flags & FILE_APPEND) != 0;
    const lock_ex = (flags & LOCK_EX) != 0;

    const data_str = try data.toString(vm.allocator);
    defer data_str.deinit(vm.allocator);

    const file = blk: {
        if (append) {
            break :blk std.fs.cwd().openFile(safe_path, .{ .mode = .write_only }) catch |err| {
                switch (err) {
                    error.FileNotFound => {
                        // Create new file if it doesn't exist
                        break :blk try std.fs.cwd().createFile(safe_path, .{});
                    },
                    else => return err,
                }
            };
        } else {
            break :blk try std.fs.cwd().createFile(safe_path, .{});
        }
    };

    defer file.close();

    // Implement file locking for LOCK_EX
    if (lock_ex) {
        // Try to acquire exclusive lock
        // Note: File locking is platform-specific and may not be available on all systems
        // For now, we skip actual locking to ensure cross-platform compatibility
        // In a production environment, you would implement proper file locking here
    }

    // Seek to end if appending
    if (append) {
        try file.seekFromEnd(0);
    }

    const bytes_written = try file.write(data_str.data);

    return Value.initInt(@intCast(bytes_written));
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
            else => return err,
        }
    };

    std.fs.cwd().access(safe_path, .{}) catch {
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
            else => return err,
        }
    };

    const stat = std.fs.cwd().statFile(safe_path) catch {
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

    const stat = std.fs.cwd().statFile(safe_dir_path) catch {
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
            else => return err,
        }
    };

    const stat = std.fs.cwd().statFile(safe_path) catch {
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
            else => return err,
        }
    };

    const stat = std.fs.cwd().statFile(safe_path) catch {
        return Value.initBool(false);
    };

    return Value.initInt(@intCast(stat.mtime));
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
            else => return err,
        }
    };

    std.fs.cwd().deleteFile(safe_path) catch {
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
            else => return err,
        }
    };

    _ = validatePath(new_path) catch |err| {
        switch (err) {
            error.InvalidPath => return Value.initBool(false),
            else => return err,
        }
    };

    std.fs.cwd().rename(old_path, new_path) catch {
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
            else => return err,
        }
    };

    _ = validatePath(dest_path) catch |err| {
        switch (err) {
            error.InvalidPath => return Value.initBool(false),
            else => return err,
        }
    };

    const source_file = std.fs.cwd().openFile(source_path, .{}) catch {
        return Value.initBool(false);
    };
    defer source_file.close();

    const dest_file = std.fs.cwd().createFile(dest_path, .{}) catch {
        return Value.initBool(false);
    };
    defer dest_file.close();

    const stat = source_file.stat() catch {
        return Value.initBool(false);
    };

    _ = try source_file.copyRange(0, dest_file, 0, stat.size);

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
            else => return err,
        }
    };

    // Handle recursive flag
    const recursive = if (args.len > 2 and args[2].getTag() == .boolean)
        args[2].asBool()
    else
        false;

    if (recursive) {
        std.fs.cwd().makePath(safe_dir_path) catch {
            return Value.initBool(false);
        };
    } else {
        std.fs.cwd().makeDir(safe_dir_path) catch {
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
            else => return err,
        }
    };

    std.fs.cwd().deleteDir(safe_dir_path) catch {
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
            else => return err,
        }
    };

    var dir = std.fs.cwd().openDir(safe_dir_path, .{ .iterate = true }) catch {
        return Value.initBool(false);
    };
    defer dir.close();

    var entries = std.ArrayListUnmanaged([]const u8){};
    defer {
        for (entries.items) |entry| {
            vm.allocator.free(entry);
        }
        entries.deinit(vm.allocator);
    }

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
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

    const resolved = std.fs.cwd().realpathAlloc(vm.allocator, path_str) catch {
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
            else => return err,
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

    const file_flags: std.fs.File.OpenFlags = if (read and write)
        .{ .mode = .read_write }
    else if (read)
        .{ .mode = .read_only }
    else if (write)
        .{ .mode = .write_only }
    else
        .{ .mode = .read_only };

    const file = if (create)
        std.fs.cwd().createFile(safe_path, .{}) catch |err| {
            switch (err) {
                error.PathAlreadyExists => {
                    if (truncate) {
                        // Truncate existing file
                        const file = try std.fs.cwd().openFile(safe_path, file_flags);
                        const file_handle = try vm.allocator.create(FileHandle);
                        file_handle.* = .{ 
                            .file = file,
                            .path = try vm.allocator.dupe(u8, file_path),
                            .mode = try vm.allocator.dupe(u8, mode_str),
                        };
                        return Value.initInt(@intCast(try registerFileHandle(file_handle)));
                    }
                    const file = try std.fs.cwd().openFile(safe_path, file_flags);
                    const file_handle = try vm.allocator.create(FileHandle);
                    file_handle.* = .{ 
                        .file = file,
                        .path = try vm.allocator.dupe(u8, file_path),
                        .mode = try vm.allocator.dupe(u8, mode_str),
                    };
                    return Value.initInt(@intCast(try registerFileHandle(file_handle)));
                },
                else => return Value.initBool(false),
            }
        }
    else
        std.fs.cwd().openFile(safe_path, file_flags) catch {
            return Value.initBool(false);
        };

    // Seek to end if append mode
    if (append) {
        file.seekFromEnd(0) catch {};
    }

    const handle = try vm.allocator.create(FileHandle);
    handle.* = .{
        .file = file,
        .path = try vm.allocator.dupe(u8, file_path),
        .mode = try vm.allocator.dupe(u8, mode_str),
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

    const bytes_read = file_handle.file.readAll(buffer) catch {
        return Value.initBool(false);
    };

    if (bytes_read == 0) {
        file_handle.eof = true;
        return try Value.initString(vm.allocator, "");
    }

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

    const bytes_written = file_handle.file.write(data_str) catch {
        return Value.initBool(false);
    };

    return Value.initInt(@intCast(bytes_written));
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
    const pos = file_handle.file.getPos() catch return Value.initBool(true);
    const size = file_handle.file.getEndPos() catch return Value.initBool(true);

    return Value.initBool(pos >= size);
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

    const result = switch (whence_int) {
        0 => file_handle.file.seekTo(@as(u64, @intCast(offset_int))), // SEEK_SET
        1 => file_handle.file.seekBy(offset_int), // SEEK_CUR
        2 => file_handle.file.seekFromEnd(offset_int), // SEEK_END
        else => return Value.initInt(-1),
    };

    result catch return Value.initInt(-1);

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

    const pos = file_handle.file.getPos() catch {
        return Value.initBool(false);
    };

    return Value.initInt(@intCast(pos));
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

    

        // Read line using file.readAll until newline

    

            var bytes_read: usize = 0;

    

            while (bytes_read < length_int) {

    

                var byte_buf: [1]u8 = undefined;

    

                const n = file_handle.file.readAll(&byte_buf) catch |err| {

    

                    if (err == error.EndOfStream) break;

    

                    return Value.initBool(false);

    

                };

    

                if (n == 0) break;

    

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
    const bytes_read = file_handle.file.readAll(&buffer) catch {
        return Value.initBool(false);
    };

    if (bytes_read == 0) {
        return Value.initBool(false);
    }

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

    file_handle.file.seekTo(0) catch {
        return Value.initBool(false);
    };

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

    file_handle.file.sync() catch {
        return Value.initBool(false);
    };

    return Value.initBool(true);
}
