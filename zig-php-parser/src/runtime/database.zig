const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const PHPString = types.PHPString;
const PHPArray = types.PHPArray;
const PHPObject = types.PHPObject;
const PHPClass = types.PHPClass;
const gc = types.gc;

/// PDO数据库抽象层
/// 提供统一的数据库访问接口
pub const PDO = struct {
    allocator: std.mem.Allocator,
    driver: Driver,
    connection: ?*Connection,
    in_transaction: bool,
    error_mode: ErrorMode,
    last_error: ?PDOError,
    attributes: std.StringHashMap(Value),

    pub const Driver = enum {
        mysql,
        sqlite,
        pgsql,

        pub fn fromString(str: []const u8) ?Driver {
            if (std.mem.eql(u8, str, "mysql")) return .mysql;
            if (std.mem.eql(u8, str, "sqlite")) return .sqlite;
            if (std.mem.eql(u8, str, "pgsql")) return .pgsql;
            return null;
        }
    };

    pub const ErrorMode = enum {
        silent,
        warning,
        exception,
    };

    pub const PDOError = struct {
        code: []const u8,
        message: []const u8,
        driver_code: i32,
    };

    pub fn init(allocator: std.mem.Allocator, dsn: []const u8, username: ?[]const u8, password: ?[]const u8) !PDO {
        // 解析DSN
        const parsed_dsn = try parseDSN(allocator, dsn);

        var pdo = PDO{
            .allocator = allocator,
            .driver = parsed_dsn.driver,
            .connection = null,
            .in_transaction = false,
            .error_mode = .exception,
            .last_error = null,
            .attributes = std.StringHashMap(Value).init(allocator),
        };

        // 建立连接
        try pdo.connect(parsed_dsn, username, password);

        return pdo;
    }

    pub fn deinit(self: *PDO) void {
        if (self.connection) |conn| {
            conn.close();
            self.allocator.destroy(conn);
        }
        self.attributes.deinit();
    }

    pub fn connect(self: *PDO, dsn: ParsedDSN, username: ?[]const u8, password: ?[]const u8) !void {
        self.connection = try self.allocator.create(Connection);
        self.connection.?.* = try Connection.init(self.allocator, self.driver, dsn, username, password);
    }

    /// 执行SQL查询
    pub fn query(self: *PDO, sql: []const u8) !?*PDOStatement {
        if (self.connection == null) {
            return error.NotConnected;
        }

        const stmt = try self.allocator.create(PDOStatement);
        stmt.* = try PDOStatement.init(self.allocator, self.connection.?, sql);

        // Execute the query
        try stmt.execute(&[_]Value{});

        return stmt;
    }

    /// 执行SQL语句（无结果集）
    pub fn exec(self: *PDO, sql: []const u8) !i64 {
        if (self.connection == null) {
            return error.NotConnected;
        }

        return try self.connection.?.exec(sql);
    }

    /// 准备SQL语句
    pub fn prepare(self: *PDO, sql: []const u8) !*PDOStatement {
        if (self.connection == null) {
            return error.NotConnected;
        }

        const stmt = try self.allocator.create(PDOStatement);
        stmt.* = try PDOStatement.init(self.allocator, self.connection.?, sql);

        return stmt;
    }

    /// 开始事务
    pub fn beginTransaction(self: *PDO) !bool {
        if (self.in_transaction) {
            return false; // Already in transaction
        }

        _ = try self.exec("BEGIN");
        self.in_transaction = true;
        return true;
    }

    /// 提交事务
    pub fn commit(self: *PDO) !bool {
        if (!self.in_transaction) {
            return false; // Not in transaction
        }

        _ = try self.exec("COMMIT");
        self.in_transaction = false;
        return true;
    }

    /// 回滚事务
    pub fn rollBack(self: *PDO) !bool {
        if (!self.in_transaction) {
            return false; // Not in transaction
        }

        _ = try self.exec("ROLLBACK");
        self.in_transaction = false;
        return true;
    }

    /// 获取最后插入ID
    pub fn lastInsertId(self: *PDO) !i64 {
        if (self.connection == null) {
            return error.NotConnected;
        }
        return self.connection.?.last_insert_id;
    }

    /// 转义字符串
    pub fn quote(self: *PDO, string: []const u8) ![]const u8 {
        // 简单的转义实现
        var result = std.ArrayList(u8).init(self.allocator);
        try result.append('\'');

        for (string) |c| {
            if (c == '\'') {
                try result.appendSlice("''");
            } else if (c == '\\') {
                try result.appendSlice("\\\\");
            } else {
                try result.append(c);
            }
        }

        try result.append('\'');
        return result.toOwnedSlice();
    }

    /// 设置属性
    pub fn setAttribute(self: *PDO, attribute: []const u8, value: Value) !void {
        try self.attributes.put(attribute, value);

        // 处理特殊属性
        if (std.mem.eql(u8, attribute, "ATTR_ERRMODE")) {
            if (value.tag == .integer) {
                self.error_mode = @enumFromInt(@as(u2, @intCast(value.data.integer)));
            }
        }
    }

    /// 获取属性
    pub fn getAttribute(self: *PDO, attribute: []const u8) ?Value {
        return self.attributes.get(attribute);
    }

    /// 获取错误信息
    pub fn errorInfo(self: *PDO) [3]?[]const u8 {
        if (self.last_error) |err| {
            return .{ err.code, err.message, null };
        }
        return .{ null, null, null };
    }

    /// 获取错误代码
    pub fn errorCode(self: *PDO) ?[]const u8 {
        if (self.last_error) |err| {
            return err.code;
        }
        return null;
    }
};

