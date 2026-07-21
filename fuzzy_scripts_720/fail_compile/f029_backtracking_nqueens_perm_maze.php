<?php
// 极度混搭: 回溯算法 + N皇后 + 全排列 + 子集 + 组合 + 迷宫
echo "=== f029: Backtracking + NQueens + Permutations + Maze ===\n";

class Backtracking {
    public static function nQueens(int $n): array {
        $solutions = [];
        $board = array_fill(0, $n, -1);
        self::solveNQueens($board, 0, $n, $solutions);
        return $solutions;
    }

    private static function solveNQueens(array &$board, int $row, int $n, array &$solutions): void {
        if ($row === $n) {
            $solutions[] = $board;
            return;
        }
        for ($col = 0; $col < $n; $col++) {
            if (self::isSafe($board, $row, $col)) {
                $board[$row] = $col;
                self::solveNQueens($board, $row + 1, $n, $solutions);
                $board[$row] = -1;
            }
        }
    }

    private static function isSafe(array $board, int $row, int $col): bool {
        for ($i = 0; $i < $row; $i++) {
            if ($board[$i] === $col) return false;
            if (abs($board[$i] - $col) === abs($i - $row)) return false;
        }
        return true;
    }

    public static function permutations(array $arr): array {
        $result = [];
        self::permute($arr, 0, $result);
        return $result;
    }

    private static function permute(array &$arr, int $start, array &$result): void {
        if ($start === count($arr)) {
            $result[] = $arr;
            return;
        }
        for ($i = $start; $i < count($arr); $i++) {
            self::swap($arr, $start, $i);
            self::permute($arr, $start + 1, $result);
            self::swap($arr, $start, $i);
        }
    }

    private static function swap(array &$arr, int $i, int $j): void {
        $tmp = $arr[$i]; $arr[$i] = $arr[$j]; $arr[$j] = $tmp;
    }

    public static function subsets(array $arr): array {
        $result = [];
        $current = [];
        self::generateSubsets($arr, 0, $current, $result);
        return $result;
    }

    private static function generateSubsets(array $arr, int $index, array &$current, array &$result): void {
        $result[] = $current;
        for ($i = $index; $i < count($arr); $i++) {
            $current[] = $arr[$i];
            self::generateSubsets($arr, $i + 1, $current, $result);
            array_pop($current);
        }
    }

    public static function combinations(int $n, int $k): array {
        $result = [];
        $current = [];
        self::generateCombinations(1, $n, $k, $current, $result);
        return $result;
    }

    private static function generateCombinations(int $start, int $n, int $k, array &$current, array &$result): void {
        if (count($current) === $k) {
            $result[] = $current;
            return;
        }
        for ($i = $start; $i <= $n; $i++) {
            $current[] = $i;
            self::generateCombinations($i + 1, $n, $k, $current, $result);
            array_pop($current);
        }
    }

    public static function solveMaze(array $maze): ?array {
        $n = count($maze);
        $solution = array_fill(0, $n, array_fill(0, $n, 0));
        if (self::mazeDFS($maze, 0, 0, $n, $solution)) {
            return $solution;
        }
        return null;
    }

    private static function mazeDFS(array $maze, int $x, int $y, int $n, array &$sol): bool {
        if ($x === $n - 1 && $y === $n - 1 && $maze[$x][$y] === 1) {
            $sol[$x][$y] = 1;
            return true;
        }
        if ($x >= 0 && $x < $n && $y >= 0 && $y < $n && $maze[$x][$y] === 1 && $sol[$x][$y] === 0) {
            $sol[$x][$y] = 1;
            if (self::mazeDFS($maze, $x + 1, $y, $n, $sol)) return true;
            if (self::mazeDFS($maze, $x, $y + 1, $n, $sol)) return true;
            if (self::mazeDFS($maze, $x - 1, $y, $n, $sol)) return true;
            if (self::mazeDFS($maze, $x, $y - 1, $n, $sol)) return true;
            $sol[$x][$y] = 0;
        }
        return false;
    }

