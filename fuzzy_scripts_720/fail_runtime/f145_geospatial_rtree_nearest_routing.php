<?php
// 极度混搭: 地理空间 + R树 + 最近邻 + 地理编码 + 路径规划
echo "=== f145: GeoSpatial + RTree + NearestNeighbor + Routing ===\n";

class GeoPoint {
    public function __construct(public float $lat, public float $lng, public string $name = '', public array $attributes = []) {}

    public function distanceTo(GeoPoint $other): float {
        // Haversine formula
        $R = 6371; // Earth radius km
        $dLat = deg2rad($other->lat - $this->lat);
        $dLng = deg2rad($other->lng - $this->lng);
        $a = sin($dLat / 2) ** 2 + cos(deg2rad($this->lat)) * cos(deg2rad($other->lat)) * sin($dLng / 2) ** 2;
        return $R * 2 * atan2(sqrt($a), sqrt(1 - $a));
    }

    public function __toString(): string { return "{$this->name}({$this->lat},{$this->lng})"; }
}

class BoundingBox {
    public function __construct(public float $minLat, public float $minLng, public float $maxLat, public float $maxLng) {}

    public function contains(GeoPoint $p): bool {
        return $p->lat >= $this->minLat && $p->lat <= $this->maxLat && $p->lng >= $this->minLng && $p->lng <= $this->maxLng;
    }

    public function intersects(BoundingBox $other): bool {
        return !($this->maxLat < $other->minLat || $this->minLat > $other->maxLat || $this->maxLng < $other->minLng || $this->minLng > $other->maxLng);
    }

    public function area(): float { return ($this->maxLat - $this->minLat) * ($this->maxLng - $this->minLng); }

    public function merge(BoundingBox $other): BoundingBox {
        return new BoundingBox(min($this->minLat, $other->minLat), min($this->minLng, $other->minLng), max($this->maxLat, $other->maxLat), max($this->maxLng, $other->maxLng));
    }

    public function expand(GeoPoint $p): BoundingBox {
        return new BoundingBox(min($this->minLat, $p->lat), min($this->minLng, $p->lng), max($this->maxLat, $p->lat), max($this->maxLng, $p->lng));
    }
}

class RTreeNode {
    public array $children = [];
    public ?BoundingBox $bbox = null;
    public ?GeoPoint $point = null;
    public bool $isLeaf = true;

    public function __construct(public int $maxChildren = 8) {}

    public function updateBBox(): void {
        if ($this->isLeaf && $this->point) {
            $this->bbox = new BoundingBox($this->point->lat, $this->point->lng, $this->point->lat, $this->point->lng);
        } elseif (!empty($this->children)) {
            $this->bbox = $this->children[0]->bbox;
            for ($i = 1; $i < count($this->children); $i++) $this->bbox = $this->bbox->merge($this->children[$i]->bbox);
        }
    }
}

class RTree {
    private RTreeNode $root;

    public function __construct(int $maxChildren = 8) { $this->root = new RTreeNode($maxChildren); }

    public function insert(GeoPoint $point): void {
        $leaf = new RTreeNode($this->root->maxChildren);
        $leaf->point = $point;
        $leaf->updateBBox();
        $this->insertNode($this->root, $leaf);
    }

    private function insertNode(RTreeNode $node, RTreeNode $entry): void {
        if ($node->isLeaf) {
            // 直接作为点插入
            if ($node->point === null) {
                $node->point = $entry->point;
                $node->updateBBox();
            } else {
                // 分裂
                $oldPoint = $node->point;
                $node->isLeaf = false;
                $node->point = null;
                $child1 = new RTreeNode($node->maxChildren); $child1->point = $oldPoint; $child1->updateBBox();
                $child2 = $entry;
                $node->children = [$child1, $child2];
                $node->updateBBox();
            }
            return;
        }
        // 选择最佳子节点
        $bestIdx = 0; $bestEnlargement = INF;
        foreach ($node->children as $i => $child) {
            $enlargement = $child->bbox->expand($entry->point)->area() - $child->bbox->area();
            if ($enlargement < $bestEnlargement) { $bestEnlargement = $enlargement; $bestIdx = $i; }
        }
        $this->insertNode($node->children[$bestIdx], $entry);
        $node->children[$bestIdx]->updateBBox();
        $node->updateBBox();
        if (count($node->children) > $node->maxChildren) $this->splitNode($node);
    }

