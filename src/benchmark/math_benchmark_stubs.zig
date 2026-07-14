//! 数学运算测试的 PHP 脚本生成存根
//! 这些函数生成对应的 PHP 测试脚本用于性能对比

const std = @import("std");
const MathBenchmark = @import("math_benchmark.zig").MathBenchmark;

/// 生成整数加法 PHP 脚本
pub fn generateIntegerAdditionScript(self: *MathBenchmark) !void {
    const path = try std.fmt.allocPrint(self.allocator, "{s}/integer_addition.php", .{self.config.script_output_dir});
    defer self.allocator.free(path);

    const file = try std.fs.cwd.createFile(path, .{});
    defer file.close();

    const writer = file.writer();
    try writer.print(
        \\<?php
        \\$sum = 0;
        \\for ($i = 0; $i < {d}; $i++) {{
        \\    $sum += $i;
        \\}}
        \\?>
        \\
    , .{self.config.iterations});
}

/// 生成整数减法 PHP 脚本
pub fn generateIntegerSubtractionScript(self: *MathBenchmark) !void {
    const path = try std.fmt.allocPrint(self.allocator, "{s}/integer_subtraction.php", .{self.config.script_output_dir});
    defer self.allocator.free(path);

    const file = try std.fs.cwd.createFile(path, .{});
    defer file.close();

    const writer = file.writer();
    try writer.print(
        \\<?php
        \\$diff = 1000000;
        \\for ($i = 0; $i < {d}; $i++) {{
        \\    $diff -= ($i % 100);
        \\}}
        \\?>
        \\
    , .{self.config.iterations});
}

// 完整实现所有 PHP 脚本生成函数
pub fn generateIntegerMultiplicationScript(self: *MathBenchmark) !void {
    const path = try std.fmt.allocPrint(self.allocator, "{s}/integer_multiplication.php", .{self.config.script_output_dir});
    defer self.allocator.free(path);
    const file = try std.fs.cwd.createFile(path, .{});
    defer file.close();
    try file.writer().print("<?php\n$product = 1;\nfor ($i = 1; $i < {d}; $i++) {{ $product = ($product * $i) % 1000000; }}\n?>\n", .{self.config.iterations});
}

pub fn generateIntegerDivisionScript(self: *MathBenchmark) !void {
    const path = try std.fmt.allocPrint(self.allocator, "{s}/integer_division.php", .{self.config.script_output_dir});
    defer self.allocator.free(path);
    const file = try std.fs.cwd.createFile(path, .{});
    defer file.close();
    try file.writer().print("<?php\n$result = 1000000;\nfor ($i = 1; $i < {d}; $i++) {{ $result = intdiv($result + $i, 2); }}\n?>\n", .{self.config.iterations});
}

pub fn generateIntegerModuloScript(self: *MathBenchmark) !void {
    const path = try std.fmt.allocPrint(self.allocator, "{s}/integer_modulo.php", .{self.config.script_output_dir});
    defer self.allocator.free(path);
    const file = try std.fs.cwd.createFile(path, .{});
    defer file.close();
    try file.writer().print("<?php\n$result = 0;\nfor ($i = 0; $i < {d}; $i++) {{ $result += $i % 97; }}\n?>\n", .{self.config.iterations});
}

pub fn generateIntegerBitwiseScript(self: *MathBenchmark) !void {
    const path = try std.fmt.allocPrint(self.allocator, "{s}/integer_bitwise.php", .{self.config.script_output_dir});
    defer self.allocator.free(path);
    const file = try std.fs.cwd.createFile(path, .{});
    defer file.close();
    try file.writer().print("<?php\n$result = 0;\nfor ($i = 0; $i < {d}; $i++) {{ $result ^= ($i & 0xFF) | ($i << 8); }}\n?>\n", .{self.config.iterations});
}

pub fn generateIntegerShiftScript(self: *MathBenchmark) !void {
    const path = try std.fmt.allocPrint(self.allocator, "{s}/integer_shift.php", .{self.config.script_output_dir});
    defer self.allocator.free(path);
    const file = try std.fs.cwd.createFile(path, .{});
    defer file.close();
    try file.writer().print("<?php\n$result = 1;\nfor ($i = 0; $i < {d}; $i++) {{ $result = ($result << 1) | ($result >> 31); }}\n?>\n", .{self.config.iterations});
}

pub fn generateFloatAdditionScript(self: *MathBenchmark) !void {
    const path = try std.fmt.allocPrint(self.allocator, "{s}/float_addition.php", .{self.config.script_output_dir});
    defer self.allocator.free(path);
    const file = try std.fs.cwd.createFile(path, .{});
    defer file.close();
    try file.writer().print("<?php\n$sum = 0.0;\nfor ($i = 0; $i < {d}; $i++) {{ $sum += $i * 0.1; }}\n?>\n", .{self.config.iterations});
}

