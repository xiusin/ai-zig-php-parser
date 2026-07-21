<?php
// 极度混搭: 搜索引擎 + 倒排索引 + TF-IDF + 分词 + 高亮
echo "=== f097: Search Engine + InvertedIndex + TF-IDF ===\n";

class Tokenizer {
    public static function tokenize(string $text): array {
        $text = strtolower($text);
        $text = preg_replace('/[^\p{L}\p{N}\s]/u', ' ', $text);
        $words = preg_split('/\s+/', $text, -1, PREG_SPLIT_NO_EMPTY);
        $stopWords = ['the', 'a', 'an', 'is', 'are', 'was', 'were', 'be', 'been', 'being', 'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would', 'could', 'should', 'may', 'might', 'can', 'to', 'of', 'in', 'on', 'at', 'by', 'for', 'with', 'about', 'as', 'into', 'through', 'during', 'and', 'or', 'not', 'no', 'but', 'if', 'then', 'so', 'it', 'its'];
        return array_values(array_filter($words, fn($w) => !in_array($w, $stopWords) && strlen($w) > 1));
    }
}

class InvertedIndex {
    private array $index = []; // term → [docId => positions]
    private array $documents = []; // docId → content
    private array $docLengths = [];

    public function addDocument(string $docId, string $content): void {
        $this->documents[$docId] = $content;
        $tokens = Tokenizer::tokenize($content);
        $this->docLengths[$docId] = count($tokens);
        foreach ($tokens as $pos => $token) {
            if (!isset($this->index[$token])) $this->index[$token] = [];
            if (!isset($this->index[$token][$docId])) $this->index[$token][$docId] = [];
            $this->index[$token][$docId][] = $pos;
        }
    }

    public function search(string $query): array {
        $terms = Tokenizer::tokenize($query);
        $scores = [];
        $totalDocs = count($this->documents);
        $avgDocLen = $totalDocs > 0 ? array_sum($this->docLengths) / $totalDocs : 0;

        foreach ($terms as $term) {
            if (!isset($this->index[$term])) continue;
            $df = count($this->index[$term]); // 文档频率
            $idf = $totalDocs > 0 ? log($totalDocs / $df) : 0;
            foreach ($this->index[$term] as $docId => $positions) {
                $tf = count($positions);
                $tfidf = $tf * $idf;
                // BM25风格
                $k1 = 1.5; $b = 0.75;
                $docLen = $this->docLengths[$docId];
                $bm25 = $idf * ($tf * ($k1 + 1)) / ($tf + $k1 * (1 - $b + $b * $docLen / $avgDocLen));
                $scores[$docId] = ($scores[$docId] ?? 0) + $bm25;
            }
        }
        arsort($scores);
        return $scores;
    }

    public function getTermFrequency(string $term, string $docId): int {
        return count($this->index[$term][$docId] ?? []);
    }

    public function getDocumentCount(): int { return count($this->documents); }
    public function getTermCount(): int { return count($this->index); }
    public function getDocument(string $docId): ?string { return $this->documents[$docId] ?? null; }
}

class SearchHighlighter {
    public static function highlight(string $content, array $terms): string {
        foreach ($terms as $term) {
            $content = preg_replace('/(' . preg_quote($term, '/') . ')/i', '[$1]', $content);
        }
        return $content;
    }

    public static function snippet(string $content, array $terms, int $contextLen = 50): string {
        $lowerContent = strtolower($content);
        $bestPos = 0; $bestScore = 0;
        $len = strlen($lowerContent);
        for ($i = 0; $i < $len; $i += 10) {
            $window = substr($lowerContent, $i, $contextLen * 2);
            $score = 0;
            foreach ($terms as $term) {
                $score += substr_count($window, strtolower($term));
            }
            if ($score > $bestScore) { $bestScore = $score; $bestPos = $i; }
        }
        $start = max(0, $bestPos - $contextLen);
        $snippet = substr($content, $start, $contextLen * 3);
        if ($start > 0) $snippet = '...' . $snippet;
        if ($start + $contextLen * 3 < $len) $snippet .= '...';
        return self::highlight($snippet, $terms);
    }
}

// 测试
echo "--- Build Index ---\n";
$index = new InvertedIndex();
$docs = [
    'doc1' => 'The quick brown fox jumps over the lazy dog',
    'doc2' => 'PHP is a popular programming language for web development',
    'doc3' => 'The fox is a smart animal that lives in forests',
    'doc4' => 'Web development with PHP and JavaScript is fun',
    'doc5' => 'A brown dog chased the fox through the forest',
    'doc6' => 'Programming languages like PHP and Python are powerful tools',
];

foreach ($docs as $id => $content) {
    $index->addDocument($id, $content);
}
echo "Documents: " . $index->getDocumentCount() . "\n";
echo "Unique terms: " . $index->getTermCount() . "\n";

echo "\n--- Search: 'fox' ---\n";
$results = $index->search('fox');
foreach ($results as $docId => $score) {
    echo "  $docId (score=" . number_format($score, 4) . "): " . $index->getDocument($docId) . "\n";
}

echo "\n--- Search: 'PHP programming' ---\n";
$results = $index->search('PHP programming');
foreach ($results as $docId => $score) {
    echo "  $docId (score=" . number_format($score, 4) . "): " . $index->getDocument($docId) . "\n";
}

echo "\n--- Search: 'brown fox' ---\n";
$results = $index->search('brown fox');
foreach ($results as $docId => $score) {
    echo "  $docId (score=" . number_format($score, 4) . "): " . $index->getDocument($docId) . "\n";
}

echo "\n--- Search: 'web development' ---\n";
$results = $index->search('web development');
foreach ($results as $docId => $score) {
    echo "  $docId (score=" . number_format($score, 4) . "): " . $index->getDocument($docId) . "\n";
}

echo "\n--- Highlight & Snippet ---\n";
$query = 'fox forest';
$terms = Tokenizer::tokenize($query);
echo "Query terms: " . json_encode($terms) . "\n";
foreach ($docs as $id => $content) {
    $snippet = SearchHighlighter::snippet($content, $terms);
    echo "  $id: $snippet\n";
}

echo "\n--- TF-IDF Analysis ---\n";
$terms = ['php', 'fox', 'web', 'dog', 'programming'];
echo "Term frequencies:\n";
foreach ($terms as $term) {
    echo "  '$term': ";
    foreach ($docs as $id => $_) {
        $tf = $index->getTermFrequency($term, $id);
        if ($tf > 0) echo "$id=$tf ";
    }
    echo "\n";
}

echo "=== f097 Done ===\n";
