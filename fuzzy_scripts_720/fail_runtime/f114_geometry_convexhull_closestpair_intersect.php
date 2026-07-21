<?php
// 极度混搭: 计算几何 + 凸包 + 最近点对 + 线段相交
echo "=== f114: Computational Geometry + ConvexHull + ClosestPair ===\n";

class Point {
    public function __construct(public float $x, public float $y) {}
    public function distTo(Point $p): float { return sqrt(($this->x - $p->x) ** 2 + ($this->y - $p->y) ** 2); }
    public function __toString(): string { return "({$this->x},{$this->y})"; }
}

class Geometry {
    public static function cross(Point $o, Point $a, Point $b): float {
        return ($a->x - $o->x) * ($b->y - $o->y) - ($a->y - $o->y) * ($b->x - $o->x);
    }

    public static function convexHull(array $points): array {
        if (count($points) < 3) return $points;
        usort($points, fn($a, $b) => $a->x === $b->x ? $a->y <=> $b->y : $a->x <=> $b->x);
        $n = count($points);

        // 下凸包
        $lower = [];
        for ($i = 0; $i < $n; $i++) {
            while (count($lower) >= 2 && self::cross($lower[count($lower) - 2], $lower[count($lower) - 1], $points[$i]) <= 0) {
                array_pop($lower);
            }
            $lower[] = $points[$i];
        }

        // 上凸包
        $upper = [];
        for ($i = $n - 1; $i >= 0; $i--) {
            while (count($upper) >= 2 && self::cross($upper[count($upper) - 2], $upper[count($upper) - 1], $points[$i]) <= 0) {
                array_pop($upper);
            }
            $upper[] = $points[$i];
        }

        array_pop($lower);
        array_pop($upper);
        return array_merge($lower, $upper);
    }

    public static function closestPair(array $points): array {
        usort($points, fn($a, $b) => $a->x <=> $b->x);
        return self::closestPairRec($points, 0, count($points) - 1);
    }

    private static function closestPairRec(array $points, int $left, int $right): array {
        if ($right - $left < 3) {
            $minDist = INF; $pair = null;
            for ($i = $left; $i <= $right; $i++) {
                for ($j = $i + 1; $j <= $right; $j++) {
                    $d = $points[$i]->distTo($points[$j]);
                    if ($d < $minDist) { $minDist = $d; $pair = [$points[$i], $points[$j]]; }
                }
            }
            return ['dist' => $minDist, 'pair' => $pair];
        }

        $mid = (int)(($left + $right) / 2);
        $midX = $points[$mid]->x;
        $leftResult = self::closestPairRec($points, $left, $mid);
        $rightResult = self::closestPairRec($points, $mid + 1, $right);
        $minDist = min($leftResult['dist'], $rightResult['dist']);
        $pair = $leftResult['dist'] <= $rightResult['dist'] ? $leftResult['pair'] : $rightResult['pair'];

        // 跨分界线的点
        $strip = [];
        for ($i = $left; $i <= $right; $i++) {
            if (abs($points[$i]->x - $midX) < $minDist) $strip[] = $points[$i];
        }
        usort($strip, fn($a, $b) => $a->y <=> $b->y);

        for ($i = 0; $i < count($strip); $i++) {
            for ($j = $i + 1; $j < count($strip) && ($strip[$j]->y - $strip[$i]->y) < $minDist; $j++) {
                $d = $strip[$i]->distTo($strip[$j]);
                if ($d < $minDist) { $minDist = $d; $pair = [$strip[$i], $strip[$j]]; }
            }
        }

        return ['dist' => $minDist, 'pair' => $pair];
    }

    public static function segmentsIntersect(Point $p1, Point $p2, Point $p3, Point $p4): bool {
        $d1 = self::cross($p3, $p4, $p1);
        $d2 = self::cross($p3, $p4, $p2);
        $d3 = self::cross($p1, $p2, $p3);
        $d4 = self::cross($p1, $p2, $p4);
        if ((($d1 > 0 && $d2 < 0) || ($d1 < 0 && $d2 > 0)) &&
            (($d3 > 0 && $d4 < 0) || ($d3 < 0 && $d4 > 0))) return true;
        return false;
    }

    public static function pointInPolygon(Point $p, array $polygon): bool {
        $n = count($polygon);
        $inside = false;
        for ($i = 0, $j = $n - 1; $i < $n; $j = $i++) {
            if (($polygon[$i]->y > $p->y) !== ($polygon[$j]->y > $p->y) &&
                $p->x < ($polygon[$j]->x - $polygon[$i]->x) * ($p->y - $polygon[$i]->y) / ($polygon[$j]->y - $polygon[$i]->y) + $polygon[$i]->x) {
                $inside = !$inside;
            }
        }
        return $inside;
    }

