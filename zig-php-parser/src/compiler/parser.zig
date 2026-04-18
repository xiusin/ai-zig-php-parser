const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const SyntaxMode = @import("syntax_mode.zig").SyntaxMode;
const SyntaxConfig = @import("syntax_mode.zig").SyntaxConfig;
const Token = @import("token.zig").Token;
const ast = @import("ast.zig");
pub const PHPContext = @import("root.zig").PHPContext;
const extension = @import("extension");

/// Syntax hooks interface for extension system
/// Allows extensions to hook into the parsing process for custom syntax
pub const SyntaxHooks = extension.SyntaxHooks;

pub const Parser = struct {
    lexer: Lexer,
    allocator: std.mem.Allocator,
    context: *PHPContext,
    curr: Token,
    peek: Token,
    syntax_mode: SyntaxMode = .php,
    /// Syntax hooks for extension system (optional)
    syntax_hooks: ?*const SyntaxHooks = null,
    /// Collect all tokens for line number calculation
    all_tokens: std.ArrayList(Token),
    block_depth: u32 = 0,
    top_level_stmt_count: usize = 0,

    pub fn init(allocator: std.mem.Allocator, context: *PHPContext, source: [:0]const u8) anyerror!Parser {
        var lexer = Lexer.init(source);
        const curr = lexer.next();
        const peek = lexer.next();
        var all_tokens = try std.ArrayList(Token).initCapacity(allocator, 100);
        try all_tokens.append(allocator, curr);
        try all_tokens.append(allocator, peek);
        return Parser{
            .lexer = lexer,
            .allocator = allocator,
            .context = context,
            .curr = curr,
            .peek = peek,
            .all_tokens = all_tokens,
        };
    }

    pub fn initWithMode(allocator: std.mem.Allocator, context: *PHPContext, source: [:0]const u8, mode: SyntaxMode) anyerror!Parser {
        var lexer = Lexer.initWithMode(source, mode);
        const curr = lexer.next();
        const peek = lexer.next();
        var all_tokens = try std.ArrayList(Token).initCapacity(allocator, 100);
        try all_tokens.append(allocator, curr);
        try all_tokens.append(allocator, peek);
        return Parser{
            .lexer = lexer,
            .allocator = allocator,
            .context = context,
            .curr = curr,
            .peek = peek,
            .syntax_mode = mode,
            .all_tokens = all_tokens,
        };
    }

    /// Initialize parser with syntax mode and syntax hooks
    pub fn initWithModeAndHooks(allocator: std.mem.Allocator, context: *PHPContext, source: [:0]const u8, mode: SyntaxMode, hooks: ?*const SyntaxHooks) anyerror!Parser {
        var lexer = Lexer.initWithMode(source, mode);
        const curr = lexer.next();
        const peek = lexer.next();
        var all_tokens = try std.ArrayList(Token).initCapacity(allocator, 100);
        try all_tokens.append(allocator, curr);
        try all_tokens.append(allocator, peek);
        return Parser{
            .lexer = lexer,
            .allocator = allocator,
            .context = context,
            .curr = curr,
            .peek = peek,
            .syntax_mode = mode,
            .syntax_hooks = hooks,
            .all_tokens = all_tokens,
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
        self.all_tokens.deinit(self.allocator);
    }

    fn nextToken(self: *Parser) void {
        self.curr = self.peek;
        self.peek = self.lexer.next();
        self.all_tokens.append(self.allocator, self.peek) catch {};
    }

    fn reportError(self: *Parser, msg: []const u8) void {
        // 从当前 token 位置计算行号
        var line: u32 = 1;
        const pos = self.curr.loc.start;
        for (self.lexer.buffer[0..@min(pos, self.lexer.buffer.len)]) |c| {
            if (c == '\n') line += 1;
        }
        const err = @import("root.zig").Error{
            .msg = self.context.arena.allocator().dupe(u8, msg) catch msg,
            .line = line,
            .column = 0,
        };
        self.context.errors.append(self.allocator, err) catch {};
    }

    fn unescapeDoubleQuoted(self: *Parser, input: []const u8) anyerror![]u8 {
        var out = std.ArrayListUnmanaged(u8){};
        errdefer out.deinit(self.allocator);
        try out.ensureTotalCapacity(self.allocator, input.len);

        var i: usize = 0;
        while (i < input.len) : (i += 1) {
            const c = input[i];
            if (c == '\\' and i + 1 < input.len) {
                const n = input[i + 1];
                switch (n) {
                    'n' => try out.append(self.allocator, '\n'),
                    'r' => try out.append(self.allocator, '\r'),
                    't' => try out.append(self.allocator, '\t'),
                    '\\' => try out.append(self.allocator, '\\'),
                    '"' => try out.append(self.allocator, '"'),
                    '$' => try out.append(self.allocator, '$'),
                    else => {
                        try out.append(self.allocator, '\\');
                        try out.append(self.allocator, n);
                    },
                }
                i += 1;
                continue;
            }
            try out.append(self.allocator, c);
        }

        return out.toOwnedSlice(self.allocator);
    }

    fn eat(self: *Parser, tag: Token.Tag) anyerror!Token {
        if (self.curr.tag == tag) {
            const t = self.curr;
            self.nextToken();
            return t;
        }
        // PHP 风格错误：unexpected <actual>, expecting <expected>
        const actual_desc = self.describeToken(self.curr);
        const expected_desc = tagToExpected(tag);
        const arena = self.context.arena.allocator();
        const msg = std.fmt.allocPrint(arena, "syntax error, unexpected {s}, expecting \"{s}\"", .{ actual_desc, expected_desc }) catch "Unexpected Token";
        self.reportError(msg);
        return error.UnexpectedToken;
    }

    fn describeToken(self: *Parser, tok: Token) []const u8 {
        return switch (tok.tag) {
            .t_variable => blk: {
                const text = self.lexer.buffer[tok.loc.start..tok.loc.end];
                const arena = self.context.arena.allocator();
                break :blk std.fmt.allocPrint(arena, "variable \"{s}\"", .{text}) catch "variable";
            },
            .t_string => "identifier",
            .semicolon => "\";\"",
            .l_paren => "\"(\"",
            .r_paren => "\")\"",
            .l_brace => "\"{\"",
            .r_brace => "\"}\"",
            .eof => "end of file",
            else => "token",
        };
    }

    fn tagToExpected(tag: Token.Tag) []const u8 {
        return switch (tag) {
            .l_paren => "(",
            .r_paren => ")",
            .l_brace => "{",
            .r_brace => "}",
            .semicolon => ";",
            .t_string => "identifier",
            else => "token",
        };
    }

    fn synchronize(self: *Parser) void {
        self.nextToken();
        while (self.curr.tag != .eof) {
            if (self.curr.tag == .semicolon) {
                self.nextToken();
                return;
            }
            switch (self.curr.tag) {
                .k_class, .k_interface, .k_trait, .k_enum, .k_function, .k_fn, .k_if, .k_for, .k_while, .k_foreach, .k_return, .k_namespace, .k_use, .k_try, .k_throw, .k_match => return,
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
                .k_class, .k_interface, .k_trait, .k_enum, .k_function, .k_fn, .k_if, .k_for, .k_while, .k_foreach, .k_return, .k_namespace, .k_use, .k_try, .k_throw, .k_match => {
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

        var in_php_mode = false;
        while (self.curr.tag != .eof) {
            if (self.curr.tag == .t_open_tag) {
                if (in_php_mode) {
                    // PHP 模式中遇到第二个 <?php → parse error
                    const loc = self.curr.loc;
                    var line: u32 = 1;
                    for (self.lexer.buffer[0..@min(loc.start, self.lexer.buffer.len)]) |c| {
                        if (c == '\n') line += 1;
                    }
                    try self.context.errors.append(self.allocator, .{
                        .msg = "syntax error, unexpected token \"<\", expecting end of file",
                        .line = line,
                        .column = 0,
                    });
                    break;
                }
                in_php_mode = true;
                self.nextToken();
                continue;
            }
            if (self.curr.tag == .t_close_tag) {
                in_php_mode = false;
                self.nextToken();
                continue;
            }
            if (self.curr.tag == .t_inline_html) {
                self.nextToken();
                continue;
            }
            // 检测重复 <?php 标签（lexer 在 script 模式将 < 解析为 .less）
            if (self.curr.tag == .less) {
                const pos = self.curr.loc.start;
                const buf = self.lexer.buffer;
                if (pos + 4 < buf.len and
                    buf[pos] == '<' and buf[pos + 1] == '?' and
                    buf[pos + 2] == 'p' and buf[pos + 3] == 'h' and
                    buf[pos + 4] == 'p')
                {
                    var line: u32 = 1;
                    for (buf[0..pos]) |c| {
                        if (c == '\n') line += 1;
                    }
                    try self.context.errors.append(self.allocator, .{
                        .msg = "syntax error, unexpected token \"<\", expecting end of file",
                        .line = line,
                        .column = 0,
                    });
                    break;
                }
            }
            const stmt = self.parseStatement() catch {
                self.synchronize();
                continue;
            };
            try stmts.append(self.allocator, stmt);
            self.top_level_stmt_count += 1;
        }

        // Copy all tokens to context for line number calculation
        try self.context.tokens.ensureUnusedCapacity(self.context.allocator, self.all_tokens.items.len);
        for (self.all_tokens.items) |token| {
            self.context.tokens.appendAssumeCapacity(token);
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
            .k_declare => self.parseDeclare(),
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
            .k_do => self.parseDoWhile(),
            .k_for => self.parseFor(),
            .k_foreach => self.parseForeach(),
            .k_try => self.parseTry(),
            .k_throw => self.parseThrow(),
            .k_echo => self.parseEcho(),
            .k_global => self.parseGlobal(),
            .k_static => {
                if (self.peek.tag == .double_colon) return self.parseExpressionStatement();
                return self.parseStatic();
            },
            .k_const => self.parseConst(),
            .k_go => self.parseGo(),
            .k_lock => self.parseLock(),
            .k_goto => self.parseGoto(),
            .k_return => self.parseReturn(),
            .k_break => self.parseBreak(),
            .k_continue => self.parseContinue(),
            .k_require, .k_require_once, .k_include, .k_include_once => self.parseInclude(),
            .k_abstract, .k_final => self.parseModifiedClassOrMember(attributes),
            .k_readonly => {
                // readonly class X or readonly property
                if (self.peek.tag == .k_class) {
                    return self.parseModifiedClassOrMember(attributes);
                }
                return self.parseClassMember(attributes, false);
            },
            .k_public, .k_protected, .k_private => self.parseClassMember(attributes, false),
            .k_switch => self.parseSwitch(),
            .k_yield => self.parseYield(),
            .k_list => self.parseListAssignment(),
            .l_bracket => {
                // Try to parse as array destructuring: [$a, $b] = $arr
                // Look ahead to check if this looks like destructuring
                const peek_tag = self.peek.tag;
                const looks_like_destructure = switch (peek_tag) {
                    .t_variable, .k_list, .comma, .t_constant_encapsed_string, .t_string, .l_bracket => true,
                    else => false,
                };

                if (looks_like_destructure) {
                    return self.parseArrayDestructuring();
                } else {
                    return self.parseExpressionStatement();
                }
            },
            .l_brace => self.parseBlock(),
            .semicolon => blk: {
                // 空语句：解析为空块（用于 for(...); while(...); 等）
                const token = self.curr;
                self.nextToken();
                break :blk self.createNode(.{ .tag = .block, .main_token = token, .data = .{ .block = .{ .stmts = &[_]ast.Node.Index{} } } });
            },
            .t_string => {
                // Check for goto label: identifier followed by colon at statement level
                if (self.peek.tag == .colon) {
                    return self.parseGotoLabel();
                }
                return self.parseExpressionStatement();
            },
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
        var adaptations = std.ArrayListUnmanaged(ast.TraitAdaptation){};

        while (true) {
            try traits.append(self.allocator, try self.parseType());
            if (self.curr.tag == .comma) {
                self.nextToken();
            } else {
                break;
            }
        }

        if (self.curr.tag == .l_brace) {
            _ = try self.eat(.l_brace);
            while (self.curr.tag != .r_brace and self.curr.tag != .eof) {
                self.parseTraitAdaptation(&adaptations) catch {
                    self.skipTraitAdaptationRecovery();
                };
            }
            _ = try self.eat(.r_brace);
        } else {
            _ = try self.eat(.semicolon);
        }

        const arena = self.context.arena.allocator();
        const traits_slice = try arena.dupe(ast.Node.Index, traits.items);
        const adaptations_slice = try arena.dupe(
            ast.TraitAdaptation,
            adaptations.items,
        );
        traits.deinit(self.allocator);
        adaptations.deinit(self.allocator);
        return self.createNode(.{
            .tag = .trait_use,
            .main_token = token,
            .data = .{ .trait_use = .{
                .traits = traits_slice,
                .adaptations = adaptations_slice,
            } },
        });
    }

    fn parseTraitAdaptation(
        self: *Parser,
        adaptations: *std.ArrayListUnmanaged(ast.TraitAdaptation),
    ) anyerror!void {
        const method_ref = try self.parseTraitMethodReference();

        if (self.curr.tag == .t_string) {
            const keyword = self.lexer.buffer[self.curr.loc.start..self.curr.loc.end];
            if (std.mem.eql(u8, keyword, "insteadof")) {
                self.nextToken();

                var excluded_traits = std.ArrayListUnmanaged(u32){};
                defer excluded_traits.deinit(self.allocator);

                while (true) {
                    try excluded_traits.append(
                        self.allocator,
                        try self.parseTraitIdentifier(),
                    );
                    if (self.curr.tag != .comma) break;
                    self.nextToken();
                }

                _ = try self.eat(.semicolon);
                try adaptations.append(self.allocator, .{
                    .insteadof = .{
                        .preferred = method_ref,
                        .excluded_traits = try self.context
                            .arena
                            .allocator()
                            .dupe(u32, excluded_traits.items),
                    },
                });
                return;
            }
        }

        _ = try self.eat(.k_as);

        var visibility: ?ast.TraitVisibility = null;
        if (isTraitVisibilityToken(self.curr.tag)) {
            visibility = self.parseTraitVisibility();
        }

        var alias_name: ?u32 = null;
        if (self.curr.tag != .semicolon) {
            alias_name = try self.parseTraitIdentifier();
        }

        _ = try self.eat(.semicolon);
        try adaptations.append(self.allocator, .{
            .alias = .{
                .original = method_ref,
                .alias = alias_name,
                .visibility = visibility,
            },
        });
    }

    fn parseTraitMethodReference(self: *Parser) anyerror!ast.TraitMethodReference {
        const first_name = try self.parseTraitIdentifier();
        if (self.curr.tag == .double_colon) {
            self.nextToken();
            return .{
                .trait_name = first_name,
                .method_name = try self.parseTraitIdentifier(),
            };
        }
        return .{
            .trait_name = null,
            .method_name = first_name,
        };
    }

    fn parseTraitIdentifier(self: *Parser) anyerror!u32 {
        if (!self.curr.isIdentifier()) {
            return error.UnexpectedToken;
        }
        const token = self.curr;
        self.nextToken();
        return try self.context.intern(
            self.lexer.buffer[token.loc.start..token.loc.end],
        );
    }

    fn isTraitVisibilityToken(tag: Token.Tag) bool {
        return switch (tag) {
            .k_public, .k_protected, .k_private => true,
            else => false,
        };
    }

    fn parseTraitVisibility(self: *Parser) ast.TraitVisibility {
        return switch (self.curr.tag) {
            .k_public => blk: {
                self.nextToken();
                break :blk .public;
            },
            .k_protected => blk: {
                self.nextToken();
                break :blk .protected;
            },
            .k_private => blk: {
                self.nextToken();
                break :blk .private;
            },
            else => unreachable,
        };
    }

    fn skipTraitAdaptationRecovery(self: *Parser) void {
        while (self.curr.tag != .semicolon and
            self.curr.tag != .r_brace and
            self.curr.tag != .eof)
        {
            self.nextToken();
        }
        if (self.curr.tag == .semicolon) {
            self.nextToken();
        }
    }

    fn parseContainerWithModifiers(self: *Parser, tag: ast.Node.Tag, attributes: []const ast.Node.Index, modifiers: ast.Node.Modifier) anyerror!ast.Node.Index {
        const token = self.curr;
        self.nextToken();
        // In Go mode, class names can be t_go_identifier
        const name_tok = if (self.syntax_mode == .go and self.curr.tag == .t_go_identifier)
            try self.eat(.t_go_identifier)
        else
            try self.eat(.t_string);
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
                try implements.append(self.allocator, try self.parseExpression(2));
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
        if (self.curr.tag == .k_function or self.curr.tag == .k_fn) {
            const is_arrow = self.curr.tag == .k_fn;
            const token = try self.eat(if (is_arrow) .k_fn else .k_function);
            // Support return-by-reference: function &methodName()
            if (self.curr.tag == .ampersand) self.nextToken();
            // Method name: t_string, t_go_identifier, or any PHP keyword (context-sensitive)
            const name_tok = if (self.curr.tag == .t_go_identifier)
                try self.eat(.t_go_identifier)
            else if (self.curr.tag == .t_string)
                try self.eat(.t_string)
            else if (self.eatKeywordAsIdentifier()) |tok|
                tok
            else try self.eat(.t_string);
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
            const body: ?ast.Node.Index = blk: {
                if (!expects_body) {
                    if (self.curr.tag == .semicolon) {
                        self.nextToken();
                        break :blk null;
                    } else {
                        return error.UnexpectedToken;
                    }
                }
                if (is_arrow) {
                    // Arrow function body: => expr
                    _ = try self.eat(.fat_arrow);
                    const expr = try self.parseExpression(0);
                    // Create an arrow_function node for the method body
                    const arrow_node = try self.createNode(.{ .tag = .arrow_function, .main_token = token, .data = .{ .arrow_function = .{ .attributes = attributes, .params = try self.context.arena.allocator().dupe(ast.Node.Index, params.items), .return_type = return_type, .body = expr, .is_static = modifiers.is_static } } });
                    // Create a block with just the arrow function as a statement
                    const block_node = try self.createNode(.{ .tag = .block, .main_token = token, .data = .{ .block = .{ .stmts = &[_]ast.Node.Index{arrow_node} } } });
                    break :blk block_node;
                }
                break :blk try self.parseBlock();
            };
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
            var properties = std.ArrayListUnmanaged(ast.Node.Index){};
            defer properties.deinit(self.allocator);

            // Parse first property
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
            }

            const first_prop = try self.createNode(.{ .tag = .property_decl, .main_token = token, .data = .{ .property_decl = .{ .attributes = attributes, .name = name_id, .modifiers = modifiers, .type = type_node, .default_value = default_value, .hooks = try self.context.arena.allocator().dupe(ast.Node.Index, hooks.items) } } });
            try properties.append(self.allocator, first_prop);

            // Parse additional properties if comma-separated
            while (self.curr.tag == .comma) {
                self.nextToken();

                var prop_name_str: []const u8 = undefined;
                if (self.syntax_mode == .go and self.curr.tag == .t_go_identifier) {
                    const name_tok = try self.eat(.t_go_identifier);
                    prop_name_str = self.lexer.buffer[name_tok.loc.start..name_tok.loc.end];
                } else {
                    const name_tok = try self.eat(.t_variable);
                    prop_name_str = self.lexer.buffer[name_tok.loc.start..name_tok.loc.end];
                    if (prop_name_str.len > 0 and prop_name_str[0] == '$') {
                        prop_name_str = prop_name_str[1..];
                    }
                }
                const prop_name_id = try self.context.intern(prop_name_str);

                var prop_default: ?ast.Node.Index = null;
                if (self.curr.tag == .equal) {
                    self.nextToken();
                    prop_default = try self.parseExpression(0);
                }

                var prop_hooks = std.ArrayListUnmanaged(ast.Node.Index){};
                if (self.curr.tag == .l_brace) {
                    self.nextToken();
                    while (self.curr.tag != .r_brace) try prop_hooks.append(self.allocator, try self.parsePropertyHook());
                    _ = try self.eat(.r_brace);
                }

                const prop_node = try self.createNode(.{ .tag = .property_decl, .main_token = token, .data = .{ .property_decl = .{ .attributes = attributes, .name = prop_name_id, .modifiers = modifiers, .type = type_node, .default_value = prop_default, .hooks = try self.context.arena.allocator().dupe(ast.Node.Index, prop_hooks.items) } } });
                try properties.append(self.allocator, prop_node);
            }

            if (self.curr.tag == .semicolon) {
                self.nextToken();
            }

            // If only one property, return it directly
            if (properties.items.len == 1) {
                return properties.items[0];
            }

            // Multiple properties: return as expr_list
            return self.createNode(.{ .tag = .expr_list, .main_token = token, .data = .{ .expr_list = .{ .exprs = try self.context.arena.allocator().dupe(ast.Node.Index, properties.items) } } });
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

        // 处理 const 声明
        if (self.curr.tag == .k_const) {
            return self.parseConst();
        }

        if (self.curr.tag == .k_function or self.curr.tag == .k_fn) {
            const is_arrow = self.curr.tag == .k_fn;
            const token = try self.eat(if (is_arrow) .k_fn else .k_function);
            // Support return-by-reference: function &methodName()
            if (self.curr.tag == .ampersand) self.nextToken();
            // Method name: t_string, t_go_identifier, or any PHP keyword (context-sensitive)
            const name_tok = if (self.curr.tag == .t_go_identifier)
                try self.eat(.t_go_identifier)
            else if (self.curr.tag == .t_string)
                try self.eat(.t_string)
            else if (self.eatKeywordAsIdentifier()) |tok|
                tok
            else try self.eat(.t_string);
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
            const body: ?ast.Node.Index = blk: {
                if (!expects_body) {
                    if (self.curr.tag == .semicolon) {
                        self.nextToken();
                        break :blk null;
                    } else {
                        return error.UnexpectedToken;
                    }
                }
                if (is_arrow) {
                    // Arrow function body: => expr
                    _ = try self.eat(.fat_arrow);
                    const expr = try self.parseExpression(0);
                    // Create an arrow_function node for the method body
                    const arrow_node = try self.createNode(.{ .tag = .arrow_function, .main_token = token, .data = .{ .arrow_function = .{ .attributes = attributes, .params = try self.context.arena.allocator().dupe(ast.Node.Index, params.items), .return_type = return_type, .body = expr, .is_static = modifiers.is_static } } });
                    // Create a block with just the arrow function as a statement
                    const block_node = try self.createNode(.{ .tag = .block, .main_token = token, .data = .{ .block = .{ .stmts = &[_]ast.Node.Index{arrow_node} } } });
                    break :blk block_node;
                }
                break :blk try self.parseBlock();
            };

            // For arrow functions, we need to create a method_decl node
            // For now, create a method_decl with the arrow function as body
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
            var properties = std.ArrayListUnmanaged(ast.Node.Index){};
            defer properties.deinit(self.allocator);

            // Parse first property
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
            }

            const first_prop = try self.createNode(.{ .tag = .property_decl, .main_token = token, .data = .{ .property_decl = .{ .attributes = attributes, .name = name_id, .modifiers = modifiers, .type = type_node, .default_value = default_value, .hooks = try self.context.arena.allocator().dupe(ast.Node.Index, hooks.items) } } });
            try properties.append(self.allocator, first_prop);

            // Parse additional properties if comma-separated
            while (self.curr.tag == .comma) {
                self.nextToken();

                var prop_name_str: []const u8 = undefined;
                if (self.syntax_mode == .go and self.curr.tag == .t_go_identifier) {
                    const name_tok = try self.eat(.t_go_identifier);
                    prop_name_str = self.lexer.buffer[name_tok.loc.start..name_tok.loc.end];
                } else {
                    const name_tok = try self.eat(.t_variable);
                    prop_name_str = self.lexer.buffer[name_tok.loc.start..name_tok.loc.end];
                    if (prop_name_str.len > 0 and prop_name_str[0] == '$') {
                        prop_name_str = prop_name_str[1..];
                    }
                }
                const prop_name_id = try self.context.intern(prop_name_str);

                var prop_default: ?ast.Node.Index = null;
                if (self.curr.tag == .equal) {
                    self.nextToken();
                    prop_default = try self.parseExpression(0);
                }

                var prop_hooks = std.ArrayListUnmanaged(ast.Node.Index){};
                if (self.curr.tag == .l_brace) {
                    self.nextToken();
                    while (self.curr.tag != .r_brace) try prop_hooks.append(self.allocator, try self.parsePropertyHook());
                    _ = try self.eat(.r_brace);
                }

                const prop_node = try self.createNode(.{ .tag = .property_decl, .main_token = token, .data = .{ .property_decl = .{ .attributes = attributes, .name = prop_name_id, .modifiers = modifiers, .type = type_node, .default_value = prop_default, .hooks = try self.context.arena.allocator().dupe(ast.Node.Index, prop_hooks.items) } } });
                try properties.append(self.allocator, prop_node);
            }

            if (self.curr.tag == .semicolon) {
                self.nextToken();
            }

            // If only one property, return it directly
            if (properties.items.len == 1) {
                return properties.items[0];
            }

            // Multiple properties: return as expr_list
            return self.createNode(.{ .tag = .expr_list, .main_token = token, .data = .{ .expr_list = .{ .exprs = try self.context.arena.allocator().dupe(ast.Node.Index, properties.items) } } });
        }
    }

    fn parsePropertyHook(self: *Parser) anyerror!ast.Node.Index {
        const token = self.curr;
        if (self.curr.tag != .k_get and self.curr.tag != .k_set) return error.ExpectedHookName;
        const name_id = try self.context.intern(self.lexer.buffer[self.curr.loc.start..self.curr.loc.end]);
        self.nextToken();
        // PHP 8.4: set hook may have parameter list: set(Type $value) { ... }
        if (self.curr.tag == .l_paren) {
            self.nextToken();
            // Skip parameter list (type and variable)
            while (self.curr.tag != .r_paren and self.curr.tag != .eof) {
                self.nextToken();
            }
            _ = try self.eat(.r_paren);
        }
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

        // Handle global namespace: namespace { ... }
        if (self.curr.tag == .l_brace) {
            // Global namespace block
            self.context.current_namespace = null;
            const body = try self.parseBlock();
            return body;
        }

        const name_tok = try self.eat(.t_string);
        const name_id = try self.context.intern(self.lexer.buffer[name_tok.loc.start..name_tok.loc.end]);
        self.context.current_namespace = name_id;

        // Handle namespace with block: namespace Foo { ... }
        if (self.curr.tag == .l_brace) {
            const body = try self.parseBlock();
            return body;
        }

        // Handle namespace with semicolon: namespace Foo;
        _ = try self.eat(.semicolon);
        return self.createNode(.{ .tag = .namespace_stmt, .main_token = token, .data = .{ .namespace_stmt = .{ .name = name_id } } });
    }

    fn parseUse(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_use);
        var use_type: u8 = 0;
        if (self.curr.tag == .k_function) {
            use_type = 1;
            self.nextToken();
        } else if (self.curr.tag == .k_const) {
            use_type = 2;
            self.nextToken();
        }
        const name_tok = try self.eat(.t_string);
        const name_id = try self.context.intern(self.lexer.buffer[name_tok.loc.start..name_tok.loc.end]);

        // Extract last part for default alias
        var parts = std.mem.splitScalar(u8, self.lexer.buffer[name_tok.loc.start..name_tok.loc.end], '\\');
        var last_part: []const u8 = "";
        while (parts.next()) |part| last_part = part;
        const default_alias_id = try self.context.intern(last_part);

        // Check for explicit alias: use App\Service as S;
        var alias_id: ?u32 = null;
        if (self.curr.tag == .k_as) {
            self.nextToken();
            const alias_tok = try self.eat(.t_string);
            alias_id = try self.context.intern(self.lexer.buffer[alias_tok.loc.start..alias_tok.loc.end]);
            try self.context.imports.put(self.allocator, alias_id.?, name_id);
        } else {
            // Use default alias (last part of namespace)
            try self.context.imports.put(self.allocator, default_alias_id, name_id);
        }

        _ = try self.eat(.semicolon);
        return self.createNode(.{ .tag = .use_stmt, .main_token = token, .data = .{ .use_stmt = .{ .namespace = name_id, .alias = alias_id, .use_type = use_type } } });
    }

    fn parseDeclare(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_declare);
        _ = try self.eat(.l_paren);

        while (true) {
            const name_tok = if (self.curr.tag == .t_string)
                try self.eat(.t_string)
            else if (self.eatKeywordAsIdentifier()) |tok|
                tok
            else
                try self.eat(.t_string);

            const name = self.lexer.buffer[name_tok.loc.start..name_tok.loc.end];
            _ = try self.eat(.equal);
            _ = try self.parseExpression(1);

            if (std.mem.eql(u8, name, "strict_types") and self.block_depth == 0 and self.top_level_stmt_count != 0) {
                self.reportError("strict_types declaration must be the very first statement in the script");
                return error.ParseError;
            }

            if (self.curr.tag != .comma) break;
            self.nextToken();
        }

        _ = try self.eat(.r_paren);
        _ = try self.eat(.semicolon);
        return self.createNode(.{ .tag = .block, .main_token = token, .data = .{ .block = .{ .stmts = &[_]ast.Node.Index{} } } });
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
                        try args.append(self.allocator, try self.parseCallArg());
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
        // In Go mode, class names can be t_go_identifier
        const name_tok = if (self.syntax_mode == .go and self.curr.tag == .t_go_identifier)
            try self.eat(.t_go_identifier)
        else
            try self.eat(.t_string);
        const raw_name_id = try self.context.intern(self.lexer.buffer[name_tok.loc.start..name_tok.loc.end]);
        const name_id = try self.context.resolveName(raw_name_id);

        // PHP enum backed type: enum Color: string { ... }
        var backed_type: ?ast.Node.Index = null;
        if (tag == .enum_decl and self.curr.tag == .colon) {
            self.nextToken();
            backed_type = try self.parseType();
        }

        var extends: ?ast.Node.Index = null;
        if (self.curr.tag == .k_extends) {
            self.nextToken();
            extends = try self.parseExpression(0);
        }
        // For enums, backed_type is stored in extends field
        if (tag == .enum_decl and backed_type != null) {
            extends = backed_type;
        }

        var implements = std.ArrayListUnmanaged(ast.Node.Index){};
        if (self.curr.tag == .k_implements) {
            self.nextToken();
            while (true) {
                try implements.append(self.allocator, try self.parseExpression(2));
                if (self.curr.tag != .comma) break;
                self.nextToken();
            }
        }

        _ = try self.eat(.l_brace);
        var members = std.ArrayListUnmanaged(ast.Node.Index){};

        const is_interface = (tag == .interface_decl);
        const is_enum = (tag == .enum_decl);

        while (self.curr.tag != .r_brace and self.curr.tag != .eof) {
            var member_attributes: []const ast.Node.Index = &.{};
            if (self.curr.tag == .t_attribute_start) member_attributes = try self.parseAttributes();

            if (is_enum and self.curr.tag == .k_case) {
                try members.append(self.allocator, try self.parseEnumCase());
            } else if (self.curr.tag == .k_use) {
                try members.append(self.allocator, try self.parseTraitUse());
            } else {
                try members.append(self.allocator, try self.parseClassMember(&.{}, is_interface));
            }
        }
        _ = try self.eat(.r_brace);

        return self.createNode(.{ .tag = tag, .main_token = token, .data = .{ .container_decl = .{ .attributes = attributes, .name = name_id, .modifiers = .{}, .extends = extends, .implements = try self.context.arena.allocator().dupe(ast.Node.Index, implements.items), .members = try self.context.arena.allocator().dupe(ast.Node.Index, members.items) } } });
    }

    /// Parse an enum case declaration: case Name; or case Name = value;
    fn parseEnumCase(self: *Parser) anyerror!ast.Node.Index {
        const case_token = try self.eat(.k_case);
        const name_tok = try self.eat(.t_string);
        const name_id = try self.context.intern(self.lexer.buffer[name_tok.loc.start..name_tok.loc.end]);
        var value: ?ast.Node.Index = null;
        if (self.curr.tag == .equal) {
            self.nextToken();
            value = try self.parseExpression(0);
        }
        _ = try self.eat(.semicolon);
        return self.createNode(.{
            .tag = .enum_case,
            .main_token = case_token,
            .data = .{ .enum_case = .{ .name = name_id, .value = value } },
        });
    }

    fn parseFunction(self: *Parser, attributes: []const ast.Node.Index) anyerror!ast.Node.Index {
        // 支持 function 和 fn 两个关键字
        const token = if (self.curr.tag == .k_fn)
            try self.eat(.k_fn)
        else
            try self.eat(.k_function);

        // Check for reference return (&)
        const returns_reference = if (self.curr.tag == .ampersand) blk: {
            self.nextToken();
            break :blk true;
        } else false;

        const name_tok = try self.eat(.t_string);
        const raw_name_id = try self.context.intern(self.lexer.buffer[name_tok.loc.start..name_tok.loc.end]);
        const name_id = try self.context.resolveName(raw_name_id);
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
        return self.createNode(.{ .tag = .function_decl, .main_token = token, .data = .{ .function_decl = .{ .attributes = attributes, .name = name_id, .params = try self.context.arena.allocator().dupe(ast.Node.Index, params.items), .body = body, .returns_reference = returns_reference } } });
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
        // In Go mode, t_go_identifier can also be a type name
        if (self.curr.tag == .t_string or self.curr.tag == .t_go_identifier or self.curr.tag == .question or
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
        // In Go mode, parameter names can be t_go_identifier (without $ prefix)
        var name_tok: Token = undefined;
        var name_str: []const u8 = undefined;
        if (self.syntax_mode == .go and self.curr.tag == .t_go_identifier) {
            name_tok = try self.eat(.t_go_identifier);
            name_str = self.lexer.buffer[name_tok.loc.start..name_tok.loc.end];
        } else {
            name_tok = try self.eat(.t_variable);
            name_str = self.lexer.buffer[name_tok.loc.start..name_tok.loc.end];
            // Keep the '$' prefix for PHP-style variables so that parameter names
            // match variable lookups in the function body (e.g., $name -> $name)
        }
        const name_id = try self.context.intern(name_str);

        var default_value: ?ast.Node.Index = null;
        if (self.curr.tag == .equal) {
            self.nextToken();
            default_value = try self.parseExpression(1); // 避免解析逗号运算符
        }

        return self.createNode(.{ .tag = .parameter, .main_token = name_tok, .data = .{ .parameter = .{ .attributes = attributes, .name = name_id, .type = type_node, .default_value = default_value, .is_promoted = modifiers.is_public or modifiers.is_protected or modifiers.is_private, .modifiers = modifiers, .is_variadic = is_variadic, .is_reference = is_reference } } });
    }

    fn parseIf(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_if);
        _ = try self.eat(.l_paren);
        const cond = try self.parseExpression(0);
        _ = try self.eat(.r_paren);
        
        // 检查是否是替代语法 (if ...): ... endif;
        const is_alternative = self.curr.tag == .colon;
        if (is_alternative) {
            _ = try self.eat(.colon);
        }
        
        const then = try self.parseStatement();
        var else_branch: ?ast.Node.Index = null;
        
        if (is_alternative) {
            // 替代语法：处理 elseif/else 直到 endif
            if (self.curr.tag == .k_elseif) {
                else_branch = try self.parseElseifAlternative();
            } else if (self.curr.tag == .k_else) {
                self.nextToken();
                if (self.curr.tag == .colon) {
                    _ = try self.eat(.colon);
                }
                else_branch = try self.parseStatement();
            }
            // 消耗 endif;
            if (self.curr.tag == .k_endif) {
                self.nextToken();
                _ = try self.eat(.semicolon);
            }
        } else {
            // 标准语法
            if (self.curr.tag == .k_elseif) {
                // elseif is parsed as else { if (...) }
                else_branch = try self.parseElseif();
            } else if (self.curr.tag == .k_else) {
                self.nextToken();
                else_branch = try self.parseStatement();
            }
        }
        return self.createNode(.{ .tag = .if_stmt, .main_token = token, .data = .{ .if_stmt = .{ .condition = cond, .then_branch = then, .else_branch = else_branch } } });
    }

    fn parseElseifAlternative(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_elseif);
        _ = try self.eat(.l_paren);
        const cond = try self.parseExpression(0);
        _ = try self.eat(.r_paren);
        if (self.curr.tag == .colon) {
            _ = try self.eat(.colon);
        }
        const then = try self.parseStatement();
        var else_branch: ?ast.Node.Index = null;
        if (self.curr.tag == .k_elseif) {
            else_branch = try self.parseElseifAlternative();
        } else if (self.curr.tag == .k_else) {
            self.nextToken();
            if (self.curr.tag == .colon) {
                _ = try self.eat(.colon);
            }
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
        
        // 检查是否是替代语法 (while ...): ... endwhile;
        const is_alternative = self.curr.tag == .colon;
        if (is_alternative) {
            _ = try self.eat(.colon);
        }
        
        const body = try self.parseStatement();
        
        if (is_alternative) {
            // 消耗 endwhile;
            if (self.curr.tag == .k_endwhile) {
                self.nextToken();
                _ = try self.eat(.semicolon);
            }
        }
        
        return self.createNode(.{ .tag = .while_stmt, .main_token = token, .data = .{ .while_stmt = .{ .condition = cond, .body = body } } });
    }

    fn parseDoWhile(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_do);
        const body = try self.parseStatement();
        _ = try self.eat(.k_while);
        _ = try self.eat(.l_paren);
        const cond = try self.parseExpression(0);
        _ = try self.eat(.r_paren);
        _ = try self.eat(.semicolon);
        return self.createNode(.{ .tag = .do_while_stmt, .main_token = token, .data = .{ .do_while_stmt = .{ .condition = cond, .body = body } } });
    }

    fn parseForeach(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_foreach);
        _ = try self.eat(.l_paren);
        const iterable = try self.parseExpression(0);
        _ = try self.eat(.k_as);

        // 检查第一个表达式是否有引用符号
        var first_by_ref = false;
        if (self.curr.tag == .ampersand) {
            _ = try self.eat(.ampersand);
            first_by_ref = true;
        }

        // 检查是否是 list() 解构语法
        const is_list_destruct = self.curr.tag == .k_list;
        
        // 解析第一个表达式（可能是 list() 解构）
        const first_expr = if (is_list_destruct)
            try self.parseListExpression()
        else
            try self.parseExpression(0);

        // 检查是否有 => 符号（键值对语法）
        var key: ?ast.Node.Index = null;
        var value: ast.Node.Index = undefined;
        var value_by_ref = false;

        if (self.curr.tag == .fat_arrow) {
            // 有 => 符号，第一个表达式是键
            _ = try self.eat(.fat_arrow);
            key = first_expr;

            // 检查值是否是引用
            if (self.curr.tag == .ampersand) {
                _ = try self.eat(.ampersand);
                value_by_ref = true;
            }
            
            // 检查值是否也是 list() 解构
            value = if (self.curr.tag == .k_list)
                try self.parseListExpression()
            else
                try self.parseExpression(0);
        } else {
            // 没有 => 符号，第一个表达式是值
            value = first_expr;
            value_by_ref = first_by_ref;
        }

        _ = try self.eat(.r_paren);

        // 检查是否是替代语法 (foreach ...): ... endforeach;
        const is_alternative = self.curr.tag == .colon;
        if (is_alternative) {
            _ = try self.eat(.colon);
        }

        const body = try self.parseStatement();

        if (is_alternative) {
            // 消耗 endforeach;
            if (self.curr.tag == .k_endforeach) {
                self.nextToken();
                _ = try self.eat(.semicolon);
            }
        }

        return self.createNode(.{ .tag = .foreach_stmt, .main_token = token, .data = .{ .foreach_stmt = .{ .iterable = iterable, .key = key, .value = value, .body = body, .value_by_ref = value_by_ref } } });
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
            const result = try self.createNode(.{ .tag = .for_stmt, .main_token = token, .data = .{ .for_stmt = .{ .init = null, .condition = null, .loop = null, .body = body } } });
            return result;
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

        // Parse initialization (expr1, expr2, ...)
        var init_expr: ?ast.Node.Index = null;
        if (self.curr.tag != .semicolon) {
            var init_exprs = std.ArrayListUnmanaged(ast.Node.Index){};
            while (true) {
                try init_exprs.append(self.allocator, try self.parseExpression(1)); // 优先级 > 逗号 (1)
                if (self.curr.tag != .comma) break;
                self.nextToken(); // consume comma
            }
            // 如果只有一个表达式，直接使用；否则创建表达式列表节点
            if (init_exprs.items.len == 1) {
                init_expr = init_exprs.items[0];
                init_exprs.deinit(self.allocator);
            } else {
                const exprs = try self.context.arena.allocator().dupe(ast.Node.Index, init_exprs.items);
                init_exprs.deinit(self.allocator);
                init_expr = try self.createNode(.{ .tag = .expr_list, .main_token = token, .data = .{ .expr_list = .{ .exprs = exprs } } });
            }
        }
        _ = try self.eat(.semicolon);

        // Parse condition (expr2)
        var condition: ?ast.Node.Index = null;
        if (self.curr.tag != .semicolon) {
            condition = try self.parseExpression(0);
        }
        _ = try self.eat(.semicolon);

        // Parse loop expression (expr3, expr4, ...)
        var loop: ?ast.Node.Index = null;
        if (self.curr.tag != .r_paren) {
            var loop_exprs = std.ArrayListUnmanaged(ast.Node.Index){};
            while (true) {
                try loop_exprs.append(self.allocator, try self.parseExpression(1)); // 优先级 > 逗号 (1)
                if (self.curr.tag != .comma) break;
                self.nextToken(); // consume comma
            }
            // 如果只有一个表达式，直接使用；否则创建表达式列表节点
            if (loop_exprs.items.len == 1) {
                loop = loop_exprs.items[0];
                loop_exprs.deinit(self.allocator);
            } else {
                const exprs = try self.context.arena.allocator().dupe(ast.Node.Index, loop_exprs.items);
                loop_exprs.deinit(self.allocator);
                loop = try self.createNode(.{ .tag = .expr_list, .main_token = token, .data = .{ .expr_list = .{ .exprs = exprs } } });
            }
        }
        _ = try self.eat(.r_paren);

        // 检查是否是替代语法 (for ...): ... endfor;
        const is_alternative = self.curr.tag == .colon;
        if (is_alternative) {
            _ = try self.eat(.colon);
        }

        const body = try self.parseStatement();

        if (is_alternative) {
            // 消耗 endfor;
            if (self.curr.tag == .k_endfor) {
                self.nextToken();
                _ = try self.eat(.semicolon);
            }
        }

        const result = try self.createNode(.{ .tag = .for_stmt, .main_token = token, .data = .{ .for_stmt = .{ .init = init_expr, .condition = condition, .loop = loop, .body = body } } });
        return result;
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
        const raw_name_id = try self.context.intern(self.lexer.buffer[name_tok.loc.start..name_tok.loc.end]);
        const name_id = try self.context.resolveName(raw_name_id);
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

    fn parseGoto(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_goto);
        // goto label;
        if (self.curr.tag != .t_string) {
            self.reportError("expected label name after goto");
            return error.ParseError;
        }
        const label_tok = self.curr;
        const label_name = try self.context.intern(self.lexer.buffer[label_tok.loc.start..label_tok.loc.end]);
        self.nextToken();
        _ = try self.eat(.semicolon);
        return self.createNode(.{ .tag = .goto_stmt, .main_token = token, .data = .{ .goto_stmt = .{ .label = label_name } } });
    }

    fn parseGotoLabel(self: *Parser) anyerror!ast.Node.Index {
        // label:
        const token = self.curr;
        const label_name = try self.context.intern(self.lexer.buffer[token.loc.start..token.loc.end]);
        self.nextToken(); // consume identifier
        _ = try self.eat(.colon); // consume colon
        return self.createNode(.{ .tag = .goto_label, .main_token = token, .data = .{ .goto_label = .{ .label = label_name } } });
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

    fn isValidAssignmentTarget(self: *Parser, node_idx: ast.Node.Index) bool {
        const node = self.context.nodes.items[node_idx];
        return switch (node.tag) {
            .variable, .variable_variable, .array_access, .property_access, .variable_property_access, .static_property_access => true,
            else => false,
        };
    }

    fn parseAssignment(self: *Parser) anyerror!ast.Node.Index {
        // Check if this is a list() assignment
        if (self.curr.tag == .k_list) {
            return self.parseListAssignment();
        }

        const target = try self.parseExpression(100);
        const op = try self.eat(.equal);

        if (!self.isValidAssignmentTarget(target)) {
            self.reportError("Can't use function return value in write context");
            return error.ParseError;
        }

        // Check for reference assignment (&)
        const is_reference = if (self.curr.tag == .ampersand) blk: {
            self.nextToken();
            break :blk true;
        } else false;

        const val = try self.parseExpression(0);
        _ = try self.eat(.semicolon);
        return self.createNode(.{ .tag = .assignment, .main_token = op, .data = .{ .assignment = .{ .target = target, .value = val, .is_reference = is_reference } } });
    }

    /// Parse array destructuring assignment: [$a, $b] = $arr or ['key' => $var] = $arr
    fn parseArrayDestructuring(self: *Parser) anyerror!ast.Node.Index {
        const bracket_token = self.curr;
        _ = try self.eat(.l_bracket);

        var targets = std.ArrayListUnmanaged(ast.Node.Index){};

        while (self.curr.tag != .r_bracket and self.curr.tag != .eof) {
            if (self.curr.tag == .comma) {
                const empty_token = Token{ .tag = .comma, .loc = .{ .start = self.lexer.pos, .end = self.lexer.pos } };
                const empty_node = try self.createNode(.{ .tag = .list_empty, .main_token = empty_token, .data = .{ .list_empty = {} } });
                try targets.append(self.allocator, empty_node);
                self.nextToken();
                continue;
            }

            // Check for keyed destructuring: 'key' => $var or 'key' => [...]
            if (self.curr.tag == .t_constant_encapsed_string or self.curr.tag == .t_string) {
                const key_token = self.curr;
                const key_text = self.lexer.buffer[key_token.loc.start..key_token.loc.end];
                self.nextToken();
                
                if (self.curr.tag == .fat_arrow) {
                    // Keyed destructuring: 'key' => target
                    self.nextToken(); // consume =>
                    
                    // Parse key as string literal (strip quotes if present)
                    var key_content = key_text;
                    if (key_content.len >= 2 and (key_content[0] == '\'' or key_content[0] == '"')) {
                        key_content = key_content[1 .. key_content.len - 1];
                    }
                    const key_id = try self.context.internLiteral(key_content);
                    const key_node = try self.createNode(.{ .tag = .literal_string, .main_token = key_token, .data = .{ .literal_string = .{ .value = key_id } } });
                    
                    // Parse the target (variable or nested array)
                    const target_node = try self.parseDestructuringTarget();
                    
                    // Create array_pair node
                    const pair_node = try self.createNode(.{ .tag = .array_pair, .main_token = key_token, .data = .{ .array_pair = .{ .key = key_node, .value = target_node } } });
                    try targets.append(self.allocator, pair_node);
                } else {
                    // Not keyed, treat as error or skip
                    continue;
                }
            } else if (self.curr.tag == .k_list) {
                const nested_list = try self.parseListExpression();
                try targets.append(self.allocator, nested_list);
            } else if (self.curr.tag == .l_bracket) {
                const nested_node = try self.parseNestedDestructuringArray();
                try targets.append(self.allocator, nested_node);
            } else if (self.curr.tag == .t_variable) {
                const var_name = self.curr;
                const name_id = try self.context.intern(self.lexer.buffer[var_name.loc.start..var_name.loc.end]);
                const var_node = try self.createNode(.{ .tag = .variable, .main_token = var_name, .data = .{ .variable = .{ .name = name_id } } });
                try targets.append(self.allocator, var_node);
                self.nextToken();
            } else {
                self.nextToken();
                continue;
            }

            if (self.curr.tag == .comma) {
                self.nextToken();
                if (self.curr.tag == .r_bracket) break;
            }
        }

        _ = try self.eat(.r_bracket);
        _ = try self.eat(.equal);
        const val = try self.parseExpression(0);
        _ = try self.eat(.semicolon);

        const arena = self.context.arena.allocator();
        return self.createNode(.{ .tag = .list_assignment, .main_token = bracket_token, .data = .{ .list_assignment = .{ .targets = try arena.dupe(ast.Node.Index, targets.items), .value = val } } });
    }

    /// Parse a nested [...] in destructuring context
    fn parseNestedDestructuringArray(self: *Parser) anyerror!ast.Node.Index {
        const bracket_token = self.curr;
        _ = try self.eat(.l_bracket);
        var nested_targets = std.ArrayListUnmanaged(ast.Node.Index){};
        
        while (self.curr.tag != .r_bracket and self.curr.tag != .eof) {
            if (self.curr.tag == .comma) {
                const empty_token = Token{ .tag = .comma, .loc = .{ .start = self.lexer.pos, .end = self.lexer.pos } };
                const empty_node = try self.createNode(.{ .tag = .list_empty, .main_token = empty_token, .data = .{ .list_empty = {} } });
                try nested_targets.append(self.allocator, empty_node);
                self.nextToken();
                continue;
            }
            
            // Check for keyed destructuring in nested array
            if (self.curr.tag == .t_constant_encapsed_string or self.curr.tag == .t_string) {
                const key_token = self.curr;
                const key_text = self.lexer.buffer[key_token.loc.start..key_token.loc.end];
                self.nextToken();
                
                if (self.curr.tag == .fat_arrow) {
                    self.nextToken(); // consume =>
                    var key_content = key_text;
                    if (key_content.len >= 2 and (key_content[0] == '\'' or key_content[0] == '"')) {
                        key_content = key_content[1 .. key_content.len - 1];
                    }
                    const key_id = try self.context.internLiteral(key_content);
                    const key_node = try self.createNode(.{ .tag = .literal_string, .main_token = key_token, .data = .{ .literal_string = .{ .value = key_id } } });
                    const target_node = try self.parseDestructuringTarget();
                    const pair_node = try self.createNode(.{ .tag = .array_pair, .main_token = key_token, .data = .{ .array_pair = .{ .key = key_node, .value = target_node } } });
                    try nested_targets.append(self.allocator, pair_node);
                } else {
                    continue;
                }
            } else if (self.curr.tag == .t_variable) {
                const var_name = self.curr;
                const name_id = try self.context.intern(self.lexer.buffer[var_name.loc.start..var_name.loc.end]);
                const var_node = try self.createNode(.{ .tag = .variable, .main_token = var_name, .data = .{ .variable = .{ .name = name_id } } });
                try nested_targets.append(self.allocator, var_node);
                self.nextToken();
            } else if (self.curr.tag == .l_bracket) {
                const inner_nested = try self.parseNestedDestructuringArray();
                try nested_targets.append(self.allocator, inner_nested);
            } else {
                self.nextToken();
                continue;
            }
            
            if (self.curr.tag == .comma) {
                self.nextToken();
                if (self.curr.tag == .r_bracket) break;
            }
        }
        _ = try self.eat(.r_bracket);
        const arena = self.context.arena.allocator();
        return self.createNode(.{ .tag = .list_assignment, .main_token = bracket_token, .data = .{ .list_assignment = .{ .targets = try arena.dupe(ast.Node.Index, nested_targets.items), .value = 0 } } });
    }

    /// Parse a destructuring target (variable or nested array)
    fn parseDestructuringTarget(self: *Parser) anyerror!ast.Node.Index {
        if (self.curr.tag == .t_variable) {
            const var_name = self.curr;
            const name_id = try self.context.intern(self.lexer.buffer[var_name.loc.start..var_name.loc.end]);
            self.nextToken();
            return self.createNode(.{ .tag = .variable, .main_token = var_name, .data = .{ .variable = .{ .name = name_id } } });
        } else if (self.curr.tag == .l_bracket) {
            return self.parseNestedDestructuringArray();
        } else if (self.curr.tag == .k_list) {
            return self.parseListExpression();
        }
        // Return a dummy empty node for invalid targets
        const empty_token = Token{ .tag = .comma, .loc = .{ .start = self.lexer.pos, .end = self.lexer.pos } };
        return self.createNode(.{ .tag = .list_empty, .main_token = empty_token, .data = .{ .list_empty = {} } });
    }

    fn parseListAssignment(self: *Parser) anyerror!ast.Node.Index {
        const list_token = self.curr;
        _ = try self.eat(.k_list);
        _ = try self.eat(.l_paren);

        var targets = std.ArrayListUnmanaged(ast.Node.Index){};

        // Parse list items
        while (self.curr.tag != .r_paren) {
            if (self.curr.tag == .comma) {
                // Empty slot: comma followed by either another comma, a closing paren,
                // or something that's not a valid list element
                const comma_pos = self.lexer.pos;
                self.nextToken(); // Move past the comma

                // Check if next token is a valid element (variable, list, or closing paren)
                const is_valid_element = switch (self.curr.tag) {
                    .t_variable, .k_list, .r_paren => true,
                    else => false,
                };

                // Create empty node if next token is not a valid element
                if (!is_valid_element) {
                    const empty_token = Token{ .tag = .comma, .loc = .{ .start = comma_pos, .end = comma_pos } };
                    const empty_node = try self.createNode(.{ .tag = .list_empty, .main_token = empty_token, .data = .{ .list_empty = {} } });
                    try targets.append(self.allocator, empty_node);
                }
                continue;
            }

            // Nested list
            if (self.curr.tag == .k_list) {
                const nested_list = try self.parseListExpression();
                try targets.append(self.allocator, nested_list);
            } else {
                // Check for keyed list: 'key' => $var or "key" => $var or 0 => $var
                const is_keyed = (self.curr.tag == .t_string or self.curr.tag == .t_constant_encapsed_string or self.curr.tag == .t_lnumber or self.curr.tag == .t_dnumber) and self.peek.tag == .fat_arrow;
                
                if (is_keyed) {
                    // Parse keyed element: 'key' => $var
                    const key_token = self.curr;
                    const key_tag = self.curr.tag;  // Save tag before nextToken
                    // Directly parse the key literal (string or number)
                    const key_expr = if (key_tag == .t_string or key_tag == .t_constant_encapsed_string) blk: {
                        const str_token = self.curr;
                        self.nextToken();
                        // For t_constant_encapsed_string, remove quotes
                        const raw_str = self.lexer.buffer[str_token.loc.start..str_token.loc.end];
                        const str_content = if (key_tag == .t_constant_encapsed_string and raw_str.len >= 2)
                            raw_str[1..raw_str.len-1]  // Remove quotes
                        else
                            raw_str;
                        const str_id = try self.context.intern(str_content);
                        break :blk try self.createNode(.{ .tag = .literal_string, .main_token = str_token, .data = .{ .literal_string = .{ .value = str_id } } });
                    } else if (key_tag == .t_lnumber) blk: {
                        const num_token = self.curr;
                        self.nextToken();
                        const num_str = self.lexer.buffer[num_token.loc.start..num_token.loc.end];
                        const num_val = std.fmt.parseInt(i64, num_str, 10) catch 0;
                        break :blk try self.createNode(.{ .tag = .literal_int, .main_token = num_token, .data = .{ .literal_int = .{ .value = num_val } } });
                    } else blk: {
                        const num_token = self.curr;
                        self.nextToken();
                        const num_str = self.lexer.buffer[num_token.loc.start..num_token.loc.end];
                        const num_val = std.fmt.parseFloat(f64, num_str) catch 0.0;
                        break :blk try self.createNode(.{ .tag = .literal_float, .main_token = num_token, .data = .{ .literal_float = .{ .value = num_val } } });
                    };
                    _ = try self.eat(.fat_arrow);
                    
                    // Parse the target (variable or nested list)
                    const target_expr = if (self.curr.tag == .k_list)
                        try self.parseListExpression()
                    else if (self.curr.tag == .t_variable) blk: {
                        const var_name = self.curr;
                        const name_id = try self.context.intern(self.lexer.buffer[var_name.loc.start..var_name.loc.end]);
                        const var_node = try self.createNode(.{ .tag = .variable, .main_token = var_name, .data = .{ .variable = .{ .name = name_id } } });
                        self.nextToken();
                        break :blk var_node;
                    } else {
                        return error.UnexpectedToken;
                    };
                    
                    // Create array_pair node for keyed element
                    const pair_node = try self.createNode(.{ .tag = .array_pair, .main_token = key_token, .data = .{ .array_pair = .{ .key = key_expr, .value = target_expr } } });
                    try targets.append(self.allocator, pair_node);
                    
                    // Skip comma if present
                    if (self.curr.tag == .comma) self.nextToken();
                } else if (self.curr.tag == .t_variable) {
                    // Single variable - get the variable name
                    const var_name = self.curr;
                    const name_id = try self.context.intern(self.lexer.buffer[var_name.loc.start..var_name.loc.end]);
                    const var_node = try self.createNode(.{ .tag = .variable, .main_token = var_name, .data = .{ .variable = .{ .name = name_id } } });
                    try targets.append(self.allocator, var_node);
                    self.nextToken();
                    
                    // Skip comma if present
                    if (self.curr.tag == .comma) self.nextToken();
                } else {
                    // Unknown token - skip it to avoid infinite loop
                    self.nextToken();
                }
            }
        }

        _ = try self.eat(.r_paren);
        _ = try self.eat(.equal);
        const val = try self.parseExpression(0);
        _ = try self.eat(.semicolon);

        const arena = self.context.arena.allocator();
        return self.createNode(.{ .tag = .list_assignment, .main_token = list_token, .data = .{ .list_assignment = .{ .targets = try arena.dupe(ast.Node.Index, targets.items), .value = val } } });
    }

    fn parseListExpression(self: *Parser) anyerror!ast.Node.Index {
        const list_token = self.curr;
        _ = try self.eat(.k_list);
        _ = try self.eat(.l_paren);

        var targets = std.ArrayListUnmanaged(ast.Node.Index){};

        while (self.curr.tag != .r_paren) {
            if (self.curr.tag == .comma) {
                // Empty slot: comma followed by either another comma, a closing paren,
                // or something that's not a valid list element
                const comma_pos = self.lexer.pos;
                self.nextToken(); // Move past the comma

                // Check if next token is a valid element (variable, list, or closing paren)
                const is_valid_element = switch (self.curr.tag) {
                    .t_variable, .k_list, .r_paren => true,
                    else => false,
                };

                // Create empty node if next token is not a valid element
                if (!is_valid_element) {
                    const empty_token = Token{ .tag = .comma, .loc = .{ .start = comma_pos, .end = comma_pos } };
                    const empty_node = try self.createNode(.{ .tag = .list_empty, .main_token = empty_token, .data = .{ .list_empty = {} } });
                    try targets.append(self.allocator, empty_node);
                }
                continue;
            }

            if (self.curr.tag == .k_list) {
                const nested = try self.parseListExpression();
                try targets.append(self.allocator, nested);
            } else {
                // Check for keyed list: 'key' => $var or "key" => $var or 0 => $var
                const is_keyed = (self.curr.tag == .t_string or self.curr.tag == .t_constant_encapsed_string or self.curr.tag == .t_lnumber or self.curr.tag == .t_dnumber) and self.peek.tag == .fat_arrow;
                
                if (is_keyed) {
                    // Parse keyed element: 'key' => $var
                    const key_token = self.curr;
                    const key_tag = self.curr.tag;  // Save tag before nextToken
                    // Directly parse the key literal (string or number)
                    const key_expr = if (key_tag == .t_string or key_tag == .t_constant_encapsed_string) blk: {
                        const str_token = self.curr;
                        self.nextToken();
                        // For t_constant_encapsed_string, remove quotes
                        const raw_str = self.lexer.buffer[str_token.loc.start..str_token.loc.end];
                        const str_content = if (key_tag == .t_constant_encapsed_string and raw_str.len >= 2)
                            raw_str[1..raw_str.len-1]  // Remove quotes
                        else
                            raw_str;
                        const str_id = try self.context.intern(str_content);
                        break :blk try self.createNode(.{ .tag = .literal_string, .main_token = str_token, .data = .{ .literal_string = .{ .value = str_id } } });
                    } else if (key_tag == .t_lnumber) blk: {
                        const num_token = self.curr;
                        self.nextToken();
                        const num_str = self.lexer.buffer[num_token.loc.start..num_token.loc.end];
                        const num_val = std.fmt.parseInt(i64, num_str, 10) catch 0;
                        break :blk try self.createNode(.{ .tag = .literal_int, .main_token = num_token, .data = .{ .literal_int = .{ .value = num_val } } });
                    } else blk: {
                        const num_token = self.curr;
                        self.nextToken();
                        const num_str = self.lexer.buffer[num_token.loc.start..num_token.loc.end];
                        const num_val = std.fmt.parseFloat(f64, num_str) catch 0.0;
                        break :blk try self.createNode(.{ .tag = .literal_float, .main_token = num_token, .data = .{ .literal_float = .{ .value = num_val } } });
                    };
                    _ = try self.eat(.fat_arrow);
                    
                    // Parse the target (variable or nested list)
                    const target_expr = if (self.curr.tag == .k_list)
                        try self.parseListExpression()
                    else if (self.curr.tag == .t_variable) blk: {
                        const var_name = self.curr;
                        const name_id = try self.context.intern(self.lexer.buffer[var_name.loc.start..var_name.loc.end]);
                        const var_node = try self.createNode(.{ .tag = .variable, .main_token = var_name, .data = .{ .variable = .{ .name = name_id } } });
                        self.nextToken();
                        break :blk var_node;
                    } else {
                        return error.UnexpectedToken;
                    };
                    
                    // Create array_pair node for keyed element
                    const pair_node = try self.createNode(.{ .tag = .array_pair, .main_token = key_token, .data = .{ .array_pair = .{ .key = key_expr, .value = target_expr } } });
                    try targets.append(self.allocator, pair_node);
                    
                    // Skip comma if present
                    if (self.curr.tag == .comma) self.nextToken();
                } else if (self.curr.tag == .t_variable) {
                    const var_name = self.curr;
                    const name_id = try self.context.intern(self.lexer.buffer[var_name.loc.start..var_name.loc.end]);
                    const var_node = try self.createNode(.{ .tag = .variable, .main_token = var_name, .data = .{ .variable = .{ .name = name_id } } });
                    try targets.append(self.allocator, var_node);
                    self.nextToken();
                    
                    // Skip comma if present
                    if (self.curr.tag == .comma) self.nextToken();
                } else {
                    // Unknown token - skip it to avoid infinite loop
                    self.nextToken();
                }
            }
        }

        _ = try self.eat(.r_paren);
        const arena = self.context.arena.allocator();
        return self.createNode(.{ .tag = .list_assignment, .main_token = list_token, .data = .{ .list_assignment = .{ .targets = try arena.dupe(ast.Node.Index, targets.items), .value = 0 } } });
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
        self.block_depth += 1;
        defer self.block_depth -= 1;

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
                // Check for dynamic property access: $obj->{'expr'}
                if (self.curr.tag == .l_brace) {
                    self.nextToken();
                    const expr_node = try self.parseExpression(0);
                    _ = try self.eat(.r_brace);
                    left = try self.createNode(.{ .tag = .variable_property_access, .main_token = op, .data = .{ .variable_property_access = .{ .target = left, .prop_variable = expr_node } } });
                    continue;
                }

                // 方法名可以是标识符，也可以是某些关键字（如 set, get）
                // In Go mode, member names are t_go_identifier; in PHP mode, they are t_string
                const member_name_tok = if (self.curr.tag == .t_string)
                    try self.eat(.t_string)
                else if (self.curr.tag == .t_go_identifier)
                    try self.eat(.t_go_identifier)
                else if (self.eatKeywordAsIdentifier()) |tok|
                    tok
                else if (self.curr.tag == .t_variable) {
                    // 可变属性: $obj->$varName
                    const var_node = try self.parseUnary();
                    left = try self.createNode(.{ .tag = .variable_property_access, .main_token = op, .data = .{ .variable_property_access = .{ .target = left, .prop_variable = var_node } } });
                    continue;
                } else try self.eat(.t_string);
                const member_id = try self.context.intern(self.lexer.buffer[member_name_tok.loc.start..member_name_tok.loc.end]);
                if (self.curr.tag == .l_paren) {
                    self.nextToken();
                    
                    // 检查是否是 first-class callable: $obj->method(...)
                    // 注意区分: method(...) 是 first-class callable, method(...$var) 是 spread
                    if (self.curr.tag == .ellipsis and self.peek.tag == .r_paren) {
                        self.nextToken();
                        _ = try self.eat(.r_paren);
                        
                        // 创建一个闭包: fn(...$args) => $obj->method(...$args)
                        // 1. 创建可变参数 ...$args
                        const args_var_id = try self.context.intern("args");
                        const args_param = try self.createNode(.{ .tag = .parameter, .main_token = op, .data = .{ .parameter = .{ .attributes = &.{}, .name = args_var_id, .type = null, .default_value = null, .is_promoted = false, .modifiers = .{}, .is_variadic = true, .is_reference = false } } });
                        
                        // 2. 创建 $args 变量引用
                        const args_var = try self.createNode(.{ .tag = .variable, .main_token = op, .data = .{ .variable = .{ .name = args_var_id } } });
                        
                        // 3. 创建 ...$args (unpack)
                        const args_unpack = try self.createNode(.{ .tag = .unpacking_expr, .main_token = op, .data = .{ .unpacking_expr = .{ .expr = args_var } } });
                        
                        // 4. 创建方法调用 $obj->method(...$args)
                        const method_call_args = try self.context.arena.allocator().alloc(ast.Node.Index, 1);
                        method_call_args[0] = args_unpack;
                        const method_call = try self.createNode(.{ .tag = .method_call, .main_token = op, .data = .{ .method_call = .{ .target = left, .method_name = member_id, .args = method_call_args } } });
                        
                        // 5. 创建箭头函数
                        const arrow_params = try self.context.arena.allocator().alloc(ast.Node.Index, 1);
                        arrow_params[0] = args_param;
                        left = try self.createNode(.{ .tag = .arrow_function, .main_token = op, .data = .{ .arrow_function = .{ .attributes = &.{}, .params = arrow_params, .return_type = null, .body = method_call, .is_static = false } } });
                    } else {
                        // 普通方法调用（包括 spread 参数 ...$var）
                        var args = std.ArrayListUnmanaged(ast.Node.Index){};
                        while (self.curr.tag != .r_paren and self.curr.tag != .eof) {
                            try args.append(self.allocator, try self.parseCallArg());
                            if (self.curr.tag == .comma) self.nextToken();
                        }
                        _ = try self.eat(.r_paren);
                        left = try self.createNode(.{ .tag = .method_call, .main_token = op, .data = .{ .method_call = .{ .target = left, .method_name = member_id, .args = try self.context.arena.allocator().dupe(ast.Node.Index, args.items) } } });
                    }
                } else {
                    left = try self.createNode(.{ .tag = .property_access, .main_token = op, .data = .{ .property_access = .{ .target = left, .property_name = member_id } } });
                }
            } else if (tag == .safe_arrow or tag == .safe_dot) {
                const member_name_tok = if (self.curr.tag == .t_string)
                    try self.eat(.t_string)
                else if (self.curr.tag == .t_go_identifier)
                    try self.eat(.t_go_identifier)
                else if (self.eatKeywordAsIdentifier()) |tok|
                    tok
                else try self.eat(.t_string);
                const member_id = try self.context.intern(self.lexer.buffer[member_name_tok.loc.start..member_name_tok.loc.end]);
                // 安全导航操作符目前只支持属性访问，不支持方法调用
                left = try self.createNode(.{ .tag = .safe_property_access, .main_token = op, .data = .{ .safe_property_access = .{ .target = left, .property_name = member_id } } });
            } else if (tag == .double_colon) {
                // Static access: ClassName::member, self::member, parent::member, $obj::member
                const left_node = self.context.nodes.items[left];

                // 获取类名ID，支持variable、self_expr、parent_expr节点
                const class_name_id = switch (left_node.tag) {
                    .variable => left_node.data.variable.name,
                    .self_expr => left_node.data.variable.name,
                    .parent_expr => left_node.data.variable.name,
                    .static_expr => left_node.data.variable.name,
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
                    // Allow keywords as valid member names after ::
                    const member_name_tok = if (self.curr.tag == .t_string)
                        try self.eat(.t_string)
                    else if (self.eatKeywordAsIdentifier()) |tok|
                        tok
                    else
                        try self.eat(.t_string);
                    const member_id = try self.context.intern(self.lexer.buffer[member_name_tok.loc.start..member_name_tok.loc.end]);
                    if (self.curr.tag == .l_paren) {
                        self.nextToken();
                        // Check for first-class callable: Class::method(...)
                        if (self.curr.tag == .ellipsis and self.peek.tag == .r_paren) {
                            self.nextToken(); // consume ...
                            _ = try self.eat(.r_paren);
                            // Build "ClassName::methodName" string for Closure::fromCallable
                            const class_str = self.context.string_pool.keys()[class_name_id];
                            const method_str = self.context.string_pool.keys()[member_id];
                            var buf: [512]u8 = undefined;
                            const callable_name = std.fmt.bufPrint(&buf, "{s}::{s}", .{ class_str, method_str }) catch "unknown";
                            const callable_id = try self.context.intern(callable_name);
                            const callable_node = try self.createNode(.{
                                .tag = .literal_string,
                                .main_token = op,
                                .data = .{ .literal_string = .{ .value = callable_id } },
                            });
                            const callable_args = try self.context.arena.allocator().alloc(ast.Node.Index, 1);
                            callable_args[0] = callable_node;
                            
                            // Create a static method call to Closure::fromCallable
                            const closure_class_id = try self.context.intern("Closure");
                            const from_callable_id = try self.context.intern("fromCallable");
                            left = try self.createNode(.{
                                .tag = .static_method_call,
                                .main_token = op,
                                .data = .{ .static_method_call = .{
                                    .class_name = closure_class_id,
                                    .method_name = from_callable_id,
                                    .args = callable_args,
                                } },
                            });
                            continue;
                        }
                        var args = std.ArrayListUnmanaged(ast.Node.Index){};
                        while (self.curr.tag != .r_paren and self.curr.tag != .eof) {
                            try args.append(self.allocator, try self.parseCallArg());
                            if (self.curr.tag == .comma) self.nextToken();
                        }
                        _ = try self.eat(.r_paren);
                        left = try self.createNode(.{ .tag = .static_method_call, .main_token = op, .data = .{ .static_method_call = .{ .class_name = class_name_id, .method_name = member_id, .args = try self.context.arena.allocator().dupe(ast.Node.Index, args.items) } } });
                    } else {
                        left = try self.createNode(.{ .tag = .class_constant_access, .main_token = op, .data = .{ .class_constant_access = .{ .class_name = class_name_id, .constant_name = member_id } } });
                    }
                }
            } else if (tag == .l_paren) {
                // PHP 8.1 first-class callable: func(...)
                if (self.curr.tag == .ellipsis and self.peek.tag == .r_paren) {
                    self.nextToken(); // consume ...
                    _ = try self.eat(.r_paren);
                    // Create a Closure::fromCallable wrapper - store function name as string
                    const closure_name_node = left;
                    const callable_args = try self.context.arena.allocator().alloc(ast.Node.Index, 1);
                    callable_args[0] = closure_name_node;
                    
                    // Create a static method call to Closure::fromCallable
                    const closure_class_id = try self.context.intern("Closure");
                    const from_callable_id = try self.context.intern("fromCallable");
                    left = try self.createNode(.{
                        .tag = .static_method_call,
                        .main_token = op,
                        .data = .{ .static_method_call = .{
                            .class_name = closure_class_id,
                            .method_name = from_callable_id,
                            .args = callable_args,
                        } },
                    });
                    continue;
                }
                var args = std.ArrayListUnmanaged(ast.Node.Index){};
                while (self.curr.tag != .r_paren) {
                    // Check for named parameter: name: value
                    if (self.curr.tag == .t_string and self.peek.tag == .colon) {
                        const name_tok = self.curr;
                        const name_id = try self.context.intern(self.lexer.buffer[name_tok.loc.start..name_tok.loc.end]);
                        self.nextToken(); // skip name
                        self.nextToken(); // skip colon
                        const value_expr = try self.parseExpression(1);
                        const named_arg_node = try self.createNode(.{
                            .tag = .named_arg,
                            .main_token = name_tok,
                            .data = .{ .named_arg = .{ .name = name_id, .value = value_expr } },
                        });
                        try args.append(self.allocator, named_arg_node);
                    } else {
                        // 使用优先级2跳过逗号运算符（逗号优先级是1）
                        try args.append(self.allocator, try self.parseExpression(2));
                    }
                    if (self.curr.tag == .comma) self.nextToken();
                }
                _ = try self.eat(.r_paren);
                left = try self.createNode(.{ .tag = .function_call, .main_token = op, .data = .{ .function_call = .{ .name = left, .args = try self.context.arena.allocator().dupe(ast.Node.Index, args.items) } } });
            } else if (tag == .l_bracket) {
                var index: ?ast.Node.Index = null;
                if (self.curr.tag != .r_bracket) {
                    index = try self.parseExpression(1);
                }
                _ = try self.eat(.r_bracket);
                left = try self.createNode(.{ .tag = .array_access, .main_token = op, .data = .{ .array_access = .{ .target = left, .index = index } } });
            } else if (tag == .pipe_greater) {
                const right = try self.parseExpression(next_p);
                left = try self.createNode(.{ .tag = .pipe_expr, .main_token = op, .data = .{ .pipe_expr = .{ .left = left, .right = right } } });
            } else if (tag == .equal) {
                if (!self.isValidAssignmentTarget(left)) {
                    self.reportError("Can't use function return value in write context");
                    return error.ParseError;
                }
                const right = try self.parseExpression(precedence);
                left = try self.createNode(.{ .tag = .assignment, .main_token = op, .data = .{ .assignment = .{ .target = left, .value = right } } });
            } else if (tag == .plus_equal or tag == .minus_equal or tag == .asterisk_equal or tag == .slash_equal or tag == .percent_equal or tag == .dot_equal or tag == .star_star_equal or tag == .less_less_equal or tag == .greater_greater_equal or tag == .and_equal or tag == .or_equal or tag == .caret_equal or tag == .double_question_equal) {
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
            } else if (tag == .k_instanceof) {
                // For instanceof, the right operand should be a class name (identifier or variable)
                // If it's a simple identifier, create a class name literal
                var right: ast.Node.Index = undefined;
                if (self.curr.tag == .t_string) {
                    // Class name is an identifier - create a string literal node
                    const name_tok = self.curr;
                    const name_id = try self.context.intern(self.lexer.buffer[name_tok.loc.start..name_tok.loc.end]);
                    self.nextToken();
                    // Create a literal_string node for the class name
                    right = try self.createNode(.{ .tag = .literal_string, .main_token = name_tok, .data = .{ .literal_string = .{ .value = name_id } } });
                } else {
                    // For variables or expressions, use normal parsing
                    right = try self.parseExpression(next_p);
                }
                left = try self.createNode(.{ .tag = .binary_expr, .main_token = op, .data = .{ .binary_expr = .{ .lhs = left, .op = .k_instanceof, .rhs = right } } });
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
            .bang, .minus, .plus, .ampersand, .tilde => {
                const token = self.curr;
                self.nextToken();
                // Use parseUnary to handle cases like !!$x or !$obj->method()
                const expr = try self.parseUnary();
                return self.createNode(.{ .tag = .unary_expr, .main_token = token, .data = .{ .unary_expr = .{ .op = tag, .expr = expr } } });
            },
            .at_sign => {
                // @ error suppression: 生成 unary_expr 节点，IR generator 包装为错误抑制
                const token = self.curr;
                self.nextToken();
                const expr = try self.parseUnary();
                return self.createNode(.{ .tag = .unary_expr, .main_token = token, .data = .{ .unary_expr = .{ .op = .at_sign, .expr = expr } } });
            },
            .t_variable, .t_go_identifier => {
                return self.parseUnaryPostfix();
            },
            .plus_plus, .minus_minus => {
                const token = self.curr;
                self.nextToken();
                // 使用parseExpression(0)解析操作数，允许解析所有运算符
                // 这样可以正确解析self::$prop等复杂表达式
                const expr = try self.parseExpression(0);
                return self.createNode(.{ .tag = .unary_expr, .main_token = token, .data = .{ .unary_expr = .{ .op = tag, .expr = expr } } });
            },
            .k_clone => return self.parseCloneExpression(),
            else => return self.parseUnaryPostfix(),
        }
    }

    // Parse primary expression with postfix operators (function calls, array access, etc.)
    fn parseUnaryPostfix(self: *Parser) anyerror!ast.Node.Index {
        var left = try self.parsePrimary();

        // Handle postfix operators: function calls, array access, method calls, property access
        while (true) {
            const tag = self.curr.tag;
            if (tag == .l_paren) {
                // Function call
                const op = self.curr;
                self.nextToken();
                // PHP 8.1 first-class callable: func(...)
                if (self.curr.tag == .ellipsis and self.peek.tag == .r_paren) {
                    self.nextToken(); // consume ...
                    _ = try self.eat(.r_paren);
                    const closure_name_node = left;
                    const callable_args = try self.context.arena.allocator().alloc(ast.Node.Index, 1);
                    callable_args[0] = closure_name_node;
                    
                    // Create a static method call to Closure::fromCallable
                    const closure_class_id = try self.context.intern("Closure");
                    const from_callable_id = try self.context.intern("fromCallable");
                    left = try self.createNode(.{
                        .tag = .static_method_call,
                        .main_token = op,
                        .data = .{ .static_method_call = .{
                            .class_name = closure_class_id,
                            .method_name = from_callable_id,
                            .args = callable_args,
                        } },
                    });
                    continue;
                }
                var args = std.ArrayList(ast.Node.Index){};
                while (self.curr.tag != .r_paren and self.curr.tag != .eof) {
                    // Check for named argument: name: value
                    if (self.curr.tag == .t_string and self.peek.tag == .colon) {
                        const name_tok = self.curr;
                        const name_id = try self.context.intern(self.lexer.buffer[name_tok.loc.start..name_tok.loc.end]);
                        self.nextToken(); // skip name
                        self.nextToken(); // skip colon
                        const value_expr = try self.parseExpression(1);
                        const named_arg_node = try self.createNode(.{
                            .tag = .named_arg,
                            .main_token = name_tok,
                            .data = .{ .named_arg = .{ .name = name_id, .value = value_expr } },
                        });
                        try args.append(self.allocator, named_arg_node);
                    } else {
                        // 使用优先级2跳过逗号运算符（逗号优先级是1）
                        try args.append(self.allocator, try self.parseExpression(2));
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
                    index = try self.parseExpression(1);
                }
                _ = try self.eat(.r_bracket);
                left = try self.createNode(.{ .tag = .array_access, .main_token = op, .data = .{ .array_access = .{ .target = left, .index = index } } });
            } else if (tag == .arrow) {
                // Method call or property access: $obj->method(...) or $obj->property
                const op = self.curr;
                self.nextToken();

                // Check for dynamic property access: $obj->{'expr'}
                if (self.curr.tag == .l_brace) {
                    self.nextToken();
                    const expr_node = try self.parseExpression(0);
                    _ = try self.eat(.r_brace);
                    left = try self.createNode(.{ .tag = .variable_property_access, .main_token = op, .data = .{ .variable_property_access = .{ .target = left, .prop_variable = expr_node } } });
                    continue;
                }

                // Parse method/property name
                const member_name_tok = if (self.curr.tag == .t_string)
                    try self.eat(.t_string)
                else if (self.curr.tag == .t_go_identifier)
                    try self.eat(.t_go_identifier)
                else if (self.eatKeywordAsIdentifier()) |tok|
                    tok
                else if (self.curr.tag == .t_variable) {
                    // 可变属性: $obj->$varName
                    const var_node = try self.parseUnaryPostfix();
                    left = try self.createNode(.{ .tag = .variable_property_access, .main_token = op, .data = .{ .variable_property_access = .{ .target = left, .prop_variable = var_node } } });
                    continue;
                } else try self.eat(.t_string);

                const member_id = try self.context.intern(self.lexer.buffer[member_name_tok.loc.start..member_name_tok.loc.end]);

                if (self.curr.tag == .l_paren) {
                    self.nextToken();
                    
                    // 检查是否是 first-class callable: $obj->method(...)
                    // 注意区分: method(...) 是 first-class callable, method(...$var) 是 spread
                    if (self.curr.tag == .ellipsis and self.peek.tag == .r_paren) {
                        self.nextToken();
                        _ = try self.eat(.r_paren);
                        
                        // 创建一个闭包: fn(...$args) => $obj->method(...$args)
                        // 1. 创建可变参数 ...$args
                        const args_var_id = try self.context.intern("args");
                        const args_param = try self.createNode(.{ .tag = .parameter, .main_token = op, .data = .{ .parameter = .{ .attributes = &.{}, .name = args_var_id, .type = null, .default_value = null, .is_promoted = false, .modifiers = .{}, .is_variadic = true, .is_reference = false } } });
                        
                        // 2. 创建 $args 变量引用
                        const args_var = try self.createNode(.{ .tag = .variable, .main_token = op, .data = .{ .variable = .{ .name = args_var_id } } });
                        
                        // 3. 创建 ...$args (unpack)
                        const args_unpack = try self.createNode(.{ .tag = .unpacking_expr, .main_token = op, .data = .{ .unpacking_expr = .{ .expr = args_var } } });
                        
                        // 4. 创建方法调用 $obj->method(...$args)
                        const method_call_args = try self.context.arena.allocator().alloc(ast.Node.Index, 1);
                        method_call_args[0] = args_unpack;
                        const method_call = try self.createNode(.{ .tag = .method_call, .main_token = op, .data = .{ .method_call = .{ .target = left, .method_name = member_id, .args = method_call_args } } });
                        
                        // 5. 创建箭头函数
                        const arrow_params = try self.context.arena.allocator().alloc(ast.Node.Index, 1);
                        arrow_params[0] = args_param;
                        left = try self.createNode(.{ .tag = .arrow_function, .main_token = op, .data = .{ .arrow_function = .{ .attributes = &.{}, .params = arrow_params, .return_type = null, .body = method_call, .is_static = false } } });
                    } else {
                        // 普通方法调用
                        var args = std.ArrayListUnmanaged(ast.Node.Index){};
                        while (self.curr.tag != .r_paren and self.curr.tag != .eof) {
                            try args.append(self.allocator, try self.parseCallArg());
                            if (self.curr.tag == .comma) self.nextToken();
                        }
                        _ = try self.eat(.r_paren);
                        left = try self.createNode(.{ .tag = .method_call, .main_token = op, .data = .{ .method_call = .{ .target = left, .method_name = member_id, .args = try self.context.arena.allocator().dupe(ast.Node.Index, args.items) } } });
                    }
                } else {
                    // Property access
                    left = try self.createNode(.{ .tag = .property_access, .main_token = op, .data = .{ .property_access = .{ .target = left, .property_name = member_id } } });
                }
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
            .k_unset => {
                const tok = try self.eat(.k_unset);
                const name_id = try self.context.intern(self.lexer.buffer[tok.loc.start..tok.loc.end]);
                return self.createNode(.{ .tag = .variable, .main_token = tok, .data = .{ .variable = .{ .name = name_id } } });
            },
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
            .k_static => {
                const t = try self.eat(.k_static);
                const name_id = try self.context.intern("static");
                return self.createNode(.{ .tag = .static_expr, .main_token = t, .data = .{ .variable = .{ .name = name_id } } });
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
            .k_yield => return self.parseYieldExpr(),
            .ellipsis => {
                const token = self.curr;
                self.nextToken();
                const expr = try self.parseExpression(100);
                return self.createNode(.{ .tag = .unpacking_expr, .main_token = token, .data = .{ .unpacking_expr = .{ .expr = expr } } });
            },
            .t_variable => {
                const t = try self.eat(.t_variable);
                const var_name = self.lexer.buffer[t.loc.start..t.loc.end];
                // 检查是否是 $$var 形式（可变变量）
                if (var_name.len >= 2 and var_name[0] == '$' and var_name[1] == '$') {
                    // $$var -> variable_variable(variable($var))
                    const inner_name = var_name[1..]; // 去掉第一个 $，保留 $var
                    const inner_name_id = try self.context.intern(inner_name);
                    const inner_var = try self.createNode(.{ .tag = .variable, .main_token = t, .data = .{ .variable = .{ .name = inner_name_id } } });
                    return self.createNode(.{ .tag = .variable_variable, .main_token = t, .data = .{ .variable_variable = .{ .expr = inner_var } } });
                }
                return self.createNode(.{ .tag = .variable, .main_token = t, .data = .{ .variable = .{ .name = try self.context.intern(var_name) } } });
            },
            .t_dollar_open_curly_brace => {
                const t = self.curr;
                self.nextToken();
                const inner_expr = try self.parseExpression(0);
                _ = try self.eat(.r_brace);
                return self.createNode(.{ .tag = .variable_variable, .main_token = t, .data = .{ .variable_variable = .{ .expr = inner_expr } } });
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
                const raw = self.lexer.buffer[t.loc.start..t.loc.end];
                
                // PHP 支持传统八进制格式 (0755) 和新格式 (0o755)
                // Zig 的 parseInt(base=0) 只支持新格式，需要手动处理传统格式
                const value = blk: {
                    // 检测传统八进制：以 0 开头，后面跟数字，且不是 0x/0b/0o
                    if (raw.len >= 2 and raw[0] == '0' and raw[1] >= '0' and raw[1] <= '7') {
                        // 可能是传统八进制，检查是否所有字符都是 0-7
                        var is_octal = true;
                        for (raw[1..]) |c| {
                            if (c < '0' or c > '7') {
                                is_octal = false;
                                break;
                            }
                        }
                        if (is_octal) {
                            // 传统八进制格式，手动解析
                            break :blk std.fmt.parseInt(i64, raw[1..], 8) catch |err| switch (err) {
                                error.Overflow => std.math.maxInt(i64),
                                else => return err,
                            };
                        }
                    }
                    
                    // 其他格式：使用 base 0 自动检测 (0x=hex, 0b=binary, 0o=octal, else=decimal)
                    break :blk std.fmt.parseInt(i64, raw, 0) catch |err| switch (err) {
                        error.Overflow => std.math.maxInt(i64),
                        else => return err,
                    };
                };
                
                return self.createNode(.{ .tag = .literal_int, .main_token = t, .data = .{ .literal_int = .{ .value = value } } });
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

                const interned_id = if (quote_type == .double) blk: {
                    const unescaped = try self.unescapeDoubleQuoted(string_content);
                    defer self.allocator.free(unescaped);
                    break :blk try self.context.internLiteral(unescaped);
                } else try self.context.internLiteral(string_content);

                return self.createNode(.{ .tag = .literal_string, .main_token = t, .data = .{ .literal_string = .{ .value = interned_id, .quote_type = quote_type } } });
            },
            .t_encapsed_and_whitespace => {
                const t = try self.eat(.t_encapsed_and_whitespace);
                // 需要对插值字符串中的文本部分进行转义处理
                const raw_content = self.lexer.buffer[t.loc.start..t.loc.end];
                const unescaped = try self.unescapeDoubleQuoted(raw_content);
                defer self.allocator.free(unescaped);
                return self.createNode(.{ .tag = .literal_string, .main_token = t, .data = .{ .literal_string = .{ .value = try self.context.internLiteral(unescaped) } } });
            },
            .t_backtick_string => {
                const t = try self.eat(.t_backtick_string);
                const raw_text = self.lexer.buffer[t.loc.start..t.loc.end];
                const string_content = if (raw_text.len >= 2 and raw_text[0] == '`' and raw_text[raw_text.len - 1] == '`')
                    raw_text[1 .. raw_text.len - 1]
                else
                    raw_text;
                return self.createNode(.{ .tag = .literal_string, .main_token = t, .data = .{ .literal_string = .{ .value = try self.context.internLiteral(string_content), .quote_type = .backtick } } });
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
                    return self.createNode(.{ .tag = .literal_string, .main_token = start_tok, .data = .{ .literal_string = .{ .value = try self.context.internLiteral(content) } } });
                } else {
                    // Heredoc: support interpolation like double-quoted strings
                    var left: ?ast.Node.Index = null;
                    while (self.curr.tag != .t_heredoc_end and self.curr.tag != .eof) {
                        const part = switch (self.curr.tag) {
                            .t_encapsed_and_whitespace => blk: {
                                const t = self.curr;
                                self.nextToken();
                                // 需要对heredoc中的文本部分进行转义处理
                                const raw_content = self.lexer.buffer[t.loc.start..t.loc.end];
                                const unescaped = try self.unescapeDoubleQuoted(raw_content);
                                defer self.allocator.free(unescaped);
                                break :blk try self.createNode(.{ .tag = .literal_string, .main_token = t, .data = .{ .literal_string = .{ .value = try self.context.internLiteral(unescaped) } } });
                            },
                            .t_variable => blk: {
                                const t = self.curr;
                                self.nextToken();
                                const var_text = self.lexer.buffer[t.loc.start..t.loc.end];

                                // 检查是否包含 -> (格式: $var->prop)
                                if (std.mem.indexOf(u8, var_text, "->")) |arrow_pos| {
                                    // 分割变量名和属性名
                                    const var_part = var_text[0..arrow_pos]; // $var
                                    const prop_part = var_text[arrow_pos + 2 ..]; // prop

                                    // 创建变量节点
                                    const var_node = try self.createNode(.{ .tag = .variable, .main_token = t, .data = .{ .variable = .{ .name = try self.context.intern(var_part) } } });

                                    // 创建属性访问节点
                                    break :blk try self.createNode(.{ .tag = .property_access, .main_token = t, .data = .{ .property_access = .{ .target = var_node, .property_name = try self.context.intern(prop_part) } } });
                                } else {
                                    // 普通变量
                                    break :blk try self.createNode(.{ .tag = .variable, .main_token = t, .data = .{ .variable = .{ .name = try self.context.intern(var_text) } } });
                                }
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
                    return left orelse try self.createNode(.{ .tag = .literal_string, .main_token = start_tok, .data = .{ .literal_string = .{ .value = try self.context.internLiteral("") } } });
                }
            },
            .l_bracket => self.parseArrayLiteral(),
            .k_array => self.parseArrayConstruct(),
            .l_brace => self.parseJsonObjectLiteral(),
            // PHP 8.0+ throw expression support (throw can be used as expression, not just statement)
            // 使用 precedence 1 避免消费 match arm 分隔逗号
            .k_throw => {
                const token = try self.eat(.k_throw);
                const expression = try self.parseExpression(1);
                return self.createNode(.{ .tag = .throw_stmt, .main_token = token, .data = .{ .throw_stmt = .{ .expression = expression } } });
            },
            // 允许 range 作为函数调用（PHP内置函数）
            .k_range => {
                const t = try self.eat(.k_range);
                const name_id = try self.context.intern("range");
                return self.createNode(.{ .tag = .variable, .main_token = t, .data = .{ .variable = .{ .name = name_id } } });
            },
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
                        const cast_type: Token.Tag = if (std.mem.eql(u8, type_name, "int") or std.mem.eql(u8, type_name, "integer"))
                            .cast_int
                        else if (std.mem.eql(u8, type_name, "float") or std.mem.eql(u8, type_name, "double") or std.mem.eql(u8, type_name, "real"))
                            .cast_float
                        else if (std.mem.eql(u8, type_name, "string"))
                            .cast_string
                        else
                            .cast_bool;
                        self.nextToken();
                        if (self.curr.tag == .r_paren) {
                            self.nextToken();
                            const cast_expr = try self.parseUnaryPostfix();
                            return self.createNode(.{ .tag = .cast_expr, .main_token = cast_token, .data = .{ .cast_expr = .{ .cast_type = cast_type, .expr = cast_expr } } });
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
                    // 需要对插值字符串中的文本部分进行转义处理
                    const raw_content = self.lexer.buffer[t.loc.start..t.loc.end];
                    const unescaped = try self.unescapeDoubleQuoted(raw_content);
                    defer self.allocator.free(unescaped);
                    part = try self.createNode(.{ .tag = .literal_string, .main_token = t, .data = .{ .literal_string = .{ .value = try self.context.internLiteral(unescaped) } } });
                },
                .t_variable => {
                    const t = try self.eat(.t_variable);
                    const var_text = self.lexer.buffer[t.loc.start..t.loc.end];

                    // 检查是否包含 -> (格式: $var->prop)
                    if (std.mem.indexOf(u8, var_text, "->")) |arrow_pos| {
                        // 分割变量名和属性名
                        const var_part = var_text[0..arrow_pos]; // $var
                        const prop_part = var_text[arrow_pos + 2 ..]; // prop

                        // 创建变量节点
                        const var_node = try self.createNode(.{ .tag = .variable, .main_token = t, .data = .{ .variable = .{ .name = try self.context.intern(var_part) } } });

                        // 创建属性访问节点
                        part = try self.createNode(.{ .tag = .property_access, .main_token = t, .data = .{ .property_access = .{ .target = var_node, .property_name = try self.context.intern(prop_part) } } });
                    } else {
                        // 普通变量
                        part = try self.createNode(.{ .tag = .variable, .main_token = t, .data = .{ .variable = .{ .name = try self.context.intern(var_text) } } });
                    }
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
        return self.createNode(.{ .tag = .literal_string, .main_token = start_token, .data = .{ .literal_string = .{ .value = try self.context.internLiteral("") } } });
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

        // Parse optional return type declaration (: type)
        var return_type: ?ast.Node.Index = null;
        if (self.curr.tag == .colon) {
            self.nextToken(); // consume ':'
            return_type = try self.parseType();
        }

        const body = try self.parseBlock();
        const arena = self.context.arena.allocator();
        const params_slice = try arena.dupe(ast.Node.Index, params.items);
        const captures_slice = try arena.dupe(ast.Node.Index, captures.items);
        params.deinit(self.allocator);
        captures.deinit(self.allocator);
        return self.createNode(.{ .tag = .closure, .main_token = token, .data = .{ .closure = .{ .attributes = &.{}, .params = params_slice, .captures = captures_slice, .return_type = return_type, .body = body, .is_static = false } } });
    }

    fn parseMatch(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_match);
        _ = try self.eat(.l_paren);
        const expr = try self.parseExpression(0);
        _ = try self.eat(.r_paren);
        _ = try self.eat(.l_brace);
        var arms = std.ArrayListUnmanaged(ast.Node.Index){};
        var default_arm: ?ast.Node.Index = null;
        const arena = self.context.arena.allocator();

        while (self.curr.tag != .r_brace and self.curr.tag != .eof) {
            if (self.curr.tag == .k_default) {
                self.nextToken();
                _ = try self.eat(.fat_arrow);
                const body = try self.parseExpression(1); // 使用 1 避免解析逗号
                default_arm = try self.createNode(.{ .tag = .match_arm, .main_token = token, .data = .{ .match_arm = .{ .conditions = &.{}, .body = body } } });
            } else {
                // Parse comma-separated conditions: expr1, expr2, ... => body
                var conds = std.ArrayListUnmanaged(ast.Node.Index){};
                const first_cond = try self.parseExpression(1);
                try conds.append(self.allocator, first_cond);
                while (self.curr.tag == .comma) {
                    self.nextToken();
                    // Stop if next is fat_arrow (shouldn't happen) or default/rbrace
                    if (self.curr.tag == .fat_arrow or self.curr.tag == .r_brace or self.curr.tag == .eof) break;
                    try conds.append(self.allocator, try self.parseExpression(1));
                }
                _ = try self.eat(.fat_arrow);
                const body = try self.parseExpression(1);
                const conditions = try arena.dupe(ast.Node.Index, conds.items);
                conds.deinit(self.allocator);
                const arm = try self.createNode(.{ .tag = .match_arm, .main_token = token, .data = .{ .match_arm = .{ .conditions = conditions, .body = body } } });
                try arms.append(self.allocator, arm);
            }
            if (self.curr.tag == .comma) self.nextToken();
        }
        _ = try self.eat(.r_brace);
        const arms_slice = try arena.dupe(ast.Node.Index, arms.items);
        arms.deinit(self.allocator);
        return self.createNode(.{ .tag = .match_expr, .main_token = token, .data = .{ .match_expr = .{ .expression = expr, .arms = arms_slice, .default = default_arm } } });
    }

    fn parseSwitch(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_switch);
        _ = try self.eat(.l_paren);
        const expr = try self.parseExpression(0);
        _ = try self.eat(.r_paren);

        // 检查是否是替代语法 (switch ...): ... endswitch;
        const is_alternative = self.curr.tag == .colon;
        if (is_alternative) {
            _ = try self.eat(.colon);
        } else {
            _ = try self.eat(.l_brace);
        }

        var cases = std.ArrayListUnmanaged(ast.Node.Index){};
        var default_case: ?ast.Node.Index = null;

        // 使用 Token.Tag 类型避免 comptime-only 错误
        const end_token: Token.Tag = if (is_alternative) .k_endswitch else .r_brace;
        while (self.curr.tag != end_token and self.curr.tag != .eof) {
            if (self.curr.tag == .k_case) {
                self.nextToken();
                const case_expr = try self.parseExpression(0);
                _ = try self.eat(.colon); // or .fat_arrow
                var stmts = std.ArrayListUnmanaged(ast.Node.Index){};
                while (self.curr.tag != .k_case and self.curr.tag != .k_default and self.curr.tag != end_token and self.curr.tag != .eof) {
                    try stmts.append(self.allocator, try self.parseStatement());
                }
                const arena = self.context.arena.allocator();
                const stmts_slice = try arena.dupe(ast.Node.Index, stmts.items);
                stmts.deinit(self.allocator);
                const case_node = try self.createNode(.{ .tag = .case, .main_token = token, .data = .{ .case = .{ .condition = case_expr, .body = stmts_slice } } });
                try cases.append(self.allocator, case_node);
            } else if (self.curr.tag == .k_default) {
                self.nextToken();
                _ = try self.eat(.colon); // or .fat_arrow
                var stmts = std.ArrayListUnmanaged(ast.Node.Index){};
                while (self.curr.tag != .k_case and self.curr.tag != .k_default and self.curr.tag != end_token and self.curr.tag != .eof) {
                    try stmts.append(self.allocator, try self.parseStatement());
                }
                const arena = self.context.arena.allocator();
                const stmts_slice = try arena.dupe(ast.Node.Index, stmts.items);
                stmts.deinit(self.allocator);
                default_case = try self.createNode(.{ .tag = .default, .main_token = token, .data = .{ .default = .{ .body = stmts_slice } } });
            } else {
                self.nextToken(); // Skip unexpected tokens
            }
        }

        if (is_alternative) {
            // 消耗 endswitch;
            if (self.curr.tag == .k_endswitch) {
                self.nextToken();
                _ = try self.eat(.semicolon);
            }
        } else {
            _ = try self.eat(.r_brace);
        }
        const arena = self.context.arena.allocator();
        const cases_slice = try arena.dupe(ast.Node.Index, cases.items);
        cases.deinit(self.allocator);
        return self.createNode(.{ .tag = .switch_stmt, .main_token = token, .data = .{ .switch_stmt = .{ .expression = expr, .cases = cases_slice, .default = default_case } } });
    }

    fn parseYieldExpr(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_yield);

        // yield from <expr>
        if (self.curr.tag == .k_from) {
            self.nextToken(); // consume 'from'
            const expr = try self.parseExpression(0);
            return self.createNode(.{
                .tag = .yield_from_expr,
                .main_token = token,
                .data = .{ .yield_from_expr = .{
                    .expr = expr,
                } },
            });
        }

        var key: ?ast.Node.Index = null;
        var value: ?ast.Node.Index = null;

        if (self.curr.tag != .semicolon and self.curr.tag != .r_brace and self.curr.tag != .r_paren) {
            value = try self.parseExpression(0);
            if (self.curr.tag == .fat_arrow) {
                self.nextToken();
                key = value;
                value = try self.parseExpression(0);
            }
        }

        return self.createNode(.{ .tag = .yield_expr, .main_token = token, .data = .{ .yield_expr = .{ .key = key, .value = value } } });
    }

    fn parseYield(self: *Parser) anyerror!ast.Node.Index {
        const idx = try self.parseYieldExpr();
        if (self.curr.tag == .semicolon) {
            self.nextToken();
        }
        return idx;
    }

    fn parseNewOrAnonymousClass(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_new);
        if (self.curr.tag == .k_class) {
            self.nextToken();

            // Parse constructor arguments
            var args = std.ArrayListUnmanaged(ast.Node.Index){};
            if (self.curr.tag == .l_paren) {
                self.nextToken();
                while (self.curr.tag != .r_paren and self.curr.tag != .eof) {
                    if (self.curr.tag == .t_string and self.peek.tag == .colon) {
                        const name_tok = self.curr;
                        const name_id = try self.context.intern(self.lexer.buffer[name_tok.loc.start..name_tok.loc.end]);
                        self.nextToken();
                        self.nextToken();
                        const value_expr = try self.parseExpression(1);
                        const named_arg_node = try self.createNode(.{
                            .tag = .named_arg,
                            .main_token = name_tok,
                            .data = .{ .named_arg = .{ .name = name_id, .value = value_expr } },
                        });
                        try args.append(self.allocator, named_arg_node);
                    } else {
                        try args.append(self.allocator, try self.parseExpression(2));
                    }
                    if (self.curr.tag == .comma) self.nextToken();
                }
                _ = try self.eat(.r_paren);
            }

            // Parse extends
            var extends: ?ast.Node.Index = null;
            if (self.curr.tag == .k_extends) {
                self.nextToken();
                extends = try self.parsePrimary();
            }

            // Parse implements
            var implements = std.ArrayListUnmanaged(ast.Node.Index){};
            if (self.curr.tag == .k_implements) {
                self.nextToken();
                while (self.curr.tag != .l_brace and self.curr.tag != .eof) {
                    try implements.append(self.allocator, try self.parsePrimary());
                    if (self.curr.tag == .comma) self.nextToken();
                }
            }

            // Parse class body
            _ = try self.eat(.l_brace);
            var members = std.ArrayListUnmanaged(ast.Node.Index){};
            while (self.curr.tag != .r_brace and self.curr.tag != .eof) {
                try members.append(self.allocator, try self.parseStatement());
            }
            _ = try self.eat(.r_brace);

            const arena = self.context.arena.allocator();
            const args_slice = try arena.dupe(ast.Node.Index, args.items);
            const implements_slice = try arena.dupe(ast.Node.Index, implements.items);
            const members_slice = try arena.dupe(ast.Node.Index, members.items);

            args.deinit(self.allocator);
            implements.deinit(self.allocator);
            members.deinit(self.allocator);

            return self.createNode(.{ .tag = .anonymous_class, .main_token = token, .data = .{ .anonymous_class = .{ .attributes = &.{}, .extends = extends, .implements = implements_slice, .members = members_slice, .args = args_slice } } });
        }

        // In Go mode, class names are t_go_identifier (without $ prefix)
        // We parse it directly to avoid adding $ prefix that parsePrimary would add
        const class_name = if (self.syntax_mode == .go and self.curr.tag == .t_go_identifier) try blk: {
            const name_tok = try self.eat(.t_go_identifier);
            const name_str = self.lexer.buffer[name_tok.loc.start..name_tok.loc.end];
            const name_id = try self.context.intern(name_str);
            break :blk self.createNode(.{ .tag = .variable, .main_token = name_tok, .data = .{ .variable = .{ .name = name_id } } });
        } else try self.parsePrimary();

        var args = std.ArrayListUnmanaged(ast.Node.Index){};

        if (self.curr.tag == .l_paren) {
            self.nextToken();
            while (self.curr.tag != .r_paren and self.curr.tag != .eof) {
                if (self.curr.tag == .t_string and self.peek.tag == .colon) {
                    const name_tok = self.curr;
                    const name_id = try self.context.intern(self.lexer.buffer[name_tok.loc.start..name_tok.loc.end]);
                    self.nextToken();
                    self.nextToken();
                    const value_expr = try self.parseExpression(1);
                    const named_arg_node = try self.createNode(.{
                        .tag = .named_arg,
                        .main_token = name_tok,
                        .data = .{ .named_arg = .{ .name = name_id, .value = value_expr } },
                    });
                    try args.append(self.allocator, named_arg_node);
                } else {
                    try args.append(self.allocator, try self.parseExpression(2));
                }
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

    inline fn getPrecedence(self: *Parser, tag: Token.Tag) u8 {
        _ = self;
        return switch (tag) {
            .plus_plus, .minus_minus => 120, // Postfix increment/decrement (highest precedence)
            .l_paren => 110,
            .l_bracket => 110, // Array access
            .arrow => 100,
            .safe_arrow => 100, // 安全导航操作符 ?-> (PHP 模式)
            .safe_dot => 100, // 安全导航操作符 ?. (Go 模式)
            .double_colon => 100, // Static access has same precedence as instance access
            .pipe_greater => 90, // Pipe operator has high precedence
            .star_star => 70, // Exponentiation (higher than multiplication)
            .asterisk, .slash, .percent => 60,
            .plus, .minus, .dot => 50, // String concatenation has same precedence as addition/subtraction
            .less_less, .greater_greater => 45, // Bit shift operators
            .less, .greater, .less_equal, .greater_equal, .spaceship => 40,
            .k_instanceof => 38, // instanceof has precedence between comparison and equality
            .equal_equal, .equal_equal_equal, .bang_equal, .bang_equal_equal => 35,
            .ampersand => 30, // Bitwise AND
            .caret => 28, // Bitwise XOR
            .pipe => 25, // Bitwise OR
            .double_ampersand => 20, // Logical AND
            .double_pipe => 10, // Logical OR
            .double_question => 8, // Null coalescing
            .question => 7, // Ternary
            .equal, .plus_equal, .minus_equal, .asterisk_equal, .slash_equal, .percent_equal, .dot_equal, .star_star_equal, .less_less_equal, .greater_greater_equal, .and_equal, .or_equal, .caret_equal, .double_question_equal => 5,
            .k_and => 4, // PHP low-precedence logical AND
            .k_xor => 3, // PHP low-precedence logical XOR
            .k_or => 2, // PHP low-precedence logical OR
            .comma => 1, // Comma operator (lowest precedence)
            else => 0,
        };
    }

    /// PHP context-sensitive keywords: any keyword that can be used as method/property name after -> or ::
    fn isKeywordUsableAsIdentifier(self: *Parser) bool {
        _ = self;
        return false;
    }

    fn isKeywordIdentifierTag(tag: Token.Tag) bool {
        return switch (tag) {
            .k_set, .k_get, .k_unset, .k_clone, .k_list, .k_print,
            .k_lock, .k_try, .k_catch, .k_finally, .k_throw, .k_match,
            .k_default, .k_static, .k_class, .k_function, .k_array,
            .k_new, .k_fn, .k_parent, .k_self, .k_public, .k_private,
            .k_protected, .k_abstract, .k_final, .k_readonly,
            .k_foreach, .k_for, .k_while, .k_do, .k_if, .k_else,
            .k_elseif, .k_switch, .k_case, .k_break, .k_continue,
            .k_return, .k_from, .k_enum, .k_interface, .k_trait,
            .k_extends, .k_implements, .k_use, .k_namespace,
            .k_echo, .k_global, .k_const, .k_var, .k_as,
            .k_yield, .k_goto, .k_declare, .k_instanceof,
            .k_include, .k_include_once, .k_require, .k_require_once,
            .k_and, .k_or, .k_xor, .k_with, .k_go,
            .k_callable, .k_iterable, .k_object, .k_mixed,
            .k_never, .k_void, .k_true, .k_false, .k_null,
            => true,
            else => false,
        };
    }

    /// Try to eat the current token as a keyword-used-as-identifier, returning it as if it were t_string
    fn eatKeywordAsIdentifier(self: *Parser) ?Token {
        if (isKeywordIdentifierTag(self.curr.tag)) {
            const tok = self.curr;
            self.nextToken();
            return tok;
        }
        return null;
    }

    /// Parse a single call argument, supporting named args (name: value) and keyword-as-name (type: value)
    fn parseCallArg(self: *Parser) anyerror!ast.Node.Index {
        // Check for named parameter: name: value or keyword: value (e.g. type: 'int')
        if ((self.curr.tag == .t_string or isKeywordIdentifierTag(self.curr.tag)) and self.peek.tag == .colon) {
            const name_tok = self.curr;
            const name_id = try self.context.intern(self.lexer.buffer[name_tok.loc.start..name_tok.loc.end]);
            self.nextToken(); // skip name
            self.nextToken(); // skip colon
            const value_expr = try self.parseExpression(1);
            return self.createNode(.{
                .tag = .named_arg,
                .main_token = name_tok,
                .data = .{ .named_arg = .{ .name = name_id, .value = value_expr } },
            });
        }
        return self.parseExpression(2);
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
        // 使用优先级1避免解析逗号运算符（逗号优先级为1，我们需要>1）
        const body = try self.parseExpression(2);

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
            // 使用优先级 1 来避免解析逗号运算符（逗号优先级为 0）
            const first_expr = try self.parseExpression(1);
            if (self.curr.tag == .fat_arrow) {
                self.nextToken();
                const value_expr = try self.parseExpression(1);
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
            // 使用优先级 1 避免解析逗号运算符
            const first_expr = try self.parseExpression(1);

            // 检查是否有 => 符号（关联数组语法）
            if (self.curr.tag == .fat_arrow) {
                // 有 => 符号，创建键值对节点
                _ = try self.eat(.fat_arrow);
                const value_expr = try self.parseExpression(1);

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
            const key_expr = try self.parseExpression(1);

            // 检查是否有 : 符号（JSON 风格）或 => 符号（PHP 风格）
            if (self.curr.tag == .colon) {
                // JSON 风格 "key": value
                _ = try self.eat(.colon);
                const value_expr = try self.parseExpression(1);

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
            // In Go mode, check for both t_variable and t_go_identifier
            if (self.peek.tag == .t_variable or self.peek.tag == .t_go_identifier or self.peek.tag == .ellipsis) {
                return left;
            }

            var types = std.ArrayListUnmanaged(ast.Node.Index){};
            try types.append(self.allocator, left);

            while (self.curr.tag == .ampersand) {
                // Check peek: if next is variable or ellipsis, stop parsing intersection
                if (self.peek.tag == .t_variable or self.peek.tag == .t_go_identifier or self.peek.tag == .ellipsis) {
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
        } else if (self.curr.tag == .t_string or self.curr.tag == .t_go_identifier or
            self.curr.tag == .k_array or
            self.curr.tag == .k_callable or self.curr.tag == .k_static or
            self.curr.tag == .k_self or self.curr.tag == .k_parent or
            self.curr.tag == .k_void or self.curr.tag == .k_mixed or
            self.curr.tag == .k_never or self.curr.tag == .k_object or
            self.curr.tag == .k_iterable or self.curr.tag == .k_null or
            self.curr.tag == .k_true or self.curr.tag == .k_false)
        {
            // Handle built-in type keywords and user-defined types
            // In Go mode, both t_string and t_go_identifier can be type names
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
