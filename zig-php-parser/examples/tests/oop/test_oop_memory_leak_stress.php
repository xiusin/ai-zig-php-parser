<?php
/**
 * OOP Memory Leak Detection Test - Stress Test
 * Creates extreme scenarios to detect memory leaks
 */

echo "=== OOP Memory Leak Detection Stress Test ===\n\n";

// Track memory usage
$baselineMemory = memory_get_usage(true);
echo "Baseline memory: " . number_format($baselineMemory) . " bytes\n\n";

// ============================================================================
// Test 1: Rapid Object Creation/Destruction
// ============================================================================
echo "--- Test 1: Rapid Object Creation/Destruction ---\n";

class RapidCreate {
    public $id;
    public $data = [];
    
    public function __construct($id) {
        $this->id = $id;
        for ($i = 0; $i < 100; $i++) {
            $this->data[] = str_repeat("x", 100);
        }
    }
}

$beforeTest1 = memory_get_usage(true);
for ($i = 0; $i < 1000; $i++) {
    $obj = new RapidCreate($i);
    // Explicitly unset to test proper cleanup
    unset($obj);
}
$afterTest1 = memory_get_usage(true);

echo "Memory after 1000 create/unset cycles: " . number_format($afterTest1) . " bytes\n";
echo "Memory increase: " . number_format($afterTest1 - $beforeTest1) . " bytes\n";
echo "Expected: ~0 bytes increase (proper cleanup)\n\n";

// ============================================================================
// Test 2: Circular Reference Stress
// ============================================================================
echo "--- Test 2: Circular Reference Stress ---\n";

class CircularNode {
    public $id;
    public $partner;
    public $data = [];
    
    public function __construct($id) {
        $this->id = $id;
        for ($i = 0; $i < 50; $i++) {
            $this->data[] = str_repeat("data{$i}_", 20);
        }
    }
}

$beforeTest2 = memory_get_usage(true);
$nodes = [];

for ($i = 0; $i < 500; $i++) {
    $nodeA = new CircularNode("A{$i}");
    $nodeB = new CircularNode("B{$i}");
    
    // Create circular references
    $nodeA->partner = $nodeB;
    $nodeB->partner = $nodeA;
    
    $nodes[] = $nodeA;
    $nodes[] = $nodeB;
}

echo "Created 1000 circularly-referenced nodes\n";
echo "Memory after creation: " . number_format(memory_get_usage(true)) . " bytes\n";

// Now unset them
foreach ($nodes as $node) {
    unset($node);
}
$nodes = [];

$afterTest2 = memory_get_usage(true);
echo "After unset all nodes: " . number_format($afterTest2) . " bytes\n";
echo "Memory increase from baseline: " . number_format($afterTest2 - $beforeTest2) . " bytes\n\n";

// ============================================================================
// Test 3: Closure Memory Stress
// ============================================================================
echo "--- Test 3: Closure Memory Stress ---\n";

class ClosureTarget {
    public $value;
    
    public function __construct($value) {
        $this->value = $value;
    }
}

$beforeTest3 = memory_get_usage(true);
$closureArrays = [];

for ($batch = 0; $batch < 100; $batch++) {
    $targets = [];
    for ($i = 0; $i < 10; $i++) {
        $targets[] = new ClosureTarget("Target{$batch}_{$i}");
    }
    
    $closures = [];
    foreach ($targets as $target) {
        $closures[] = function() use ($target) {
            return $target->value;
        };
    }
    
    $closureArrays[] = $closures;
    // Keep targets alive with closures
}

$afterTest3 = memory_get_usage(true);
echo "Created 100 batches of 10 closures each with captured objects\n";
echo "Memory: " . number_format($afterTest3) . " bytes\n";
echo "Memory increase from baseline: " . number_format($afterTest3 - $beforeTest3) . " bytes\n\n";

// ============================================================================
// Test 4: Exception Chain Stress
// ============================================================================
echo "--- Test 4: Exception Chain Stress ---\n";

class ExceptionA extends Exception {}
class ExceptionB extends Exception {}
class ExceptionC extends Exception {}

function createExceptionChain($depth) {
    $current = null;
    for ($i = $depth; $i >= 0; $i--) {
        $class = "Exception" . chr(65 + ($i % 3));
        $message = "Error at level {$i}";
        if ($current !== null) {
            $current = new $class($message, 0, $current);
        } else {
            $current = new $class($message);
        }
    }
    return $current;
}

$beforeTest4 = memory_get_usage(true);
$exceptions = [];

for ($i = 0; $i < 200; $i++) {
    $exceptions[] = createExceptionChain(10);
}

echo "Created 200 exception chains of depth 10\n";
echo "Memory: " . number_format(memory_get_usage(true)) . " bytes\n";

unset($exceptions);
$afterTest4 = memory_get_usage(true);
echo "After unset: " . number_format($afterTest4) . " bytes\n";
echo "Memory increase from baseline: " . number_format($afterTest4 - $beforeTest4) . " bytes\n\n";

// ============================================================================
// Test 5: Array of Objects Stress
// ============================================================================
echo "--- Test 5: Array of Objects Stress ---\n";

