<?php
// 极度混搭: Geo空间 + R树简化 + KNN + 范围搜索 + 地理编码
echo "=== f085: Geo Spatial + RTree + KNN + Range ===\n";

class Point {
    public function __construct(public float $x, public float $y, public string $label = '') {}
    public function distanceTo(Point $other): float { return sqrt(($this->x - $other->x)**2 + ($this->y - $other->y)**2); }
    public function __toString(): string { return "({$this->x},{$this->y})"; }
}

class BoundingBox {
    public function __construct(public float $minX, public float $minY, public float $maxX, public float $maxY) {}

    public function contains(Point $p): bool {
        return $p->x >= $this->minX && $p->x <= $this->maxX && $p->y >= $this->minY && $p->y <= $this->maxY;
    }

    public function intersects(self $other): bool {
        return !($this->maxX < $other->minX || $this->minX > $other->maxX ||
                 $this->maxY < $other->minY || $this->minY > $other->maxY);
    }

    public function area(): float { return ($this->maxX - $this->minX) * ($this->maxY - $this->minY); }

    public static function fromPoints(array $points): self {
        $xs = array_map(fn($p) => $p->x, $points);
        $ys = array_map(fn($p) => $p->y, $points);
        return new self(min($xs), min($ys), max($xs), max($ys));
    }
}

class RTreeNode {
    public ?BoundingBox $mbr = null;
    public array $children = [];
    public ?Point $point = null;
    public bool $isLeaf;

    public function __construct(bool $isLeaf = false) { $this->isLeaf = $isLeaf; }
}

class RTree {
    private RTreeNode $root;
    private int $count = 0;

    public function __construct(private int $maxEntries = 4) {
        $this->root = new RTreeNode(true);
    }

    public function insert(Point $point): void {
        $leaf = new RTreeNode(true);
        $leaf->point = $point;
        $leaf->mbr = new BoundingBox($point->x, $point->y, $point->x, $point->y);
        $this->insertNode($this->root, $leaf);
        $this->count++;
    }

    private function insertNode(RTreeNode $node, RTreeNode $newNode): void {
        if ($node->isLeaf) {
            $node->children[] = $newNode;
            $node->mbr = $node->mbr ? $this->mergeMBR($node->mbr, $newNode->mbr) : $newNode->mbr;
            if (count($node->children) > $this->maxEntries) {
                $this->splitNode($node);
            }
        } else {
            // 选择扩展最小的子节点
            $bestChild = null; $bestExpansion = PHP_FLOAT_MAX;
            foreach ($node->children as $child) {
                $merged = $this->mergeMBR($child->mbr, $newNode->mbr);
                $expansion = $merged->area() - $child->mbr->area();
                if ($expansion < $bestExpansion) { $bestExpansion = $expansion; $bestChild = $child; }
            }
            $this->insertNode($bestChild, $newNode);
            $node->mbr = $this->mergeMBR($node->mbr, $newNode->mbr);
        }
    }

    private function splitNode(RTreeNode $node): void {
        // 简化：只处理叶子节点分裂
        $children = $node->children;
        $mid = (int)(count($children) / 2);
        $node->children = array_slice($children, 0, $mid);
        $node->mbr = BoundingBox::fromPoints(array_map(fn($c) => $c->point, $node->children));

        $newNode = new RTreeNode(true);
        $newNode->children = array_slice($children, $mid);
        $newNode->mbr = BoundingBox::fromPoints(array_map(fn($c) => $c->point, $newNode->children));
        // 简化：不向上传播
    }

    private function mergeMBR(BoundingBox $a, BoundingBox $b): BoundingBox {
        return new BoundingBox(min($a->minX, $b->minX), min($a->minY, $b->minY), max($a->maxX, $b->maxX), max($a->maxY, $b->maxY));
    }

    public function rangeSearch(BoundingBox $bbox): array {
        $results = [];
        $this->rangeSearchNode($this->root, $bbox, $results);
        return $results;
    }

    private function rangeSearchNode(RTreeNode $node, BoundingBox $bbox, array &$results): void {
        if ($node->mbr === null || !$node->mbr->intersects($bbox)) return;
        if ($node->point !== null && $bbox->contains($node->point)) {
            $results[] = $node->point;
        }
        foreach ($node->children as $child) {
            $this->rangeSearchNode($child, $bbox, $results);
        }
    }