    public static function polygonArea(array $polygon): float {
        $area = 0; $n = count($polygon);
        for ($i = 0; $i < $n; $i++) {
            $j = ($i + 1) % $n;
            $area += $polygon[$i]->x * $polygon[$j]->y - $polygon[$j]->x * $polygon[$i]->y;
        }
        return abs($area) / 2;
    }

    public static function lineIntersection(Point $p1, Point $p2, Point $p3, Point $p4): ?Point {
        $denom = ($p1->x - $p2->x) * ($p3->y - $p4->y) - ($p1->y - $p2->y) * ($p3->x - $p4->x);
        if (abs($denom) < 1e-10) return null;
        $t = (($p1->x - $p3->x) * ($p3->y - $p4->y) - ($p1->y - $p3->y) * ($p3->x - $p4->x)) / $denom;
        return new Point($p1->x + $t * ($p2->x - $p1->x), $p1->y + $t * ($p2->y - $p1->y));
    }
}

// 测试
echo "--- Convex Hull (Graham Scan) ---\n";
$points = [
    new Point(0, 0), new Point(2, 0), new Point(1, 1), new Point(2, 2), new Point(0, 2),
    new Point(0.5, 0.5), new Point(1.5, 1.5), new Point(3, 1), new Point(1, 3), new Point(1, -1),
];
echo "Points: " . implode(', ', $points) . "\n";
$hull = Geometry::convexHull($points);
echo "Convex hull: " . implode(' → ', $hull) . "\n";
echo "Hull area: " . Geometry::polygonArea($hull) . "\n";

echo "\n--- Closest Pair ---\n";
mt_srand(42);
$randPoints = [];
for ($i = 0; $i < 20; $i++) $randPoints[] = new Point(mt_rand(0, 100) / 10, mt_rand(0, 100) / 10);
$result = Geometry::closestPair($randPoints);
echo "Closest pair: " . $result['pair'][0] . " and " . $result['pair'][1] . " dist=" . number_format($result['dist'], 4) . "\n";

// 暴力验证
$bruteMin = INF;
$brutePair = null;
for ($i = 0; $i < count($randPoints); $i++) {
    for ($j = $i + 1; $j < count($randPoints); $j++) {
        $d = $randPoints[$i]->distTo($randPoints[$j]);
        if ($d < $bruteMin) { $bruteMin = $d; $brutePair = [$randPoints[$i], $randPoints[$j]]; }
    }
}
echo "Brute force: " . $brutePair[0] . " and " . $brutePair[1] . " dist=" . number_format($bruteMin, 4) . "\n";
echo "Match: " . var_export(abs($result['dist'] - $bruteMin) < 1e-6, true) . "\n";

echo "\n--- Segment Intersection ---\n";
$segTests = [
    [new Point(0, 0), new Point(2, 2), new Point(0, 2), new Point(2, 0), true],
    [new Point(0, 0), new Point(1, 1), new Point(2, 2), new Point(3, 3), false],
    [new Point(0, 0), new Point(3, 0), new Point(1, 1), new Point(2, -1), true],
    [new Point(0, 0), new Point(0, 1), new Point(1, 0), new Point(1, 1), false],
];
foreach ($segTests as [$p1, $p2, $p3, $p4, $expected]) {
    $result = Geometry::segmentsIntersect($p1, $p2, $p3, $p4);
    echo "  [$p1-$p2] vs [$p3-$p4]: " . var_export($result, true) . " (expected " . var_export($expected, true) . ") " . ($result === $expected ? '✓' : '✗') . "\n";
}

echo "\n--- Line Intersection ---\n";
$int = Geometry::lineIntersection(new Point(0, 0), new Point(2, 2), new Point(0, 2), new Point(2, 0));
echo "Intersection of y=x and y=2-x: " . $int . "\n";

echo "\n--- Point in Polygon ---\n";
$square = [new Point(0, 0), new Point(4, 0), new Point(4, 4), new Point(0, 4)];
$testPoints = [new Point(2, 2), new Point(0, 0), new Point(5, 5), new Point(2, 4.01)];
foreach ($testPoints as $p) {
    echo "  $p in square: " . var_export(Geometry::pointInPolygon($p, $square), true) . "\n";
}

$triangle = [new Point(0, 0), new Point(4, 0), new Point(2, 4)];
echo "\n  Triangle " . implode('→', $triangle) . " area=" . Geometry::polygonArea($triangle) . "\n";
foreach ([new Point(2, 1), new Point(2, 3.5), new Point(3, 0.1)] as $p) {
    echo "  $p in triangle: " . var_export(Geometry::pointInPolygon($p, $triangle), true) . "\n";
}

echo "\n--- Polygon Area ---\n";
$pentagon = [
    new Point(0, 0), new Point(2, 0), new Point(3, 2), new Point(1, 4), new Point(-1, 2),
];
echo "Pentagon area: " . Geometry::polygonArea($pentagon) . "\n";

echo "=== f114 Done ===\n";