class ArrayItem {
    public $id;
    public $name;
    public $data = [];
    public $children = [];
    
    public function __construct($id) {
        $this->id = $id;
        $this->name = "Item{$id}";
        for ($i = 0; $i < 10; $i++) {
            $this->data[] = str_repeat("d", 50);
        }
    }
}

$beforeTest5 = memory_get_usage(true);
$itemArrays = [];

for ($batch = 0; $batch < 50; $batch++) {
    $items = [];
    for ($i = 0; $i < 100; $i++) {
        $items[] = new ArrayItem($batch * 100 + $i);
    }
    $itemArrays[] = $items;
}

$afterTest5 = memory_get_usage(true);
echo "Created 50 batches of 100 objects each (5000 total)\n";
echo "Memory: " . number_format($afterTest5) . " bytes\n";
echo "Memory increase from baseline: " . number_format($afterTest5 - $beforeTest5) . " bytes\n\n";

// ============================================================================
// Test 6: Static Registry Stress
// ============================================================================
echo "--- Test 6: Static Registry Stress ---\n";

class StaticRegistry {
    private static $data = [];
    private static $count = 0;
    
    public static function register($key, $value) {
        self::$data[$key] = $value;
        self::$count++;
    }
    
    public static function get($key) {
        return self::$data[$key] ?? null;
    }
    
    public static function clear() {
        self::$data = [];
        self::$count = 0;
    }
    
    public static function getCount() {
        return self::$count;
    }
}

$beforeTest6 = memory_get_usage(true);

for ($i = 0; $i < 1000; $i++) {
    $obj = new ArrayItem($i);
    StaticRegistry::register("key{$i}", $obj);
}

echo "Registered 1000 objects in static registry\n";
echo "Registry count: " . StaticRegistry::getCount() . "\n";
echo "Memory: " . number_format(memory_get_usage(true)) . " bytes\n";

StaticRegistry::clear();
$afterTest6 = memory_get_usage(true);
echo "After clear: " . number_format($afterTest6) . " bytes\n";
echo "Memory increase from baseline: " . number_format($afterTest6 - $beforeTest6) . " bytes\n\n";

// ============================================================================
// Test 7: Object Graph Stress
// ============================================================================
echo "--- Test 7: Object Graph Stress ---\n";

class GraphNode {
    public $id;
    public $neighbors = [];
    public $data = [];
    
    public function __construct($id) {
        $this->id = $id;
        for ($i = 0; $i < 20; $i++) {
            $this->data[] = str_repeat("g", 30);
        }
    }
    
    public function addNeighbor(GraphNode $node) {
        $this->neighbors[] = $node;
    }
}

$beforeTest7 = memory_get_usage(true);

// Create a complex graph
$nodes = [];
for ($i = 0; $i < 300; $i++) {
    $nodes[] = new GraphNode($i);
}

// Connect nodes in a complex pattern
for ($i = 0; $i < count($nodes); $i++) {
    $node = $nodes[$i];
    // Connect to next 5 nodes
    for ($j = 1; $j <= 5; $j++) {
        if ($i + $j < count($nodes)) {
            $node->addNeighbor($nodes[$i + $j]);
        }
    }
    // Connect to random previous nodes
    if ($i > 0) {
        $node->addNeighbor($nodes[rand(0, $i - 1)]);
    }
}

echo "Created graph with 300 nodes\n";
echo "Memory: " . number_format(memory_get_usage(true)) . " bytes\n";

unset($nodes);
$afterTest7 = memory_get_usage(true);
echo "After unset: " . number_format($afterTest7) . " bytes\n";
echo "Memory increase from baseline: " . number_format($afterTest7 - $beforeTest7) . " bytes\n\n";

// ============================================================================
// Final Memory Report
// ============================================================================
echo "=== Final Memory Report ===\n";
$finalMemory = memory_get_usage(true);
echo "Final memory: " . number_format($finalMemory) . " bytes\n";
echo "Total increase from baseline: " . number_format($finalMemory - $baselineMemory) . " bytes\n";
echo "Peak memory: " . number_format(memory_get_peak_usage(true)) . " bytes\n\n";

// ============================================================================
// PHP Reference Comparison (if available)
// ============================================================================
echo "=== Expected PHP Behavior Reference ===\n";
echo "In PHP with proper garbage collection:\n";
echo "- Memory should be mostly reclaimed after unset\n";
echo "- Circular references should be properly collected\n";
echo "- Static registries should retain memory until cleared\n";
echo "- Peak memory should be reasonable for workload\n\n";

echo "=== Memory Leak Indicators ===\n";
$totalIncrease = $finalMemory - $baselineMemory;
if ($totalIncrease > 10 * 1024 * 1024) { // 10MB
    echo "WARNING: Significant memory increase detected (" . number_format($totalIncrease) . " bytes)\n";
    echo "This may indicate memory leaks in the interpreter.\n";
} else {
    echo "Memory increase within acceptable range (" . number_format($totalIncrease) . " bytes)\n";
}

echo "\nDone\n";
