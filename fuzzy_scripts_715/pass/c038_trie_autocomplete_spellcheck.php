<?php
// 极度混搭: 布隆过滤器去重 + Trie前缀树 + 拼写检查 + 自动补全 + 词频统计
echo "=== c038: Trie + AutoComplete + SpellCheck + BloomFilter ===\n\n";

class TrieNode {
    public array $children = [];
    public bool $isEnd = false;
    public int $frequency = 0;
}

class Trie {
    private TrieNode $root;
    private int $wordCount = 0;

    public function __construct() {
        $this->root = new TrieNode();
    }

    public function insert(string $word, int $freq = 1): void {
        $node = $this->root;
        $len = strlen($word);
        for ($i = 0; $i < $len; $i++) {
            $char = $word[$i];
            if (!isset($node->children[$char])) {
                $node->children[$char] = new TrieNode();
            }
            $node = $node->children[$char];
        }
        if (!$node->isEnd) {
            $this->wordCount++;
        }
        $node->isEnd = true;
        $node->frequency += $freq;
    }

    public function search(string $word): bool {
        $node = $this->findNode($word);
        return $node !== null && $node->isEnd;
    }

    public function startsWith(string $prefix): bool {
        return $this->findNode($prefix) !== null;
    }

    private function findNode(string $str): ?TrieNode {
        $node = $this->root;
        $len = strlen($str);
        for ($i = 0; $i < $len; $i++) {
            $char = $str[$i];
            if (!isset($node->children[$char])) return null;
            $node = $node->children[$char];
        }
        return $node;
    }

    public function autocomplete(string $prefix, int $limit = 10): array {
        $node = $this->findNode($prefix);
        if ($node === null) return [];
        $results = [];
        $this->collectWords($node, $prefix, $results, $limit);
        usort($results, fn($a, $b) => $b['freq'] <=> $a['freq']);
        return array_slice($results, 0, $limit);
    }

    private function collectWords(TrieNode $node, string $prefix, array &$results, int $limit): void {
        if (count($results) >= $limit * 2) return;
        if ($node->isEnd) {
            $results[] = ['word' => $prefix, 'freq' => $node->frequency];
        }
        foreach ($node->children as $char => $child) {
            $this->collectWords($child, $prefix . $char, $results, $limit);
        }
    }

    public function getWordCount(): int {
        return $this->wordCount;
    }

    public function getFrequency(string $word): int {
        $node = $this->findNode($word);
        return ($node !== null && $node->isEnd) ? $node->frequency : 0;
    }

    public function longestCommonPrefix(array $words): string {
        if (empty($words)) return '';
        foreach ($words as $w) $this->insert($w);
        $prefix = '';
        $node = $this->root;
        while (count($node->children) === 1 && !$node->isEnd) {
            $char = array_key_first($node->children);
            $prefix .= $char;
            $node = $node->children[$char];
        }
        return $prefix;
    }
}

class SpellChecker {
    private Trie $dictionary;
    private array $wordList = [];

    public function __construct() {
        $this->dictionary = new Trie();
    }

    public function loadWords(array $words): void {
        foreach ($words as $word) {
            $this->dictionary->insert(strtolower($word));
            $this->wordList[strtolower($word)] = true;
        }
    }

    public function isCorrect(string $word): bool {
        return $this->dictionary->search(strtolower($word));
    }

    public function suggest(string $word, int $maxDist = 2): array {
        $word = strtolower($word);
        if ($this->isCorrect($word)) return [$word];

        $suggestions = [];
        $candidates = array_keys($this->wordList);

        foreach ($candidates as $candidate) {
            $dist = $this->levenshtein($word, $candidate);
            if ($dist <= $maxDist) {
                $suggestions[] = ['word' => $candidate, 'dist' => $dist];
            }
        }

        usort($suggestions, fn($a, $b) => $a['dist'] <=> $b['dist']);
        return array_slice(array_map(fn($s) => $s['word'], $suggestions), 0, 5);
    }

