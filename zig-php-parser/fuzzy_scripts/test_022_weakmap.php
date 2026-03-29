<?php
// Test 022: WeakMap, WeakReference, and garbage collection simulation
class WeakLab {
    public function process(): string {
        $out = "";

        // WeakMap
        $map = new WeakMap();

        $obj1 = new stdClass();
        $obj1->data = 'Object 1 data';

        $obj2 = new stdClass();
        $obj2->data = 'Object 2 data';

        $map[$obj1] = ['value' => 'first'];
        $map[$obj2] = ['value' => 'second'];

        $out .= "WeakMap initial size: " . count($map) . "\n";
        $out .= "obj1 in map: " . (isset($map[$obj1]) ? 'yes' : 'no') . "\n";
        $out .= "obj1 value: " . ($map[$obj1]['value'] ?? 'null') . "\n";

        // Iterate
        foreach ($map as $obj => $value) {
            $out .= "Iterating: " . $obj->data . " = " . $value['value'] . "\n";
        }

        // WeakRef
        $ref = WeakReference::create($obj1);
        $out .= "\nWeakRef original: " . ($ref->get()?->data ?? 'null') . "\n";

        // Destroy object
        unset($obj1);

        $out .= "WeakRef after unset obj1: " . ($ref->get()?->data ?? 'null') . "\n";
        $out .= "WeakMap size after GC: " . count($map) . "\n";

        // New object
        $obj3 = new stdClass();
        $obj3->data = 'Object 3';
        $map[$obj3] = ['value' => 'third'];
        $out .= "New obj3 added, map size: " . count($map) . "\n";

        return $out;
    }

    public function gcStatus(): string {
        $out = "";
        $out .= "gc_enabled: " . (gc_enabled() ? 'true' : 'false') . "\n";
        $out .= "gc_collect_cycles: " . gc_collect_cycles() . "\n";

        $memBefore = memory_get_usage();
        $temp = [];
        for ($i = 0; $i < 1000; $i++) {
            $temp[] = new stdClass();
        }
        $memAfter = memory_get_usage();
        unset($temp);
        gc_collect_cycles();

        $out .= "Memory before: $memBefore, after: $memAfter, delta: " . ($memAfter - $memBefore) . "\n";

        return $out;
    }
}

$lab = new WeakLab();
echo $lab->process();
echo "\n";
echo $lab->gcStatus();