<?php
// 极度混搭: 内存管理 + GC标记清除 + 引用计数 + 分代回收
echo "=== f102: Memory Mgmt + MarkSweep + RefCount + Generational ===\n";

class GCObject {
    public int $id;
    public int $refCount = 1;
    public bool $marked = false;
    public array $references = [];
    public int $generation = 0;
    public int $size;

    public function __construct(int $id, int $size = 64) { $this->id = $id; $this->size = $size; }

    public function addRef(GCObject $obj): void { $this->references[] = $obj->id; }
    public function __toString(): string { return "Obj#{$this->id}(gen={$this->generation},refs=" . count($this->references) . ")"; }
}

class MarkSweepGC {
    private array $heap = [];
    private array $roots = [];
    private int $nextId = 1;
    private array $stats = ['allocations' => 0, 'collections' => 0, 'freed' => 0, 'total_freed' => 0];

    public function allocate(int $size = 64): GCObject {
        $obj = new GCObject($this->nextId++, $size);
        $this->heap[$obj->id] = $obj;
        $this->stats['allocations']++;
        return $obj;
    }

    public function addRoot(GCObject $obj): void { $this->roots[$obj->id] = $obj->id; }
    public function removeRoot(int $id): void { unset($this->roots[$id]); }

    public function collect(): int {
        // Mark
        foreach ($this->heap as $obj) $obj->marked = false;
        $this->stats['collections']++;
        foreach ($this->roots as $rootId) {
            $this->mark($rootId);
        }
        // Sweep
        $freed = 0;
        foreach ($this->heap as $id => $obj) {
            if (!$obj->marked) {
                $freed += $obj->size;
                unset($this->heap[$id]);
                $this->stats['freed']++;
            } else {
                $obj->generation++;
            }
        }
        $this->stats['total_freed'] += $freed;
        return $freed;
    }

    private function mark(int $id): void {
        if (!isset($this->heap[$id])) return;
        $obj = $this->heap[$id];
        if ($obj->marked) return;
        $obj->marked = true;
        foreach ($obj->references as $refId) $this->mark($refId);
    }

    public function getHeapSize(): int { return count($this->heap); }
    public function getMemoryUsage(): int { return array_sum(array_map(fn($o) => $o->size, $this->heap)); }
    public function getStats(): array { return $this->stats; }
}

class RefCountGC {
    private array $objects = [];
    private array $stats = ['allocations' => 0, 'deallocations' => 0, 'cycles_detected' => 0];

    public function allocate(int $size = 64): GCObject {
        $obj = new GCObject(count($this->objects) + 1, $size);
        $this->objects[$obj->id] = $obj;
        $this->stats['allocations']++;
        return $obj;
    }

    public function addReference(GCObject $from, GCObject $to): void {
        $from->addRef($to);
        $to->refCount++;
    }

    public function release(GCObject $obj): void {
        $obj->refCount--;
        if ($obj->refCount <= 0) {
            foreach ($obj->references as $refId) {
                if (isset($this->objects[$refId])) $this->release($this->objects[$refId]);
            }
            unset($this->objects[$obj->id]);
            $this->stats['deallocations']++;
        }
    }

    public function detectCycles(): array {
        $cycles = [];
        foreach ($this->objects as $obj) {
            $visited = [];
            $this->findCycle($obj->id, $obj->id, $visited, $cycles);
        }
        return $cycles;
    }

    private function findCycle(int $start, int $current, array &$visited, array &$cycles): void {
        if (in_array($current, $visited)) {
            if ($current === $start) {
                $cycles[] = array_merge($visited, [$current]);
                $this->stats['cycles_detected']++;
            }
            return;
        }
        $visited[] = $current;
        if (!isset($this->objects[$current])) return;
        foreach ($this->objects[$current]->references as $ref) {
            $this->findCycle($start, $ref, $visited, $cycles);
        }
        array_pop($visited);
    }

    public function getObjectCount(): int { return count($this->objects); }
    public function getStats(): array { return $this->stats; }
}

class GenerationalGC {
    private array $youngGen = [];
    private array $oldGen = [];
    private int $nextId = 1;
    private array $stats = ['minor_gc' => 0, 'major_gc' => 0, 'promotions' => 0, 'minor_freed' => 0, 'major_freed' => 0];

    public function allocate(int $size = 64): GCObject {
        $obj = new GCObject($this->nextId++, $size);
        $this->youngGen[$obj->id] = $obj;
        return $obj;
    }

