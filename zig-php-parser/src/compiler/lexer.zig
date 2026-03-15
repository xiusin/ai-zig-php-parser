const std = @import("std");
const Token = @import("token.zig").Token;
pub const SyntaxMode = @import("syntax_mode.zig").SyntaxMode;
pub const SyntaxConfig = @import("syntax_mode.zig").SyntaxConfig;
const keyword_lookup = @import("keyword_lookup.zig");

pub const Lexer = struct {
    buffer: [:0]const u8,
    pos: usize = 0,
    state: State = .initial,
    heredoc_label: ?[]const u8 = null,
    interp_nesting_level: u32 = 0,
    syntax_mode: SyntaxMode = .php,

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

    pub fn initWithMode(buffer: [:0]const u8, mode: SyntaxMode) Lexer {
        return .{ .buffer = buffer, .syntax_mode = mode };
    }

    pub fn next(self: *Lexer) Token {
        const in_interp_expr = (self.state == .double_quote or self.state == .heredoc) and self.interp_nesting_level > 0;

        if (self.state == .script or in_interp_expr) {
            self.skipWhitespace();
        }

        if (self.pos >= self.buffer.len) return .{ .tag = .eof, .loc = .{ .start = self.pos, .end = self.pos } };

        const start = self.pos;
        const char = self.buffer[self.pos];

        if (in_interp_expr) {
            if (char == '}') {
                self.interp_nesting_level -= 1;
                self.pos += 1;
                return .{ .tag = .r_brace, .loc = .{ .start = start, .end = self.pos } };
            }
            if (char == '{') {
                self.interp_nesting_level += 1;
            }
        } else {
            switch (self.state) {
                .initial => {
                    if (char == '<' and std.mem.startsWith(u8, self.buffer[self.pos..], "<?php")) {
                        self.pos += 5;
                        self.state = .script;
                        return .{ .tag = .t_open_tag, .loc = .{ .start = start, .end = self.pos } };
                    }
                    while (self.pos < self.buffer.len and self.buffer[self.pos] != '<') self.pos += 1;
                    return .{ .tag = .t_inline_html, .loc = .{ .start = start, .end = self.pos } };
                },
                .script => {},
                .double_quote => return self.lexInterpolation(start, '"'),
                .heredoc => return self.lexInterpolation(start, 0),
                .nowdoc => return self.lexNowdoc(start),
            }
        }

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
            '.' => if (self.match('.')) (if (self.match('.')) .{ .tag = .ellipsis, .loc = .{ .start = start, .end = self.pos } } else .{ .tag = .invalid, .loc = .{ .start = start, .end = self.pos } }) else if (self.match('=')) .{ .tag = .dot_equal, .loc = .{ .start = start, .end = self.pos } } else blk: {
                // In Go mode, . followed by identifier is property access (like -> in PHP)
                if (self.syntax_mode == .go and self.pos < self.buffer.len) {
                    const next_char = self.buffer[self.pos];
                    if ((next_char >= 'a' and next_char <= 'z') or
                        (next_char >= 'A' and next_char <= 'Z') or next_char == '_')
                    {
                        break :blk .{ .tag = .arrow, .loc = .{ .start = start, .end = self.pos } };
                    }
                }
                break :blk .{ .tag = .dot, .loc = .{ .start = start, .end = self.pos } };
            },
            '$' => blk: {
                // In Go mode, $ is not allowed for variables
                if (self.syntax_mode == .go) {
                    break :blk .{ .tag = .invalid, .loc = .{ .start = start, .end = self.pos } };
                }
                break :blk self.lexVariable(start);
            },
            '+' => if (self.match('+')) .{ .tag = .plus_plus, .loc = .{ .start = start, .end = self.pos } } else if (self.match('=')) .{ .tag = .plus_equal, .loc = .{ .start = start, .end = self.pos } } else .{ .tag = .plus, .loc = .{ .start = start, .end = self.pos } },
            '-' => if (self.match('>')) .{ .tag = .arrow, .loc = .{ .start = start, .end = self.pos } } else if (self.match('-')) .{ .tag = .minus_minus, .loc = .{ .start = start, .end = self.pos } } else if (self.match('=')) .{ .tag = .minus_equal, .loc = .{ .start = start, .end = self.pos } } else .{ .tag = .minus, .loc = .{ .start = start, .end = self.pos } },
            '*' => if (self.match('*')) (if (self.match('=')) .{ .tag = .star_star_equal, .loc = .{ .start = start, .end = self.pos } } else .{ .tag = .star_star, .loc = .{ .start = start, .end = self.pos } }) else if (self.match('=')) .{ .tag = .asterisk_equal, .loc = .{ .start = start, .end = self.pos } } else .{ .tag = .asterisk, .loc = .{ .start = start, .end = self.pos } },
            '/' => if (self.match('=')) .{ .tag = .slash_equal, .loc = .{ .start = start, .end = self.pos } } else if (self.match('/')) self.skipLineComment(start) else if (self.match('*')) self.skipBlockComment(start) else .{ .tag = .slash, .loc = .{ .start = start, .end = self.pos } },
            '%' => if (self.match('=')) .{ .tag = .percent_equal, .loc = .{ .start = start, .end = self.pos } } else .{ .tag = .percent, .loc = .{ .start = start, .end = self.pos } },
            '^' => if (self.match('=')) .{ .tag = .caret_equal, .loc = .{ .start = start, .end = self.pos } } else .{ .tag = .caret, .loc = .{ .start = start, .end = self.pos } },
            '~' => .{ .tag = .tilde, .loc = .{ .start = start, .end = self.pos } },
            '?' => if (self.match('>')) .{ .tag = .t_close_tag, .loc = .{ .start = start, .end = self.pos } } else if (self.match('?')) .{ .tag = .double_question, .loc = .{ .start = start, .end = self.pos } } else if (self.match('-')) {
                // Check for ?-> (safe arrow in PHP mode)
                if (self.match('>')) {
                    return .{ .tag = .safe_arrow, .loc = .{ .start = start, .end = self.pos } };
                }
                // If not ?->, it's invalid
                return .{ .tag = .invalid, .loc = .{ .start = start, .end = self.pos } };
            } else if (self.match('.')) {
                // ?. (safe dot in Go mode)
                return .{ .tag = .safe_dot, .loc = .{ .start = start, .end = self.pos } };
            } else .{ .tag = .question, .loc = .{ .start = start, .end = self.pos } },
            '=' => if (self.match('>')) .{ .tag = .fat_arrow, .loc = .{ .start = start, .end = self.pos } } else if (self.match('=')) (if (self.match('=')) .{ .tag = .equal_equal_equal, .loc = .{ .start = start, .end = self.pos } } else .{ .tag = .equal_equal, .loc = .{ .start = start, .end = self.pos } }) else .{ .tag = .equal, .loc = .{ .start = start, .end = self.pos } },
            '!' => if (self.match('=')) (if (self.match('=')) .{ .tag = .bang_equal_equal, .loc = .{ .start = start, .end = self.pos } } else .{ .tag = .bang_equal, .loc = .{ .start = start, .end = self.pos } }) else .{ .tag = .bang, .loc = .{ .start = start, .end = self.pos } },
            '&' => if (self.match('&')) .{ .tag = .double_ampersand, .loc = .{ .start = start, .end = self.pos } } else if (self.match('=')) .{ .tag = .and_equal, .loc = .{ .start = start, .end = self.pos } } else .{ .tag = .ampersand, .loc = .{ .start = start, .end = self.pos } },
            '|' => if (self.match('|')) .{ .tag = .double_pipe, .loc = .{ .start = start, .end = self.pos } } else if (self.match('=')) .{ .tag = .or_equal, .loc = .{ .start = start, .end = self.pos } } else if (self.match('>')) .{ .tag = .pipe_greater, .loc = .{ .start = start, .end = self.pos } } else .{ .tag = .pipe, .loc = .{ .start = start, .end = self.pos } },
            '<' => if (self.match('<')) {
                if (self.match('<')) return self.lexHeredocStart(start);
                if (self.match('=')) return .{ .tag = .less_less_equal, .loc = .{ .start = start, .end = self.pos } };
                return .{ .tag = .less_less, .loc = .{ .start = start, .end = self.pos } };
            } else if (self.match('=')) {
                // Check for <=> (spaceship) first, then <= (less_equal)
                if (self.match('>')) {
                    return .{ .tag = .spaceship, .loc = .{ .start = start, .end = self.pos } };
                }
                return .{ .tag = .less_equal, .loc = .{ .start = start, .end = self.pos } };
            } else .{ .tag = .less, .loc = .{ .start = start, .end = self.pos } },
            '>' => if (self.match('>')) (if (self.match('=')) .{ .tag = .greater_greater_equal, .loc = .{ .start = start, .end = self.pos } } else .{ .tag = .greater_greater, .loc = .{ .start = start, .end = self.pos } }) else if (self.match('=')) .{ .tag = .greater_equal, .loc = .{ .start = start, .end = self.pos } } else .{ .tag = .greater, .loc = .{ .start = start, .end = self.pos } },
            '#' => if (self.match('[')) .{ .tag = .t_attribute_start, .loc = .{ .start = start, .end = self.pos } } else self.skipLineComment(start),
            ':' => if (self.match(':')) .{ .tag = .double_colon, .loc = .{ .start = start, .end = self.pos } } else .{ .tag = .colon, .loc = .{ .start = start, .end = self.pos } },
            '0'...'9' => self.lexNumber(start),
            'a'...'z', 'A'...'Z', '_' => self.lexIdentifier(start),
            '\\' => if (self.pos < self.buffer.len and ((self.buffer[self.pos] >= 'a' and self.buffer[self.pos] <= 'z') or (self.buffer[self.pos] >= 'A' and self.buffer[self.pos] <= 'Z') or self.buffer[self.pos] == '_')) self.lexIdentifier(start) else .{ .tag = .invalid, .loc = .{ .start = start, .end = self.pos } },
            '\'' => self.lexSingleQuoteString(start),
            '"' => self.lexDoubleQuoteString(start),
            '`' => self.lexBacktickString(start),
            else => .{ .tag = .invalid, .loc = .{ .start = start, .end = self.pos } },
        };
    }

    fn lexInterpolation(self: *Lexer, start: usize, end_char: u8) Token {
        if (end_char != 0 and self.buffer[self.pos] == end_char) {
            self.pos += 1;
            self.state = .script;
            return .{ .tag = .t_double_quote, .loc = .{ .start = start, .end = self.pos } };
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
                    self.interp_nesting_level += 1;
                    return .{ .tag = .t_dollar_open_curly_brace, .loc = .{ .start = start, .end = self.pos } };
                }
                if (std.ascii.isAlphabetic(self.buffer[self.pos + 1]) or self.buffer[self.pos + 1] == '_') {
                    return self.lexVariableInInterpolation(start);
                }
            }
        }

        if (self.buffer[self.pos] == '{' and self.pos + 1 < self.buffer.len and self.buffer[self.pos + 1] == '$') {
            self.pos += 1;
            self.interp_nesting_level += 1;
            return .{ .tag = .t_curly_open, .loc = .{ .start = start, .end = self.pos } };
        }

        while (self.pos < self.buffer.len) {
            const c = self.buffer[self.pos];
            if (c == end_char and end_char != 0) break;
            // 处理转义字符：跳过 \$ 等转义序列
            if (c == '\\' and self.pos + 1 < self.buffer.len) {
                self.pos += 2; // 跳过反斜杠和下一个字符
                continue;
            }
            if (c == '$' or (c == '{' and self.pos + 1 < self.buffer.len and self.buffer[self.pos + 1] == '$')) break;
            if (self.heredoc_label) |label| {
                if (std.mem.startsWith(u8, self.buffer[self.pos..], label)) break;
            }
            self.pos += 1;
        }
        return .{ .tag = .t_encapsed_and_whitespace, .loc = .{ .start = start, .end = self.pos } };
    }

    fn lexNowdoc(self: *Lexer, start: usize) Token {
        if (self.heredoc_label) |label| {
            // Check if we're at the ending label (must be at start of line)
            if (self.isAtLineStart(start) and std.mem.startsWith(u8, self.buffer[self.pos..], label)) {
                self.pos += label.len;
                self.state = .script;
                self.heredoc_label = null;
                return .{ .tag = .t_heredoc_end, .loc = .{ .start = start, .end = self.pos } };
            }
        }
        while (self.pos < self.buffer.len) {
            if (self.heredoc_label) |label| {
                // Check for label at start of new line
                if (self.buffer[self.pos] == '\n') {
                    const next_pos = self.pos + 1;
                    if (next_pos < self.buffer.len and std.mem.startsWith(u8, self.buffer[next_pos..], label)) {
                        self.pos += 1; // include the newline in content
                        break;
                    }
                }
            }
            self.pos += 1;
        }
        return .{ .tag = .t_encapsed_and_whitespace, .loc = .{ .start = start, .end = self.pos } };
    }

    fn isAtLineStart(self: *Lexer, pos: usize) bool {
        if (pos == 0) return true;
        const prev_char = self.buffer[pos - 1];
        return prev_char == '\n' or prev_char == '\r';
    }

    fn lexHeredocStart(self: *Lexer, start: usize) Token {
        self.skipWhitespace();
        var is_nowdoc = false;
        var is_quoted_heredoc = false;

        // Check for nowdoc (single quotes) or quoted heredoc (double quotes)
        if (self.match('\'')) {
            is_nowdoc = true;
        } else if (self.match('"')) {
            is_quoted_heredoc = true;
        }

        const label_start = self.pos;
        while (self.pos < self.buffer.len and (std.ascii.isAlphanumeric(self.buffer[self.pos]) or self.buffer[self.pos] == '_')) self.pos += 1;
        const label = self.buffer[label_start..self.pos];

        // Skip closing quote if present
        if (is_nowdoc) _ = self.match('\'');
        if (is_quoted_heredoc) _ = self.match('"');

        // Skip newline after label
        if (self.pos < self.buffer.len and self.buffer[self.pos] == '\r') self.pos += 1;
        if (self.pos < self.buffer.len and self.buffer[self.pos] == '\n') self.pos += 1;

        self.heredoc_label = label;
        self.state = if (is_nowdoc) .nowdoc else .heredoc;
        return .{ .tag = if (is_nowdoc) .t_nowdoc_start else .t_heredoc_start, .loc = .{ .start = start, .end = self.pos } };
    }

    fn match(self: *Lexer, expected: u8) bool {
        if (self.pos < self.buffer.len and self.buffer[self.pos] == expected) {
            self.pos += 1;
            return true;
        }
        return false;
    }

    fn skipWhitespace(self: *Lexer) void {
        while (self.pos < self.buffer.len) {
            if (self.pos + 16 <= self.buffer.len) {
                const vector: @Vector(16, u8) = self.buffer[self.pos..][0..16].*;
                const mask = (vector == @as(@Vector(16, u8), @splat(' '))) | (vector == @as(@Vector(16, u8), @splat('\t'))) | (vector == @as(@Vector(16, u8), @splat('\n'))) | (vector == @as(@Vector(16, u8), @splat('\r')));
                const bitmask: u16 = @bitCast(mask);
                if (bitmask == 0xFFFF) {
                    self.pos += 16;
                    continue;
                }
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

    fn skipBlockComment(self: *Lexer, start: usize) Token {
        _ = start;
        while (self.pos < self.buffer.len) {
            if (self.buffer[self.pos] == '*' and self.pos + 1 < self.buffer.len and self.buffer[self.pos + 1] == '/') {
                self.pos += 2;
                break;
            }
            self.pos += 1;
        }
        return self.next();
    }

    fn lexVariable(self: *Lexer, start: usize) Token {
        if (self.buffer[self.pos] == '$') self.pos += 1;
        while (self.pos < self.buffer.len and (std.ascii.isAlphanumeric(self.buffer[self.pos]) or self.buffer[self.pos] == '_')) self.pos += 1;
        return .{ .tag = .t_variable, .loc = .{ .start = start, .end = self.pos } };
    }

    fn lexVariableInInterpolation(self: *Lexer, start: usize) Token {
        // 在字符串插值中识别变量，支持 $var->prop 和 $var[key]
        if (self.buffer[self.pos] == '$') self.pos += 1;

        // 识别变量名
        while (self.pos < self.buffer.len and (std.ascii.isAlphanumeric(self.buffer[self.pos]) or self.buffer[self.pos] == '_')) {
            self.pos += 1;
        }

        // 检查是否有 -> 属性访问
        if (self.pos + 1 < self.buffer.len and self.buffer[self.pos] == '-' and self.buffer[self.pos + 1] == '>') {
            self.pos += 2; // skip ->

            // 识别属性名
            while (self.pos < self.buffer.len and (std.ascii.isAlphanumeric(self.buffer[self.pos]) or self.buffer[self.pos] == '_')) {
                self.pos += 1;
            }
        }
        // TODO: 支持 $var[key] 语法

        return .{ .tag = .t_variable, .loc = .{ .start = start, .end = self.pos } };
    }

    fn lexIdentifier(self: *Lexer, start: usize) Token {
        while (self.pos < self.buffer.len and (std.ascii.isAlphanumeric(self.buffer[self.pos]) or self.buffer[self.pos] == '_' or self.buffer[self.pos] == '\\')) self.pos += 1;
        const text = self.buffer[start..self.pos];

        // 使用高性能关键词查找（完美哈希表，O(1)复杂度）
        // 短关键词（2-5字符）使用超快速路径，长关键词使用哈希表
        if (text.len <= 5) {
            if (keyword_lookup.lookupFast(text)) |tag| {
                return .{ .tag = tag, .loc = .{ .start = start, .end = self.pos } };
            }
        } else if (text.len <= 15) {
            if (keyword_lookup.lookup(text)) |tag| {
                return .{ .tag = tag, .loc = .{ .start = start, .end = self.pos } };
            }
        }

        // 非关键词：Go模式返回t_go_identifier，PHP模式返回t_string
        const tag: Token.Tag = if (self.syntax_mode == .go) .t_go_identifier else .t_string;
        return .{ .tag = tag, .loc = .{ .start = start, .end = self.pos } };
    }

    fn lexNumber(self: *Lexer, start: usize) Token {
        var has_dot = false;
        var has_exp = false;

        // Handle different number formats
        if (self.buffer[self.pos] == '0' and self.pos + 1 < self.buffer.len) {
            const next_char = self.buffer[self.pos + 1];
            if (next_char == 'x' or next_char == 'X') {
                // Hexadecimal
                self.pos += 2;
                while (self.pos < self.buffer.len and (std.ascii.isHex(self.buffer[self.pos]) or self.buffer[self.pos] == '_')) {
                    self.pos += 1;
                }
                return .{ .tag = .t_lnumber, .loc = .{ .start = start, .end = self.pos } };
            } else if (next_char == 'b' or next_char == 'B') {
                // Binary
                self.pos += 2;
                while (self.pos < self.buffer.len and (self.buffer[self.pos] == '0' or self.buffer[self.pos] == '1' or self.buffer[self.pos] == '_')) {
                    self.pos += 1;
                }
                return .{ .tag = .t_lnumber, .loc = .{ .start = start, .end = self.pos } };
            } else if (next_char == 'o' or next_char == 'O') {
                // Octal
                self.pos += 2;
                while (self.pos < self.buffer.len and (self.buffer[self.pos] >= '0' and self.buffer[self.pos] <= '7' or self.buffer[self.pos] == '_')) {
                    self.pos += 1;
                }
                return .{ .tag = .t_lnumber, .loc = .{ .start = start, .end = self.pos } };
            }
        }

        // Decimal number
        while (self.pos < self.buffer.len and (std.ascii.isDigit(self.buffer[self.pos]) or self.buffer[self.pos] == '_')) {
            self.pos += 1;
        }

        // Check for decimal point
        if (self.pos < self.buffer.len and self.buffer[self.pos] == '.' and
            self.pos + 1 < self.buffer.len and std.ascii.isDigit(self.buffer[self.pos + 1]))
        {
            has_dot = true;
            self.pos += 1;
            while (self.pos < self.buffer.len and (std.ascii.isDigit(self.buffer[self.pos]) or self.buffer[self.pos] == '_')) {
                self.pos += 1;
            }
        }

        // Check for scientific notation
        if (self.pos < self.buffer.len and (self.buffer[self.pos] == 'e' or self.buffer[self.pos] == 'E')) {
            has_exp = true;
            self.pos += 1;
            if (self.pos < self.buffer.len and (self.buffer[self.pos] == '+' or self.buffer[self.pos] == '-')) {
                self.pos += 1;
            }
            while (self.pos < self.buffer.len and (std.ascii.isDigit(self.buffer[self.pos]) or self.buffer[self.pos] == '_')) {
                self.pos += 1;
            }
        }

        return .{ .tag = if (has_dot or has_exp) .t_dnumber else .t_lnumber, .loc = .{ .start = start, .end = self.pos } };
    }

    fn lexSingleQuoteString(self: *Lexer, start: usize) Token {
        while (self.pos < self.buffer.len and self.buffer[self.pos] != '\'') {
            if (self.buffer[self.pos] == '\\') self.pos += 1;
            self.pos += 1;
        }
        if (self.pos < self.buffer.len) self.pos += 1;
        return .{ .tag = .t_constant_encapsed_string, .loc = .{ .start = start, .end = self.pos } };
    }

    fn lexDoubleQuoteString(self: *Lexer, start: usize) Token {
        // Check if this is a simple string without interpolation
        var pos = self.pos;
        var has_interpolation = false;

        while (pos < self.buffer.len and self.buffer[pos] != '"') {
            if (self.buffer[pos] == '\\') {
                pos += 2; // Skip escaped character (including \$)
                continue;
            } else if (self.buffer[pos] == '$') {
                // Check if this is variable interpolation
                if (pos + 1 < self.buffer.len and
                    (std.ascii.isAlphabetic(self.buffer[pos + 1]) or self.buffer[pos + 1] == '_' or self.buffer[pos + 1] == '{'))
                {
                    has_interpolation = true;
                    break;
                }
            } else if (self.buffer[pos] == '{' and pos + 1 < self.buffer.len and self.buffer[pos + 1] == '$') {
                has_interpolation = true;
                break;
            }
            pos += 1;
        }

        if (has_interpolation) {
            // Handle interpolated string - set state and return appropriate token
            self.state = .double_quote;
            return .{ .tag = .t_double_quote, .loc = .{ .start = start, .end = self.pos } };
        } else {
            // Simple string without interpolation - consume the whole string
            while (self.pos < self.buffer.len and self.buffer[self.pos] != '"') {
                if (self.buffer[self.pos] == '\\') self.pos += 1; // Skip escaped character
                self.pos += 1;
            }
            if (self.pos < self.buffer.len) self.pos += 1; // Consume closing quote
            return .{ .tag = .t_constant_encapsed_string, .loc = .{ .start = start, .end = self.pos } };
        }
    }

    fn lexString(self: *Lexer, start: usize) Token {
        while (self.pos < self.buffer.len and self.buffer[self.pos] != '"') self.pos += 1;
        if (self.pos < self.buffer.len) self.pos += 1;
        return .{ .tag = .t_constant_encapsed_string, .loc = .{ .start = start, .end = self.pos } };
    }

    /// 解析反引号原始字符串（类似Go的``多行字符串）
    /// 不进行任何转义处理，保留原始内容
    fn lexBacktickString(self: *Lexer, start: usize) Token {
        while (self.pos < self.buffer.len and self.buffer[self.pos] != '`') {
            self.pos += 1;
        }
        if (self.pos < self.buffer.len) self.pos += 1;
        return .{ .tag = .t_backtick_string, .loc = .{ .start = start, .end = self.pos } };
    }
};