pub fn generateFloatSubtractionScript(self: *MathBenchmark) !void {
    const path = try std.fmt.allocPrint(self.allocator, "{s}/float_subtraction.php", .{self.config.script_output_dir});
    defer self.allocator.free(path);
    const file = try std.fs.cwd.createFile(path, .{});
    defer file.close();
    try file.writer().print("<?php\n$diff = 1000000.0;\nfor ($i = 0; $i < {d}; $i++) {{ $diff -= $i * 0.01; }}\n?>\n", .{self.config.iterations});
}

pub fn generateFloatMultiplicationScript(self: *MathBenchmark) !void {
    const path = try std.fmt.allocPrint(self.allocator, "{s}/float_multiplication.php", .{self.config.script_output_dir});
    defer self.allocator.free(path);
    const file = try std.fs.cwd.createFile(path, .{});
    defer file.close();
    try file.writer().print("<?php\n$product = 1.0;\nfor ($i = 1; $i < {d}; $i++) {{ $product *= 1.0001; if ($product > 1e6) $product = 1.0; }}\n?>\n", .{self.config.iterations});
}

pub fn generateFloatDivisionScript(self: *MathBenchmark) !void {
    const path = try std.fmt.allocPrint(self.allocator, "{s}/float_division.php", .{self.config.script_output_dir});
    defer self.allocator.free(path);
    const file = try std.fs.cwd.createFile(path, .{});
    defer file.close();
    try file.writer().print("<?php\n$result = 1000000.0;\nfor ($i = 1; $i < {d}; $i++) {{ $result = $result / 1.0001; }}\n?>\n", .{self.config.iterations});
}

pub fn generateFloatTrigonometricScript(self: *MathBenchmark) !void {
    const path = try std.fmt.allocPrint(self.allocator, "{s}/float_trigonometric.php", .{self.config.script_output_dir});
    defer self.allocator.free(path);
    const file = try std.fs.cwd.createFile(path, .{});
    defer file.close();
    try file.writer().print("<?php\n$result = 0.0;\nfor ($i = 0; $i < {d}; $i++) {{ $result += sin($i * 0.01) + cos($i * 0.01); }}\n?>\n", .{self.config.iterations});
}

pub fn generateFloatExpLogScript(self: *MathBenchmark) !void {
    const path = try std.fmt.allocPrint(self.allocator, "{s}/float_exp_log.php", .{self.config.script_output_dir});
    defer self.allocator.free(path);
    const file = try std.fs.cwd.createFile(path, .{});
    defer file.close();
    try file.writer().print("<?php\n$result = 0.0;\nfor ($i = 1; $i < {d}; $i++) {{ $result += exp(log($i)); }}\n?>\n", .{self.config.iterations});
}

pub fn generateMathSqrtScript(self: *MathBenchmark) !void {
    const path = try std.fmt.allocPrint(self.allocator, "{s}/math_sqrt.php", .{self.config.script_output_dir});
    defer self.allocator.free(path);
    const file = try std.fs.cwd.createFile(path, .{});
    defer file.close();
    try file.writer().print("<?php\n$result = 0.0;\nfor ($i = 1; $i < {d}; $i++) {{ $result += sqrt($i); }}\n?>\n", .{self.config.iterations});
}

pub fn generateMathPowScript(self: *MathBenchmark) !void {
    const path = try std.fmt.allocPrint(self.allocator, "{s}/math_pow.php", .{self.config.script_output_dir});
    defer self.allocator.free(path);
    const file = try std.fs.cwd.createFile(path, .{});
    defer file.close();
    try file.writer().print("<?php\n$result = 0.0;\nfor ($i = 1; $i < {d}; $i++) {{ $result += pow($i % 10, 2); }}\n?>\n", .{self.config.iterations});
}

pub fn generateMathAbsScript(self: *MathBenchmark) !void {
    const path = try std.fmt.allocPrint(self.allocator, "{s}/math_abs.php", .{self.config.script_output_dir});
    defer self.allocator.free(path);
    const file = try std.fs.cwd.createFile(path, .{});
    defer file.close();
    try file.writer().print("<?php\n$result = 0;\nfor ($i = -{d}; $i < {d}; $i++) {{ $result += abs($i); }}\n?>\n", .{ self.config.iterations / 2, self.config.iterations / 2 });
}

