const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const Token = @import("token.zig").Token;
const ast = @import("ast.zig");
const PHPContext = @import("root.zig").PHPContext;

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

    pub fn deinit(self: *Parser) void { _ = self; }

    fn nextToken(self: *Parser) void {
        self.curr = self.peek;
        self.peek = self.lexer.next();
    }

    fn reportError(self: *Parser, msg: []const u8) void {
        const err = @import("root.zig").Error{
            .msg = self.context.arena.allocator().dupe(u8, msg) catch msg,
            .line = 0, .column = 0,
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
                .k_class, .k_interface, .k_trait, .k_enum, .k_function, .k_if, .k_for, .k_while, .k_foreach, .k_return, .k_namespace, .k_use => return,
                else => self.nextToken(),
            }
        }
    }

    pub fn parse(self: *Parser) anyerror!ast.Node.Index {
        var stmts = std.ArrayListUnmanaged(ast.Node.Index){};
        defer stmts.deinit(self.allocator);
        while (self.curr.tag != .eof) {
            if (self.curr.tag == .t_open_tag or self.curr.tag == .t_close_tag or self.curr.tag == .t_inline_html) {
                self.nextToken(); continue;
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
            .k_function => {
                if (self.peek.tag == .l_paren) return self.parseExpressionStatement();
                return self.parseFunction(attributes);
            },
            .k_if => self.parseIf(),
            .k_while => self.parseWhile(),
            .k_for => self.parseFor(),
            .k_foreach => self.parseForeach(),
            .k_echo => self.parseEcho(),
            .k_global => self.parseGlobal(),
            .k_static => self.parseStatic(),
            .k_const => self.parseConst(),
            .k_go => self.parseGo(),
            .k_return => self.parseReturn(),
            .k_public, .k_protected, .k_private, .k_readonly, .k_final, .k_abstract => self.parseClassMember(attributes),
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
            defer params.deinit(self.allocator);
            while (self.curr.tag != .r_paren) {
                try params.append(self.allocator, try self.parseParameter());
                if (self.curr.tag == .comma) self.nextToken();
            }
            _ = try self.eat(.r_paren);
            const body = if (modifiers.is_abstract) null else try self.parseBlock();
            return self.createNode(.{ .tag = .method_decl, .main_token = token, .data = .{ .method_decl = .{ .attributes = attributes, .name = name_id, .modifiers = modifiers, .params = try self.context.arena.allocator().dupe(ast.Node.Index, params.items), .return_type = null, .body = body } } });
        } else {
            const token = self.curr;
            const name_tok = try self.eat(.t_variable);
            const name_id = try self.context.intern(self.lexer.buffer[name_tok.loc.start..name_tok.loc.end]);
            var hooks = std.ArrayListUnmanaged(ast.Node.Index){};
            defer hooks.deinit(self.allocator);
            if (self.curr.tag == .l_brace) {
                self.nextToken();
                while (self.curr.tag != .r_brace) try hooks.append(self.allocator, try self.parsePropertyHook());
                _ = try self.eat(.r_brace);
            } else if (self.curr.tag == .semicolon) {
                self.nextToken();
            }
            return self.createNode(.{ .tag = .property_decl, .main_token = token, .data = .{ .property_decl = .{ .attributes = attributes, .name = name_id, .modifiers = modifiers, .type = null, .default_value = null, .hooks = try self.context.arena.allocator().dupe(ast.Node.Index, hooks.items) } } });
        }
    }

    fn parsePropertyHook(self: *Parser) anyerror!ast.Node.Index {
        const token = self.curr;
        if (self.curr.tag != .k_get and self.curr.tag != .k_set) return error.ExpectedHookName;
        const name_id = try self.context.intern(self.lexer.buffer[self.curr.loc.start..self.curr.loc.end]);
        self.nextToken();
        var body: ast.Node.Index = 0;
        if (self.curr.tag == .fat_arrow) {
            self.nextToken(); body = try self.parseExpression(0); _ = try self.eat(.semicolon);
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
        defer attrs.deinit(self.allocator);
        while (self.curr.tag == .t_attribute_start) {
            self.nextToken();
            while (self.curr.tag != .r_bracket and self.curr.tag != .eof) {
                const name_tok = try self.eat(.t_string);
                const name_id = try self.context.intern(self.lexer.buffer[name_tok.loc.start..name_tok.loc.end]);
                if (self.curr.tag == .l_paren) {
                    self.nextToken(); while (self.curr.tag != .r_paren) self.nextToken(); self.nextToken();
                }
                const attr_node = try self.createNode(.{ .tag = .attribute, .main_token = name_tok, .data = .{ .attribute = .{ .name = name_id, .args = &.{} } } });
                try attrs.append(self.allocator, attr_node);
                if (self.curr.tag == .comma) self.nextToken();
            }
            _ = try self.eat(.r_bracket);
        }
        return try self.context.arena.allocator().dupe(ast.Node.Index, attrs.items);
    }

    fn parseContainer(self: *Parser, tag: ast.Node.Tag, attributes: []const ast.Node.Index) anyerror!ast.Node.Index {
        const token = self.curr; self.nextToken();
        const name_tok = try self.eat(.t_string);
        const name_id = try self.context.intern(self.lexer.buffer[name_tok.loc.start..name_tok.loc.end]);
        var extends: ?ast.Node.Index = null;
        if (self.curr.tag == .k_extends) { self.nextToken(); extends = try self.parseExpression(0); }
        var implements = std.ArrayListUnmanaged(ast.Node.Index){};
        defer implements.deinit(self.allocator);
        if (self.curr.tag == .k_implements) {
            self.nextToken();
            while (true) {
                try implements.append(self.allocator, try self.parseExpression(0));
                if (self.curr.tag != .comma) break; self.nextToken();
            }
        }
        const body = try self.parseBlock();
        return self.createNode(.{ .tag = tag, .main_token = token, .data = .{ .container_decl = .{ .attributes = attributes, .name = name_id, .modifiers = .{}, .extends = extends, .implements = try self.context.arena.allocator().dupe(ast.Node.Index, implements.items), .members = &.{body} } } });
    }

    fn parseFunction(self: *Parser, attributes: []const ast.Node.Index) anyerror!ast.Node.Index {
        const token = try self.eat(.k_function);
        const name_tok = try self.eat(.t_string);
        const name_id = try self.context.intern(self.lexer.buffer[name_tok.loc.start..name_tok.loc.end]);
        _ = try self.eat(.l_paren); 
        var params = std.ArrayListUnmanaged(ast.Node.Index){};
        defer params.deinit(self.allocator);
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
        if (self.curr.tag == .ellipsis) { is_variadic = true; self.nextToken(); }
        const name_tok = try self.eat(.t_variable);
        const name_id = try self.context.intern(self.lexer.buffer[name_tok.loc.start..name_tok.loc.end]);
        return self.createNode(.{ .tag = .parameter, .main_token = name_tok, .data = .{ .parameter = .{ .attributes = attributes, .name = name_id, .type = type_node, .is_promoted = modifiers.is_public or modifiers.is_protected or modifiers.is_private, .modifiers = modifiers, .is_variadic = is_variadic, .is_reference = is_reference } } });
    }

    fn parseIf(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_if); _ = try self.eat(.l_paren);
        const cond = try self.parseExpression(0); _ = try self.eat(.r_paren);
        const then = try self.parseStatement();
        var else_branch: ?ast.Node.Index = null;
        if (self.curr.tag == .k_else) { self.nextToken(); else_branch = try self.parseStatement(); }
        return self.createNode(.{ .tag = .if_stmt, .main_token = token, .data = .{ .if_stmt = .{ .condition = cond, .then_branch = then, .else_branch = else_branch } } });
    }

    fn parseWhile(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_while); _ = try self.eat(.l_paren);
        const cond = try self.parseExpression(0); _ = try self.eat(.r_paren);
        const body = try self.parseStatement();
        return self.createNode(.{ .tag = .while_stmt, .main_token = token, .data = .{ .while_stmt = .{ .condition = cond, .body = body } } });
    }

    fn parseForeach(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_foreach); _ = try self.eat(.l_paren);
        const iterable = try self.parseExpression(0); _ = try self.eat(.k_as);
        const value = try self.parseExpression(0); _ = try self.eat(.r_paren);
        const body = try self.parseStatement();
        return self.createNode(.{ .tag = .foreach_stmt, .main_token = token, .data = .{ .foreach_stmt = .{ .iterable = iterable, .key = null, .value = value, .body = body } } });
    }

    fn parseFor(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_for); _ = try self.eat(.l_paren);
        _ = try self.eat(.semicolon); _ = try self.eat(.semicolon); _ = try self.eat(.r_paren);
        _ = try self.parseStatement();
        return self.createNode(.{ .tag = .for_stmt, .main_token = token, .data = .{ .none = {} } });
    }

    fn parseGlobal(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_global);
        var vars = std.ArrayListUnmanaged(ast.Node.Index){};
        defer vars.deinit(self.allocator);
        while (true) {
            try vars.append(self.allocator, try self.parseExpression(100));
            if (self.curr.tag != .comma) break; self.nextToken();
        }
        _ = try self.eat(.semicolon);
        return self.createNode(.{ .tag = .global_stmt, .main_token = token, .data = .{ .global_stmt = .{ .vars = try self.context.arena.allocator().dupe(ast.Node.Index, vars.items) } } });
    }

    fn parseStatic(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_static);
        var vars = std.ArrayListUnmanaged(ast.Node.Index){};
        defer vars.deinit(self.allocator);
        while (true) {
            try vars.append(self.allocator, try self.parseExpression(0));
            if (self.curr.tag != .comma) break; self.nextToken();
        }
        _ = try self.eat(.semicolon);
        return self.createNode(.{ .tag = .static_stmt, .main_token = token, .data = .{ .static_stmt = .{ .vars = try self.context.arena.allocator().dupe(ast.Node.Index, vars.items) } } });
    }

    fn parseConst(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_const);
        const name_tok = try self.eat(.t_string);
        const name_id = try self.context.intern(self.lexer.buffer[name_tok.loc.start..name_tok.loc.end]);
        _ = try self.eat(.equal); const val = try self.parseExpression(0); _ = try self.eat(.semicolon);
        return self.createNode(.{ .tag = .const_decl, .main_token = token, .data = .{ .const_decl = .{ .name = name_id, .value = val } } });
    }

    fn parseGo(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_go);
        const call = try self.parseExpression(0); _ = try self.eat(.semicolon);
        return self.createNode(.{ .tag = .go_stmt, .main_token = token, .data = .{ .go_stmt = .{ .call = call } } });
    }

    fn parseReturn(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_return);
        var expr: ?ast.Node.Index = null;
        if (self.curr.tag != .semicolon) expr = try self.parseExpression(0);
        _ = try self.eat(.semicolon);
        return self.createNode(.{ .tag = .return_stmt, .main_token = token, .data = .{ .return_stmt = .{ .expr = expr } } });
    }

    fn parseEcho(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_echo);
        const expr = try self.parseExpression(0); _ = try self.eat(.semicolon);
        return self.createNode(.{ .tag = .echo_stmt, .main_token = token, .data = .{ .echo_stmt = .{ .expr = expr } } });
    }

    fn parseAssignment(self: *Parser) anyerror!ast.Node.Index {
        const target = try self.parseExpression(100);
        const op = try self.eat(.equal);
        const val = try self.parseExpression(0); _ = try self.eat(.semicolon);
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
        var left = try self.parsePrimary();
        while (true) {
            const tag = self.curr.tag;
            const next_p = self.getPrecedence(tag);
            if (next_p <= precedence) break;
            const op = self.curr; self.nextToken();
            if (tag == .arrow) {
                const method_name_tok = try self.eat(.t_string);
                const method_id = try self.context.intern(self.lexer.buffer[method_name_tok.loc.start..method_name_tok.loc.end]);
                left = try self.createNode(.{ .tag = .method_call, .main_token = op, .data = .{ .method_call = .{ .target = left, .method_name = method_id, .args = &.{} } } });
            } else if (tag == .l_paren) {
                var args = std.ArrayListUnmanaged(ast.Node.Index){};
                defer args.deinit(self.allocator);
                while (self.curr.tag != .r_paren) {
                    try args.append(self.allocator, try self.parseExpression(0));
                    if (self.curr.tag == .comma) self.nextToken();
                }
                _ = try self.eat(.r_paren);
                left = try self.createNode(.{ .tag = .function_call, .main_token = op, .data = .{ .function_call = .{ .name = left, .args = try self.context.arena.allocator().dupe(ast.Node.Index, args.items) } } });
            } else {
                const right = try self.parseExpression(next_p);
                left = try self.createNode(.{ .tag = .binary_expr, .main_token = op, .data = .{ .binary_expr = .{ .lhs = left, .op = op.tag, .rhs = right } } });
            }
        }
        return left;
    }

    fn parsePrimary(self: *Parser) anyerror!ast.Node.Index {
        return switch (self.curr.tag) {
            .k_function => self.parseClosure(),
            .k_match => self.parseMatch(),
            .k_new => self.parseNewOrAnonymousClass(),
            .ellipsis => {
                const token = self.curr; self.nextToken();
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
            .t_constant_encapsed_string => {
                const t = try self.eat(.t_constant_encapsed_string);
                return self.createNode(.{ .tag = .literal_string, .main_token = t, .data = .{ .literal_string = .{ .value = try self.context.intern(self.lexer.buffer[t.loc.start..t.loc.end]) } } });
            },
            .t_encapsed_and_whitespace => {
                const t = try self.eat(.t_encapsed_and_whitespace);
                return self.createNode(.{ .tag = .literal_string, .main_token = t, .data = .{ .literal_string = .{ .value = try self.context.intern(self.lexer.buffer[t.loc.start..t.loc.end]) } } });
            },
            .l_paren => {
                self.nextToken(); const expr = try self.parseExpression(0); _ = try self.eat(.r_paren); return expr;
            },
            else => error.InvalidExpression,
        };
    }

    fn parseClosure(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_function); _ = try self.eat(.l_paren); _ = try self.eat(.r_paren);
        var captures = std.ArrayListUnmanaged(ast.Node.Index){};
        defer captures.deinit(self.allocator);
        if (self.curr.tag == .k_use) {
            self.nextToken(); _ = try self.eat(.l_paren);
            while (self.curr.tag != .r_paren) {
                try captures.append(self.allocator, try self.parseExpression(0));
                if (self.curr.tag == .comma) self.nextToken();
            }
            _ = try self.eat(.r_paren);
        }
        const body = try self.parseBlock();
        const arena = self.context.arena.allocator();
        return self.createNode(.{ .tag = .closure, .main_token = token, .data = .{ .closure = .{ .attributes = &.{}, .params = &.{}, .captures = try arena.dupe(ast.Node.Index, captures.items), .return_type = null, .body = body, .is_static = false } } });
    }

    fn parseMatch(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_match); _ = try self.eat(.l_paren);
        const expr = try self.parseExpression(0); _ = try self.eat(.r_paren); _ = try self.eat(.l_brace);
        var arms = std.ArrayListUnmanaged(ast.Node.Index){};
        defer arms.deinit(self.allocator);
        while (self.curr.tag != .r_brace and self.curr.tag != .eof) {
            const cond = try self.parseExpression(0); _ = try self.eat(.fat_arrow); const body = try self.parseExpression(0);
            const arm = try self.createNode(.{ .tag = .match_arm, .main_token = token, .data = .{ .match_arm = .{ .conditions = &.{cond}, .body = body } } });
            try arms.append(self.allocator, arm);
            if (self.curr.tag == .comma) self.nextToken();
        }
        _ = try self.eat(.r_brace);
        const arena = self.context.arena.allocator();
        return self.createNode(.{ .tag = .match_expr, .main_token = token, .data = .{ .match_expr = .{ .expression = expr, .arms = try arena.dupe(ast.Node.Index, arms.items) } } });
    }

    fn parseNewOrAnonymousClass(self: *Parser) anyerror!ast.Node.Index {
        const token = try self.eat(.k_new);
        if (self.curr.tag == .k_class) {
            self.nextToken(); const body = try self.parseBlock();
            return self.createNode(.{ .tag = .anonymous_class, .main_token = token, .data = .{ .anonymous_class = .{ .attributes = &.{}, .extends = null, .implements = &.{}, .members = &.{body}, .args = &.{} } } });
        }
        return self.parseExpression(100);
    }

    fn getPrecedence(self: *Parser, tag: Token.Tag) u8 {
        _ = self;
        return switch (tag) {
            .l_paren => 110, .arrow => 100,
            .asterisk, .slash => 60, .plus, .minus => 50,
            .less, .greater, .less_equal, .greater_equal => 40,
            .equal_equal, .equal_equal_equal, .bang_equal, .bang_equal_equal => 30,
            .double_ampersand => 20, .double_pipe => 10, .equal => 5,
            else => 0,
        };
    }

    fn createNode(self: *Parser, node: ast.Node) anyerror!ast.Node.Index {
        const idx: u32 = @intCast(self.context.nodes.items.len);
        try self.context.nodes.append(self.allocator, node);
        return idx;
    }

    fn parseType(self: *Parser) anyerror!ast.Node.Index {
        return self.parseUnionType();
    }

    fn parseUnionType(self: *Parser) anyerror!ast.Node.Index {
        const left = try self.parseIntersectionType();

        if (self.curr.tag == .pipe) {
            var types = std.ArrayListUnmanaged(ast.Node.Index){};
            defer types.deinit(self.allocator);
            try types.append(self.allocator, left);

            while (self.curr.tag == .pipe) {
                self.nextToken();
                try types.append(self.allocator, try self.parseIntersectionType());
            }

            const arena = self.context.arena.allocator();
            return self.createNode(.{ .tag = .union_type, .main_token = self.curr, .data = .{ .union_type = .{ .types = try arena.dupe(ast.Node.Index, types.items) } } });
        }

        return left;
    }

    fn parseIntersectionType(self: *Parser) anyerror!ast.Node.Index {
        const left = try self.parsePrimaryType();

        if (self.curr.tag == .ampersand) {
             var types = std.ArrayListUnmanaged(ast.Node.Index){};
            defer types.deinit(self.allocator);
            try types.append(self.allocator, left);

            while (self.curr.tag == .ampersand) {
                self.nextToken();
                try types.append(self.allocator, try self.parsePrimaryType());
            }

            const arena = self.context.arena.allocator();
            return self.createNode(.{ .tag = .intersection_type, .main_token = self.curr, .data = .{ .intersection_type = .{ .types = try arena.dupe(ast.Node.Index, types.items) } } });
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