    public static function solveSudoku(array &$board): bool {
        for ($row = 0; $row < 9; $row++) {
            for ($col = 0; $col < 9; $col++) {
                if ($board[$row][$col] === 0) {
                    for ($num = 1; $num <= 9; $num++) {
                        if (self::isValidSudoku($board, $row, $col, $num)) {
                            $board[$row][$col] = $num;
                            if (self::solveSudoku($board)) return true;
                            $board[$row][$col] = 0;
                        }
                    }
                    return false;
                }
            }
        }
        return true;
    }

    private static function isValidSudoku(array &$board, int $row, int $col, int $num): bool {
        for ($i = 0; $i < 9; $i++) {
            if ($board[$row][$i] === $num) return false;
            if ($board[$i][$col] === $num) return false;
        }
        $boxRow = (int)($row / 3) * 3;
        $boxCol = (int)($col / 3) * 3;
        for ($i = 0; $i < 3; $i++) {
            for ($j = 0; $j < 3; $j++) {
                if ($board[$boxRow + $i][$boxCol + $j] === $num) return false;
            }
        }
        return true;
    }
}

// === 测试 ===
echo "--- N-Queens ---\n";
for ($n = 4; $n <= 6; $n++) {
    $solutions = Backtracking::nQueens($n);
    echo "N=$n: " . count($solutions) . " solutions\n";
    if ($n === 4) {
        foreach ($solutions as $i => $sol) {
            echo "  Solution " . ($i + 1) . ": " . implode(',', $sol) . "\n";
        }
    }
}

echo "\n--- Permutations ---\n";
$perms = Backtracking::permutations([1, 2, 3]);
echo "Permutations of [1,2,3] (" . count($perms) . "):\n";
foreach ($perms as $p) {
    echo "  [" . implode(',', $p) . "]\n";
}

echo "\n--- Subsets ---\n";
$subs = Backtracking::subsets([1, 2, 3]);
echo "Subsets of [1,2,3] (" . count($subs) . "):\n";
foreach ($subs as $s) {
    echo "  [" . implode(',', $s) . "]\n";
}

echo "\n--- Combinations ---\n";
$combs = Backtracking::combinations(5, 3);
echo "C(5,3) = " . count($combs) . " combinations:\n";
foreach (array_slice($combs, 0, 5) as $c) {
    echo "  [" . implode(',', $c) . "]\n";
}
echo "  ... (" . (count($combs) - 5) . " more)\n";

echo "\n--- Maze ---\n";
$maze = [
    [1, 0, 0, 0, 0],
    [1, 1, 0, 1, 0],
    [0, 1, 1, 1, 0],
    [0, 0, 0, 1, 0],
    [0, 0, 0, 1, 1],
];
echo "Maze:\n";
foreach ($maze as $row) echo "  " . implode(' ', $row) . "\n";
$solution = Backtracking::solveMaze($maze);
if ($solution !== null) {
    echo "Solution path:\n";
    foreach ($solution as $row) echo "  " . implode(' ', $row) . "\n";
} else {
    echo "No solution\n";
}

echo "\n--- Sudoku ---\n";
$sudoku = [
    [5, 3, 0, 0, 7, 0, 0, 0, 0],
    [6, 0, 0, 1, 9, 5, 0, 0, 0],
    [0, 9, 8, 0, 0, 0, 0, 6, 0],
    [8, 0, 0, 0, 6, 0, 0, 0, 3],
    [4, 0, 0, 8, 0, 3, 0, 0, 1],
    [7, 0, 0, 0, 2, 0, 0, 0, 6],
    [0, 6, 0, 0, 0, 0, 2, 8, 0],
    [0, 0, 0, 4, 1, 9, 0, 0, 5],
    [0, 0, 0, 0, 8, 0, 0, 7, 9],
];
echo "Puzzle:\n";
foreach ($sudoku as $row) echo "  " . implode(' ', $row) . "\n";
Backtracking::solveSudoku($sudoku);
echo "Solved:\n";
foreach ($sudoku as $row) echo "  " . implode(' ', $row) . "\n";

echo "=== f029 Done ===\n";