/// PDO语句
pub const PDOStatement = struct {
    allocator: std.mem.Allocator,
    connection: *Connection,
    sql: []const u8,
    bound_params: std.StringHashMap(Value),
    result_set: ?*ResultSet,
    fetch_mode: FetchMode,
    column_count: usize,
    row_count: i64,

    pub const FetchMode = enum {
        both,
        assoc,
        num,
        obj,
        column,
        class,
        lazy,
    };

    pub fn init(allocator: std.mem.Allocator, connection: *Connection, sql: []const u8) !PDOStatement {
        return PDOStatement{
            .allocator = allocator,
            .connection = connection,
            .sql = try allocator.dupe(u8, sql),
            .bound_params = std.StringHashMap(Value).init(allocator),
            .result_set = null,
            .fetch_mode = .both,
            .column_count = 0,
            .row_count = 0,
        };
    }

    pub fn deinit(self: *PDOStatement) void {
        self.allocator.free(self.sql);

        var iter = self.bound_params.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.release(self.allocator);
        }
        self.bound_params.deinit();

        if (self.result_set) |rs| {
            rs.deinit();
            self.allocator.destroy(rs);
        }
    }

    /// 绑定参数
    pub fn bindParam(self: *PDOStatement, param: []const u8, value: Value) !void {
        if (self.bound_params.get(param)) |old_value| {
            old_value.release(self.allocator);
        }
        try self.bound_params.put(param, value.retain());
    }

    /// 绑定值
    pub fn bindValue(self: *PDOStatement, param: []const u8, value: Value) !void {
        try self.bindParam(param, value);
    }

    /// 执行语句
    pub fn execute(self: *PDOStatement, params: []const Value) !bool {
        // Bind positional parameters if provided
        for (params, 0..) |param, i| {
            const key = try std.fmt.allocPrint(self.allocator, "{d}", .{i + 1});
            defer self.allocator.free(key);
            try self.bindParam(key, param);
        }

        // Build final SQL with bound parameters
        const final_sql = try self.buildSQL();
        defer self.allocator.free(final_sql);

        // Execute query
        self.result_set = try self.connection.executeQuery(final_sql);
        if (self.result_set) |rs| {
            self.column_count = rs.column_count;
            self.row_count = rs.row_count;
        }

        return true;
    }

    fn buildSQL(self: *PDOStatement) ![]const u8 {
        var result = std.ArrayList(u8).init(self.allocator);
        var i: usize = 0;
        var param_index: usize = 1;

        while (i < self.sql.len) {
            if (self.sql[i] == '?') {
                // 位置参数
                const key = try std.fmt.allocPrint(self.allocator, "{d}", .{param_index});
                defer self.allocator.free(key);

                if (self.bound_params.get(key)) |value| {
                    const str = try self.valueToSQL(value);
                    defer self.allocator.free(str);
                    try result.appendSlice(str);
                }
                param_index += 1;
            } else if (self.sql[i] == ':') {
                // 命名参数
                var j = i + 1;
                while (j < self.sql.len and (std.ascii.isAlphanumeric(self.sql[j]) or self.sql[j] == '_')) {
                    j += 1;
                }
                const param_name = self.sql[i + 1 .. j];

                if (self.bound_params.get(param_name)) |value| {
                    const str = try self.valueToSQL(value);
                    defer self.allocator.free(str);
                    try result.appendSlice(str);
                }
                i = j;
                continue;
            } else {
                try result.append(self.sql[i]);
            }
            i += 1;
        }

        return result.toOwnedSlice();
    }

    fn valueToSQL(self: *PDOStatement, value: Value) ![]const u8 {
        return switch (value.tag) {
            .null => try self.allocator.dupe(u8, "NULL"),
            .boolean => try self.allocator.dupe(u8, if (value.data.boolean) "1" else "0"),
            .integer => try std.fmt.allocPrint(self.allocator, "{d}", .{value.data.integer}),
            .float => try std.fmt.allocPrint(self.allocator, "{d}", .{value.data.float}),
            .string => try std.fmt.allocPrint(self.allocator, "'{s}'", .{value.data.string.data.data}),
            else => try self.allocator.dupe(u8, "NULL"),
        };
    }

    /// 获取下一行
    pub fn fetch(self: *PDOStatement) !?Value {
        if (self.result_set == null) {
            return null;
        }

        const row = self.result_set.?.fetchRow() orelse return null;

        return switch (self.fetch_mode) {
            .assoc => try self.rowToAssocArray(row),
            .num => try self.rowToNumArray(row),
            .both => try self.rowToBothArray(row),
            .obj => try self.rowToObject(row),
            else => try self.rowToAssocArray(row),
        };
    }

    /// 获取所有行
    pub fn fetchAll(self: *PDOStatement) !Value {
        const result = try Value.initArray(self.allocator);
        const arr = result.data.array.data;

        // Reset result set to beginning
        if (self.result_set) |rs| {
            rs.reset();
        }

        while (try self.fetch()) |row| {
            try arr.push(self.allocator, row);
        }

        return result;
    }

    /// 获取单列
    pub fn fetchColumn(self: *PDOStatement, column_number: usize) !?Value {
        if (self.result_set == null) {
            return null;
        }

        const row = self.result_set.?.fetchRow() orelse return null;
        if (column_number < row.values.len) {
            return row.values[column_number];
        }
        return null;
    }

    /// 设置获取模式
    pub fn setFetchMode(self: *PDOStatement, mode: FetchMode) void {
        self.fetch_mode = mode;
    }

    /// 获取列数
    pub fn columnCount(self: *PDOStatement) usize {
        return self.column_count;
    }

    /// 获取影响行数
    pub fn rowCount(self: *PDOStatement) i64 {
        return self.row_count;
    }

    fn rowToAssocArray(self: *PDOStatement, row: *ResultSet.Row) !Value {
        const result = try Value.initArray(self.allocator);
        const arr = result.data.array.data;

        for (row.columns, 0..) |col_name, i| {
            const key = types.ArrayKey{ .string = try PHPString.init(self.allocator, col_name) };
            try arr.set(self.allocator, key, row.values[i]);
        }

        return result;
    }

    fn rowToNumArray(self: *PDOStatement, row: *ResultSet.Row) !Value {
        const result = try Value.initArray(self.allocator);
        const arr = result.data.array.data;

        for (row.values, 0..) |val, i| {
            const key = types.ArrayKey{ .integer = @intCast(i) };
            try arr.set(self.allocator, key, val);
        }

        return result;
    }

    fn rowToBothArray(self: *PDOStatement, row: *ResultSet.Row) !Value {
        const result = try Value.initArray(self.allocator);
        const arr = result.data.array.data;

        for (row.columns, 0..) |col_name, i| {
            // 数字索引
            const num_key = types.ArrayKey{ .integer = @intCast(i) };
            try arr.set(self.allocator, num_key, row.values[i]);

            // 列名索引
            const str_key = types.ArrayKey{ .string = try PHPString.init(self.allocator, col_name) };
            try arr.set(self.allocator, str_key, row.values[i]);
        }

        return result;
    }

    fn rowToObject(self: *PDOStatement, row: *ResultSet.Row) !Value {
        // 创建stdClass对象
        const std_class_name = try PHPString.init(self.allocator, "stdClass");
        var std_class = PHPClass.init(self.allocator, std_class_name);

        const php_object = try self.allocator.create(PHPObject);
        php_object.* = PHPObject.init(self.allocator, &std_class);

        for (row.columns, 0..) |col_name, i| {
            try php_object.setProperty(self.allocator, col_name, row.values[i]);
        }

        const box = try self.allocator.create(gc.Box(*PHPObject));
        box.* = .{
            .ref_count = 1,
            .gc_info = .{},
            .data = php_object,
        };

        return Value{ .tag = .object, .data = .{ .object = box } };
    }
};

