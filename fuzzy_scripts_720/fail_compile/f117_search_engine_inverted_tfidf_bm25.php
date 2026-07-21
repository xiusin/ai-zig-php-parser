<?php
// 极度混搭: 搜索引擎 + 倒排索引 + TF-IDF + BM25 + 分词
echo "=== f117: Search Engine + InvertedIndex + TF-IDF + BM25 ===\n";

class Tokenizer {
    public static function tokenize(string $text): array {
        $text = strtolower($text);
        $text = preg_replace('/[^\w\s]/', ' ', $text);
        $words = explode(' ', $text);
        return array_values(array_filter($words, fn($w) => strlen($w) > 1));
    }

    public static function stopwordFilter(array $tokens): array {
        $stopwords = array_flip(['the', 'is', 'at', 'of', 'on', 'and', 'a', 'to', 'in', 'it', 'that', 'was', 'for', 'are', 'with', 'this', 'but']);
        return array_values(array_filter($tokens, fn($t) => !isset($stopwords[$t])));
    }

    public static function stem(string $word): string {
        // 简化词干提取
        if (str_ends_with($word, 'ing')) return substr($word, 0, -3);
        if (str_ends_with($word, 'ed')) return substr($word, 0, -2);
        if (str_ends_with($word, 's') && !str_ends_with($word, 'ss')) return substr($word, 0, -1);
        return $word;
    }

    public static function process(string $text): array {
        $tokens = self::tokenize($text);
        $tokens = self::stopwordFilter($tokens);
        return array_map(fn($t) => self::stem($t), $tokens);
    }
}

class InvertedIndex {
    private array $index = []; // term => [docId => positions]
    private array $documents = []; // docId => text
    private array $docLengths = [];
    private int $totalDocs = 0;
    private float $avgDocLength = 0;

    public function addDocument(int $docId, string $text): void {
        $this->documents[$docId] = $text;
        $tokens = Tokenizer::process($text);
        $this->docLengths[$docId] = count($tokens);
        $this->totalDocs++;
        $this->avgDocLength = array_sum($this->docLengths) / $this->totalDocs;

        foreach ($tokens as $pos => $token) {
            if (!isset($this->index[$token])) $this->index[$token] = [];
            if (!isset($this->index[$token][$docId])) $this->index[$token][$docId] = [];
            $this->index[$token][$docId][] = $pos;
        }
    }

    public function search(string $query): array {
        $tokens = Tokenizer::process($query);
        $results = [];
        foreach ($tokens as $token) {
            if (isset($this->index[$token])) {
                foreach ($this->index[$token] as $docId => $positions) {
                    if (!isset($results[$docId])) $results[$docId] = [];
                    $results[$docId][$token] = count($positions);
                }
            }
        }
        return $results;
    }

    public function tfidf(string $term, int $docId): float {
        if (!isset($this->index[$term][$docId])) return 0;
        $tf = count($this->index[$term][$docId]);
        $df = count($this->index[$term]);
        $idf = log(($this->totalDocs + 1) / ($df + 1)) + 1;
        return $tf * $idf;
    }

    public function bm25(string $term, int $docId, float $k1 = 1.5, float $b = 0.75): float {
        if (!isset($this->index[$term][$docId])) return 0;
        $tf = count($this->index[$term][$docId]);
        $df = count($this->index[$term]);
        $idf = log(($this->totalDocs - $df + 0.5) / ($df + 0.5) + 1);
        $docLen = $this->docLengths[$docId];
        $tfNorm = ($tf * ($k1 + 1)) / ($tf + $k1 * (1 - $b + $b * $docLen / $this->avgDocLength));
        return $idf * $tfNorm;
    }

    public function searchTFIDF(string $query): array {
        $tokens = Tokenizer::process($query);
        $scores = [];
        foreach ($tokens as $token) {
            if (isset($this->index[$token])) {
                foreach (array_keys($this->index[$token]) as $docId) {
                    $scores[$docId] = ($scores[$docId] ?? 0) + $this->tfidf($token, $docId);
                }
            }
        }
        arsort($scores);
        return $scores;
    }

    public function searchBM25(string $query): array {
        $tokens = Tokenizer::process($query);
        $scores = [];
        foreach ($tokens as $token) {
            if (isset($this->index[$token])) {
                foreach (array_keys($this->index[$token]) as $docId) {
                    $scores[$docId] = ($scores[$docId] ?? 0) + $this->bm25($token, $docId);
                }
            }
        }
        arsort($scores);
        return $scores;
    }

