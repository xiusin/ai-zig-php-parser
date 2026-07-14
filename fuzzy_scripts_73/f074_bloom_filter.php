<?php
// f074: 布隆过滤器 (Bloom Filter)
echo "=== Bloom Filter ===\n\n";

class BloomFilter {
    private array $bits;
    private int $size;
    private int $hashCount;
    private int $count = 0;

    public function __construct(int $size = 256, int $hashCount = 4) {
        $this->size = $size;
        $this->hashCount = $hashCount;
        $this->bits = array_fill(0, $size, 0);
    }

    private function hash(string $data, int $seed): int {
        $hash = $seed;
        for ($i = 0; $i < strlen($data); $i++) {
            $hash = (($hash * 31) + ord($data[$i])) % $this->size;
            $hash = ($hash ^ ($hash >> 3)) % $this->size;
        }
        return abs($hash) % $this->size;
    }

    public function add(string $item): void {
        for ($i = 0; $i < $this->hashCount; $i++) {
            $pos = $this->hash($item, $i + 1);
            $this->bits[$pos] = 1;
        }
        $this->count++;
    }

    public function mightContain(string $item): bool {
        for ($i = 0; $i < $this->hashCount; $i++) {
            $pos = $this->hash($item, $i + 1);
            if ($this->bits[$pos] === 0) {
                return false;
            }
        }
        return true;
    }

    public function getCount(): int {
        return $this->count;
    }

    public function getBitCount(): int {
        $sum = 0;
        foreach ($this->bits as $bit) {
            $sum += $bit;
        }
        return $sum;
    }

    public function getFillRatio(): float {
        return $this->getBitCount() / $this->size;
    }
}

// 测试
echo "--- Basic Operations ---\n";
$bf = new BloomFilter(128, 4);
$bf->add('apple');
$bf->add('banana');
$bf->add('cherry');

echo "Contains 'apple': " . ($bf->mightContain('apple') ? 'true' : 'false') . "\n";
echo "Contains 'banana': " . ($bf->mightContain('banana') ? 'true' : 'false') . "\n";
echo "Contains 'cherry': " . ($bf->mightContain('cherry') ? 'true' : 'false') . "\n";
echo "Contains 'grape': " . ($bf->mightContain('grape') ? 'true' : 'false') . "\n";
echo "Contains 'orange': " . ($bf->mightContain('orange') ? 'true' : 'false') . "\n";
echo "Count: " . $bf->getCount() . "\n";
echo "Bit count: " . $bf->getBitCount() . "\n";
printf("Fill ratio: %.4f\n", $bf->getFillRatio());

echo "\n--- Bulk Add ---\n";
$bf2 = new BloomFilter(512, 5);
$words = ['hello', 'world', 'php', 'zig', 'compiler', 'runtime', 'memory', 'string',
          'array', 'object', 'class', 'function', 'method', 'property', 'static',
          'interface', 'trait', 'namespace', 'closure', 'generator'];
foreach ($words as $word) {
    $bf2->add($word);
}

$testWords = ['hello', 'php', 'zig', 'missing', 'unknown', 'test'];
foreach ($testWords as $word) {
    echo "  '$word': " . ($bf2->mightContain($word) ? 'maybe' : 'no') . "\n";
}
echo "Count: " . $bf2->getCount() . "\n";
printf("Fill ratio: %.4f\n", $bf2->getFillRatio());

echo "\n--- False Positive Test ---\n";
$bf3 = new BloomFilter(64, 3);
$bf3->add('cat');
$bf3->add('dog');
$bf3->add('bird');

$fpCount = 0;
$totalTests = 0;
$testSet = ['fish', 'reptile', 'insect', 'mammal', 'plant', 'rock', 'water', 'fire',
            'earth', 'wind', 'storm', 'ocean', 'mountain', 'river', 'forest', 'desert'];
foreach ($testSet as $item) {
    $totalTests++;
    if ($bf3->mightContain($item)) {
        $fpCount++;
        echo "  False positive: '$item'\n";
    }
}
echo "False positives: $fpCount / $totalTests\n";
printf("FP rate: %.4f\n", $fpCount / $totalTests);

echo "\n--- Set Operations ---\n";
$bfA = new BloomFilter(256, 4);
$bfB = new BloomFilter(256, 4);
$bfA->add('shared');
$bfA->add('only_a');
$bfB->add('shared');
$bfB->add('only_b');

echo "A contains 'shared': " . ($bfA->mightContain('shared') ? 'true' : 'false') . "\n";
echo "B contains 'shared': " . ($bfB->mightContain('shared') ? 'true' : 'false') . "\n";
echo "A contains 'only_b': " . ($bfA->mightContain('only_b') ? 'true' : 'false') . "\n";
echo "B contains 'only_a': " . ($bfB->mightContain('only_a') ? 'true' : 'false') . "\n";