/// 数据库连接
pub const Connection = struct {
    allocator: std.mem.Allocator,
    driver: PDO.Driver,
    host: []const u8,
    port: u16,
    database: []const u8,
    username: ?[]const u8,
    password: ?[]const u8,
    connected: bool,
    last_insert_id: i64,
    memory_db: MemoryDatabase,

    pub fn init(allocator: std.mem.Allocator, driver: PDO.Driver, dsn: ParsedDSN, username: ?[]const u8, password: ?[]const u8) !Connection {
        return Connection{
            .allocator = allocator,
            .driver = driver,
            .host = dsn.host,
            .port = dsn.port,
            .database = dsn.database,
            .username = username,
            .password = password,
            .connected = true, // 模拟连接成功
            .last_insert_id = 0,
            .memory_db = MemoryDatabase.init(allocator),
        };
    }

    pub fn close(self: *Connection) void {
        self.memory_db.deinit();
        self.connected = false;
    }

    pub fn exec(self: *Connection, sql: []const u8) !i64 {
        if (!self.connected) {
            return error.NotConnected;
        }

        // Execute SQL on memory database
        const affected_rows = try self.memory_db.executeSQL(sql);
        return affected_rows;
    }

    pub fn executeQuery(self: *Connection, sql: []const u8) !?*ResultSet {
        if (!self.connected) {
            return error.NotConnected;
        }

        // Handle SELECT queries
        if (self.memory_db.executeSelect(sql)) |rs| {
            return rs;
        } else |_| {
            // For non-SELECT queries, just execute and return empty result set
            _ = try self.memory_db.executeSQL(sql);
            const rs = try self.allocator.create(ResultSet);
            rs.* = ResultSet.init(self.allocator);
            return rs;
        }
    }
};