    public function getStats(): array {
        return ['documents' => $this->totalDocs, 'terms' => count($this->index), 'avg_doc_length' => round($this->avgDocLength, 1)];
    }

    public function getDocument(int $docId): ?string { return $this->documents[$docId] ?? null; }
}

class SearchHighlighter {
    public static function highlight(string $text, array $terms): string {
        foreach ($terms as $term) {
            $text = preg_replace('/(' . preg_quote($term, '/') . ')/i', '[$1]', $text);
        }
        return $text;
    }
}

// 测试
echo "--- Build Index ---\n";
$index = new InvertedIndex();
$docs = [
    1 => "The quick brown fox jumps over the lazy dog",
    2 => "A quick brown dog outruns the quick fox",
    3 => "Lazy cats and lazy dogs sleep all day",
    4 => "The fox and the dog are friends",
    5 => "Quick thinking saves the day for the fox",
    6 => "Dogs and cats can be friends too",
    7 => "The lazy dog sleeps while the fox hunts",
];
foreach ($docs as $id => $text) $index->addDocument($id, $text);
echo "Index stats: " . json_encode($index->getStats()) . "\n";

echo "\n--- Tokenizer ---\n";
$text = "The Quick Brown Foxes are running quickly!";
echo "Original: $text\n";
echo "Tokens: " . json_encode(Tokenizer::process($text)) . "\n";

echo "\n--- Boolean Search ---\n";
$results = $index->search('fox dog');
foreach ($results as $docId => $termFreqs) {
    echo "  Doc $docId: " . json_encode($termFreqs) . " - \"" . substr($index->getDocument($docId), 0, 40) . "...\"\n";
}

echo "\n--- TF-IDF Search ---\n";
$tfidfResults = $index->searchTFIDF('quick fox');
echo "Query: 'quick fox'\n";
foreach ($tfidfResults as $docId => $score) {
    echo "  Doc $docId: score=" . number_format($score, 4) . " - \"" . $index->getDocument($docId) . "\"\n";
}

echo "\n--- BM25 Search ---\n";
$bm25Results = $index->searchBM25('quick fox');
echo "Query: 'quick fox'\n";
foreach ($bm25Results as $docId => $score) {
    echo "  Doc $docId: score=" . number_format($score, 4) . " - \"" . $index->getDocument($docId) . "\"\n";
}

echo "\n--- Compare TF-IDF vs BM25 ---\n";
$queries = ['lazy dog', 'fox', 'quick', 'friends cats dogs', 'sleeps hunts'];
foreach ($queries as $q) {
    $tfidf = $index->searchTFIDF($q);
    $bm25 = $index->searchBM25($q);
    $tfTop = array_key_first($tfidf);
    $bm25Top = array_key_first($bm25);
    $agree = $tfTop === $bm25Top ? 'AGREE' : 'DIFFER';
    echo "  '$q': TF-IDF top=doc$tfTop (" . number_format($tfidf[$tfTop] ?? 0, 3) . ") BM25 top=doc$bm25Top (" . number_format($bm25[$bm25Top] ?? 0, 3) . ") [$agree]\n";
}

echo "\n--- Highlight ---\n";
$highlighted = SearchHighlighter::highlight($docs[1], ['quick', 'fox']);
echo "Original: " . $docs[1] . "\n";
echo "Highlighted: $highlighted\n";

echo "\n--- Phrase Search Simulation ---\n";
$phrase = 'lazy dog';
echo "Phrase: '$phrase'\n";
$phraseTokens = Tokenizer::process($phrase);
foreach ($docs as $id => $text) {
    $docTokens = Tokenizer::process($text);
    $found = false;
    for ($i = 0; $i <= count($docTokens) - count($phraseTokens); $i++) {
        $match = true;
        for ($j = 0; $j < count($phraseTokens); $j++) {
            if ($docTokens[$i + $j] !== $phraseTokens[$j]) { $match = false; break; }
        }
        if ($match) { $found = true; break; }
    }
    if ($found) echo "  Doc $id: FOUND - \"" . $docs[$id] . "\"\n";
}

echo "=== f117 Done ===\n";