    private function splitNode(RTreeNode $node): void {
        // 简化: 均分
        $mid = (int)(count($node->children) / 2);
        $left = array_slice($node->children, 0, $mid);
        $right = array_slice($node->children, $mid);
        $node->children = $left;
        $node->updateBBox();
        $newNode = new RTreeNode($node->maxChildren);
        $newNode->isLeaf = false;
        $newNode->children = $right;
        $newNode->updateBBox();
        $node->children[] = $newNode;
    }

    public function search(BoundingBox $bbox): array {
        return $this->searchNode($this->root, $bbox);
    }

    private function searchNode(RTreeNode $node, BoundingBox $bbox): array {
        $results = [];
        if ($node->isLeaf) {
            if ($node->point && $bbox->contains($node->point)) $results[] = $node->point;
            return $results;
        }
        foreach ($node->children as $child) {
            if ($child->bbox && $bbox->intersects($child->bbox)) $results = array_merge($results, $this->searchNode($child, $bbox));
        }
        return $results;
    }

    public function nearestNeighbors(GeoPoint $point, int $k): array {
        $all = $this->getAllPoints($this->root);
        usort($all, fn($a, $b) => $point->distanceTo($a) <=> $point->distanceTo($b));
        return array_slice($all, 0, $k);
    }

    private function getAllPoints(RTreeNode $node): array {
        if ($node->isLeaf) return $node->point ? [$node->point] : [];
        $points = [];
        foreach ($node->children as $child) {
            if ($child->isLeaf && $child->point) $points[] = $child->point;
            else $points = array_merge($points, $this->getAllPoints($child));
        }
        return $points;
    }
}

class GeoCoder {
    private array $locations = [];

    public function register(string $name, GeoPoint $point): void { $this->locations[strtolower($name)] = $point; }

    public function geocode(string $address): ?GeoPoint { return $this->locations[strtolower($address)] ?? null; }
    public function reverseGeocode(float $lat, float $lng): ?string {
        $point = new GeoPoint($lat, $lng);
        $best = null; $bestDist = INF;
        foreach ($this->locations as $name => $loc) {
            $dist = $point->distanceTo($loc);
            if ($dist < $bestDist) { $bestDist = $dist; $best = $name; }
        }
        return $best;
    }
}

class RoutePlanner {
    private array $graph = [];
    private array $points = [];

    public function addPoint(GeoPoint $p): void { $this->points[$p->name] = $p; }
    public function addRoad(string $from, string $to, float $distance = 0): void {
        if ($distance === 0 && isset($this->points[$from]) && isset($this->points[$to])) {
            $distance = $this->points[$from]->distanceTo($this->points[$to]);
        }
        $this->graph[$from][$to] = $distance;
        $this->graph[$to][$from] = $distance;
    }

    public function shortestPath(string $start, string $end): array {
        $dist = []; $prev = []; $visited = [];
        foreach (array_keys($this->graph) as $node) { $dist[$node] = INF; $prev[$node] = null; }
        $dist[$start] = 0;
        while (true) {
            $minDist = INF; $minNode = null;
            foreach ($dist as $node => $d) {
                if (!isset($visited[$node]) && $d < $minDist) { $minDist = $d; $minNode = $node; }
            }
            if ($minNode === null || $minNode === $end) break;
            $visited[$minNode] = true;
            foreach ($this->graph[$minNode] ?? [] as $neighbor => $weight) {
                if (isset($visited[$neighbor])) continue;
                $newDist = $dist[$minNode] + $weight;
                if ($newDist < $dist[$neighbor]) { $dist[$neighbor] = $newDist; $prev[$neighbor] = $minNode; }
            }
        }
        $path = [];
        $current = $end;
        while ($current !== null) { array_unshift($path, $current); $current = $prev[$current]; }
        return ['path' => $path, 'distance' => $dist[$end]];
    }
}

