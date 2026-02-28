const std = @import("std");
const Lexer = @import("src/compiler/lexer.zig").Lexer;

pub fn main() !void {
    const source = "<?php for ($i = 0; $i < 3; $i++) { echo $i; }";
    
    var lexer = Lexer.init(source);
    
    var count: u32 = 0;
    while (count < 20) : (count += 1) {
        const token = lexer.next();
        std.debug.print("{s}: '{s}'\n", .{@tagName(token.tag), lexer.buffer[token.loc.start..token.loc.end]});
        if (token.tag == .eof) break;
    }
}
