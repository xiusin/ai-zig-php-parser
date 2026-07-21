<?php
// 极度混搭: 原型模式 + 深拷贝/浅拷贝 + 克隆链 + 属性合并
echo "=== f035: Prototype + Deep Clone + Property Merge ===\n";

class PrototypeData implements \Cloneable {
    public array $tags = [];
    public ?PrototypeData $parent = null;

    public function __construct(
        public string $name,
        public array $config = []
    ) {}

    public function __clone() {
        // 深拷贝：克隆嵌套对象
        if ($this->parent !== null) {
            $this->parent = clone $this->parent;
        }
        $this->tags = array_map(fn($t) => $t, $this->tags);
        $this->config = array_merge([], $this->config);
    }

    public function addTag(string $tag): self {
        $this->tags[] = $tag;
        return $this;
    }

    public function merge(self $other): self {
        $this->config = array_merge($this->config, $other->config);
        $this->tags = array_unique(array_merge($this->tags, $other->tags));
        return $this;
    }

    public function __toString(): string {
        $tags = implode(',', $this->tags);
        $parent = $this->parent ? " parent={$this->parent->name}" : '';
        return "{$this->name}[config=" . json_encode($this->config) . " tags=[$tags]$parent]";
    }
}

// 测试
$original = new PrototypeData('original', ['timeout' => 30, 'retries' => 3]);
$original->addTag('production')->addTag('v2');

// 浅拷贝（PHP默认clone是浅拷贝，但我们实现了深拷贝）
$clone = clone $original;
$clone->name = 'clone';
$clone->addTag('cloned');
$clone->config['timeout'] = 60;

echo "Original: $original\n";
echo "Clone:    $clone\n";

// 深拷贝测试（嵌套对象）
$parent = new PrototypeData('parent', ['level' => 1]);
$child = new PrototypeData('child', ['level' => 2]);
$child->parent = $parent;
$child->addTag('child-tag');

$childClone = clone $child;
$childClone->name = 'child-clone';
$childClone->parent->name = 'parent-modified';

echo "\nChild:     $child\n";
echo "ChildClone: $childClone\n";
echo "Parent name unchanged: " . $child->parent->name . "\n";

// 合并
$base = new PrototypeData('base', ['a' => 1, 'b' => 2]);
$base->addTag('base')->addTag('common');
$override = new PrototypeData('override', ['b' => 3, 'c' => 4]);
$override->addTag('override')->addTag('common');

$merged = clone $base;
$merged->merge($override);
echo "\nMerged: $merged\n";

echo "=== f035 Done ===\n";