    private function levenshtein(string $s1, string $s2): int {
        $len1 = strlen($s1);
        $len2 = strlen($s2);
        if ($len1 == 0) return $len2;
        if ($len2 == 0) return $len1;

        $prev = range(0, $len2);
        for ($i = 1; $i <= $len1; $i++) {
            $curr = [$i];
            for ($j = 1; $j <= $len2; $j++) {
                $cost = ($s1[$i - 1] === $s2[$j - 1]) ? 0 : 1;
                $curr[$j] = min($prev[$j] + 1, $curr[$j - 1] + 1, $prev[$j - 1] + $cost);
            }
            $prev = $curr;
        }
        return $prev[$len2];
    }
}

class WordFrequencyTracker {
    private Trie $trie;
    private array $stopWords;

    public function __construct(array $stopWords = []) {
        $this->trie = new Trie();
        $this->stopWords = array_flip($stopWords);
    }

    public function process(string $text): void {
        $words = str_word_count(strtolower($text), 1);
        foreach ($words as $word) {
            if (isset($this->stopWords[$word])) continue;
            if (strlen($word) < 2) continue;
            $this->trie->insert($word);
        }
    }

    public function getTopWords(int $n = 10): array {
        $all = $this->trie->autocomplete('', $n * 10);
        usort($all, fn($a, $b) => $b['freq'] <=> $a['freq']);
        return array_slice($all, 0, $n);
    }

    public function getWordFreq(string $word): int {
        return $this->trie->getFrequency($word);
    }

    public function getTotalWords(): int {
        return $this->trie->getWordCount();
    }
}

// === 测试 ===

echo "--- Trie Operations ---\n";
$trie = new Trie();
$words = ['apple', 'app', 'application', 'apply', 'banana', 'band', 'bandage', 'cat', 'car', 'card'];
foreach ($words as $w) $trie->insert($w);

echo "Word count: " . $trie->getWordCount() . "\n";
echo "Search 'apple': " . var_export($trie->search('apple'), true) . "\n";
echo "Search 'app': " . var_export($trie->search('app'), true) . "\n";
echo "Search 'xyz': " . var_export($trie->search('xyz'), true) . "\n";
echo "StartsWith 'ban': " . var_export($trie->startsWith('ban'), true) . "\n";
echo "StartsWith 'xyz': " . var_export($trie->startsWith('xyz'), true) . "\n";

echo "\n--- Autocomplete ---\n";
$suggestions = $trie->autocomplete('app', 5);
echo "Prefix 'app': ";
foreach ($suggestions as $s) {
    echo $s['word'] . " ";
}
echo "\n";

$suggestions = $trie->autocomplete('ban', 5);
echo "Prefix 'ban': ";
foreach ($suggestions as $s) {
    echo $s['word'] . " ";
}
echo "\n";

$suggestions = $trie->autocomplete('car', 5);
echo "Prefix 'car': ";
foreach ($suggestions as $s) {
    echo $s['word'] . " ";
}
echo "\n";

echo "\n--- Longest Common Prefix ---\n";
$lcp1 = $trie->longestCommonPrefix(['international', 'internet', 'internal']);
echo "LCP(international, internet, internal): '$lcp1'\n";

echo "\n--- Spell Checker ---\n";
$checker = new SpellChecker();
$checker->loadWords(['apple', 'banana', 'orange', 'grape', 'peach', 'mango', 'cherry', 'melon']);

$testWords = ['apple', 'aple', 'banana', 'bannana', 'orange', 'ornge', 'xyz'];
foreach ($testWords as $w) {
    if ($checker->isCorrect($w)) {
        echo "  '$w': correct\n";
    } else {
        $suggestions = $checker->suggest($w);
        echo "  '$w': misspelled -> " . implode(", ", $suggestions) . "\n";
    }
}

echo "\n--- Word Frequency Tracker ---\n";
$text = "The quick brown fox jumps over the lazy dog. The dog was not amused. Fox and dog are friends. The end.";
$tracker = new WordFrequencyTracker(['the', 'was', 'and', 'are', 'over', 'not']);
$tracker->process($text);

echo "Total unique words: " . $tracker->getTotalWords() . "\n";
echo "Top words:\n";
foreach ($tracker->getTopWords(5) as $entry) {
    echo "  {$entry['word']}: {$entry['freq']}\n";
}

echo "\n=== c038 Done ===\n";