/// 结果集
pub const ResultSet = struct {
    allocator: std.mem.Allocator,
    rows: std.ArrayList(Row),
    columns: [][]const u8,
    current_row: usize,
    column_count: usize,
    row_count: i64,

    pub const Row = struct {
        columns: [][]const u8,
        values: []Value,
    };

    pub fn init(allocator: std.mem.Allocator) ResultSet {
        return ResultSet{
            .allocator = allocator,
            .rows = std.ArrayList(Row).init(allocator),
            .columns = &[_][]const u8{},
            .current_row = 0,
            .column_count = 0,
            .row_count = 0,
        };
    }

    pub fn deinit(self: *ResultSet) void {
        for (self.rows.items) |*row| {
            for (row.values) |*val| {
                val.release(self.allocator);
            }
            self.allocator.free(row.values);
        }
        self.rows.deinit();
    }

    pub fn fetchRow(self: *ResultSet) ?*Row {
        if (self.current_row >= self.rows.items.len) {
            return null;
        }
        const row = &self.rows.items[self.current_row];
        self.current_row += 1;
        return row;
    }

    pub fn reset(self: *ResultSet) void {
        self.current_row = 0;
    }
};

/// 解析DSN
const ParsedDSN = struct {
    driver: PDO.Driver,
    host: []const u8,
    port: u16,
    database: []const u8,
    charset: []const u8,
};

pub fn parseDSN(allocator: std.mem.Allocator, dsn: []const u8) !ParsedDSN {
    var result = ParsedDSN{
        .driver = .mysql,
        .host = "localhost",
        .port = 3306,
        .database = "",
        .charset = "utf8mb4",
    };

    // 解析驱动类型
    if (std.mem.indexOf(u8, dsn, ":")) |colon_pos| {
        const driver_str = dsn[0..colon_pos];
        result.driver = PDO.Driver.fromString(driver_str) orelse .mysql;

        // 解析参数
        const params = dsn[colon_pos + 1 ..];
        var parts = std.mem.splitScalar(u8, params, ';');

        while (parts.next()) |part| {
            if (std.mem.indexOf(u8, part, "=")) |eq_pos| {
                const key = part[0..eq_pos];
                const value = part[eq_pos + 1 ..];

                if (std.mem.eql(u8, key, "host")) {
                    result.host = try allocator.dupe(u8, value);
                } else if (std.mem.eql(u8, key, "port")) {
                    result.port = std.fmt.parseInt(u16, value, 10) catch 3306;
                } else if (std.mem.eql(u8, key, "dbname")) {
                    result.database = try allocator.dupe(u8, value);
                } else if (std.mem.eql(u8, key, "charset")) {
                    result.charset = try allocator.dupe(u8, value);
                }
            }
        }
    }

    return result;
}

