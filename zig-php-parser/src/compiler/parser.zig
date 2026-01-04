const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const SyntaxMode = @import("syntax_mode.zig").SyntaxMode;
const SyntaxConfig = @import("syntax_mode.zig").SyntaxConfig;
const Token = @import("token.zig").Token;
const ast = @import("ast.zig");
pub const PHPContext = @import("root.zig").PHPContext;
const extension_api = @import("../extension/api.zig");

/// Syntax hooks interface for extension system
/// Allows extensions to hook into the parsing process for custom syntax
pub const SyntaxHooks = extension_api.SyntaxHooks;

pub const Parser = struct {
    lexer: Lexer,
    allocator: std.mem.Allocator,
    context: *PHPContext,
    curr: Token,
    peek: Token,
    syntax_mode: SyntaxMode = .php,
    /// Syntax hooks for extension system (optional)
    syntax_hooks: ?*const SyntaxHooks = null,

    pub fn init(allocator: std.mem.Allocator, context: *PHPContext, source: [:0]const u8) anyerror!Parser {
        var lexer = Lexer.init(source);
        const curr = lexer.next();
        const peek = lexer.next();
        return Parser{
            .lexer = lexer,
            .allocator = allocator,
            .context = context,
            .curr = curr,
            .peek = peek,
        };
    }

    pub fn initWithMode(allocator: std.mem.Allocator, context: *PHPContext, source: [:0]const u8, mode: SyntaxMode) anyerror!Parser {
        var lexer = Lexer.initWithMode(source, mode);
        const curr = lexer.next();
        const peek = lexer.next();
        return Parser{
            .lexer = lexer,
            .allocator = allocator,
            .context = context,
            .curr = curr,
            .peek = peek,
            .syntax_mode = mode,
        };
    }

    /// Initialize parser with syntax mode and syntax hooks
    pub fn initWithModeAndHooks(allocator: std.mem.Allocator, context: *PHPContext, source: [:0]const u8, mode: SyntaxMode, hooks: ?*const SyntaxHooks) anyerror!Parser {
        var lexer = Lexer.initWithMode(source, mode);
        const curr = lexer.next();
        const peek = lexer.next();
        return Parser{
            .lexer = lexer,
            .allocator = allocator,
            .context = context,
            .curr = curr,
            .peek = peek,
            .syntax_mode = mode,
            .syntax_hooks = hooks,
        };
    }

    /// Set syntax hooks after initialization
    pub fn setSyntaxHooks(self: *Parser, hooks: ?*const SyntaxHooks) void {
        self.syntax_hooks = hooks;
    }

    /// Check if a token is a custom keyword registered by extensions
    pub fn isCustomKeyword(self: *Parser, token_text: []const u8) bool {
        if (self.syntax_hooks) |hooks| {
            for (hooks.custom_keywords) |keyword| {
                if (std.mem.eql(u8, token_text, keyword)) {
                    return true;
                }
            }
        }
        return false;
    }

    pub fn deinit(self: *Parser) void {
        _ = self;
    }

    fn nextToken(self: *Parser) void {
        self.curr = self.peek;
        self.peek = self.lexer.next();
    }

    fn reportError(self: *Parser, msg: []const u8) void {
        const err = @import("root.zig").Error{
            .msg = self.context.arena.allocator().dupe(u8, msg) catch msg,
            .line = 0,
            .column = 0,
        };
        self.context.errors.append(self.allocator, err) catch {};
    }

    fn eat(self: *Parser, tag: Token.Tag) anyerror!Token {
        if (self.curr.tag == tag) {
            const t = self.curr;
            self.nextToken();
            return t;
        }
        self.reportError("Unexpected Token");
        return error.UnexpectedToken;
    }

    fn synchronize(self: *Parser) void {
        self.nextToken();
        while (self.curr.tag != .eof) {
            if (self.curr.tag == .semicolon) {
                self.nextToken();
                return;
            }
            switch (self.curr.tag) {
                .k_class, .k_interface, .k_trait, .k_enum, .k_function, .k_fn, .k_if, .k_for, .k_while, .k_foreach, .k_return, .k_namespace, .k_use, .k_try, .k_throw, .k_match, .k_switch => return,
                else => self.nextToken(),
            }
        }
    }

    fn recoverFromError(self: *Parser, expected: []const Token.Tag) void {
        // Enhanced error recovery - try to find a recovery point
        var recovery_attempts: u8 = 0;
        const max_recovery_attempts = 10;

        while (self.curr.tag != .eof and recovery_attempts < max_recovery_attempts) {
            // Check if current token is one of the expected tokens
            for (expected) |exp_tag| {
                if (self.curr.tag == exp_tag) return;
            }

            // Check for statement boundaries
            switch (self.curr.tag) {
                .semicolon => {
                    self.nextToken();
                    return;
                },
                .r_brace => {
                    // Don't consume the closing brace, let the caller handle it
                    return;
                },
                .k_class, .k_interface, .k_trait, .k_enum, .k_function, .k_fn, .k_if, .k_for, .k_while, .k_foreach, .k_return, .k_namespace, .k_use, .k_try, .k_throw, .k_match, .k_switch => {
                    // Found a statement start, stop here
                    return;
                },
                else => {
                    self.nextToken();
                    recovery_attempts += 1;
                },
            }
        }
    }

    pub fn parse(self: *Parser) anyerror!ast.Node.Index {
        var stmts = std.ArrayListUnmanaged(ast.Node.Index){};
        defer stmts.deinit(self.allocator);

        while (self.curr.tag != .eof) {
            if (self.curr.tag == .t_open_tag or self.curr.tag == .t_close_tag or self.curr.tag == .t_inline_html) {
                self.nextToken();
                continue;
            }
            const stmt = self.parseStatement() catch |err| {
                std.debug.print("DEBUG: parseStatement failed with error: {any} at token: {any} ({s})\n", .{ err, self.curr.tag, self.lexer.buffer[self.curr.loc.start..self.curr.loc.end] });
                self.synchronize();
                continue;
            };
            try stmts.append(self.allocator, stmt);
        }
        const arena = self.context.arena.allocator();
        return self.createNode(.{
            .tag = .root,
            .main_token = .{ .tag = .t_open_tag, .loc = .{ .start = 0, .end = 0 } },
            .data = .{ .root = .{ .stmts = try arena.dupe(ast.Node.Index, stmts.items) } },
        });
    }

    fn parseStatement(self: *Parser) anyerror!ast.Node.Index {
        var attributes: []const ast.Node.Index = &.{};
        if (self.curr.tag == .t_attribute_start) attributes = try self.parseAttributes();

        // Check syntax hooks first for custom statement parsing
        if (self.syntax_hooks) |hooks| {
            if (hooks.parse_statement) |parse_stmt_hook| {
                // Pass current token tag as u32 to the hook
                const token_tag: u32 = @intFromEnum(self.curr.tag);
                const hook_result = parse_stmt_hook(@ptrCast(self), token_tag) catch null;
                if (hook_result) |result| {
                    // Hook handled the statement, return the result
                    return result;
                }
                // Hook returned null, fall through to default parsing
            }
        }

        // Check for custom keywords registered by extensions
        if (self.curr.tag == .t_string or self.curr.tag == .t_go_identifier) {
            const token_text = self.lexer.buffer[self.curr.loc.start..self.curr.loc.end];
            if (self.isCustomKeyword(token_text)) {
                // Custom keyword found, try syntax hook
                if (self.syntax_hooks) |hooks| {
                    if (hooks.parse_statement) |parse_stmt_hook| {
                        const token_tag: u32 = @intFromEnum(self.curr.tag);
                        const hook_result = parse_stmt_hook(@ptrCast(self), token_tag) catch null;
                        if (hook_result) |result| {
                            return result;
                        }
                        // Fall through to default parsing
                    }
                }
            }
        }

        return switch (self.curr.tag) {
            .k_namespace => self.parseNamespace(),
            .k_use => self.parseUse(),
            .k_class => self.parseContainer(.class_decl, attributes),
            .k_interface => self.parseContainer(.interface_decl, attributes),
            .k_trait => self.parseContainer(.trait_decl, attributes),
            .k_enum => self.parseContainer(.enum_decl, attributes),
            .k_struct => self.parseContainer(.struct_decl, attributes),
            .k_function, .k_fn => {
                if (self.peek.tag == .l_paren) return self.parseExpressionStatement();
                return self.parseFunction(attributes);
            },
            .k_if => self.parseIf(),
            .k_while => self.parseWhile(),
            .k_for => self.parseFor(),
            .k_foreach => self.parseForeach(),
            .k_try => self.parseTry(),
            .k_throw => self.parseThrow(),
            .k_echo => self.parseEcho(),
            .k_global => self.parseGlobal(),
            .k_static => self.parseStatic(),
            .k_const => self.parseConst(),
            .k_go => self.parseGo(),
            .k_lock => self.parseLock(),
            .k_return => self.parseReturn(),
            .k_break => self.parseBreak(),
            .k_continue => self.parseContinue(),
            .k_require, .k_require_once, .k_include, .k_include_once => self.parseInclude(),
            .k_abstract, .k_final => self.parseModifiedClassOrMember(attributes),
            .k_public, .k_protected, .k_private, .k_readonly => self.parseClassMember(attributes, false),
            .l_brace => self.parseBlock(),
            .t_variable => {
                if (self.peek.tag == .equal) return self.parseAssignment();
                return self.parseExpressionStatement();
            },
            .t_go_identifier => {
                // Go mode: identifiers can be variables for assignment
                if (self.peek.tag == .equal) return self.parseAssignment();
                return self.parseExpressionStatement();
            },
            else => self.parseExpressionStatement(),
        };
    }

    /// 解析带修饰符的类定义或类成员（abstract class / final class / abstract method 等）
    fn parseModifiedClassOrMember(self: *Parser, attributes: []const ast.Node.Index) anyerror!ast.Node.Index {
        var modifiers = ast.Node.Modifier{};

        // 收集所有前置修饰符
        while (true) {
            switch (self.curr.tag) {
                .k_abstract => modifiers.is_abstract = true,
                .k_final => modifiers.is_final = true,
                .k_public => modifiers.is_public = true,
                .k_protected => modifiers.is_protected = true,
                .k_private => modifiers.is_private = true,
                .k_static => modifiers.is_static = true,
                .k_readonly => modifiers.is_readonly = true,
                else => break,
            }
            self.nextToken();
        }

        // 检查是否是类定义
        if (self.curr.tag == .k_class) {
            return self.parseContainerWithModifiers(.class_decl, attributes, modifiers);
        }

        // 否则是类成员（方法或属性）
        return self.parseClassMemberWithModifiers(attributes, modifiers, false);
    }

    /// 解析带修饰符的容器（class/interface/trait等）
    fn parseTraitUse(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_use);
        var traits = std.ArrayListUnmanaged(ast.Node.Index){};

        while (true) {
            try traits.append(self.allocator, try self.parseType());
            if (self.curr.tag == .comma) {
                self.nextToken();
            } else {
                break;
            }
        }

        // Handle adaptations block { ... } or semicolon
        if (self.curr.tag == .l_brace) {
            _ = try self.eat(.l_brace);
            var balance: usize = 1;
            while (balance > 0 and self.curr.tag != .eof) {
                if (self.curr.tag == .l_brace) balance += 1;
                if (self.curr.tag == .r_brace) balance -= 1;
                if (balance > 0) self.nextToken();
            }
            if (self.curr.tag == .r_brace) self.nextToken();
        } else {
            _ = try self.eat(.semicolon);
        }

        const arena = self.context.arena.allocator();
        const traits_slice = try arena.dupe(ast.Node.Index, traits.items);
        traits.deinit(self.allocator);
        return self.createNode(.{ .tag = .trait_use, .main_token = token, .data = .{ .trait_use = .{ .traits = traits_slice } } });
    }

    fn parseContainerWithModifiers(self: *Parser, tag: ast.Node.Tag, attributes: []const ast.Node.Index, modifiers: ast.Node.Modifier) anyerror!ast.Node.Index {
        const token = self.curr;
        self.nextToken();
        const name_tok = try self.eat(.t_string);
        const name_id = try self.context.intern(self.lexer.buffer[name_tok.loc.start..name_tok.loc.end]);
        var extends: ?ast.Node.Index = null;
        if (self.curr.tag == .k_extends) {
            self.nextToken();
            extends = try self.parseExpression(0);
        }
        var implements = std.ArrayListUnmanaged(ast.Node.Index){};
        if (self.curr.tag == .k_implements) {
            self.nextToken();
            while (true) {
                try implements.append(self.allocator, try self.parseExpression(0));
                if (self.curr.tag != .comma) break;
                self.nextToken();
            }
        }

        _ = try self.eat(.l_brace);
        var members = std.ArrayListUnmanaged(ast.Node.Index){};

        const is_interface = (tag == .interface_decl);

        while (self.curr.tag != .r_brace and self.curr.tag != .eof) {
            var member_attributes: []const ast.Node.Index = &.{};
            if (self.curr.tag == .t_attribute_start) member_attributes = try self.parseAttributes();

            if (self.curr.tag == .k_const) {
                try members.append(self.allocator, try self.parseConst());
            } else if (self.curr.tag == .k_use) {
                try members.append(self.allocator, try self.parseTraitUse());
            } else {
                try members.append(self.allocator, try self.parseClassMember(member_attributes, is_interface));
            }
        }
        _ = try self.eat(.r_brace);

        const arena = self.context.arena.allocator();
        const implements_slice = try arena.dupe(ast.Node.Index, implements.items);
        const members_slice = try arena.dupe(ast.Node.Index, members.items);
        implements.deinit(self.allocator);
        members.deinit(self.allocator);

        return self.createNode(.{ .tag = tag, .main_token = token, .data = .{ .container_decl = .{ .attributes = attributes, .name = name_id, .modifiers = modifiers, .extends = extends, .implements = implements_slice, .members = members_slice } } });
    }

    /// 解析带预先收集好的修饰符的类成员
    fn parseClassMemberWithModifiers(self: *Parser, attributes: []const ast.Node.Index, modifiers: ast.Node.Modifier, is_interface: bool) anyerror!ast.Node.Index {
        if (self.curr.tag == .k_function) {
            const token = try self.eat(.k_function);
            // Method name can be t_string or t_go_identifier in Go mode
            const name_tok = if (self.curr.tag == .t_go_identifier)
                try self.eat(.t_go_identifier)
            else
                try self.eat(.t_string);
            const name_id = try self.context.intern(self.lexer.buffer[name_tok.loc.start..name_tok.loc.end]);
            _ = try self.eat(.l_paren);
            var params = std.ArrayListUnmanaged(ast.Node.Index){};
            while (self.curr.tag != .r_paren) {
                try params.append(self.allocator, try self.parseParameter());
                if (self.curr.tag == .comma) self.nextToken();
            }
            _ = try self.eat(.r_paren);
            var return_type: ?ast.Node.Index = null;
            if (self.curr.tag == .colon) {
                self.nextToken();
                return_type = try self.parseType();
            }
            // abstract方法和接口方法没有方法体，以分号结尾
            const expects_body = !modifiers.is_abstract and !is_interface;
            const body = if (!expects_body) blk: {
                if (self.curr.tag == .semicolon) {
                    self.nextToken();
                } else {
                    return error.UnexpectedToken;
                }
                break :blk null;
            } else try self.parseBlock();
            return self.createNode(.{ .tag = .method_decl, .main_token = token, .data = .{ .method_decl = .{ .attributes = attributes, .name = name_id, .modifiers = modifiers, .params = try self.context.arena.allocator().dupe(ast.Node.Index, params.items), .return_type = return_type, .body = body } } });
        } else {
            const token = self.curr;
            var type_node: ?ast.Node.Index = null;
            // Check for type hint (same as parseParameter type detection)
            // In Go mode, t_go_identifier can also be a type name
            if (self.curr.tag == .t_string or self.curr.tag == .t_go_identifier or self.curr.tag == .question or
                self.curr.tag == .k_array or self.curr.tag == .k_callable or
                self.curr.tag == .k_static or self.curr.tag == .k_self or self.curr.tag == .k_parent or
                self.curr.tag == .k_void or self.curr.tag == .k_mixed or self.curr.tag == .k_never or
                self.curr.tag == .k_object or self.curr.tag == .k_iterable or self.curr.tag == .k_null or
                self.curr.tag == .k_true or self.curr.tag == .k_false)
            {
                // In Go mode, we need to check if this is a type or a property name
                // If followed by another identifier or $variable, it's a type
                if (self.syntax_mode == .go and self.curr.tag == .t_go_identifier) {
                    // Check if next token is also an identifier (meaning current is type)
                    if (self.peek.tag == .t_go_identifier or self.peek.tag == .t_variable) {
                        type_node = try self.parseType();
                    }
                    // Otherwise, current token is the property name, not a type
                } else {
                    type_node = try self.parseType();
                }
            }
            
            // In Go mode, property names can be t_go_identifier (without $ prefix)
            var name_str: []const u8 = undefined;
            if (self.syntax_mode == .go and self.curr.tag == .t_go_identifier) {
                const name_tok = try self.eat(.t_go_identifier);
                name_str = self.lexer.buffer[name_tok.loc.start..name_tok.loc.end];
            } else {
                const name_tok = try self.eat(.t_variable);
                name_str = self.lexer.buffer[name_tok.loc.start..name_tok.loc.end];
                // Strip leading '$' from PHP-style variable
                if (name_str.len > 0 and name_str[0] == '$') {
                    name_str = name_str[1..];
                }
            }
            const name_id = try self.context.intern(name_str);

            var default_value: ?ast.Node.Index = null;
            if (self.curr.tag == .equal) {
                self.nextToken();
                default_value = try self.parseExpression(0);
            }

            var hooks = std.ArrayListUnmanaged(ast.Node.Index){};
            if (self.curr.tag == .l_brace) {
                self.nextToken();
                while (self.curr.tag != .r_brace) try hooks.append(self.allocator, try self.parsePropertyHook());
                _ = try self.eat(.r_brace);
            } else if (self.curr.tag == .semicolon) {
                self.nextToken();
            }
            return self.createNode(.{ .tag = .property_decl, .main_token = token, .data = .{ .property_decl = .{ .attributes = attributes, .name = name_id, .modifiers = modifiers, .type = type_node, .default_value = default_value, .hooks = try self.context.arena.allocator().dupe(ast.Node.Index, hooks.items) } } });
        }
    }

    fn parseClassMember(self: *Parser, attributes: []const ast.Node.Index, is_interface: bool) anyerror!ast.Node.Index {
        var modifiers = ast.Node.Modifier{};
        while (true) {
            switch (self.curr.tag) {
                .k_public => modifiers.is_public = true,
                .k_protected => modifiers.is_protected = true,
                .k_private => modifiers.is_private = true,
                .k_static => modifiers.is_static = true,
                .k_final => modifiers.is_final = true,
                .k_abstract => modifiers.is_abstract = true,
                .k_readonly => modifiers.is_readonly = true,
                else => break,
            }
            self.nextToken();
        }

        if (self.curr.tag == .k_function) {
            const token = try self.eat(.k_function);
            // Method name can be t_string or t_go_identifier in Go mode
            const name_tok = if (self.curr.tag == .t_go_identifier)
                try self.eat(.t_go_identifier)
            else
                try self.eat(.t_string);
            const name_id = try self.context.intern(self.lexer.buffer[name_tok.loc.start..name_tok.loc.end]);
            _ = try self.eat(.l_paren);
            var params = std.ArrayListUnmanaged(ast.Node.Index){};
            while (self.curr.tag != .r_paren) {
                try params.append(self.allocator, try self.parseParameter());
                if (self.curr.tag == .comma) self.nextToken();
            }
            _ = try self.eat(.r_paren);
            var return_type: ?ast.Node.Index = null;
            if (self.curr.tag == .colon) {
                self.nextToken();
                return_type = try self.parseType();
            }

            const expects_body = !modifiers.is_abstract and !is_interface;
            const body = if (!expects_body) blk: {
                if (self.curr.tag == .semicolon) {
                    self.nextToken();
                } else {
                    return error.UnexpectedToken;
                }
                break :blk null;
            } else try self.parseBlock();
            return self.createNode(.{ .tag = .method_decl, .main_token = token, .data = .{ .method_decl = .{ .attributes = attributes, .name = name_id, .modifiers = modifiers, .params = try self.context.arena.allocator().dupe(ast.Node.Index, params.items), .return_type = return_type, .body = body } } });
        } else {
            const token = self.curr;
            var type_node: ?ast.Node.Index = null;
            // Check for type hint (same as parseParameter type detection)
            // In Go mode, t_go_identifier can also be a type name
            if (self.curr.tag == .t_string or self.curr.tag == .t_go_identifier or self.curr.tag == .question or
                self.curr.tag == .k_array or self.curr.tag == .k_callable or
                self.curr.tag == .k_static or self.curr.tag == .k_self or self.curr.tag == .k_parent or
                self.curr.tag == .k_void or self.curr.tag == .k_mixed or self.curr.tag == .k_never or
                self.curr.tag == .k_object or self.curr.tag == .k_iterable or self.curr.tag == .k_null or
                self.curr.tag == .k_true or self.curr.tag == .k_false)
            {
                // In Go mode, we need to check if this is a type or a property name
                // If followed by another identifier or $variable, it's a type
                if (self.syntax_mode == .go and self.curr.tag == .t_go_identifier) {
                    // Check if next token is also an identifier (meaning current is type)
                    if (self.peek.tag == .t_go_identifier or self.peek.tag == .t_variable) {
                        type_node = try self.parseType();
                    }
                    // Otherwise, current token is the property name, not a type
                } else {
                    type_node = try self.parseType();
                }
            }
            
            // In Go mode, property names can be t_go_identifier (without $ prefix)
            var name_str: []const u8 = undefined;
            if (self.syntax_mode == .go and self.curr.tag == .t_go_identifier) {
                const name_tok = try self.eat(.t_go_identifier);
                name_str = self.lexer.buffer[name_tok.loc.start..name_tok.loc.end];
            } else {
                const name_tok = try self.eat(.t_variable);
                name_str = self.lexer.buffer[name_tok.loc.start..name_tok.loc.end];
                // Strip leading '$' from PHP-style variable
                if (name_str.len > 0 and name_str[0] == '$') {
                    name_str = name_str[1..];
                }
            }
            const name_id = try self.context.intern(name_str);

            var default_value: ?ast.Node.Index = null;
            if (self.curr.tag == .equal) {
                self.nextToken();
                default_value = try self.parseExpression(0);
            }

            var hooks = std.ArrayListUnmanaged(ast.Node.Index){};
            if (self.curr.tag == .l_brace) {
                self.nextToken();
                while (self.curr.tag != .r_brace) try hooks.append(self.allocator, try self.parsePropertyHook());
                _ = try self.eat(.r_brace);
            } else if (self.curr.tag == .semicolon) {
                self.nextToken();
            }
            return self.createNode(.{ .tag = .property_decl, .main_token = token, .data = .{ .property_decl = .{ .attributes = attributes, .name = name_id, .modifiers = modifiers, .type = type_node, .default_value = default_value, .hooks = try self.context.arena.allocator().dupe(ast.Node.Index, hooks.items) } } });
        }
    }

    fn parsePropertyHook(self: *Parser) anyerror!ast.Node.Index {
        const token = self.curr;
        if (self.curr.tag != .k_get and self.curr.tag != .k_set) return error.ExpectedHookName;
        const name_id = try self.context.intern(self.lexer.buffer[self.curr.loc.start..self.curr.loc.end]);
        self.nextToken();
        var body: ast.Node.Index = 0;
        if (self.curr.tag == .fat_arrow) {
            self.nextToken();
            body = try self.parseExpression(0);
            _ = try self.eat(.semicolon);
        } else {
            body = try self.parseBlock();
        }
        return self.createNode(.{ .tag = .property_hook, .main_token = token, .data = .{ .property_hook = .{ .name = name_id, .body = body } } });
    }

    fn parseNamespace(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_namespace);
        const name_tok = try self.eat(.t_string);
        const name_id = try self.context.intern(self.lexer.buffer[name_tok.loc.start..name_tok.loc.end]);
        self.context.current_namespace = name_id;
        _ = try self.eat(.semicolon);
        return self.createNode(.{ .tag = .expression_stmt, .main_token = token, .data = .{ .none = {} } });
    }

    fn parseUse(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_use);
        const name_tok = try self.eat(.t_string);
        const name_id = try self.context.intern(self.lexer.buffer[name_tok.loc.start..name_tok.loc.end]);
        var parts = std.mem.splitScalar(u8, self.lexer.buffer[name_tok.loc.start..name_tok.loc.end], '\\');
        var last_part: []const u8 = "";
        while (parts.next()) |part| last_part = part;
        const alias_id = try self.context.intern(last_part);
        try self.context.imports.put(self.allocator, alias_id, name_id);
        _ = try self.eat(.semicolon);
        return self.createNode(.{ .tag = .expression_stmt, .main_token = token, .data = .{ .none = {} } });
    }

    fn parseAttributes(self: *Parser) anyerror![]const ast.Node.Index {
        var attrs = std.ArrayListUnmanaged(ast.Node.Index){};
        while (self.curr.tag == .t_attribute_start) {
            self.nextToken();
            while (self.curr.tag != .r_bracket and self.curr.tag != .eof) {
                const name_tok = try self.eat(.t_string);
                const name_id = try self.context.intern(self.lexer.buffer[name_tok.loc.start..name_tok.loc.end]);

                var args = std.ArrayListUnmanaged(ast.Node.Index){};

                if (self.curr.tag == .l_paren) {
                    self.nextToken();
                    while (self.curr.tag != .r_paren and self.curr.tag != .eof) {
                        try args.append(self.allocator, try self.parseExpression(0));
                        if (self.curr.tag == .comma) self.nextToken();
                    }
                    _ = try self.eat(.r_paren);
                }

                const attr_node = try self.createNode(.{ .tag = .attribute, .main_token = name_tok, .data = .{ .attribute = .{ .name = name_id, .args = try self.context.arena.allocator().dupe(ast.Node.Index, args.items) } } });
                try attrs.append(self.allocator, attr_node);
                if (self.curr.tag == .comma) self.nextToken();
            }
            _ = try self.eat(.r_bracket);
        }
        return try self.context.arena.allocator().dupe(ast.Node.Index, attrs.items);
    }

    fn parseContainer(self: *Parser, tag: ast.Node.Tag, attributes: []const ast.Node.Index) anyerror!ast.Node.Index {
        const token = self.curr;
        self.nextToken();
        const name_tok = try self.eat(.t_string);
        const name_id = try self.context.intern(self.lexer.buffer[name_tok.loc.start..name_tok.loc.end]);
        var extends: ?ast.Node.Index = null;
        if (self.curr.tag == .k_extends) {
            self.nextToken();
            extends = try self.parseExpression(0);
        }
        var implements = std.ArrayListUnmanaged(ast.Node.Index){};
        if (self.curr.tag == .k_implements) {
            self.nextToken();
            while (true) {
                try implements.append(self.allocator, try self.parseExpression(0));
                if (self.curr.tag != .comma) break;
                self.nextToken();
            }
        }

        _ = try self.eat(.l_brace);
        var members = std.ArrayListUnmanaged(ast.Node.Index){};

        const is_interface = (tag == .interface_decl);

        while (self.curr.tag != .r_brace and self.curr.tag != .eof) {
            var member_attributes: []const ast.Node.Index = &.{};
            if (self.curr.tag == .t_attribute_start) member_attributes = try self.parseAttributes();

            if (self.curr.tag == .k_const) {
                try members.append(self.allocator, try self.parseConst());
            } else if (self.curr.tag == .k_use) {
                try members.append(self.allocator, try self.parseTraitUse());
            } else {
                try members.append(self.allocator, try self.parseClassMember(member_attributes, is_interface));
            }
        }
        _ = try self.eat(.r_brace);

        return self.createNode(.{ .tag = tag, .main_token = token, .data = .{ .container_decl = .{ .attributes = attributes, .name = name_id, .modifiers = .{}, .extends = extends, .implements = try self.context.arena.allocator().dupe(ast.Node.Index, implements.items), .members = try self.context.arena.allocator().dupe(ast.Node.Index, members.items) } } });
    }

    fn parseFunction(self: *Parser, attributes: []const ast.Node.Index) anyerror!ast.Node.Index {
        // 支持 function 和 fn 两个关键字
        const token = if (self.curr.tag == .k_fn)
            try self.eat(.k_fn)
        else
            try self.eat(.k_function);
        const name_tok = try self.eat(.t_string);
        const name_id = try self.context.intern(self.lexer.buffer[name_tok.loc.start..name_tok.loc.end]);
        _ = try self.eat(.l_paren);
        var params = std.ArrayListUnmanaged(ast.Node.Index){};
        while (self.curr.tag != .r_paren) {
            try params.append(self.allocator, try self.parseParameter());
            if (self.curr.tag == .comma) self.nextToken();
        }
        _ = try self.eat(.r_paren);

        // Parse optional return type declaration (: type or : ?type)
        // We skip the return type as the AST doesn't currently store it
        if (self.curr.tag == .colon) {
            self.nextToken(); // consume ':'
            _ = try self.parseType();
        }

        const body = try self.parseBlock();
        return self.createNode(.{ .tag = .function_decl, .main_token = token, .data = .{ .function_decl = .{ .attributes = attributes, .name = name_id, .params = try self.context.arena.allocator().dupe(ast.Node.Index, params.items), .body = body } } });
    }

    fn parseParameter(self: *Parser) anyerror!ast.Node.Index {
        var attributes: []const ast.Node.Index = &.{};
        if (self.curr.tag == .t_attribute_start) attributes = try self.parseAttributes();
        var modifiers = ast.Node.Modifier{};
        while (true) {
            switch (self.curr.tag) {
                .k_public => modifiers.is_public = true,
                .k_protected => modifiers.is_protected = true,
                .k_private => modifiers.is_private = true,
                .k_readonly => modifiers.is_readonly = true,
                else => break,
            }
            self.nextToken();
        }
        var type_node: ?ast.Node.Index = null;
        // Handle type declarations including nullable (?type), array, callable, etc.
        // t_string covers user types and built-in types like int, float, string, bool
        if (self.curr.tag == .t_string or self.curr.tag == .question or
            self.curr.tag == .k_array or self.curr.tag == .k_callable or
            self.curr.tag == .k_static or self.curr.tag == .k_self or self.curr.tag == .k_parent or
            self.curr.tag == .k_void or self.curr.tag == .k_mixed or self.curr.tag == .k_never or
            self.curr.tag == .k_object or self.curr.tag == .k_iterable or self.curr.tag == .k_null or
            self.curr.tag == .k_true or self.curr.tag == .k_false)
        {
            type_node = try self.parseType();
        }
        var is_reference = false;
        if (self.curr.tag == .ampersand) {
            is_reference = true;
            self.nextToken();
        }
        var is_variadic = false;
        if (self.curr.tag == .ellipsis) {
            is_variadic = true;
            self.nextToken();
        }
        const name_tok = try self.eat(.t_variable);
        const name_id = try self.context.intern(self.lexer.buffer[name_tok.loc.start..name_tok.loc.end]);

        var default_value: ?ast.Node.Index = null;
        if (self.curr.tag == .equal) {
            self.nextToken();
            default_value = try self.parseExpression(0);
        }

        return self.createNode(.{ .tag = .parameter, .main_token = name_tok, .data = .{ .parameter = .{ .attributes = attributes, .name = name_id, .type = type_node, .default_value = default_value, .is_promoted = modifiers.is_public or modifiers.is_protected or modifiers.is_private, .modifiers = modifiers, .is_variadic = is_variadic, .is_reference = is_reference } } });
    }

    fn parseIf(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_if);
        _ = try self.eat(.l_paren);
        const cond = try self.parseExpression(0);
        _ = try self.eat(.r_paren);
        const then = try self.parseStatement();
        var else_branch: ?ast.Node.Index = null;
        if (self.curr.tag == .k_elseif) {
            // elseif is parsed as else { if (...) }
            else_branch = try self.parseElseif();
        } else if (self.curr.tag == .k_else) {
            self.nextToken();
            else_branch = try self.parseStatement();
        }
        return self.createNode(.{ .tag = .if_stmt, .main_token = token, .data = .{ .if_stmt = .{ .condition = cond, .then_branch = then, .else_branch = else_branch } } });
    }

    fn parseElseif(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_elseif);
        _ = try self.eat(.l_paren);
        const cond = try self.parseExpression(0);
        _ = try self.eat(.r_paren);
        const then = try self.parseStatement();
        var else_branch: ?ast.Node.Index = null;
        if (self.curr.tag == .k_elseif) {
            else_branch = try self.parseElseif();
        } else if (self.curr.tag == .k_else) {
            self.nextToken();
            else_branch = try self.parseStatement();
        }
        return self.createNode(.{ .tag = .if_stmt, .main_token = token, .data = .{ .if_stmt = .{ .condition = cond, .then_branch = then, .else_branch = else_branch } } });
    }

    fn parseWhile(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_while);
        _ = try self.eat(.l_paren);
        const cond = try self.parseExpression(0);
        _ = try self.eat(.r_paren);
        const body = try self.parseStatement();
        return self.createNode(.{ .tag = .while_stmt, .main_token = token, .data = .{ .while_stmt = .{ .condition = cond, .body = body } } });
    }

    fn parseForeach(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_foreach);
        _ = try self.eat(.l_paren);
        const iterable = try self.parseExpression(0);
        _ = try self.eat(.k_as);

        // 解析第一个表达式
        const first_expr = try self.parseExpression(0);

        // 检查是否有 => 符号（键值对语法）
        var key: ?ast.Node.Index = null;
        var value: ast.Node.Index = undefined;

        if (self.curr.tag == .fat_arrow) {
            // 有 => 符号，第一个表达式是键
            _ = try self.eat(.fat_arrow);
            key = first_expr;
            value = try self.parseExpression(0);
        } else {
            // 没有 => 符号，第一个表达式是值
            value = first_expr;
        }

        _ = try self.eat(.r_paren);
        const body = try self.parseStatement();
        return self.createNode(.{ .tag = .foreach_stmt, .main_token = token, .data = .{ .foreach_stmt = .{ .iterable = iterable, .key = key, .value = value, .body = body } } });
    }

    fn parseTry(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_try);
        const body = try self.parseBlock();

        var catch_clauses = std.ArrayListUnmanaged(ast.Node.Index){};
        defer catch_clauses.deinit(self.allocator);

        while (self.curr.tag == .k_catch) {
            const catch_token = try self.eat(.k_catch);
            _ = try self.eat(.l_paren);

            var exception_type: ?ast.Node.Index = null;
            var variable: ?ast.Node.Index = null;

            if (self.curr.tag == .t_string) {
                exception_type = try self.parseType();
            }

            if (self.curr.tag == .t_variable) {
                const var_token = try self.eat(.t_variable);
                const var_name = try self.context.intern(self.lexer.buffer[var_token.loc.start..var_token.loc.end]);
                variable = try self.createNode(.{ .tag = .variable, .main_token = var_token, .data = .{ .variable = .{ .name = var_name } } });
            }

            _ = try self.eat(.r_paren);
            const catch_body = try self.parseBlock();

            const catch_clause = try self.createNode(.{ .tag = .catch_clause, .main_token = catch_token, .data = .{ .catch_clause = .{ .exception_type = exception_type, .variable = variable, .body = catch_body } } });
            try catch_clauses.append(self.allocator, catch_clause);
        }

        var finally_clause: ?ast.Node.Index = null;
        if (self.curr.tag == .k_finally) {
            const finally_token = try self.eat(.k_finally);
            const finally_body = try self.parseBlock();
            finally_clause = try self.createNode(.{ .tag = .finally_clause, .main_token = finally_token, .data = .{ .finally_clause = .{ .body = finally_body } } });
        }

        const arena = self.context.arena.allocator();
        return self.createNode(.{ .tag = .try_stmt, .main_token = token, .data = .{ .try_stmt = .{ .body = body, .catch_clauses = try arena.dupe(ast.Node.Index, catch_clauses.items), .finally_clause = finally_clause } } });
    }

    fn parseThrow(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_throw);
        const expression = try self.parseExpression(0);
        _ = try self.eat(.semicolon);
        return self.createNode(.{ .tag = .throw_stmt, .main_token = token, .data = .{ .throw_stmt = .{ .expression = expression } } });
    }

    fn parseFor(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_for);

        // Infinite loop: for { ... }
        if (self.curr.tag == .l_brace) {
            const body = try self.parseBlock();
            return self.createNode(.{ .tag = .for_stmt, .main_token = token, .data = .{ .for_stmt = .{ .init = null, .condition = null, .loop = null, .body = body } } });
        }

        // Range loop: for range 10, for $i range 10, or for range 10 as $i
        if (self.curr.tag == .k_range or self.curr.tag == .t_variable) {
            var variable: ?ast.Node.Index = null;

            // 检查是否有变量（for $i range 10）
            if (self.curr.tag == .t_variable) {
                variable = try self.parseExpression(0); // 解析变量
                _ = try self.eat(.k_range); // 吃掉range关键字
            } else {
                // for range 10（无变量）
                _ = try self.eat(.k_range); // 吃掉range关键字
            }

            const count = try self.parseExpression(0); // 解析范围数值

            // Check for "as $var" syntax (for range 10 as $i)
            if (self.curr.tag == .k_as) {
                self.nextToken(); // consume 'as'
                variable = try self.parseExpression(0); // parse the variable
            }

            const body = try self.parseStatement();
            return self.createNode(.{ .tag = .for_range_stmt, .main_token = token, .data = .{ .for_range_stmt = .{ .count = count, .variable = variable, .body = body } } });
        }

        // Standard PHP for loop: for (...)
        _ = try self.eat(.l_paren);

        // Parse initialization (expr1)
        var init_expr: ?ast.Node.Index = null;
        if (self.curr.tag != .semicolon) {
            init_expr = try self.parseExpression(0);
        }
        _ = try self.eat(.semicolon);

        // Parse condition (expr2)
        var condition: ?ast.Node.Index = null;
        if (self.curr.tag != .semicolon) {
            condition = try self.parseExpression(0);
        }
        _ = try self.eat(.semicolon);

        // Parse loop expression (expr3)
        var loop: ?ast.Node.Index = null;
        if (self.curr.tag != .r_paren) {
            loop = try self.parseExpression(0);
        }
        _ = try self.eat(.r_paren);

        const body = try self.parseStatement();

        return self.createNode(.{ .tag = .for_stmt, .main_token = token, .data = .{ .for_stmt = .{ .init = init_expr, .condition = condition, .loop = loop, .body = body } } });
    }

    fn parseGlobal(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_global);
        var vars = std.ArrayListUnmanaged(ast.Node.Index){};
        while (true) {
            try vars.append(self.allocator, try self.parseExpression(100));
            if (self.curr.tag != .comma) break;
            self.nextToken();
        }
        _ = try self.eat(.semicolon);
        return self.createNode(.{ .tag = .global_stmt, .main_token = token, .data = .{ .global_stmt = .{ .vars = try self.context.arena.allocator().dupe(ast.Node.Index, vars.items) } } });
    }

    fn parseStatic(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_static);
        var vars = std.ArrayListUnmanaged(ast.Node.Index){};
        while (true) {
            try vars.append(self.allocator, try self.parseExpression(0));
            if (self.curr.tag != .comma) break;
            self.nextToken();
        }
        _ = try self.eat(.semicolon);
        return self.createNode(.{ .tag = .static_stmt, .main_token = token, .data = .{ .static_stmt = .{ .vars = try self.context.arena.allocator().dupe(ast.Node.Index, vars.items) } } });
    }

    fn parseConst(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_const);
        const name_tok = try self.eat(.t_string);
        const name_id = try self.context.intern(self.lexer.buffer[name_tok.loc.start..name_tok.loc.end]);
        _ = try self.eat(.equal);
        const val = try self.parseExpression(0);
        _ = try self.eat(.semicolon);
        return self.createNode(.{ .tag = .const_decl, .main_token = token, .data = .{ .const_decl = .{ .name = name_id, .value = val } } });
    }

    fn parseGo(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_go);
        const call = try self.parseExpression(0);
        _ = try self.eat(.semicolon);
        return self.createNode(.{ .tag = .go_stmt, .main_token = token, .data = .{ .go_stmt = .{ .call = call } } });
    }

    fn parseLock(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_lock);
        const body = try self.parseBlock();
        return self.createNode(.{ .tag = .lock_stmt, .main_token = token, .data = .{ .lock_stmt = .{ .body = body } } });
    }

    fn parseInclude(self: *Parser) anyerror!ast.Node.Index {
        const token = self.curr;
        const is_require = token.tag == .k_require or token.tag == .k_require_once;
        const is_once = token.tag == .k_require_once or token.tag == .k_include_once;
        const tag: ast.Node.Tag = if (is_require) .require_stmt else .include_stmt;
        self.nextToken();
        const expr = try self.parseExpression(0);
        _ = try self.eat(.semicolon);
        return self.createNode(.{ .tag = tag, .main_token = token, .data = .{ .include_stmt = .{ .path = expr, .is_once = is_once, .is_require = is_require } } });
    }

    fn parseReturn(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_return);
        var expr: ?ast.Node.Index = null;
        if (self.curr.tag != .semicolon) expr = try self.parseExpression(0);
        _ = try self.eat(.semicolon);
        return self.createNode(.{ .tag = .return_stmt, .main_token = token, .data = .{ .return_stmt = .{ .expr = expr } } });
    }

    fn parseBreak(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_break);
        var level: ?ast.Node.Index = null;
        if (self.curr.tag != .semicolon) {
            level = try self.parseExpression(0);
        }
        _ = try self.eat(.semicolon);
        return self.createNode(.{ .tag = .break_stmt, .main_token = token, .data = .{ .break_stmt = .{ .level = level } } });
    }

    fn parseContinue(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_continue);
        var level: ?ast.Node.Index = null;
        if (self.curr.tag != .semicolon) {
            level = try self.parseExpression(0);
        }
        _ = try self.eat(.semicolon);
        return self.createNode(.{ .tag = .continue_stmt, .main_token = token, .data = .{ .continue_stmt = .{ .level = level } } });
    }

    fn parseEcho(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_echo);
        var exprs = std.ArrayListUnmanaged(ast.Node.Index){};
        defer exprs.deinit(self.allocator);

        // Parse first expression
        try exprs.append(self.allocator, try self.parseExpression(0));

        // Parse additional expressions separated by commas
        while (self.curr.tag == .comma) {
            self.nextToken();
            try exprs.append(self.allocator, try self.parseExpression(0));
        }

        _ = try self.eat(.semicolon);
        const arena = self.context.arena.allocator();
        return self.createNode(.{ .tag = .echo_stmt, .main_token = token, .data = .{ .echo_stmt = .{ .exprs = try arena.dupe(ast.Node.Index, exprs.items) } } });
    }

    fn parseAssignment(self: *Parser) anyerror!ast.Node.Index {
        const target = try self.parseExpression(100);
        const op = try self.eat(.equal);
        const val = try self.parseExpression(0);
        _ = try self.eat(.semicolon);
        return self.createNode(.{ .tag = .assignment, .main_token = op, .data = .{ .assignment = .{ .target = target, .value = val } } });
    }

    fn parseExpressionStatement(self: *Parser) anyerror!ast.Node.Index {
        const expr = try self.parseExpression(0);
        if (self.curr.tag == .semicolon) self.nextToken();
        return expr;
    }

    fn parseBlock(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.l_brace);
        var stmts = std.ArrayListUnmanaged(ast.Node.Index){};
        defer stmts.deinit(self.allocator);

        while (self.curr.tag != .r_brace and self.curr.tag != .eof) {
            try stmts.append(self.allocator, try self.parseStatement());
        }
        _ = try self.eat(.r_brace);
        const arena = self.context.arena.allocator();
        return self.createNode(.{ .tag = .block, .main_token = token, .data = .{ .block = .{ .stmts = try arena.dupe(ast.Node.Index, stmts.items) } } });
    }

    fn parseExpression(self: *Parser, precedence: u8) anyerror!ast.Node.Index {
        // Check syntax hooks first for custom expression parsing
        if (self.syntax_hooks) |hooks| {
            if (hooks.parse_expression) |parse_expr_hook| {
                const hook_result = parse_expr_hook(@ptrCast(self), precedence) catch null;
                if (hook_result) |result| {
                    // Hook handled the expression, return the result
                    return result;
                }
                // Hook returned null, fall through to default parsing
            }
        }

        var left = try self.parseUnary();
        while (true) {
            const tag = self.curr.tag;
            const next_p = self.getPrecedence(tag);
            if (next_p <= precedence) break;
            const op = self.curr;
            self.nextToken();
            if (tag == .arrow) {
                // 方法名可以是标识符，也可以是某些关键字（如 set, get）
                // In Go mode, member names are t_go_identifier; in PHP mode, they are t_string
                const member_name_tok = if (self.curr.tag == .t_string)
                    try self.eat(.t_string)
                else if (self.curr.tag == .t_go_identifier)
                    try self.eat(.t_go_identifier)
                else if (self.curr.tag == .k_set or self.curr.tag == .k_get or
                    self.curr.tag == .k_unset or self.curr.tag == .k_clone or
                    self.curr.tag == .k_list or self.curr.tag == .k_print or
                    self.curr.tag == .k_lock or self.curr.tag == .k_try or
                    self.curr.tag == .k_catch or self.curr.tag == .k_finally or
                    self.curr.tag == .k_throw or self.curr.tag == .k_match or
                    self.curr.tag == .k_default or self.curr.tag == .k_static or
                    self.curr.tag == .k_class or self.curr.tag == .k_function or
                    self.curr.tag == .k_array or self.curr.tag == .k_new)
                blk: {
                    const tok = self.curr;
                    self.nextToken();
                    break :blk tok;
                } else try self.eat(.t_string);
                const member_id = try self.context.intern(self.lexer.buffer[member_name_tok.loc.start..member_name_tok.loc.end]);
                if (self.curr.tag == .l_paren) {
                    self.nextToken();
                    var args = std.ArrayListUnmanaged(ast.Node.Index){};
                    while (self.curr.tag != .r_paren and self.curr.tag != .eof) {
                        try args.append(self.allocator, try self.parseExpression(0));
                        if (self.curr.tag == .comma) self.nextToken();
                    }
                    _ = try self.eat(.r_paren);
                    left = try self.createNode(.{ .tag = .method_call, .main_token = op, .data = .{ .method_call = .{ .target = left, .method_name = member_id, .args = try self.context.arena.allocator().dupe(ast.Node.Index, args.items) } } });
                } else {
                    left = try self.createNode(.{ .tag = .property_access, .main_token = op, .data = .{ .property_access = .{ .target = left, .property_name = member_id } } });
                }
            } else if (tag == .double_colon) {
                // Static access: ClassName::member, self::member, parent::member, $obj::member
                const left_node = self.context.nodes.items[left];

                // 获取类名ID，支持variable、self_expr、parent_expr节点
                const class_name_id = switch (left_node.tag) {
                    .variable => left_node.data.variable.name,
                    .self_expr => left_node.data.variable.name,
                    .parent_expr => left_node.data.variable.name,
                    else => {
                        self.reportError("Invalid static access target");
                        return error.InvalidStaticAccess;
                    },
                };

                if (self.curr.tag == .t_variable) {
                    const prop_tok = try self.eat(.t_variable);
                    var prop_str = self.lexer.buffer[prop_tok.loc.start..prop_tok.loc.end];
                    // Strip leading '$'
                    if (prop_str.len > 0 and prop_str[0] == '$') {
                        prop_str = prop_str[1..];
                    }
                    const prop_id = try self.context.intern(prop_str);
                    left = try self.createNode(.{ .tag = .static_property_access, .main_token = op, .data = .{ .static_property_access = .{ .class_name = class_name_id, .property_name = prop_id } } });
                } else {
                    const member_name_tok = try self.eat(.t_string);
                    const member_id = try self.context.intern(self.lexer.buffer[member_name_tok.loc.start..member_name_tok.loc.end]);
                    if (self.curr.tag == .l_paren) {
                        self.nextToken();
                        var args = std.ArrayListUnmanaged(ast.Node.Index){};
                        while (self.curr.tag != .r_paren and self.curr.tag != .eof) {
                            try args.append(self.allocator, try self.parseExpression(0));
                            if (self.curr.tag == .comma) self.nextToken();
                        }
                        _ = try self.eat(.r_paren);
                        left = try self.createNode(.{ .tag = .static_method_call, .main_token = op, .data = .{ .static_method_call = .{ .class_name = class_name_id, .method_name = member_id, .args = try self.context.arena.allocator().dupe(ast.Node.Index, args.items) } } });
                    } else {
                        left = try self.createNode(.{ .tag = .class_constant_access, .main_token = op, .data = .{ .class_constant_access = .{ .class_name = class_name_id, .constant_name = member_id } } });
                    }
                }
            } else if (tag == .l_paren) {
                var args = std.ArrayListUnmanaged(ast.Node.Index){};
                while (self.curr.tag != .r_paren) {
                    // Check for named parameter: name: value
                    if (self.curr.tag == .t_string and self.peek.tag == .colon) {
                        const name_tok = self.curr;
                        const name_id = try self.context.intern(self.lexer.buffer[name_tok.loc.start..name_tok.loc.end]);
                        self.nextToken(); // skip name
                        self.nextToken(); // skip colon
                        const value_expr = try self.parseExpression(0);
                        const named_arg_node = try self.createNode(.{
                            .tag = .named_arg,
                            .main_token = name_tok,
                            .data = .{ .named_arg = .{ .name = name_id, .value = value_expr } },
                        });
                        try args.append(self.allocator, named_arg_node);
                    } else {
                        try args.append(self.allocator, try self.parseExpression(0));
                    }
                    if (self.curr.tag == .comma) self.nextToken();
                }
                _ = try self.eat(.r_paren);
                left = try self.createNode(.{ .tag = .function_call, .main_token = op, .data = .{ .function_call = .{ .name = left, .args = try self.context.arena.allocator().dupe(ast.Node.Index, args.items) } } });
            } else if (tag == .l_bracket) {
                var index: ?ast.Node.Index = null;
                if (self.curr.tag != .r_bracket) {
                    index = try self.parseExpression(0);
                }
                _ = try self.eat(.r_bracket);
                left = try self.createNode(.{ .tag = .array_access, .main_token = op, .data = .{ .array_access = .{ .target = left, .index = index } } });
            } else if (tag == .pipe_greater) {
                const right = try self.parseExpression(next_p);
                left = try self.createNode(.{ .tag = .pipe_expr, .main_token = op, .data = .{ .pipe_expr = .{ .left = left, .right = right } } });
            } else if (tag == .equal) {
                const right = try self.parseExpression(precedence);
                left = try self.createNode(.{ .tag = .assignment, .main_token = op, .data = .{ .assignment = .{ .target = left, .value = right } } });
            } else if (tag == .plus_equal or tag == .minus_equal or tag == .asterisk_equal or tag == .slash_equal or tag == .percent_equal) {
                const right = try self.parseExpression(precedence);
                left = try self.createNode(.{ .tag = .compound_assignment, .main_token = op, .data = .{ .compound_assignment = .{ .target = left, .op = tag, .value = right } } });
            } else if (tag == .question) {
                var then_expr: ?ast.Node.Index = null;
                if (self.curr.tag != .colon) {
                    then_expr = try self.parseExpression(0);
                }
                _ = try self.eat(.colon);
                const else_expr = try self.parseExpression(next_p);
                left = try self.createNode(.{ .tag = .ternary_expr, .main_token = op, .data = .{ .ternary_expr = .{ .cond = left, .then_expr = then_expr, .else_expr = else_expr } } });
            } else if (tag == .plus_plus or tag == .minus_minus) {
                left = try self.createNode(.{ .tag = .postfix_expr, .main_token = op, .data = .{ .postfix_expr = .{ .op = tag, .expr = left } } });
            } else {
                const right = try self.parseExpression(next_p);
                
                // In Go mode, + operator on strings should be concatenation (like PHP's .)
                var effective_op = op.tag;
                if (self.syntax_mode == .go and tag == .plus) {
                    // Check if both operands are string literals
                    const left_node = self.context.nodes.items[left];
                    const right_node = self.context.nodes.items[right];
                    const left_is_string = left_node.tag == .literal_string;
                    const right_is_string = right_node.tag == .literal_string;
                    
                    if (left_is_string or right_is_string) {
                        // Use dot (concat) operator for string concatenation
                        effective_op = .dot;
                    }
                }
                
                left = try self.createNode(.{ .tag = .binary_expr, .main_token = op, .data = .{ .binary_expr = .{ .lhs = left, .op = effective_op, .rhs = right } } });
            }
        }
        return left;
    }

    fn parseUnary(self: *Parser) anyerror!ast.Node.Index {
        const tag = self.curr.tag;
        switch (tag) {
            .bang, .minus, .plus, .ampersand => {
                const token = self.curr;
                self.nextToken();
                // Use parseUnaryPostfix to handle cases like !empty($x)
                const expr = try self.parseUnaryPostfix();
                return self.createNode(.{ .tag = .unary_expr, .main_token = token, .data = .{ .unary_expr = .{ .op = tag, .expr = expr } } });
            },
            .t_variable, .t_go_identifier => {
                return self.parseUnaryPostfix();
            },
            .plus_plus, .minus_minus => {
                const token = self.curr;
                self.nextToken();
                const expr = try self.parseUnary();
                return self.createNode(.{ .tag = .unary_expr, .main_token = token, .data = .{ .unary_expr = .{ .op = tag, .expr = expr } } });
            },
            .k_clone => return self.parseCloneExpression(),
            else => return self.parseUnaryPostfix(),
        }
    }

    // Parse primary expression with postfix operators (function calls, array access, etc.)
    fn parseUnaryPostfix(self: *Parser) anyerror!ast.Node.Index {
        var left = try self.parsePrimary();

        // Handle postfix operators: function calls, array access
        while (true) {
            const tag = self.curr.tag;
            if (tag == .l_paren) {
                // Function call
                const op = self.curr;
                self.nextToken();
                var args = std.ArrayList(ast.Node.Index){};
                while (self.curr.tag != .r_paren and self.curr.tag != .eof) {
                    // Check for named argument: name: value
                    if (self.curr.tag == .t_string and self.peek.tag == .colon) {
                        const name_tok = self.curr;
                        const name_id = try self.context.intern(self.lexer.buffer[name_tok.loc.start..name_tok.loc.end]);
                        self.nextToken(); // skip name
                        self.nextToken(); // skip colon
                        const value_expr = try self.parseExpression(0);
                        const named_arg_node = try self.createNode(.{
                            .tag = .named_arg,
                            .main_token = name_tok,
                            .data = .{ .named_arg = .{ .name = name_id, .value = value_expr } },
                        });
                        try args.append(self.allocator, named_arg_node);
                    } else {
                        try args.append(self.allocator, try self.parseExpression(0));
                    }
                    if (self.curr.tag == .comma) self.nextToken();
                }
                _ = try self.eat(.r_paren);
                left = try self.createNode(.{ .tag = .function_call, .main_token = op, .data = .{ .function_call = .{ .name = left, .args = try self.context.arena.allocator().dupe(ast.Node.Index, args.items) } } });
            } else if (tag == .l_bracket) {
                // Array access
                const op = self.curr;
                self.nextToken();
                var index: ?ast.Node.Index = null;
                if (self.curr.tag != .r_bracket) {
                    index = try self.parseExpression(0);
                }
                _ = try self.eat(.r_bracket);
                left = try self.createNode(.{ .tag = .array_access, .main_token = op, .data = .{ .array_access = .{ .target = left, .index = index } } });
            } else {
                break;
            }
        }

        return left;
    }

    fn parsePrimary(self: *Parser) anyerror!ast.Node.Index {
        return switch (self.curr.tag) {
            .t_double_quote => self.parseInterpolatedString(),
            .k_function => self.parseClosure(),
            .k_fn => self.parseArrowFunction(),
            .k_match => self.parseMatch(),
            .k_new => self.parseNewOrAnonymousClass(),
            .k_clone => self.parseCloneExpression(),
            // self:: 和 parent:: 静态访问关键字
            .k_self => {
                const t = try self.eat(.k_self);
                const name_id = try self.context.intern("self");
                return self.createNode(.{ .tag = .self_expr, .main_token = t, .data = .{ .variable = .{ .name = name_id } } });
            },
            .k_parent => {
                const t = try self.eat(.k_parent);
                const name_id = try self.context.intern("parent");
                return self.createNode(.{ .tag = .parent_expr, .main_token = t, .data = .{ .variable = .{ .name = name_id } } });
            },
            .k_true => {
                const t = try self.eat(.k_true);
                return self.createNode(.{ .tag = .literal_bool, .main_token = t, .data = .{ .literal_int = .{ .value = 1 } } });
            },
            .k_false => {
                const t = try self.eat(.k_false);
                return self.createNode(.{ .tag = .literal_bool, .main_token = t, .data = .{ .literal_int = .{ .value = 0 } } });
            },
            .k_null => {
                const t = try self.eat(.k_null);
                return self.createNode(.{ .tag = .literal_null, .main_token = t, .data = .{ .none = {} } });
            },
            .m_dir, .m_file, .m_line, .m_function, .m_class, .m_method, .m_namespace => {
                const t = self.curr;
                const kind: ast.MagicConstantKind = switch (t.tag) {
                    .m_dir => .dir,
                    .m_file => .file,
                    .m_line => .line,
                    .m_function => .function,
                    .m_class => .class,
                    .m_method => .method,
                    .m_namespace => .namespace,
                    else => .dir,
                };
                self.nextToken();
                return self.createNode(.{ .tag = .magic_constant, .main_token = t, .data = .{ .magic_constant = .{ .kind = kind } } });
            },
            .ellipsis => {
                const token = self.curr;
                self.nextToken();
                const expr = try self.parseExpression(100);
                return self.createNode(.{ .tag = .unpacking_expr, .main_token = token, .data = .{ .unpacking_expr = .{ .expr = expr } } });
            },
            .t_variable => {
                const t = try self.eat(.t_variable);
                return self.createNode(.{ .tag = .variable, .main_token = t, .data = .{ .variable = .{ .name = try self.context.intern(self.lexer.buffer[t.loc.start..t.loc.end]) } } });
            },
            .t_go_identifier => {
                // Go mode: identifiers are variables, add $ prefix for VM compatibility
                const t = try self.eat(.t_go_identifier);
                const raw_name = self.lexer.buffer[t.loc.start..t.loc.end];
                const var_name = try std.fmt.allocPrint(self.allocator, "${s}", .{raw_name});
                defer self.allocator.free(var_name);
                const name_id = try self.context.intern(var_name);
                return self.createNode(.{ .tag = .variable, .main_token = t, .data = .{ .variable = .{ .name = name_id } } });
            },
            .t_string => {
                const t = try self.eat(.t_string);
                const raw_name = self.lexer.buffer[t.loc.start..t.loc.end];

                // In Go mode, treat identifiers as variables by adding $ prefix
                if (self.syntax_mode == .go) {
                    // Add $ prefix for VM compatibility
                    const var_name = try std.fmt.allocPrint(self.allocator, "${s}", .{raw_name});
                    defer self.allocator.free(var_name);
                    const name_id = try self.context.intern(var_name);
                    return self.createNode(.{ .tag = .variable, .main_token = t, .data = .{ .variable = .{ .name = name_id } } });
                }

                // PHP mode: resolve as constant/class name
                const name_id = try self.context.intern(raw_name);
                const resolved_id = try self.context.resolveName(name_id);
                return self.createNode(.{ .tag = .variable, .main_token = t, .data = .{ .variable = .{ .name = resolved_id } } });
            },
            .t_lnumber => {
                const t = try self.eat(.t_lnumber);
                return self.createNode(.{ .tag = .literal_int, .main_token = t, .data = .{ .literal_int = .{ .value = try std.fmt.parseInt(i64, self.lexer.buffer[t.loc.start..t.loc.end], 10) } } });
            },
            .t_dnumber => {
                const t = try self.eat(.t_dnumber);
                const float_val = try std.fmt.parseFloat(f64, self.lexer.buffer[t.loc.start..t.loc.end]);
                return self.createNode(.{ .tag = .literal_float, .main_token = t, .data = .{ .literal_float = .{ .value = float_val } } });
            },
            .t_constant_encapsed_string => {
                const t = try self.eat(.t_constant_encapsed_string);
                const raw_text = self.lexer.buffer[t.loc.start..t.loc.end];
                // Determine quote type and remove quotes
                const quote_type: @import("ast.zig").QuoteType = if (raw_text.len >= 2)
                    if (raw_text[0] == '"') .double else if (raw_text[0] == '\'') .single else .double
                else
                    .double;
                const string_content = if (raw_text.len >= 2 and
                    ((raw_text[0] == '"' and raw_text[raw_text.len - 1] == '"') or
                        (raw_text[0] == '\'' and raw_text[raw_text.len - 1] == '\'')))
                    raw_text[1 .. raw_text.len - 1]
                else
                    raw_text;
                return self.createNode(.{ .tag = .literal_string, .main_token = t, .data = .{ .literal_string = .{ .value = try self.context.intern(string_content), .quote_type = quote_type } } });
            },
            .t_encapsed_and_whitespace => {
                const t = try self.eat(.t_encapsed_and_whitespace);
                return self.createNode(.{ .tag = .literal_string, .main_token = t, .data = .{ .literal_string = .{ .value = try self.context.intern(self.lexer.buffer[t.loc.start..t.loc.end]) } } });
            },
            .t_backtick_string => {
                const t = try self.eat(.t_backtick_string);
                const raw_text = self.lexer.buffer[t.loc.start..t.loc.end];
                const string_content = if (raw_text.len >= 2 and raw_text[0] == '`' and raw_text[raw_text.len - 1] == '`')
                    raw_text[1 .. raw_text.len - 1]
                else
                    raw_text;
                return self.createNode(.{ .tag = .literal_string, .main_token = t, .data = .{ .literal_string = .{ .value = try self.context.intern(string_content), .quote_type = .backtick } } });
            },
            .t_heredoc_start, .t_nowdoc_start => {
                // Parse heredoc/nowdoc string with interpolation support
                const start_tok = self.curr;
                const is_nowdoc = self.curr.tag == .t_nowdoc_start;
                self.nextToken();

                if (is_nowdoc) {
                    // Nowdoc: no interpolation, just get content
                    var content: []const u8 = "";
                    if (self.curr.tag == .t_encapsed_and_whitespace) {
                        const content_tok = self.curr;
                        content = self.lexer.buffer[content_tok.loc.start..content_tok.loc.end];
                        self.nextToken();
                    }
                    if (self.curr.tag == .t_heredoc_end) {
                        self.nextToken();
                    }
                    return self.createNode(.{ .tag = .literal_string, .main_token = start_tok, .data = .{ .literal_string = .{ .value = try self.context.intern(content) } } });
                } else {
                    // Heredoc: support interpolation like double-quoted strings
                    var left: ?ast.Node.Index = null;
                    while (self.curr.tag != .t_heredoc_end and self.curr.tag != .eof) {
                        const part = switch (self.curr.tag) {
                            .t_encapsed_and_whitespace => blk: {
                                const t = self.curr;
                                self.nextToken();
                                break :blk try self.createNode(.{ .tag = .literal_string, .main_token = t, .data = .{ .literal_string = .{ .value = try self.context.intern(self.lexer.buffer[t.loc.start..t.loc.end]) } } });
                            },
                            .t_variable => blk: {
                                const t = self.curr;
                                self.nextToken();
                                break :blk try self.createNode(.{ .tag = .variable, .main_token = t, .data = .{ .variable = .{ .name = try self.context.intern(self.lexer.buffer[t.loc.start..t.loc.end]) } } });
                            },
                            .t_curly_open => blk: {
                                self.nextToken(); // skip {
                                const expr = try self.parseExpression(0);
                                if (self.curr.tag == .r_brace) self.nextToken();
                                break :blk expr;
                            },
                            else => break,
                        };
                        left = if (left) |l| try self.createNode(.{ .tag = .binary_expr, .main_token = start_tok, .data = .{ .binary_expr = .{ .lhs = l, .op = .dot, .rhs = part } } }) else part;
                    }
                    if (self.curr.tag == .t_heredoc_end) {
                        self.nextToken();
                    }
                    return left orelse try self.createNode(.{ .tag = .literal_string, .main_token = start_tok, .data = .{ .literal_string = .{ .value = try self.context.intern("") } } });
                }
            },
            .l_bracket => self.parseArrayLiteral(),
            .k_array => self.parseArrayConstruct(),
            .l_brace => self.parseJsonObjectLiteral(),
            .l_paren => {
                self.nextToken();
                // Check for type cast: (int), (float), (string), (array), (object), (bool)
                if (self.curr.tag == .k_array or self.curr.tag == .k_object) {
                    const cast_type = self.curr.tag;
                    const cast_token = self.curr;
                    self.nextToken();
                    if (self.curr.tag == .r_paren) {
                        self.nextToken();
                        // Parse the expression being cast
                        const cast_expr = try self.parseUnaryPostfix();
                        return self.createNode(.{ .tag = .cast_expr, .main_token = cast_token, .data = .{ .cast_expr = .{ .cast_type = cast_type, .expr = cast_expr } } });
                    }
                } else if (self.curr.tag == .t_string) {
                    // Check for type names like int, float, string, bool
                    const type_name = self.lexer.buffer[self.curr.loc.start..self.curr.loc.end];
                    if (std.mem.eql(u8, type_name, "int") or std.mem.eql(u8, type_name, "float") or
                        std.mem.eql(u8, type_name, "string") or std.mem.eql(u8, type_name, "bool") or
                        std.mem.eql(u8, type_name, "integer") or std.mem.eql(u8, type_name, "boolean") or
                        std.mem.eql(u8, type_name, "double") or std.mem.eql(u8, type_name, "real"))
                    {
                        const cast_token = self.curr;
                        self.nextToken();
                        if (self.curr.tag == .r_paren) {
                            self.nextToken();
                            const cast_expr = try self.parseUnaryPostfix();
                            // Use t_string as cast_type and store name for VM to handle
                            return self.createNode(.{ .tag = .cast_expr, .main_token = cast_token, .data = .{ .cast_expr = .{ .cast_type = .t_string, .expr = cast_expr } } });
                        }
                    }
                }
                // Regular parenthesized expression
                const expr = try self.parseExpression(0);
                _ = try self.eat(.r_paren);
                return expr;
            },
            else => {
                self.reportError("Unexpected token in expression");
                return error.InvalidExpression;
            },
        };
    }

    fn parseInterpolatedString(self: *Parser) anyerror!ast.Node.Index {
        const start_token = try self.eat(.t_double_quote);
        var left: ?ast.Node.Index = null;

        while (self.curr.tag != .t_double_quote and self.curr.tag != .eof) {
            var part: ast.Node.Index = 0;
            const op_token = self.curr;

            switch (self.curr.tag) {
                .t_encapsed_and_whitespace => {
                    const t = try self.eat(.t_encapsed_and_whitespace);
                    part = try self.createNode(.{ .tag = .literal_string, .main_token = t, .data = .{ .literal_string = .{ .value = try self.context.intern(self.lexer.buffer[t.loc.start..t.loc.end]) } } });
                },
                .t_variable => {
                    const t = try self.eat(.t_variable);
                    part = try self.createNode(.{ .tag = .variable, .main_token = t, .data = .{ .variable = .{ .name = try self.context.intern(self.lexer.buffer[t.loc.start..t.loc.end]) } } });
                },
                .t_curly_open => {
                    self.nextToken(); // Consume {$
                    part = try self.parseExpression(0);
                    _ = try self.eat(.r_brace);
                },
                .t_dollar_open_curly_brace => {
                    self.nextToken(); // Consume ${
                    // ${name} 语法：name 应作为变量名处理，需加上 $ 前缀
                    if (self.curr.tag == .t_string) {
                        const t = try self.eat(.t_string);
                        const raw_name = self.lexer.buffer[t.loc.start..t.loc.end];
                        // 添加 $ 前缀作为变量名
                        const var_name = try std.fmt.allocPrint(self.allocator, "${s}", .{raw_name});
                        defer self.allocator.free(var_name);
                        part = try self.createNode(.{ .tag = .variable, .main_token = t, .data = .{ .variable = .{ .name = try self.context.intern(var_name) } } });
                    } else {
                        // 复杂表达式 ${expr}
                        part = try self.parseExpression(0);
                    }
                    _ = try self.eat(.r_brace);
                },
                else => {
                    self.reportError("Unexpected token in interpolated string");
                    return error.InvalidInterpolation;
                },
            }

            if (left) |l| {
                left = try self.createNode(.{ .tag = .binary_expr, .main_token = op_token, .data = .{ .binary_expr = .{ .lhs = l, .op = .dot, .rhs = part } } });
            } else {
                left = part;
            }
        }

        _ = try self.eat(.t_double_quote);

        if (left) |l| return l;

        // Empty string ""
        return self.createNode(.{ .tag = .literal_string, .main_token = start_token, .data = .{ .literal_string = .{ .value = try self.context.intern("") } } });
    }

    fn parseClosure(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_function);
        _ = try self.eat(.l_paren);

        // Parse parameters
        var params = std.ArrayListUnmanaged(ast.Node.Index){};
        while (self.curr.tag != .r_paren and self.curr.tag != .eof) {
            try params.append(self.allocator, try self.parseParameter());
            if (self.curr.tag == .comma) self.nextToken();
        }

        _ = try self.eat(.r_paren);

        // Parse capture list (use clause)
        var captures = std.ArrayListUnmanaged(ast.Node.Index){};
        if (self.curr.tag == .k_use) {
            self.nextToken();
            _ = try self.eat(.l_paren);
            while (self.curr.tag != .r_paren) {
                try captures.append(self.allocator, try self.parseExpression(0));
                if (self.curr.tag == .comma) self.nextToken();
            }
            _ = try self.eat(.r_paren);
        }

        const body = try self.parseBlock();
        const arena = self.context.arena.allocator();
        const params_slice = try arena.dupe(ast.Node.Index, params.items);
        const captures_slice = try arena.dupe(ast.Node.Index, captures.items);
        params.deinit(self.allocator);
        captures.deinit(self.allocator);
        return self.createNode(.{ .tag = .closure, .main_token = token, .data = .{ .closure = .{ .attributes = &.{}, .params = params_slice, .captures = captures_slice, .return_type = null, .body = body, .is_static = false } } });
    }

    fn parseMatch(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_match);
        _ = try self.eat(.l_paren);
        const expr = try self.parseExpression(0);
        _ = try self.eat(.r_paren);
        _ = try self.eat(.l_brace);
        var arms = std.ArrayListUnmanaged(ast.Node.Index){};
        while (self.curr.tag != .r_brace and self.curr.tag != .eof) {
            const cond = try self.parseExpression(0);
            _ = try self.eat(.fat_arrow);
            const body = try self.parseExpression(0);
            const arm = try self.createNode(.{ .tag = .match_arm, .main_token = token, .data = .{ .match_arm = .{ .conditions = &.{cond}, .body = body } } });
            try arms.append(self.allocator, arm);
            if (self.curr.tag == .comma) self.nextToken();
        }
        _ = try self.eat(.r_brace);
        const arena = self.context.arena.allocator();
        const arms_slice = try arena.dupe(ast.Node.Index, arms.items);
        arms.deinit(self.allocator);
        return self.createNode(.{ .tag = .match_expr, .main_token = token, .data = .{ .match_expr = .{ .expression = expr, .arms = arms_slice } } });
    }

    fn parseNewOrAnonymousClass(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_new);
        if (self.curr.tag == .k_class) {
            self.nextToken();
            const body = try self.parseBlock();
            return self.createNode(.{ .tag = .anonymous_class, .main_token = token, .data = .{ .anonymous_class = .{ .attributes = &.{}, .extends = null, .implements = &.{}, .members = &.{body}, .args = &.{} } } });
        }

        const class_name = try self.parsePrimary();
        var args = std.ArrayListUnmanaged(ast.Node.Index){};

        if (self.curr.tag == .l_paren) {
            self.nextToken();
            while (self.curr.tag != .r_paren and self.curr.tag != .eof) {
                try args.append(self.allocator, try self.parseExpression(0));
                if (self.curr.tag == .comma) self.nextToken();
            }
            _ = try self.eat(.r_paren);
        }

        const arena = self.context.arena.allocator();
        const args_slice = try arena.dupe(ast.Node.Index, args.items);
        args.deinit(self.allocator);
        return self.createNode(.{ .tag = .object_instantiation, .main_token = token, .data = .{ .object_instantiation = .{ .class_name = class_name, .args = args_slice } } });
    }

    fn parseCloneExpression(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_clone);
        const object = try self.parseExpression(100);

        if (self.curr.tag == .k_with) {
            self.nextToken();
            _ = try self.eat(.l_brace);

            var properties = std.ArrayListUnmanaged(ast.Node.Index){};

            while (self.curr.tag != .r_brace and self.curr.tag != .eof) {
                const prop_name = try self.parseExpression(0);
                _ = try self.eat(.colon);
                const prop_value = try self.parseExpression(0);

                // Create a property assignment node
                const assignment = try self.createNode(.{ .tag = .assignment, .main_token = token, .data = .{ .assignment = .{ .target = prop_name, .value = prop_value } } });
                try properties.append(self.allocator, assignment);

                if (self.curr.tag == .comma) self.nextToken();
            }
            _ = try self.eat(.r_brace);

            // Create array node for properties
            const arena = self.context.arena.allocator();
            const props_slice = try arena.dupe(ast.Node.Index, properties.items);
            properties.deinit(self.allocator);
            const props_array = try self.createNode(.{ .tag = .array_init, .main_token = token, .data = .{ .array_init = .{ .elements = props_slice } } });

            return self.createNode(.{ .tag = .clone_with_expr, .main_token = token, .data = .{ .clone_with_expr = .{ .object = object, .properties = props_array } } });
        } else {
            // Regular clone without modifications
            return self.createNode(.{ .tag = .unary_expr, .main_token = token, .data = .{ .unary_expr = .{ .op = .k_clone, .expr = object } } });
        }
    }

    fn getPrecedence(self: *Parser, tag: Token.Tag) u8 {
        _ = self;
        return switch (tag) {
            .plus_plus, .minus_minus => 120, // Postfix increment/decrement (highest precedence)
            .l_paren => 110,
            .l_bracket => 110, // Array access
            .arrow => 100,
            .double_colon => 100, // Static access has same precedence as instance access
            .pipe_greater => 90, // Pipe operator has high precedence
            .asterisk, .slash, .percent => 60,
            .plus, .minus, .dot => 50, // String concatenation has same precedence as addition/subtraction
            .less, .greater, .less_equal, .greater_equal, .spaceship => 40,
            .equal_equal, .equal_equal_equal, .bang_equal, .bang_equal_equal => 35,
            .ampersand => 30, // Bitwise AND
            .pipe => 25, // Bitwise OR
            .double_ampersand => 20, // Logical AND
            .double_pipe => 10, // Logical OR
            .double_question => 8, // Null coalescing
            .question => 7, // Ternary
            .equal, .plus_equal, .minus_equal, .asterisk_equal, .slash_equal, .percent_equal => 5,
            else => 0,
        };
    }

    fn createNode(self: *Parser, node: ast.Node) anyerror!ast.Node.Index {
        const idx: u32 = @intCast(self.context.nodes.items.len);
        try self.context.nodes.append(self.allocator, node);
        return idx;
    }

    fn parseArrowFunction(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_fn);
        _ = try self.eat(.l_paren);

        var params = std.ArrayListUnmanaged(ast.Node.Index){};

        while (self.curr.tag != .r_paren) {
            try params.append(self.allocator, try self.parseParameter());
            if (self.curr.tag == .comma) self.nextToken();
        }
        _ = try self.eat(.r_paren);

        var return_type: ?ast.Node.Index = null;
        if (self.curr.tag == .colon) {
            self.nextToken();
            return_type = try self.parseType();
        }

        _ = try self.eat(.fat_arrow);
        const body = try self.parseExpression(0);

        const arena = self.context.arena.allocator();
        const params_slice = try arena.dupe(ast.Node.Index, params.items);

        // 在创建节点前清理params数组，避免内存泄漏
        params.deinit(self.allocator);

        return self.createNode(.{ .tag = .arrow_function, .main_token = token, .data = .{ .arrow_function = .{ .attributes = &.{}, .params = params_slice, .return_type = return_type, .body = body, .is_static = false } } });
    }

    fn parseArrayConstruct(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_array);
        _ = try self.eat(.l_paren);

        var elements = std.ArrayListUnmanaged(ast.Node.Index){};
        while (self.curr.tag != .r_paren) {
            // Check for key => value syntax
            const first_expr = try self.parseExpression(0);
            if (self.curr.tag == .fat_arrow) {
                self.nextToken();
                const value_expr = try self.parseExpression(0);
                const pair = try self.createNode(.{ .tag = .array_pair, .main_token = token, .data = .{ .array_pair = .{ .key = first_expr, .value = value_expr } } });
                try elements.append(self.allocator, pair);
            } else {
                try elements.append(self.allocator, first_expr);
            }

            if (self.curr.tag == .comma) {
                self.nextToken();
            } else {
                break;
            }
        }
        _ = try self.eat(.r_paren);

        return self.createNode(.{ .tag = .array_init, .main_token = token, .data = .{ .array_init = .{ .elements = try self.context.arena.allocator().dupe(ast.Node.Index, elements.items) } } });
    }

    fn parseArrayLiteral(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.l_bracket);

        var elements = std.ArrayListUnmanaged(ast.Node.Index){};

        while (self.curr.tag != .r_bracket and self.curr.tag != .eof) {
            // 解析第一个表达式（可能是键或值）
            const first_expr = try self.parseExpression(0);

            // 检查是否有 => 符号（关联数组语法）
            if (self.curr.tag == .fat_arrow) {
                // 有 => 符号，创建键值对节点
                _ = try self.eat(.fat_arrow);
                const value_expr = try self.parseExpression(0);

                // 创建键值对节点
                const pair_node = try self.createNode(.{ .tag = .array_pair, .main_token = token, .data = .{ .array_pair = .{ .key = first_expr, .value = value_expr } } });
                try elements.append(self.allocator, pair_node);
            } else {
                // 没有 => 符号，普通数组元素
                try elements.append(self.allocator, first_expr);
            }

            if (self.curr.tag == .comma) {
                self.nextToken();
            } else {
                break;
            }
        }

        _ = try self.eat(.r_bracket);

        // 先复制到arena，然后立即清理ArrayList
        const arena = self.context.arena.allocator();
        const elements_slice = try arena.dupe(ast.Node.Index, elements.items);

        // 在复制后立即清理，避免后续操作导致的问题
        elements.deinit(self.allocator);

        return self.createNode(.{ .tag = .array_init, .main_token = token, .data = .{ .array_init = .{ .elements = elements_slice } } });
    }

    /// 解析 JSON 风格的对象字面量 {"key": "value", ...}
    /// 将其转换为 PHP 关联数组
    fn parseJsonObjectLiteral(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.l_brace);

        var elements = std.ArrayListUnmanaged(ast.Node.Index){};

        while (self.curr.tag != .r_brace and self.curr.tag != .eof) {
            // JSON 对象的键必须是字符串
            const key_expr = try self.parseExpression(0);

            // 检查是否有 : 符号（JSON 风格）或 => 符号（PHP 风格）
            if (self.curr.tag == .colon) {
                // JSON 风格 "key": value
                _ = try self.eat(.colon);
                const value_expr = try self.parseExpression(0);

                // 创建键值对节点
                const pair_node = try self.createNode(.{ .tag = .array_pair, .main_token = token, .data = .{ .array_pair = .{ .key = key_expr, .value = value_expr } } });
                try elements.append(self.allocator, pair_node);
            } else if (self.curr.tag == .fat_arrow) {
                // PHP 风格 "key" => value
                _ = try self.eat(.fat_arrow);
                const value_expr = try self.parseExpression(0);

                const pair_node = try self.createNode(.{ .tag = .array_pair, .main_token = token, .data = .{ .array_pair = .{ .key = key_expr, .value = value_expr } } });
                try elements.append(self.allocator, pair_node);
            } else {
                self.reportError("Expected ':' or '=>' in object literal");
                return error.InvalidExpression;
            }

            if (self.curr.tag == .comma) {
                self.nextToken();
            } else {
                break;
            }
        }

        _ = try self.eat(.r_brace);

        // 先复制到arena，然后立即清理ArrayList
        const arena = self.context.arena.allocator();
        const elements_slice = try arena.dupe(ast.Node.Index, elements.items);
        elements.deinit(self.allocator);

        return self.createNode(.{ .tag = .array_init, .main_token = token, .data = .{ .array_init = .{ .elements = elements_slice } } });
    }

    fn parseType(self: *Parser) anyerror!ast.Node.Index {
        return self.parseUnionType();
    }

    fn parseUnionType(self: *Parser) anyerror!ast.Node.Index {
        const left = try self.parseIntersectionType();

        if (self.curr.tag == .pipe) {
            var types = std.ArrayListUnmanaged(ast.Node.Index){};
            try types.append(self.allocator, left);

            while (self.curr.tag == .pipe) {
                self.nextToken();
                try types.append(self.allocator, try self.parseIntersectionType());
            }

            const arena = self.context.arena.allocator();
            const types_slice = try arena.dupe(ast.Node.Index, types.items);
            types.deinit(self.allocator);
            return self.createNode(.{ .tag = .union_type, .main_token = self.curr, .data = .{ .union_type = .{ .types = types_slice } } });
        }

        return left;
    }

    fn parseIntersectionType(self: *Parser) anyerror!ast.Node.Index {
        const left = try self.parsePrimaryType();

        // Check for intersection type: Type&OtherType
        // But NOT reference parameter: int &$var (ampersand followed by variable)
        if (self.curr.tag == .ampersand) {
            // Use peek to see if next token is a variable (reference parameter case)
            // If so, don't parse as intersection type - let parseParameter handle it
            if (self.peek.tag == .t_variable or self.peek.tag == .ellipsis) {
                return left;
            }

            var types = std.ArrayListUnmanaged(ast.Node.Index){};
            try types.append(self.allocator, left);

            while (self.curr.tag == .ampersand) {
                // Check peek: if next is variable or ellipsis, stop parsing intersection
                if (self.peek.tag == .t_variable or self.peek.tag == .ellipsis) {
                    break;
                }
                self.nextToken();
                try types.append(self.allocator, try self.parsePrimaryType());
            }

            if (types.items.len > 1) {
                const arena = self.context.arena.allocator();
                const types_slice = try arena.dupe(ast.Node.Index, types.items);
                types.deinit(self.allocator);
                return self.createNode(.{ .tag = .intersection_type, .main_token = self.curr, .data = .{ .intersection_type = .{ .types = types_slice } } });
            }
            types.deinit(self.allocator);
        }

        return left;
    }

    fn parsePrimaryType(self: *Parser) anyerror!ast.Node.Index {
        // Handle nullable types (?type)
        if (self.curr.tag == .question) {
            const q_tok = self.curr;
            self.nextToken();
            const inner_type = try self.parsePrimaryType();
            return self.createNode(.{ .tag = .nullable_type, .main_token = q_tok, .data = .{ .nullable_type = .{ .inner = inner_type } } });
        } else if (self.curr.tag == .l_paren) {
            self.nextToken();
            const type_node = try self.parseType();
            _ = try self.eat(.r_paren);
            return type_node;
        } else if (self.curr.tag == .t_string or self.curr.tag == .k_array or
            self.curr.tag == .k_callable or self.curr.tag == .k_static or
            self.curr.tag == .k_self or self.curr.tag == .k_parent or
            self.curr.tag == .k_void or self.curr.tag == .k_mixed or
            self.curr.tag == .k_never or self.curr.tag == .k_object or
            self.curr.tag == .k_iterable or self.curr.tag == .k_null or
            self.curr.tag == .k_true or self.curr.tag == .k_false)
        {
            // Handle built-in type keywords and user-defined types
            const type_name_tok = self.curr;
            self.nextToken();
            const type_name_id = try self.context.intern(self.lexer.buffer[type_name_tok.loc.start..type_name_tok.loc.end]);
            return self.createNode(.{ .tag = .named_type, .main_token = type_name_tok, .data = .{ .named_type = .{ .name = type_name_id } } });
        } else {
            self.reportError("Expected type name");
            return error.UnexpectedToken;
        }
    }
};
