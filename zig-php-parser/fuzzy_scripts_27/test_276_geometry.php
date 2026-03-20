<?php
function distance2D(array $p1, array $p2): float {
    $dx = $p2[0] - $p1[0];
    $dy = $p2[1] - $p1[1];
    return sqrt($dx * $dx + $dy * $dy);
}

function distance3D(array $p1, array $p2): float {
    $dx = $p2[0] - $p1[0];
    $dy = $p2[1] - $p1[1];
    $dz = $p2[2] - $p1[2];
    return sqrt($dx * $dx + $dy * $dy + $dz * $dz);
}

function midpoint(array $p1, array $p2): array {
    return [($p1[0] + $p2[0]) / 2, ($p1[1] + $p2[1]) / 2];
}

function slope(array $p1, array $p2): float {
    if ($p2[0] - $p1[0] === 0) return INF;
    return ($p2[1] - $p1[1]) / ($p2[0] - $p1[0]);
}

function manhattanDistance(array $p1, array $p2): int|float {
    return abs($p2[0] - $p1[0]) + abs($p2[1] - $p1[1]);
}

echo sprintf("%.2f\n", distance2D([0, 0], [3, 4]));
echo sprintf("%.2f\n", distance3D([0, 0, 0], [1, 2, 2]));
echo implode(',', midpoint([0, 0], [4, 4])) . "\n";
echo sprintf("%.2f\n", slope([1, 1], [3, 3]));
echo manhattanDistance([0, 0], [3, 4]) . "\n";
echo "OK\n";