/// 内存数据库表
pub const Table = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    columns: std.ArrayList(Column),
    rows: std.ArrayList(Row),
    auto_increment: i64,

    pub const Column = struct {
        name: []const u8,
        type_name: []const u8,
        nullable: bool,
        primary_key: bool,
        auto_increment: bool,
    };

    pub const Row = struct {
        values: std.ArrayList(Value),
    };

    pub fn init(allocator: std.mem.Allocator, name: []const u8) Table {
        return Table{
            .allocator = allocator,
            .name = allocator.dupe(u8, name) catch unreachable,
            .columns = std.ArrayList(Column){},
            .rows = std.ArrayList(Row){},
            .auto_increment = 1,
        };
    }

    pub fn deinit(self: *Table) void {
        self.allocator.free(self.name);
        for (self.columns.items) |*col| {
            self.allocator.free(col.name);
            self.allocator.free(col.type_name);
        }
        self.columns.deinit();

        for (self.rows.items) |*row| {
            for (row.values.items) |*val| {
                val.release(self.allocator);
            }
            row.values.deinit();
        }
        self.rows.deinit();
    }

    pub fn addColumn(self: *Table, name: []const u8, type_name: []const u8, nullable: bool, primary_key: bool, auto_increment: bool) !void {
        const col = Column{
            .name = try self.allocator.dupe(u8, name),
            .type_name = try self.allocator.dupe(u8, type_name),
            .nullable = nullable,
            .primary_key = primary_key,
            .auto_increment = auto_increment,
        };
        try self.columns.append(self.allocator, col);
    }

    pub fn insertRow(self: *Table, values: []Value) !i64 {
        var row = Row{ .values = std.ArrayList(Value){} };

        // Copy values and handle auto-increment
        for (values, 0..) |val, i| {
            if (i < self.columns.items.len and self.columns.items[i].auto_increment) {
                // Auto-increment column
                const auto_val = Value.initInt(self.auto_increment);
                try row.values.append(self.allocator, auto_val);
                self.auto_increment += 1;
            } else {
                try row.values.append(self.allocator, val.retain());
            }
        }

        try self.rows.append(self.allocator, row);
        return @intCast(self.rows.items.len - 1); // Return row index as ID
    }

    pub fn findColumnIndex(self: *Table, column_name: []const u8) ?usize {
        for (self.columns.items, 0..) |col, i| {
            if (std.mem.eql(u8, col.name, column_name)) {
                return i;
            }
        }
        return null;
    }
};