    public function knnSearch(Point $query, int $k): array {
        $all = [];
        $this->collectPoints($this->root, $all);
        usort($all, fn($a, $b) => $a->distanceTo($query) <=> $b->distanceTo($query));
        return array_slice($all, 0, $k);
    }

    private function collectPoints(RTreeNode $node, array &$points): void {
        if ($node->point !== null) { $points[] = $node->point; return; }
        foreach ($node->children as $child) $this->collectPoints($child, $points);
    }

    public function count(): int { return $this->count; }
}

class GeoCoder {
    private array $locations = [];

    public function addLocation(string $name, float $lat, float $lng): void {
        $this->locations[$name] = ['lat' => $lat, 'lng' => $lng];
    }

    public function geocode(string $name): ?array { return $this->locations[$name] ?? null; }

    public function haversineDistance(float $lat1, float $lng1, float $lat2, float $lng2): float {
        $R = 6371; // km
        $dLat = deg2rad($lat2 - $lat1);
        $dLng = deg2rad($lng2 - $lng1);
        $a = sin($dLat/2)**2 + cos(deg2rad($lat1)) * cos(deg2rad($lat2)) * sin($dLng/2)**2;
        $c = 2 * atan2(sqrt($a), sqrt(1-$a));
        return $R * $c;
    }

    public function findNearby(string $name, float $radiusKm): array {
        $origin = $this->geocode($name);
        if ($origin === null) return [];
        $nearby = [];
        foreach ($this->locations as $locName => $loc) {
            if ($locName === $name) continue;
            $dist = $this->haversineDistance($origin['lat'], $origin['lng'], $loc['lat'], $loc['lng']);
            if ($dist <= $radiusKm) $nearby[$locName] = round($dist, 2);
        }
        asort($nearby);
        return $nearby;
    }
}

// 测试
echo "--- R-Tree Insert & Range Search ---\n";
$rtree = new RTree(4);
$points = [
    new Point(1, 1, 'A'), new Point(2, 5, 'B'), new Point(5, 2, 'C'),
    new Point(8, 8, 'D'), new Point(3, 3, 'E'), new Point(7, 4, 'F'),
    new Point(6, 7, 'G'), new Point(9, 1, 'H'), new Point(4, 6, 'I'),
    new Point(2, 8, 'J'),
];
foreach ($points as $p) $rtree->insert($p);
echo "Inserted " . $rtree->count() . " points\n";

$bbox = new BoundingBox(1, 1, 5, 5);
$inRange = $rtree->rangeSearch($bbox);
echo "\nRange search (1,1)-(5,5):\n";
foreach ($inRange as $p) echo "  {$p->label} at $p\n";

echo "\n--- KNN Search ---\n";
$query = new Point(5, 5);
$knn = $rtree->knnSearch($query, 3);
echo "3 nearest to $query:\n";
foreach ($knn as $p) {
    echo "  {$p->label} at $p (dist=" . number_format($p->distanceTo($query), 2) . ")\n";
}

echo "\n--- GeoCoder ---\n";
$geo = new GeoCoder();
$geo->addLocation('Beijing', 39.9042, 116.4074);
$geo->addLocation('Shanghai', 31.2304, 121.4737);
$geo->addLocation('Guangzhou', 23.1291, 113.2644);
$geo->addLocation('Shenzhen', 22.5431, 114.0579);
$geo->addLocation('Hangzhou', 30.2741, 120.1551);

echo "Beijing coords: " . json_encode($geo->geocode('Beijing')) . "\n";
echo "\nNearby Beijing (1000km):\n";
$nearby = $geo->findNearby('Beijing', 1000);
foreach ($nearby as $city => $dist) echo "  $city: {$dist}km\n";

echo "\nNearby Shanghai (200km):\n";
$nearby = $geo->findNearby('Shanghai', 200);
foreach ($nearby as $city => $dist) echo "  $city: {$dist}km\n";

echo "\n--- Distances ---\n";
$cities = ['Beijing', 'Shanghai', 'Guangzhou', 'Shenzhen'];
for ($i = 0; $i < count($cities); $i++) {
    for ($j = $i + 1; $j < count($cities); $j++) {
        $c1 = $geo->geocode($cities[$i]);
        $c2 = $geo->geocode($cities[$j]);
        $dist = $geo->haversineDistance($c1['lat'], $c1['lng'], $c2['lat'], $c2['lng']);
        echo "  {$cities[$i]} → {$cities[$j]}: " . number_format($dist, 0) . "km\n";
    }
}

echo "=== f085 Done ===\n";