// 测试
echo "--- GeoPoints ---\n";
$cities = [
    new GeoPoint(40.7128, -74.0060, 'New York'),
    new GeoPoint(34.0522, -118.2437, 'Los Angeles'),
    new GeoPoint(41.8781, -87.6298, 'Chicago'),
    new GeoPoint(29.7604, -95.3698, 'Houston'),
    new GeoPoint(39.9526, -75.1652, 'Philadelphia'),
    new GeoPoint(37.7749, -122.4194, 'San Francisco'),
    new GeoPoint(47.6062, -122.3321, 'Seattle'),
    new GeoPoint(25.7617, -80.1918, 'Miami'),
    new GeoPoint(42.3601, -71.0589, 'Boston'),
    new GeoPoint(33.4484, -112.0740, 'Phoenix'),
];
foreach ($cities as $city) echo "  $city\n";

echo "\n--- Distance Calculation ---\n";
echo "NY → LA: " . number_format($cities[0]->distanceTo($cities[1]), 0) . " km\n";
echo "NY → Chicago: " . number_format($cities[0]->distanceTo($cities[2]), 0) . " km\n";
echo "SF → Seattle: " . number_format($cities[5]->distanceTo($cities[6]), 0) . " km\n";
echo "Miami → Boston: " . number_format($cities[7]->distanceTo($cities[8]), 0) . " km\n";

echo "\n--- R-Tree Spatial Index ---\n";
$rtree = new RTree();
foreach ($cities as $city) $rtree->insert($city);

echo "Search NYC area:\n";
$nycBox = new BoundingBox(40, -75, 42, -73);
$nearby = $rtree->search($nycBox);
foreach ($nearby as $p) echo "  Found: $p\n";

echo "\nSearch West Coast:\n";
$westBox = new BoundingBox(32, -125, 49, -115);
$westCoast = $rtree->search($westBox);
foreach ($westCoast as $p) echo "  Found: $p\n";

echo "\n--- Nearest Neighbors ---\n";
$target = new GeoPoint(36.0, -100.0, 'Center');
$nn = $rtree->nearestNeighbors($target, 3);
echo "3 nearest to $target:\n";
foreach ($nn as $p) echo "  $p (distance: " . number_format($target->distanceTo($p), 0) . " km)\n";

echo "\n--- Geocoding ---\n";
$geocoder = new GeoCoder();
foreach ($cities as $city) $geocoder->register($city->name, $city);
$geocoded = $geocoder->geocode('New York');
echo "Geocode 'New York': $geocoded\n";
$geocoded2 = $geocoder->geocode('Chicago');
echo "Geocode 'Chicago': $geocoded2\n";
$reverse = $geocoder->reverseGeocode(40.7, -74.0);
echo "Reverse geocode (40.7, -74.0): $reverse\n";

echo "\n--- Route Planning ---\n";
$planner = new RoutePlanner();
foreach ($cities as $city) $planner->addPoint($city);
// Add some roads
$roads = [
    ['New York', 'Philadelphia'], ['New York', 'Boston'], ['Philadelphia', 'Boston'],
    ['New York', 'Chicago'], ['Chicago', 'Houston'], ['Houston', 'Miami'],
    ['Los Angeles', 'San Francisco'], ['San Francisco', 'Seattle'], ['Los Angeles', 'Phoenix'],
    ['Phoenix', 'Houston'], ['Chicago', 'Los Angeles'],
];
foreach ($roads as [$a, $b]) $planner->addRoad($a, $b);

$routes = [
    ['New York', 'Los Angeles'],
    ['New York', 'Miami'],
    ['Seattle', 'Miami'],
    ['San Francisco', 'Boston'],
    ['Chicago', 'Phoenix'],
];
foreach ([$routes[0], $routes[1], $routes[2]] as [$from, $to]) {
    $result = $planner->shortestPath($from, $to);
    echo "  $from → $to: " . implode(' → ', $result['path']) . " (" . number_format($result['distance'], 0) . " km)\n";
}

echo "\n--- Multiple Nearest Neighbors ---\n";
$queryPoints = [
    new GeoPoint(38, -97, 'Center US'),
    new GeoPoint(42, -72, 'Northeast'),
    new GeoPoint(35, -120, 'West'),
];
foreach ($queryPoints as $qp) {
    $nn = $rtree->nearestNeighbors($qp, 5);
    echo "  Near $qp:\n";
    foreach ($nn as $p) echo "    $p (" . number_format($qp->distanceTo($p), 0) . " km)\n";
}

echo "=== f145 Done ===\n";
