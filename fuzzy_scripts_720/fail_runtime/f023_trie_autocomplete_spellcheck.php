<?php
// 极度混搭: Trie前缀树 + 自动补全 + 拼写检查 + 词频统计
echo "=== f023: Trie + Autocomplete + Spellcheck ===\n";

class TrieNode {
    public array $children = [];
    public bool $isEnd = false;
    public int $frequency = 0;

    public function hasChild(string $char): bool {
        return isset($this->children[$char]);
    }

    public function getChild(string $char): ?TrieNode {
        return $this->children[$char] ?? null;
    }

    public function addChild(string $char): TrieNode {
        if (!isset($this->children[$char])) {
            $this->children[$char] = new TrieNode();
        }
        return $this->children[$char];
    }
}

class Trie {
    private TrieNode $root;
    private int $wordCount = 0;

    public function __construct() {
        $this->root = new TrieNode();
    }

    public function insert(string $word, int $frequency = 1): void {
        $word = strtolower($word);
        $node = $this->root;
        for ($i = 0; $i < strlen($word); $i++) {
            $node = $node->addChild($word[$i]);
        }
        if (!$node->isEnd) {
            $this->wordCount++;
            $node->isEnd = true;
        }
        $node->frequency += $frequency;
    }

    public function search(string $word): bool {
        $node = $this->findNode(strtolower($word));
        return $node !== null && $node->isEnd;
    }

    public function startsWith(string $prefix): bool {
        return $this->findNode(strtolower($prefix)) !== null;
    }

    private function findNode(string $prefix): ?TrieNode {
        $node = $this->root;
        for ($i = 0; $i < strlen($prefix); $i++) {
            $node = $node->getChild($prefix[$i]);
            if ($node === null) return null;
        }
        return $node;
    }

    public function autocomplete(string $prefix, int $limit = 10): array {
        $node = $this->findNode(strtolower($prefix));
        if ($node === null) return [];

        $results = [];
        $this->collectWords($node, strtolower($prefix), $results);
        usort($results, fn($a, $b) => $b['frequency'] <=> $a['frequency']);
        return array_slice($results, 0, $limit);
    }

    private function collectWords(TrieNode $node, string $prefix, array &$results): void {
        if ($node->isEnd) {
            $results[] = ['word' => $prefix, 'frequency' => $node->frequency];
        }
        foreach ($node->children as $char => $child) {
            $this->collectWords($child, $prefix . $char, $results);
        }
    }

    public function spellcheck(string $word, int $maxDistance = 2): array {
        $word = strtolower($word);
        if ($this->search($word)) return [$word];

        $allWords = [];
        $this->collectWords($this->root, '', $allWords);

        $suggestions = [];
        foreach ($allWords as $entry) {
            $dist = self::levenshtein($word, $entry['word']);
            if ($dist <= $maxDistance) {
                $suggestions[] = ['word' => $entry['word'], 'distance' => $dist, 'frequency' => $entry['frequency']];
            }
        }
        usort($suggestions, function($a, $b) {
            if ($a['distance'] !== $b['distance']) return $a['distance'] <=> $b['distance'];
            return $b['frequency'] <=> $a['frequency'];
        });
        return array_slice($suggestions, 0, 5);
    }

    public static function levenshtein(string $s1, string $s2): int {
        $len1 = strlen($s1);
        $len2 = strlen($s2);
        if ($len1 === 0) return $len2;
        if ($len2 === 0) return $len1;

        $prev = range(0, $len2);
        for ($i = 1; $i <= $len1; $i++) {
            $curr = [$i];
            for ($j = 1; $j <= $len2; $j++) {
                $cost = $s1[$i-1] === $s2[$j-1] ? 0 : 1;
                $curr[$j] = min($prev[$j] + 1, $curr[$j-1] + 1, $prev[$j-1] + $cost);
            }
            $prev = $curr;
        }
        return $prev[$len2];
    }

    public function count(): int { return $this->wordCount; }

    public function getAllWords(): array {
        $results = [];
        $this->collectWords($this->root, '', $results);
        return $results;
    }
}

// === 测试 ===
$trie = new Trie();

// 插入词典
$words = [
    ['apple', 100],
    ['application', 80],
    ['apply', 60],
    ['app', 90],
    ['banana', 50],
    ['band', 40],
    ['bandana', 10],
    ['cherry', 30],
    ['chapter', 25],
    ['charter', 15],
    ['computer', 70],
    ['compute', 55],
    ['company', 65],
    ['complete', 45],
    ['conversation', 35],
    ['convert', 40],
    ['cookie', 20],
    ['cool', 50],
    ['cooperation', 15],
];

foreach ($words as [$word, $freq]) {
    $trie->insert($word, $freq);
}

echo "Total words: " . $trie->count() . "\n";

echo "\n--- Search ---\n";
$searchWords = ['apple', 'app', 'apply', 'banana', 'missing', 'computer'];
foreach ($searchWords as $w) {
    echo "  search '$w': " . var_export($trie->search($w), true) . "\n";
}

echo "\n--- StartsWith ---\n";
$prefixes = ['app', 'ban', 'comp', 'xyz'];
foreach ($prefixes as $p) {
    echo "  startsWith '$p': " . var_export($trie->startsWith($p), true) . "\n";
}

echo "\n--- Autocomplete ---\n";
$autocompletePrefixes = ['app', 'ban', 'comp', 'co'];
foreach ($autocompletePrefixes as $p) {
    $suggestions = $trie->autocomplete($p, 5);
    echo "  '$p' → ";
    $words = array_map(fn($s) => $s['word'] . "({$s['frequency']})", $suggestions);
    echo implode(', ', $words) . "\n";
}

echo "\n--- Spellcheck ---\n";
$typos = ['aple', 'aplication', 'bannana', 'compter', 'cooke', 'covert'];
foreach ($typos as $typo) {
    $suggestions = $trie->spellcheck($typo);
    echo "  '$typo' → ";
    if (empty($suggestions)) {
        echo "No suggestions\n";
    } else {
        $words = array_map(fn($s) => $s['word'] . "(d={$s['distance']})", $suggestions);
        echo implode(', ', $words) . "\n";
    }
}

echo "\n--- Levenshtein Distance ---\n";
$pairs = [
    ['kitten', 'sitting'],
    ['hello', 'hallo'],
    ['abc', 'xyz'],
    ['same', 'same'],
    ['', 'abc'],
];
foreach ($pairs as [$a, $b]) {
    echo "  '$a' → '$b': " . Trie::levenshtein($a, $b) . "\n";
}

echo "=== f023 Done ===\n";
