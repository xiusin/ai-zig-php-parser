<?php
// Test 016: Math functions, random, and number formatting
class MathLab {
    public function process(): string {
        $out = "";

        // Basic math
        $out .= "abs(-42): " . abs(-42) . "\n";
        $out .= "abs(3.14): " . abs(3.14) . "\n";
        $out .= "round(3.5): " . round(3.5) . "\n";
        $out .= "round(3.4): " . round(3.4) . "\n";
        $out .= "floor(3.9): " . floor(3.9) . "\n";
        $out .= "ceil(3.1): " . ceil(3.1) . "\n";

        // Min/max
        $out .= "min(1,3,2): " . min(1, 3, 2) . "\n";
        $out .= "max(1,3,2): " . max(1, 3, 2) . "\n";
        $out .= "min([3,1,2]): " . min([3, 1, 2]) . "\n";
        $out .= "max([3,1,2]): " . max([3, 1, 2]) . "\n";

        // Power
        $out .= "pow(2, 10): " . pow(2, 10) . "\n";
        $out .= "2**10: " . (2**10) . "\n";
        $out .= "sqrt(16): " . sqrt(16) . "\n";

        // Logarithms
        $out .= "log(exp(1)): " . log(exp(1)) . "\n";
        $out .= "log10(100): " . log10(100) . "\n";
        $out .= "log2(8): " . log2(8) . "\n";

        // Trigonometry
        $out .= "sin(pi/2): " . sin(M_PI/2) . "\n";
        $out .= "cos(0): " . cos(0) . "\n";
        $out .= "tan(pi/4): " . tan(M_PI/4) . "\n";
        $out .= "asin(1): " . asin(1) . "\n";
        $out .= "acos(1): " . acos(1) . "\n";
        $out .= "atan(1): " . atan(1) . "\n";
        $out .= "hypot(3, 4): " . hypot(3, 4) . "\n";

        // Constants
        $out .= "M_PI: " . M_PI . "\n";
        $out .= "M_E: " . M_E . "\n";
        $out .= "M_SQRT2: " . M_SQRT2 . "\n";
        $out .= "M_LN2: " . M_LN2 . "\n";

        // Base conversion
        $out .= "base_convert('FF', 16, 10): " . base_convert('FF', 16, 10) . "\n";
        $out .= "base_convert('1010', 2, 16): " . base_convert('1010', 2, 16) . "\n";

        // Number formatting
        $out .= "number_format(1234567.89, 2): " . number_format(1234567.89, 2) . "\n";
        $out .= "number_format(1234567.89, 2, ',', '.'): " . number_format(1234567.89, 2, ',', '.') . "\n";

        // Bitwise
        $out .= "\nBitwise operations:\n";
        $out .= "5 & 3: " . (5 & 3) . "\n";
        $out .= "5 | 3: " . (5 | 3) . "\n";
        $out .= "5 ^ 3: " . (5 ^ 3) . "\n";
        $out .= "~5: " . (~5) . "\n";
        $out .= "5 << 1: " . (5 << 1) . "\n";
        $out .= "5 >> 1: " . (5 >> 1) . "\n";

        // Intdiv and fmod
        $out .= "\nintdiv(10, 3): " . intdiv(10, 3) . "\n";
        $out .= "fmod(10.5, 3.2): " . fmod(10.5, 3.2) . "\n";

        // Is finite, infinite, nan
        $out .= "\nis_finite(1.0): " . (is_finite(1.0) ? 'true' : 'false') . "\n";
        $out .= "is_infinite(INF): " . (is_infinite(INF) ? 'true' : 'false') . "\n";
        $out .= "is_nan(sqrt(-1)): " . (is_nan(sqrt(-1)) ? 'true' : 'false') . "\n";

        return $out;
    }

    public function random(): string {
        $out = "";

        // Rand
        $out .= "rand(1, 100): " . rand(1, 100) . "\n";
        $out .= "mt_rand(1, 100): " . mt_rand(1, 100) . "\n";

        // Random bytes
        $bytes = random_bytes(8);
        $out .= "random_bytes(8) hex: " . bin2hex($bytes) . "\n";

        // Random int
        $out .= "random_int(1, 100): " . random_int(1, 100) . "\n";

        // Seed
        mt_srand(12345);
        $out .= "mt_srand(12345), mt_rand(): " . mt_rand() . "\n";
        mt_srand(12345);
        $out .= "mt_srand(12345), mt_rand() again: " . mt_rand() . "\n";

        return $out;
    }
}

$lab = new MathLab();
echo $lab->process();
echo "\n";
echo $lab->random();