/// 内存数据库
pub const MemoryDatabase = struct {
    allocator: std.mem.Allocator,
    tables: std.StringHashMap(*Table),

    pub fn init(allocator: std.mem.Allocator) MemoryDatabase {
        return MemoryDatabase{
            .allocator = allocator,
            .tables = std.StringHashMap(*Table).init(allocator),
        };
    }

    pub fn deinit(self: *MemoryDatabase) void {
        var iter = self.tables.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.tables.deinit();
    }

    pub fn createTable(self: *MemoryDatabase, table_name: []const u8) !*Table {
        const table = try self.allocator.create(Table);
        table.* = Table.init(self.allocator, table_name);
        try self.tables.put(table_name, table);
        return table;
    }

    pub fn getTable(self: *MemoryDatabase, table_name: []const u8) ?*Table {
        return self.tables.get(table_name);
    }

    pub fn executeSQL(self: *MemoryDatabase, sql: []const u8) !i64 {
        // Simple SQL parser for basic operations
        const trimmed = std.mem.trim(u8, sql, " \t\n\r");

        // Check SQL type - use simple case-insensitive comparison
        const lower_sql = std.ascii.allocLowerString(self.allocator, trimmed) catch return 0;
        defer self.allocator.free(lower_sql);

        if (std.mem.startsWith(u8, lower_sql, "create table")) {
            return try self.executeCreateTable(trimmed);
        } else if (std.mem.startsWith(u8, lower_sql, "insert into")) {
            return try self.executeInsert(trimmed);
        } else if (std.mem.startsWith(u8, lower_sql, "select")) {
            return 0; // SELECT handled separately
        } else if (std.mem.startsWith(u8, lower_sql, "begin") or
            std.mem.startsWith(u8, lower_sql, "commit") or
            std.mem.startsWith(u8, lower_sql, "rollback"))
        {
            return 0; // Transaction commands
        }

        return 0; // Default success
    }

    fn executeCreateTable(self: *MemoryDatabase, sql: []const u8) !i64 {
        // Very basic CREATE TABLE parser
        // Expected format: CREATE TABLE table_name (col1 type, col2 type...)
        var i: usize = "CREATE TABLE ".len;

        // Skip whitespace
        while (i < sql.len and (sql[i] == ' ' or sql[i] == '\t')) i += 1;

        // Parse table name
        const table_name_start = i;
        while (i < sql.len and sql[i] != ' ' and sql[i] != '(') i += 1;
        const table_name = sql[table_name_start..i];

        // Skip to column definitions
        while (i < sql.len and sql[i] != '(') i += 1;
        i += 1; // Skip '('

        const table = try self.createTable(table_name);

        // Parse columns (very simplified)
        var col_start = i;
        while (i < sql.len) {
            if (sql[i] == ',' or sql[i] == ')') {
                const col_def = std.mem.trim(u8, sql[col_start..i], " \t");
                if (col_def.len > 0) {
                    try self.parseColumnDefinition(table, col_def);
                }
                col_start = i + 1;
            }
            if (sql[i] == ')') break;
            i += 1;
        }

        return 0;
    }

    fn parseColumnDefinition(_: *MemoryDatabase, table: *Table, col_def: []const u8) !void {
        var parts = std.mem.splitScalar(u8, col_def, ' ');
        const col_name = parts.next() orelse return;
        const col_type = parts.next() orelse "TEXT";

        // Check for constraints
        var nullable = true;
        var primary_key = false;
        var auto_increment = false;

        while (parts.next()) |constraint| {
            var lower_buf: [64]u8 = undefined;
            const lower_constraint = if (constraint.len <= lower_buf.len)
                std.ascii.lowerString(lower_buf[0..constraint.len], constraint)
            else
                constraint;
            if (std.mem.eql(u8, lower_constraint, "not") and parts.next() != null and std.mem.eql(u8, parts.peek().?, "null")) {
                nullable = false;
            } else if (std.mem.eql(u8, lower_constraint, "primary") and parts.next() != null and std.mem.eql(u8, parts.peek().?, "key")) {
                primary_key = true;
            } else if (std.mem.eql(u8, lower_constraint, "autoincrement") or std.mem.eql(u8, lower_constraint, "auto_increment")) {
                auto_increment = true;
            }
        }

        try table.addColumn(col_name, col_type, nullable, primary_key, auto_increment);
    }

    fn executeInsert(self: *MemoryDatabase, sql: []const u8) !i64 {
        // Very basic INSERT parser
        // Expected format: INSERT INTO table_name VALUES (val1, val2, ...)
        var i: usize = "INSERT INTO ".len;

        // Parse table name
        while (i < sql.len and (sql[i] == ' ' or sql[i] == '\t')) i += 1;
        const table_name_start = i;
        while (i < sql.len and sql[i] != ' ') i += 1;
        const table_name = sql[table_name_start..i];

        const table = self.getTable(table_name) orelse return error.TableNotFound;

        // Skip to VALUES
        // Find VALUES keyword
        while (i < sql.len) : (i += 1) {
            if (i + 6 <= sql.len) {
                var buf: [6]u8 = undefined;
                const lower = std.ascii.lowerString(&buf, sql[i .. i + 6]);
                if (std.mem.eql(u8, lower, "values")) break;
            }
        }
        i += "VALUES".len;

        // Skip to values
        while (i < sql.len and sql[i] != '(') i += 1;
        i += 1; // Skip '('

        // Parse values (simplified - assumes string values)
        var values = std.ArrayList(Value){};
        defer values.deinit(self.allocator);

        var val_start = i;
        var in_string = false;
        var paren_count: i32 = 0;

        while (i < sql.len) {
            if (sql[i] == '\'' and (i == 0 or sql[i - 1] != '\\')) {
                in_string = !in_string;
            } else if (!in_string and sql[i] == '(') {
                paren_count += 1;
            } else if (!in_string and sql[i] == ')') {
                paren_count -= 1;
                if (paren_count < 0) {
                    // End of values
                    const val_str = std.mem.trim(u8, sql[val_start..i], " \t");
                    if (val_str.len > 0) {
                        const value = try self.parseValue(val_str);
                        try values.append(self.allocator, value);
                    }
                    break;
                }
            } else if (!in_string and sql[i] == ',' and paren_count == 0) {
                const val_str = std.mem.trim(u8, sql[val_start..i], " \t");
                if (val_str.len > 0) {
                    const value = try self.parseValue(val_str);
                    try values.append(self.allocator, value);
                }
                val_start = i + 1;
            }
            i += 1;
        }

        const row_id = try table.insertRow(values.items);

        // Clean up values (they were retained by insertRow)
        for (values.items) |*val| {
            val.release(self.allocator);
        }

        return row_id + 1; // Return affected rows
    }

    fn parseValue(self: *MemoryDatabase, value_str: []const u8) !Value {
        const trimmed = std.mem.trim(u8, value_str, " \t");

        // Handle NULL
        var lower_buf: [64]u8 = undefined;
        const lower_trimmed = if (trimmed.len <= lower_buf.len)
            std.ascii.lowerString(lower_buf[0..trimmed.len], trimmed)
        else
            trimmed;
        if (std.mem.eql(u8, lower_trimmed, "null")) {
            return Value.initNull();
        }

        // Handle strings (quoted)
        if (trimmed.len >= 2 and trimmed[0] == '\'' and trimmed[trimmed.len - 1] == '\'') {
            const str_content = trimmed[1 .. trimmed.len - 1];
            return try Value.initString(self.allocator, str_content);
        }

        // Handle integers
        if (std.fmt.parseInt(i64, trimmed, 10)) |int_val| {
            return Value.initInt(int_val);
        } else |_| {}

        // Default to string
        return try Value.initString(self.allocator, trimmed);
    }

    pub fn executeSelect(self: *MemoryDatabase, sql: []const u8) !?*ResultSet {
        // Very basic SELECT parser
        // Expected format: SELECT * FROM table_name
        const trimmed = std.mem.trim(u8, sql, " \t\n\r");

        if (!std.mem.startsWith(u8, std.ascii.lowerString(trimmed, &[_]u8{}), "select")) {
            return null;
        }

        // Find table name after FROM
        const from_pos = std.mem.indexOf(u8, std.ascii.lowerString(trimmed, &[_]u8{}), "from");
        if (from_pos == null) {
            const rs = try self.allocator.create(ResultSet);
            rs.* = ResultSet.init(self.allocator);
            return rs;
        }

        const from_clause = trimmed[from_pos + 4 ..];
        const table_name_end = std.mem.indexOfAny(u8, from_clause, " \t\n\r;") orelse from_clause.len;
        const table_name = std.mem.trim(u8, from_clause[0..table_name_end], " \t\n\r");

        const table = self.getTable(table_name) orelse {
            // Table doesn't exist, return empty result set
            const rs = try self.allocator.create(ResultSet);
            rs.* = ResultSet.init(self.allocator);
            return rs;
        };

        // Create result set with table data
        const rs = try self.allocator.create(ResultSet);
        rs.* = ResultSet.init(self.allocator);

        // Set column names
        rs.columns = try self.allocator.alloc([]const u8, table.columns.items.len);
        rs.column_count = table.columns.items.len;

        for (table.columns.items, 0..) |col, i| {
            rs.columns[i] = try self.allocator.dupe(u8, col.name);
        }

        // Add all rows
        rs.row_count = @intCast(table.rows.items.len);
        for (table.rows.items) |table_row| {
            var result_row = ResultSet.Row{
                .columns = rs.columns,
                .values = try self.allocator.alloc(Value, table_row.values.items.len),
            };

            for (table_row.values.items, 0..) |val, i| {
                result_row.values[i] = val.retain();
            }

            try rs.rows.append(self.allocator, result_row);
        }

        return rs;
    }
};
pub const MySQLi = struct {
    allocator: std.mem.Allocator,
    connection: ?*Connection,
    last_error: ?[]const u8,
    affected_rows: i64,
    insert_id: i64,

    pub fn init(allocator: std.mem.Allocator) MySQLi {
        return MySQLi{
            .allocator = allocator,
            .connection = null,
            .last_error = null,
            .affected_rows = 0,
            .insert_id = 0,
        };
    }

    pub fn deinit(self: *MySQLi) void {
        if (self.connection) |conn| {
            conn.close();
            self.allocator.destroy(conn);
        }
    }

    /// 连接数据库
    pub fn connect(self: *MySQLi, host: []const u8, username: []const u8, password: []const u8, database: []const u8, port: u16) !bool {
        const dsn = ParsedDSN{
            .driver = .mysql,
            .host = host,
            .port = port,
            .database = database,
            .charset = "utf8mb4",
        };

        self.connection = try self.allocator.create(Connection);
        self.connection.?.* = try Connection.init(self.allocator, .mysql, dsn, username, password);

        return true;
    }

    /// 执行查询
    pub fn query(self: *MySQLi, sql: []const u8) !?*MySQLiResult {
        if (self.connection == null) {
            return error.NotConnected;
        }

        const rs = try self.connection.?.executeQuery(sql);
        if (rs) |result_set| {
            const result = try self.allocator.create(MySQLiResult);
            result.* = MySQLiResult{
                .allocator = self.allocator,
                .result_set = result_set,
                .num_rows = result_set.row_count,
                .field_count = result_set.column_count,
            };
            return result;
        }

        return null;
    }

    /// 准备语句
    pub fn prepare(self: *MySQLi, sql: []const u8) !*MySQLiStmt {
        if (self.connection == null) {
            return error.NotConnected;
        }

        const stmt = try self.allocator.create(MySQLiStmt);
        stmt.* = try MySQLiStmt.init(self.allocator, self.connection.?, sql);

        return stmt;
    }

    /// 转义字符串
    pub fn realEscapeString(self: *MySQLi, string: []const u8) ![]const u8 {
        var result = std.ArrayList(u8).init(self.allocator);

        for (string) |c| {
            switch (c) {
                0 => try result.appendSlice("\\0"),
                '\n' => try result.appendSlice("\\n"),
                '\r' => try result.appendSlice("\\r"),
                '\\' => try result.appendSlice("\\\\"),
                '\'' => try result.appendSlice("\\'"),
                '"' => try result.appendSlice("\\\""),
                else => try result.append(c),
            }
        }

        return result.toOwnedSlice();
    }

    /// 关闭连接
    pub fn close(self: *MySQLi) void {
        if (self.connection) |conn| {
            conn.close();
            self.allocator.destroy(conn);
            self.connection = null;
        }
    }
};