pub fn generateMathRoundScript(self: *MathBenchmark) !void {
    const path = try std.fmt.allocPrint(self.allocator, "{s}/math_round.php", .{self.config.script_output_dir});
    defer self.allocator.free(path);
    const file = try std.fs.cwd.createFile(path, .{});
    defer file.close();
    try file.writer().print("<?php\n$result = 0.0;\nfor ($i = 0; $i < {d}; $i++) {{ $result += round($i * 0.123456, 2); }}\n?>\n", .{self.config.iterations});
}

pub fn generateMathFloorCeilScript(self: *MathBenchmark) !void {
    const path = try std.fmt.allocPrint(self.allocator, "{s}/math_floor_ceil.php", .{self.config.script_output_dir});
    defer self.allocator.free(path);
    const file = try std.fs.cwd.createFile(path, .{});
    defer file.close();
    try file.writer().print("<?php\n$result = 0.0;\nfor ($i = 0; $i < {d}; $i++) {{ $result += floor($i * 0.7) + ceil($i * 0.3); }}\n?>\n", .{self.config.iterations});
}

pub fn generateMathMinMaxScript(self: *MathBenchmark) !void {
    const path = try std.fmt.allocPrint(self.allocator, "{s}/math_min_max.php", .{self.config.script_output_dir});
    defer self.allocator.free(path);
    const file = try std.fs.cwd.createFile(path, .{});
    defer file.close();
    try file.writer().print("<?php\n$result = 0;\nfor ($i = 0; $i < {d}; $i++) {{ $result += min($i, 1000) + max($i, 0); }}\n?>\n", .{self.config.iterations});
}

pub fn generateComplexAdditionScript(self: *MathBenchmark) !void {
    const path = try std.fmt.allocPrint(self.allocator, "{s}/complex_addition.php", .{self.config.script_output_dir});
    defer self.allocator.free(path);
    const file = try std.fs.cwd.createFile(path, .{});
    defer file.close();
    try file.writer().print("<?php\n$real = 0.0; $imag = 0.0;\nfor ($i = 0; $i < {d}; $i++) {{ $real += $i * 0.1; $imag += $i * 0.2; }}\n?>\n", .{self.config.iterations});
}

pub fn generateComplexSubtractionScript(self: *MathBenchmark) !void {
    const path = try std.fmt.allocPrint(self.allocator, "{s}/complex_subtraction.php", .{self.config.script_output_dir});
    defer self.allocator.free(path);
    const file = try std.fs.cwd.createFile(path, .{});
    defer file.close();
    try file.writer().print("<?php\n$real = 1000.0; $imag = 1000.0;\nfor ($i = 0; $i < {d}; $i++) {{ $real -= $i * 0.01; $imag -= $i * 0.02; }}\n?>\n", .{self.config.iterations});
}

pub fn generateComplexMultiplicationScript(self: *MathBenchmark) !void {
    const path = try std.fmt.allocPrint(self.allocator, "{s}/complex_multiplication.php", .{self.config.script_output_dir});
    defer self.allocator.free(path);
    const file = try std.fs.cwd.createFile(path, .{});
    defer file.close();
    try file.writer().print("<?php\n$r1=1.0; $i1=0.0;\nfor ($i=0; $i<{d}; $i++) {{ $r2=$i*0.01; $i2=$i*0.02; $nr=$r1*$r2-$i1*$i2; $ni=$r1*$i2+$i1*$r2; $r1=$nr; $i1=$ni; if(abs($r1)>1e6) {{ $r1=1.0; $i1=0.0; }} }}\n?>\n", .{self.config.iterations});
}

pub fn generateComplexDivisionScript(self: *MathBenchmark) !void {
    const path = try std.fmt.allocPrint(self.allocator, "{s}/complex_division.php", .{self.config.script_output_dir});
    defer self.allocator.free(path);
    const file = try std.fs.cwd.createFile(path, .{});
    defer file.close();
    try file.writer().print("<?php\n$r1=1000.0; $i1=1000.0;\nfor ($i=1; $i<{d}; $i++) {{ $r2=$i*0.1; $i2=$i*0.2; $d=$r2*$r2+$i2*$i2; $nr=($r1*$r2+$i1*$i2)/$d; $ni=($i1*$r2-$r1*$i2)/$d; $r1=$nr; $i1=$ni; }}\n?>\n", .{self.config.iterations});
}

