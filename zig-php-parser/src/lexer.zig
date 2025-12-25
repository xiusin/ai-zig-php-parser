const std = @import("std");
const Token = @import("token.zig").Token;

pub const Lexer = struct {
    buffer: [:0]const u8,
    pos: usize = 0,
    state: State = .initial,
    heredoc_label: ?[]const u8 = null,

    pub const State = enum {
        initial,
        script,
        double_quote,
        heredoc,
        nowdoc,
    };

    pub fn init(buffer: [:0]const u8) Lexer {
        return .{ .buffer = buffer };
    }

    pub fn next(self: *Lexer) Token {
        if (self.state == .script) self.skipWhitespace();
        if (self.pos >= self.buffer.len) return .{ .tag = .eof, .loc = .{ .start = self.pos, .end = self.pos } };
        
        const start = self.pos;
        const char = self.buffer[self.pos];

        if (self.state == .initial) {
            if (char == '<' and std.mem.startsWith(u8, self.buffer[self.pos..], "<?php")) {
                self.pos += 5; self.state = .script;
                return .{ .tag = .t_open_tag, .loc = .{ .start = start, .end = self.pos } };
            }
            while (self.pos < self.buffer.len and self.buffer[self.pos] != '<') self.pos += 1;
            return .{ .tag = .t_inline_html, .loc = .{ .start = start, .end = self.pos } };
        }

        if (self.state == .double_quote) return self.lexInterpolation(start, '"');
        if (self.state == .heredoc) return self.lexInterpolation(start, 0);
        if (self.state == .nowdoc) return self.lexNowdoc(start);

        self.pos += 1;
        return switch (char) {
            '(' => .{ .tag = .l_paren, .loc = .{ .start = start, .end = self.pos } },
            ')' => .{ .tag = .r_paren, .loc = .{ .start = start, .end = self.pos } },
            '[' => .{ .tag = .l_bracket, .loc = .{ .start = start, .end = self.pos } },
            ']' => .{ .tag = .r_bracket, .loc = .{ .start = start, .end = self.pos } },
            '{' => .{ .tag = .l_brace, .loc = .{ .start = start, .end = self.pos } },
            '}' => .{ .tag = .r_brace, .loc = .{ .start = start, .end = self.pos } },
            ';' => .{ .tag = .semicolon, .loc = .{ .start = start, .end = self.pos } },
            ',' => .{ .tag = .comma, .loc = .{ .start = start, .end = self.pos } },
            '.' => if (self.match('.')) (if (self.match('.')) .{ .tag = .ellipsis, .loc = .{ .start = start, .end = self.pos } } else .{ .tag = .invalid, .loc = .{ .start = start, .end = self.pos } }) else .{ .tag = .dot, .loc = .{ .start = start, .end = self.pos } },
            '$' => self.lexVariable(start),
            '-' => if (self.match('>')) .{ .tag = .arrow, .loc = .{ .start = start, .end = self.pos } } else .{ .tag = .minus, .loc = .{ .start = start, .end = self.pos } },
            '=' => if (self.match('>')) .{ .tag = .fat_arrow, .loc = .{ .start = start, .end = self.pos } } 
                  else if (self.match('=')) (if (self.match('=')) .{ .tag = .equal_equal_equal, .loc = .{ .start = start, .end = self.pos } } else .{ .tag = .equal_equal, .loc = .{ .start = start, .end = self.pos } })
                  else .{ .tag = .equal, .loc = .{ .start = start, .end = self.pos } },
            '!' => if (self.match('=')) (if (self.match('=')) .{ .tag = .bang_equal_equal, .loc = .{ .start = start, .end = self.pos } } else .{ .tag = .bang_equal, .loc = .{ .start = start, .end = self.pos } })
                  else .{ .tag = .invalid, .loc = .{ .start = start, .end = self.pos } },
            '<' => if (self.match('<')) {
                if (self.match('<')) return self.lexHeredocStart(start);
                return .{ .tag = .invalid, .loc = .{ .start = start, .end = self.pos } };
            } else if (self.match('=')) .{ .tag = .less_equal, .loc = .{ .start = start, .end = self.pos } } 
            else if (self.match('>')) .{ .tag = .spaceship, .loc = .{ .start = start, .end = self.pos } } 
            else .{ .tag = .less, .loc = .{ .start = start, .end = self.pos } },
            '>' => if (self.match('=')) .{ .tag = .greater_equal, .loc = .{ .start = start, .end = self.pos } } else .{ .tag = .greater, .loc = .{ .start = start, .end = self.pos } },
            '#' => if (self.match('[')) .{ .tag = .t_attribute_start, .loc = .{ .start = start, .end = self.pos } } else self.skipLineComment(start),
            ':' => if (self.match(':')) .{ .tag = .double_colon, .loc = .{ .start = start, .end = self.pos } } else .{ .tag = .colon, .loc = .{ .start = start, .end = self.pos } },
            '0'...'9' => self.lexNumber(start),
            'a'...'z', 'A'...'Z', '_' => self.lexIdentifier(start),
            '\'' => self.lexSingleQuoteString(start),
            '"' => {
                self.state = .double_quote;
                return .{ .tag = .invalid, .loc = .{ .start = start, .end = self.pos } };
            },
            else => .{ .tag = .invalid, .loc = .{ .start = start, .end = self.pos } },
        };
    }

    fn lexInterpolation(self: *Lexer, start: usize, end_char: u8) Token {
        if (end_char != 0 and self.buffer[self.pos] == end_char) {
            self.pos += 1;
            self.state = .script;
            return .{ .tag = .invalid, .loc = .{ .start = start, .end = self.pos } };
        }
        
        if (self.heredoc_label) |label| {
            if (std.mem.startsWith(u8, self.buffer[self.pos..], label)) {
                self.pos += label.len;
                self.state = .script;
                self.heredoc_label = null;
                return .{ .tag = .t_heredoc_end, .loc = .{ .start = start, .end = self.pos } };
            }
        }

        if (self.buffer[self.pos] == '$') {
            if (self.pos + 1 < self.buffer.len) {
                if (self.buffer[self.pos + 1] == '{') {
                    self.pos += 2;
                    return .{ .tag = .t_dollar_open_curly_brace, .loc = .{ .start = start, .end = self.pos } };
                }
                if (std.ascii.isAlphabetic(self.buffer[self.pos + 1]) or self.buffer[self.pos + 1] == '_') {
                    return self.lexVariable(start);
                }
            }
        }
        if (self.buffer[self.pos] == '{' and self.pos + 1 < self.buffer.len and self.buffer[self.pos+1] == '$') {
            self.pos += 2;
            return .{ .tag = .t_curly_open, .loc = .{ .start = start, .end = self.pos } };
        }

        while (self.pos < self.buffer.len) {
            const c = self.buffer[self.pos];
            if (c == end_char and end_char != 0) break;
            if (c == '$' or (c == '{' and self.pos + 1 < self.buffer.len and self.buffer[self.pos+1] == '$')) break;
            if (self.heredoc_label) |label| {
                if (std.mem.startsWith(u8, self.buffer[self.pos..], label)) break;
            }
            self.pos += 1;
        }
        return .{ .tag = .t_encapsed_and_whitespace, .loc = .{ .start = start, .end = self.pos } };
    }

    fn lexNowdoc(self: *Lexer, start: usize) Token {
        if (self.heredoc_label) |label| {
            if (std.mem.startsWith(u8, self.buffer[self.pos..], label)) {
                self.pos += label.len;
                self.state = .script;
                self.heredoc_label = null;
                return .{ .tag = .t_heredoc_end, .loc = .{ .start = start, .end = self.pos } };
            }
        }
        while (self.pos < self.buffer.len) {
            if (self.heredoc_label) |label| {
                if (std.mem.startsWith(u8, self.buffer[self.pos..], label)) break;
            }
            self.pos += 1;
        }
        return .{ .tag = .t_encapsed_and_whitespace, .loc = .{ .start = start, .end = self.pos } };
    }

    fn lexHeredocStart(self: *Lexer, start: usize) Token {
        self.skipWhitespace();
        const label_start = self.pos;
        var is_nowdoc = false;
        if (self.match('"')) is_nowdoc = true;
        
        while (self.pos < self.buffer.len and (std.ascii.isAlphanumeric(self.buffer[self.pos]) or self.buffer[self.pos] == '_')) self.pos += 1;
        const label = self.buffer[label_start..self.pos];
        if (is_nowdoc) _ = self.match('"');
        
        self.heredoc_label = label;
        self.state = if (is_nowdoc) .nowdoc else .heredoc;
        return .{ .tag = if (is_nowdoc) .t_nowdoc_start else .t_heredoc_start, .loc = .{ .start = start, .end = self.pos } };
    }

    fn match(self: *Lexer, expected: u8) bool {
        if (self.pos < self.buffer.len and self.buffer[self.pos] == expected) {
            self.pos += 1; return true;
        }
        return false;
    }

    fn skipWhitespace(self: *Lexer) void {
        while (self.pos < self.buffer.len) {
            if (self.pos + 16 <= self.buffer.len) {
                const vector: @Vector(16, u8) = self.buffer[self.pos..][0..16].*;
                const mask = (vector == @as(@Vector(16, u8), @splat(' '))) | (vector == @as(@Vector(16, u8), @splat('\t'))) | (vector == @as(@Vector(16, u8), @splat('\n'))) | (vector == @as(@Vector(16, u8), @splat('\r')));
                const bitmask: u16 = @bitCast(mask);
                if (bitmask == 0xFFFF) { self.pos += 16; continue; }
                const first_non_ws = @ctz(~bitmask);
                self.pos += first_non_ws;
                break;
            }
            switch (self.buffer[self.pos]) {
                ' ', '\t', '\r', '\n' => self.pos += 1,
                else => break,
            }
        }
    }

    fn skipLineComment(self: *Lexer, start: usize) Token {
        _ = start;
        while (self.pos < self.buffer.len and self.buffer[self.pos] != '\n') self.pos += 1;
        return self.next();
    }

    fn lexVariable(self: *Lexer, start: usize) Token {
        if (self.buffer[self.pos] == '$') self.pos += 1;
        while (self.pos < self.buffer.len and (std.ascii.isAlphanumeric(self.buffer[self.pos]) or self.buffer[self.pos] == '_')) self.pos += 1;
        return .{ .tag = .t_variable, .loc = .{ .start = start, .end = self.pos } };
    }

    fn lexIdentifier(self: *Lexer, start: usize) Token {
        while (self.pos < self.buffer.len and (std.ascii.isAlphanumeric(self.buffer[self.pos]) or self.buffer[self.pos] == '_' or self.buffer[self.pos] == '\\')) self.pos += 1;
        const text = self.buffer[start..self.pos];
        const tag: Token.Tag = if (std.mem.eql(u8, text, "class")) .k_class
        else if (std.mem.eql(u8, text, "interface")) .k_interface
        else if (std.mem.eql(u8, text, "trait")) .k_trait
        else if (std.mem.eql(u8, text, "enum")) .k_enum
        else if (std.mem.eql(u8, text, "extends")) .k_extends
        else if (std.mem.eql(u8, text, "implements")) .k_implements
        else if (std.mem.eql(u8, text, "use")) .k_use
        else if (std.mem.eql(u8, text, "public")) .k_public
        else if (std.mem.eql(u8, text, "private")) .k_private
        else if (std.mem.eql(u8, text, "protected")) .k_protected
        else if (std.mem.eql(u8, text, "static")) .k_static
        else if (std.mem.eql(u8, text, "readonly")) .k_readonly
        else if (std.mem.eql(u8, text, "final")) .k_final
        else if (std.mem.eql(u8, text, "abstract")) .k_abstract
        else if (std.mem.eql(u8, text, "function")) .k_function
        else if (std.mem.eql(u8, text, "fn")) .k_fn
        else if (std.mem.eql(u8, text, "new")) .k_new
        else if (std.mem.eql(u8, text, "if")) .k_if
        else if (std.mem.eql(u8, text, "else")) .k_else
        else if (std.mem.eql(u8, text, "elseif")) .k_elseif
        else if (std.mem.eql(u8, text, "while")) .k_while
        else if (std.mem.eql(u8, text, "for")) .k_for
        else if (std.mem.eql(u8, text, "foreach")) .k_foreach
        else if (std.mem.eql(u8, text, "as")) .k_as
        else if (std.mem.eql(u8, text, "match")) .k_match
        else if (std.mem.eql(u8, text, "default")) .k_default
        else if (std.mem.eql(u8, text, "namespace")) .k_namespace
        else if (std.mem.eql(u8, text, "global")) .k_global
        else if (std.mem.eql(u8, text, "const")) .k_const
        else if (std.mem.eql(u8, text, "go")) .k_go
        else if (std.mem.eql(u8, text, "return")) .k_return
        else if (std.mem.eql(u8, text, "echo")) .k_echo
        else if (std.mem.eql(u8, text, "get")) .k_get
        else if (std.mem.eql(u8, text, "set")) .k_set
        else .t_string;
        return .{ .tag = tag, .loc = .{ .start = start, .end = self.pos } };
    }

    fn lexNumber(self: *Lexer, start: usize) Token {
        while (self.pos < self.buffer.len and (std.ascii.isDigit(self.buffer[self.pos]) or self.buffer[self.pos] == '_')) self.pos += 1;
        return .{ .tag = .t_lnumber, .loc = .{ .start = start, .end = self.pos } };
    }

    fn lexSingleQuoteString(self: *Lexer, start: usize) Token {
        while (self.pos < self.buffer.len and self.buffer[self.pos] != '\'') {
            if (self.buffer[self.pos] == '\\') self.pos += 1;
            self.pos += 1;
        }
        if (self.pos < self.buffer.len) self.pos += 1;
        return .{ .tag = .t_constant_encapsed_string, .loc = .{ .start = start, .end = self.pos } };
    }

    fn lexString(self: *Lexer, start: usize) Token {
        while (self.pos < self.buffer.len and self.buffer[self.pos] != '"') self.pos += 1;
        if (self.pos < self.buffer.len) self.pos += 1;
        return .{ .tag = .t_constant_encapsed_string, .loc = .{ .start = start, .end = self.pos } };
    }
};