    public function minorGC(array $rootIds): int {
        $this->stats['minor_gc']++;
        $freed = 0;
        $marked = [];
        foreach ($rootIds as $id) $this->markGen($id, $marked, true);
        foreach ($this->youngGen as $id => $obj) {
            if (!isset($marked[$id])) {
                $freed += $obj->size;
                unset($this->youngGen[$id]);
                $this->stats['minor_freed']++;
            } elseif ($obj->generation >= 2) {
                $this->oldGen[$id] = $obj;
                unset($this->youngGen[$id]);
                $this->stats['promotions']++;
            } else {
                $obj->generation++;
            }
        }
        return $freed;
    }

    public function majorGC(array $rootIds): int {
        $this->stats['major_gc']++;
        $freed = 0;
        $marked = [];
        foreach ($rootIds as $id) $this->markGen($id, $marked, false);
        foreach ($this->oldGen as $id => $obj) {
            if (!isset($marked[$id])) {
                $freed += $obj->size;
                unset($this->oldGen[$id]);
                $this->stats['major_freed']++;
            }
        }
        return $freed;
    }

    private function markGen(int $id, array &$marked, bool $youngOnly): void {
        if (isset($marked[$id])) return;
        $obj = $this->youngGen[$id] ?? $this->oldGen[$id] ?? null;
        if ($obj === null) return;
        if ($youngOnly && !isset($this->youngGen[$id])) return;
        $marked[$id] = true;
        foreach ($obj->references as $ref) $this->markGen($ref, $marked, $youngOnly);
    }

    public function getStats(): array { return $this->stats; }
    public function getTotalObjects(): int { return count($this->youngGen) + count($this->oldGen); }
}

// 测试
echo "--- Mark-Sweep GC ---\n";
$gc = new MarkSweepGC();
$root = $gc->allocate(128);
$gc->addRoot($root);
$child1 = $gc->allocate(64); $root->addRef($child1);
$child2 = $gc->allocate(64); $root->addRef($child2);
$grandchild = $gc->allocate(32); $child1->addRef($grandchild);
$orphan = $gc->allocate(256); // 无引用

echo "Heap: " . $gc->getHeapSize() . " objects, " . $gc->getMemoryUsage() . " bytes\n";
$freed = $gc->collect();
echo "After GC: freed $freed bytes, heap=" . $gc->getHeapSize() . " objects\n";
echo "Stats: " . json_encode($gc->getStats()) . "\n";

echo "\n--- Reference Counting ---\n";
$rc = new RefCountGC();
$a = $rc->allocate(100);
$b = $rc->allocate(200);
$c = $rc->allocate(50);
$rc->addReference($a, $b);
$rc->addReference($b, $c);
echo "Objects: " . $rc->getObjectCount() . "\n";
echo "a.refs=" . count($a->references) . " b.refCount={$b->refCount}\n";
$rc->release($a);
echo "After release a: " . $rc->getObjectCount() . " objects\n";
echo "Stats: " . json_encode($rc->getStats()) . "\n";

echo "\n--- Cycle Detection ---\n";
$rc2 = new RefCountGC();
$x = $rc2->allocate(100);
$y = $rc2->allocate(100);
$rc2->addReference($x, $y);
$rc2->addReference($y, $x); // 循环引用
echo "Cycle detection: " . count($rc2->detectCycles()) . " cycles found\n";

echo "\n--- Generational GC ---\n";
$gen = new GenerationalGC();
$roots = [];
for ($i = 0; $i < 5; $i++) {
    $obj = $gen->allocate(64);
    $roots[] = $obj->id;
}
// 分配临时对象
for ($i = 0; $i < 10; $i++) $gen->allocate(32);
echo "Total objects: " . $gen->getTotalObjects() . "\n";
$minorFreed = $gen->minorGC($roots);
echo "Minor GC: freed $minorFreed bytes\n";
echo "After minor: " . $gen->getTotalObjects() . " objects\n";
// 再次 minor (晋升)
$minorFreed2 = $gen->minorGC($roots);
echo "Minor GC 2: freed $minorFreed2 bytes\n";
$majorFreed = $gen->majorGC($roots);
echo "Major GC: freed $majorFreed bytes\n";
echo "Stats: " . json_encode($gen->getStats()) . "\n";

echo "=== f102 Done ===\n";