pub fn generateComplexConjugateScript(self: *MathBenchmark) !void {
    const path = try std.fmt.allocPrint(self.allocator, "{s}/complex_conjugate.php", .{self.config.script_output_dir});
    defer self.allocator.free(path);
    const file = try std.fs.cwd.createFile(path, .{});
    defer file.close();
    try file.writer().print("<?php\n$result = 0.0;\nfor ($i = 0; $i < {d}; $i++) {{ $real = $i * 0.1; $imag = $i * 0.2; $result += $real - $imag; }}\n?>\n", .{self.config.iterations});
}

pub fn generateComplexMagnitudeScript(self: *MathBenchmark) !void {
    const path = try std.fmt.allocPrint(self.allocator, "{s}/complex_magnitude.php", .{self.config.script_output_dir});
    defer self.allocator.free(path);
    const file = try std.fs.cwd.createFile(path, .{});
    defer file.close();
    try file.writer().print("<?php\n$result = 0.0;\nfor ($i = 0; $i < {d}; $i++) {{ $real = $i * 0.1; $imag = $i * 0.2; $result += sqrt($real*$real + $imag*$imag); }}\n?>\n", .{self.config.iterations});
}

pub fn generateMatrixAdditionScript(self: *MathBenchmark) !void {
    const path = try std.fmt.allocPrint(self.allocator, "{s}/matrix_addition.php", .{self.config.script_output_dir});
    defer self.allocator.free(path);
    const file = try std.fs.cwd.createFile(path, .{});
    defer file.close();
    try file.writer().print("<?php\n$m1=[[1,2],[3,4]]; $m2=[[5,6],[7,8]];\nfor ($i=0; $i<{d}; $i++) {{ $r=[[0,0],[0,0]]; for($j=0;$j<2;$j++) for($k=0;$k<2;$k++) $r[$j][$k]=$m1[$j][$k]+$m2[$j][$k]; }}\n?>\n", .{self.config.iterations});
}

pub fn generateMatrixSubtractionScript(self: *MathBenchmark) !void {
    const path = try std.fmt.allocPrint(self.allocator, "{s}/matrix_subtraction.php", .{self.config.script_output_dir});
    defer self.allocator.free(path);
    const file = try std.fs.cwd.createFile(path, .{});
    defer file.close();
    try file.writer().print("<?php\n$m1=[[10,20],[30,40]]; $m2=[[1,2],[3,4]];\nfor ($i=0; $i<{d}; $i++) {{ $r=[[0,0],[0,0]]; for($j=0;$j<2;$j++) for($k=0;$k<2;$k++) $r[$j][$k]=$m1[$j][$k]-$m2[$j][$k]; }}\n?>\n", .{self.config.iterations});
}

pub fn generateMatrixMultiplicationScript(self: *MathBenchmark) !void {
    const path = try std.fmt.allocPrint(self.allocator, "{s}/matrix_multiplication.php", .{self.config.script_output_dir});
    defer self.allocator.free(path);
    const file = try std.fs.cwd.createFile(path, .{});
    defer file.close();
    try file.writer().print("<?php\n$m1=[[1,2],[3,4]]; $m2=[[5,6],[7,8]];\nfor ($i=0; $i<{d}; $i++) {{ $r=[[0,0],[0,0]]; for($j=0;$j<2;$j++) for($k=0;$k<2;$k++) for($l=0;$l<2;$l++) $r[$j][$k]+=$m1[$j][$l]*$m2[$l][$k]; }}\n?>\n", .{self.config.iterations});
}

pub fn generateMatrixTransposeScript(self: *MathBenchmark) !void {
    const path = try std.fmt.allocPrint(self.allocator, "{s}/matrix_transpose.php", .{self.config.script_output_dir});
    defer self.allocator.free(path);
    const file = try std.fs.cwd.createFile(path, .{});
    defer file.close();
    try file.writer().print("<?php\n$m=[[1,2,3],[4,5,6],[7,8,9]];\nfor ($i=0; $i<{d}; $i++) {{ $r=[[0,0,0],[0,0,0],[0,0,0]]; for($j=0;$j<3;$j++) for($k=0;$k<3;$k++) $r[$k][$j]=$m[$j][$k]; }}\n?>\n", .{self.config.iterations});
}

pub fn generateMatrixDeterminantScript(self: *MathBenchmark) !void {
    const path = try std.fmt.allocPrint(self.allocator, "{s}/matrix_determinant.php", .{self.config.script_output_dir});
    defer self.allocator.free(path);
    const file = try std.fs.cwd.createFile(path, .{});
    defer file.close();
    try file.writer().print("<?php\n$m=[[1,2],[3,4]];\nfor ($i=0; $i<{d}; $i++) {{ $det = $m[0][0]*$m[1][1] - $m[0][1]*$m[1][0]; }}\n?>\n", .{self.config.iterations});
}