/// MySQLi结果集
pub const MySQLiResult = struct {
    allocator: std.mem.Allocator,
    result_set: *ResultSet,
    num_rows: i64,
    field_count: usize,

    pub fn deinit(self: *MySQLiResult) void {
        self.result_set.deinit();
        self.allocator.destroy(self.result_set);
    }

    pub fn fetchAssoc(self: *MySQLiResult) !?Value {
        const row = self.result_set.fetchRow() orelse return null;

        const result = try Value.initArray(self.allocator);
        const arr = result.data.array.data;

        for (row.columns, 0..) |col_name, i| {
            const key = types.ArrayKey{ .string = try PHPString.init(self.allocator, col_name) };
            try arr.set(self.allocator, key, row.values[i]);
        }

        return result;
    }

    pub fn fetchRow(self: *MySQLiResult) !?Value {
        const row = self.result_set.fetchRow() orelse return null;

        const result = try Value.initArray(self.allocator);
        const arr = result.data.array.data;

        for (row.values, 0..) |val, i| {
            const key = types.ArrayKey{ .integer = @intCast(i) };
            try arr.set(self.allocator, key, val);
        }

        return result;
    }

    pub fn fetchAll(self: *MySQLiResult) !Value {
        const result = try Value.initArray(self.allocator);
        const arr = result.data.array.data;

        while (try self.fetchAssoc()) |row| {
            try arr.push(self.allocator, row);
        }

        return result;
    }

    pub fn free(self: *MySQLiResult) void {
        self.deinit();
    }
};

