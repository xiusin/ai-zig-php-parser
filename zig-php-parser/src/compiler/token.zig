const std = @import("std");

pub const Token = struct {
    tag: Tag,
    loc: Loc,

    pub const Loc = struct { start: usize, end: usize };

    pub const Tag = enum {
        eof,
        invalid,
        // Tags
        t_open_tag,
        t_open_tag_with_echo,
        t_close_tag,
        // Literals
        t_variable,
        t_constant_encapsed_string,
        t_lnumber,
        t_dnumber,
        t_inline_html,
        t_string,
        t_string_varname,
        t_double_quote,
        t_heredoc_start,
        t_heredoc_end,
        t_nowdoc_start,
        t_encapsed_and_whitespace,
        t_backtick_string, // 反引号原始字符串（类似Go的``）
        // Interpolation
        t_dollar_open_curly_brace, // ${
        t_curly_open, // {$
        // Class-like Keywords
        k_class,
        k_interface,
        k_trait,
        k_enum,
        k_struct,
        k_extends,
        k_implements,
        k_use,
        // Modifiers
        k_public,
        k_private,
        k_protected,
        k_static,
        k_readonly,
        k_final,
        k_abstract,
        // Control Flow
        k_if,
        k_else,
        k_elseif,
        k_while,
        k_do,
        k_for,
        k_foreach,
        k_as,
        k_match,
        k_default,
        k_switch,
        k_case,
        k_break,
        k_continue,
        k_return,
        k_try,
        k_catch,
        k_finally,
        k_throw,
        k_goto,
        k_yield,
        k_yield_from,
        k_from,
        k_range,
        k_in,
        // Other Keywords
        k_function,
        k_fn,
        k_new,
        k_echo,
        k_global,
        k_const,
        k_namespace,
        k_declare,
        k_list,
        k_and,
        k_or,
        k_xor,
        k_instanceof,
        k_clone,
        k_print,
        k_var,
        k_unset,
        k_include,
        k_include_once,
        k_require,
        k_require_once,
        k_go, // Coroutine
        k_lock, // Mutex lock syntax sugar
        k_get,
        k_set, // PHP 8.4 Property Hooks
        // Class context keywords
        k_self,
        k_parent,
        k_static_ref, // static:: 用于后期静态绑定
        // Magic constants
        m_dir, // __DIR__
        m_file, // __FILE__
        m_line, // __LINE__
        m_function, // __FUNCTION__
        m_class, // __CLASS__
        m_method, // __METHOD__
        m_namespace, // __NAMESPACE__
        // Literals
        k_true,
        k_false,
        k_null,
        // Type keywords
        k_array,
        k_callable,
        k_iterable,
        k_object,
        k_mixed,
        k_never,
        k_void,
        // Symbols
        l_paren,
        r_paren,
        l_bracket,
        r_bracket,
        l_brace,
        r_brace,
        semicolon,
        comma,
        dot,
        colon,
        arrow,
        fat_arrow,
        double_colon,
        ellipsis,
        // Operators
        plus,
        minus,
        asterisk,
        slash,
        percent,
        equal,
        plus_plus,
        minus_minus,
        plus_equal,
        minus_equal,
        asterisk_equal,
        slash_equal,
        percent_equal,
        equal_equal,
        equal_equal_equal,
        bang_equal,
        bang_equal_equal,
        less,
        greater,
        less_equal,
        greater_equal,
        spaceship,
        double_question,
        double_ampersand,
        double_pipe,
        ampersand,
        pipe,
        pipe_greater, // |> (pipe operator)
        bang,
        question, // ! and ?
        k_with, // with keyword for clone with
        t_attribute_start, // #[
        // Go mode specific tokens
        t_go_identifier, // Go mode identifier (variable without $ prefix)
    };

    /// Check if the token is a Go mode identifier
    pub fn isGoIdentifier(self: Token) bool {
        return self.tag == .t_go_identifier;
    }

    /// Check if the token is any kind of variable (PHP or Go mode)
    pub fn isVariable(self: Token) bool {
        return self.tag == .t_variable or self.tag == .t_go_identifier;
    }

    /// Check if the token is an identifier (string or Go identifier)
    pub fn isIdentifier(self: Token) bool {
        return self.tag == .t_string or self.tag == .t_go_identifier;
    }
};
