const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const Token = @import("token.zig").Token;
const ast = @import("ast.zig");
pub const PHPContext = @import("root.zig").PHPContext;

pub const Parser = struct {
    lexer: Lexer,
    allocator: std.mem.Allocator,
    context: *PHPContext,
    curr: Token,
    peek: Token,

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
        while (self.curr.tag != .eof) {
            if (self.curr.tag == .t_open_tag or self.curr.tag == .t_close_tag or self.curr.tag == .t_inline_html) {
                self.nextToken();
                continue;
            }
            const stmt = self.parseStatement() catch {
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
            .k_return => self.parseReturn(),
            .k_break => self.parseBreak(),
            .k_continue => self.parseContinue(),
            .k_public, .k_protected, .k_private, .k_readonly, .k_final, .k_abstract => self.parseClassMember(attributes),
            .l_brace => self.parseBlock(),
            .t_variable => {
                if (self.peek.tag == .equal) return self.parseAssignment();
                return self.parseExpressionStatement();
            },
            else => self.parseExpressionStatement(),
        };
    }

    fn parseClassMember(self: *Parser, attributes: []const ast.Node.Index) anyerror!ast.Node.Index {
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
            const name_tok = try self.eat(.t_string);
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
            const body = if (modifiers.is_abstract) null else try self.parseBlock();
            return self.createNode(.{ .tag = .method_decl, .main_token = token, .data = .{ .method_decl = .{ .attributes = attributes, .name = name_id, .modifiers = modifiers, .params = try self.context.arena.allocator().dupe(ast.Node.Index, params.items), .return_type = return_type, .body = body } } });
        } else {
            const token = self.curr;
            var type_node: ?ast.Node.Index = null;
            if (self.curr.tag == .t_string or self.curr.tag == .question) {
                type_node = try self.parseType();
            }
            const name_tok = try self.eat(.t_variable);
            const name_id = try self.context.intern(self.lexer.buffer[name_tok.loc.start..name_tok.loc.end]);
            var hooks = std.ArrayListUnmanaged(ast.Node.Index){};
            if (self.curr.tag == .l_brace) {
                self.nextToken();
                while (self.curr.tag != .r_brace) try hooks.append(self.allocator, try self.parsePropertyHook());
                _ = try self.eat(.r_brace);
            } else if (self.curr.tag == .semicolon) {
                self.nextToken();
            }
            return self.createNode(.{ .tag = .property_decl, .main_token = token, .data = .{ .property_decl = .{ .attributes = attributes, .name = name_id, .modifiers = modifiers, .type = type_node, .default_value = null, .hooks = try self.context.arena.allocator().dupe(ast.Node.Index, hooks.items) } } });
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

        while (self.curr.tag != .r_brace and self.curr.tag != .eof) {
            var member_attributes: []const ast.Node.Index = &.{};
            if (self.curr.tag == .t_attribute_start) member_attributes = try self.parseAttributes();

            if (self.curr.tag == .k_const) {
                try members.append(self.allocator, try self.parseConst());
            } else {
                try members.append(self.allocator, try self.parseClassMember(member_attributes));
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
        if (self.curr.tag == .t_string) {
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
        if (self.curr.tag == .k_else) {
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

        // Range loop: for range 10 或 for $i range 10
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
        while (self.curr.tag != .r_brace and self.curr.tag != .eof) {
            try stmts.append(self.allocator, try self.parseStatement());
        }
        _ = try self.eat(.r_brace);
        const arena = self.context.arena.allocator();
        return self.createNode(.{ .tag = .block, .main_token = token, .data = .{ .block = .{ .stmts = try arena.dupe(ast.Node.Index, stmts.items) } } });
    }

    fn parseExpression(self: *Parser, precedence: u8) anyerror!ast.Node.Index {
        var left = try self.parseUnary();
        while (true) {
            const tag = self.curr.tag;
            const next_p = self.getPrecedence(tag);
            if (next_p <= precedence) break;
            const op = self.curr;
            self.nextToken();
            if (tag == .arrow) {
                // 方法名可以是标识符，也可以是某些关键字（如 set, get）
                const member_name_tok = if (self.curr.tag == .t_string)
                    try self.eat(.t_string)
                else if (self.curr.tag == .k_set or self.curr.tag == .k_get or
                    self.curr.tag == .k_unset or self.curr.tag == .k_clone or
                    self.curr.tag == .k_list or self.curr.tag == .k_print)
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
                // Static access: ClassName::member
                const left_node = self.context.nodes.items[left];
                if (left_node.tag != .variable) {
                    self.reportError("Invalid static access target");
                    return error.InvalidStaticAccess;
                }
                const class_name_id = left_node.data.variable.name;
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
            } else if (tag == .l_paren) {
                var args = std.ArrayListUnmanaged(ast.Node.Index){};
                while (self.curr.tag != .r_paren) {
                    try args.append(self.allocator, try self.parseExpression(0));
                    if (self.curr.tag == .comma) self.nextToken();
                }
                _ = try self.eat(.r_paren);
                left = try self.createNode(.{ .tag = .function_call, .main_token = op, .data = .{ .function_call = .{ .name = left, .args = try self.context.arena.allocator().dupe(ast.Node.Index, args.items) } } });
            } else if (tag == .pipe_greater) {
                const right = try self.parseExpression(next_p);
                left = try self.createNode(.{ .tag = .pipe_expr, .main_token = op, .data = .{ .pipe_expr = .{ .left = left, .right = right } } });
            } else if (tag == .equal) {
                const right = try self.parseExpression(precedence);
                left = try self.createNode(.{ .tag = .assignment, .main_token = op, .data = .{ .assignment = .{ .target = left, .value = right } } });
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
                left = try self.createNode(.{ .tag = .binary_expr, .main_token = op, .data = .{ .binary_expr = .{ .lhs = left, .op = op.tag, .rhs = right } } });
            }
        }
        return left;
    }

    fn parseUnary(self: *Parser) anyerror!ast.Node.Index {
        const tag = self.curr.tag;
        switch (tag) {
            .bang, .minus, .plus, .t_variable, .ampersand => {
                // Determine if it's a unary op or start of primary
                if (tag == .t_variable) {
                    return self.parsePrimary();
                }

                const token = self.curr;
                self.nextToken();
                const expr = try self.parseUnary();
                return self.createNode(.{ .tag = .unary_expr, .main_token = token, .data = .{ .unary_expr = .{ .op = tag, .expr = expr } } });
            },
            .plus_plus, .minus_minus => {
                const token = self.curr;
                self.nextToken();
                const expr = try self.parseUnary();
                return self.createNode(.{ .tag = .unary_expr, .main_token = token, .data = .{ .unary_expr = .{ .op = tag, .expr = expr } } });
            },
            .k_clone => return self.parseCloneExpression(),
            else => return self.parsePrimary(),
        }
    }

    fn parsePrimary(self: *Parser) anyerror!ast.Node.Index {
        return switch (self.curr.tag) {
            .t_double_quote => self.parseInterpolatedString(),
            .k_function => self.parseClosure(),
            .k_fn => self.parseArrowFunction(),
            .k_match => self.parseMatch(),
            .k_new => self.parseNewOrAnonymousClass(),
            .k_clone => self.parseCloneExpression(),
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
            .t_string => {
                const t = try self.eat(.t_string);
                const name_id = try self.context.intern(self.lexer.buffer[t.loc.start..t.loc.end]);
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
            .l_bracket => self.parseArrayLiteral(),
            .l_paren => {
                self.nextToken();
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
                    part = try self.parseExpression(0);
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
            .equal => 5,
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

        if (self.curr.tag == .ampersand) {
            var types = std.ArrayListUnmanaged(ast.Node.Index){};
            try types.append(self.allocator, left);

            while (self.curr.tag == .ampersand) {
                self.nextToken();
                try types.append(self.allocator, try self.parsePrimaryType());
            }

            const arena = self.context.arena.allocator();
            const types_slice = try arena.dupe(ast.Node.Index, types.items);
            types.deinit(self.allocator);
            return self.createNode(.{ .tag = .intersection_type, .main_token = self.curr, .data = .{ .intersection_type = .{ .types = types_slice } } });
        }

        return left;
    }

    fn parsePrimaryType(self: *Parser) anyerror!ast.Node.Index {
        if (self.curr.tag == .l_paren) {
            self.nextToken();
            const type_node = try self.parseType();
            _ = try self.eat(.r_paren);
            return type_node;
        } else {
            const type_name_tok = try self.eat(.t_string);
            const type_name_id = try self.context.intern(self.lexer.buffer[type_name_tok.loc.start..type_name_tok.loc.end]);
            return self.createNode(.{ .tag = .named_type, .main_token = type_name_tok, .data = .{ .named_type = .{ .name = type_name_id } } });
        }
    }
};