/// MySQLi预处理语句
pub const MySQLiStmt = struct {
    allocator: std.mem.Allocator,
    connection: *Connection,
    sql: []const u8,
    bound_params: std.ArrayList(Value),
    result: ?*MySQLiResult,

    pub fn init(allocator: std.mem.Allocator, connection: *Connection, sql: []const u8) !MySQLiStmt {
        return MySQLiStmt{
            .allocator = allocator,
            .connection = connection,
            .sql = try allocator.dupe(u8, sql),
            .bound_params = std.ArrayList(Value).init(allocator),
            .result = null,
        };
    }

    pub fn deinit(self: *MySQLiStmt) void {
        self.allocator.free(self.sql);
        for (self.bound_params.items) |*param| {
            param.release(self.allocator);
        }
        self.bound_params.deinit();
        if (self.result) |r| {
            r.deinit();
            self.allocator.destroy(r);
        }
    }

    pub fn bindParam(self: *MySQLiStmt, value: Value) !void {
        try self.bound_params.append(value.retain());
    }

    pub fn execute(self: *MySQLiStmt) !bool {
        // 构建SQL并执行
        const rs = try self.connection.executeQuery(self.sql);
        if (rs) |result_set| {
            self.result = try self.allocator.create(MySQLiResult);
            self.result.?.* = MySQLiResult{
                .allocator = self.allocator,
                .result_set = result_set,
                .num_rows = result_set.row_count,
                .field_count = result_set.column_count,
            };
        }
        return true;
    }

    pub fn getResult(self: *MySQLiStmt) ?*MySQLiResult {
        return self.result;
    }

    pub fn close(self: *MySQLiStmt) void {
        self.deinit();
    }
};

test "pdo basic operations" {
    const allocator = std.testing.allocator;

    var pdo = try PDO.init(allocator, "mysql:host=localhost;dbname=test", "root", "password");
    defer pdo.deinit();

    try std.testing.expect(pdo.connection != null);
}
