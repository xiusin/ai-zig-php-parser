<?php
// 极度混搭: 机器学习 + 决策树 + 朴素贝叶斯 + KNN
echo "=== f115: ML + DecisionTree + NaiveBayes + KNN ===\n";

class Dataset {
    public array $samples = [];
    public array $labels = [];
    public int $featureCount = 0;

    public function add(array $features, string $label): void {
        $this->samples[] = $features;
        $this->labels[] = $label;
        $this->featureCount = max($this->featureCount, count($features));
    }

    public function count(): int { return count($this->samples); }
    public function getLabels(): array { return array_unique($this->labels); }
    public function split(float $ratio): array {
        $indices = range(0, $this->count() - 1);
        shuffle($indices);
        $splitAt = (int)($this->count() * $ratio);
        $trainIdx = array_slice($indices, 0, $splitAt);
        $testIdx = array_slice($indices, $splitAt);
        $train = new Dataset(); $test = new Dataset();
        foreach ($trainIdx as $i) $train->add($this->samples[$i], $this->labels[$i]);
        foreach ($testIdx as $i) $test->add($this->samples[$i], $this->labels[$i]);
        return [$train, $test];
    }
}

class DecisionTree {
    private $root = null;

    public function train(Dataset $data): void {
        $this->root = $this->buildTree($data->samples, $data->labels, 0);
    }

    private function buildTree(array $samples, array $labels, int $depth): array {
        if (count(array_unique($labels)) === 1) return ['type' => 'leaf', 'label' => $labels[0]];
        if ($depth >= 5 || count($samples) < 2) {
            $counts = array_count_values($labels);
            arsort($counts);
            return ['type' => 'leaf', 'label' => array_key_first($counts)];
        }
        $bestSplit = $this->findBestSplit($samples, $labels);
        if ($bestSplit === null) {
            $counts = array_count_values($labels);
            arsort($counts);
            return ['type' => 'leaf', 'label' => array_key_first($counts)];
        }
        [$feature, $threshold] = $bestSplit;
        $leftSamples = []; $leftLabels = []; $rightSamples = []; $rightLabels = [];
        for ($i = 0; $i < count($samples); $i++) {
            if ($samples[$i][$feature] <= $threshold) { $leftSamples[] = $samples[$i]; $leftLabels[] = $labels[$i]; }
            else { $rightSamples[] = $samples[$i]; $rightLabels[] = $labels[$i]; }
        }
        if (empty($leftSamples) || empty($rightSamples)) {
            $counts = array_count_values($labels); arsort($counts);
            return ['type' => 'leaf', 'label' => array_key_first($counts)];
        }
        return [
            'type' => 'node',
            'feature' => $feature,
            'threshold' => $threshold,
            'left' => $this->buildTree($leftSamples, $leftLabels, $depth + 1),
            'right' => $this->buildTree($rightSamples, $rightLabels, $depth + 1),
        ];
    }

    private function findBestSplit(array $samples, array $labels): ?array {
        $bestGain = 0; $bestSplit = null;
        $n = count($samples);
        if ($n === 0) return null;
        $featureCount = count($samples[0]);
        for ($f = 0; $f < $featureCount; $f++) {
            $values = array_unique(array_column($samples, $f));
            sort($values);
            for ($i = 0; $i < count($values) - 1; $i++) {
                $threshold = ($values[$i] + $values[$i + 1]) / 2;
                $leftLabels = []; $rightLabels = [];
                for ($j = 0; $j < $n; $j++) {
                    if ($samples[$j][$f] <= $threshold) $leftLabels[] = $labels[$j];
                    else $rightLabels[] = $labels[$j];
                }
                if (empty($leftLabels) || empty($rightLabels)) continue;
                $gain = $this->gini($labels) - ($this->gini($leftLabels) * count($leftLabels) + $this->gini($rightLabels) * count($rightLabels)) / $n;
                if ($gain > $bestGain) { $bestGain = $gain; $bestSplit = [$f, $threshold]; }
            }
        }
        return $bestSplit;
    }

    private function gini(array $labels): float {
        if (empty($labels)) return 0;
        $counts = array_count_values($labels);
        $total = count($labels);
        $impurity = 1.0;
        foreach ($counts as $count) $impurity -= ($count / $total) ** 2;
        return $impurity;
    }

    public function predict(array $features): string {
        $node = $this->root;
        while ($node['type'] === 'node') {
            if ($features[$node['feature']] <= $node['threshold']) $node = $node['left'];
            else $node = $node['right'];
        }
        return $node['label'];
    }

    public function accuracy(Dataset $data): float {
        $correct = 0;
        for ($i = 0; $i < $data->count(); $i++) {
            if ($this->predict($data->samples[$i]) === $data->labels[$i]) $correct++;
        }
        return $data->count() > 0 ? $correct / $data->count() : 0;
    }
}

class NaiveBayes {
    private array $mean = []; private array $var = []; private array $priors = [];
    private array $classes = [];

    public function train(Dataset $data): void {
        $this->classes = $data->getLabels();
        $featureCount = $data->featureCount;
        foreach ($this->classes as $class) {
            $classSamples = [];
            for ($i = 0; $i < $data->count(); $i++) {
                if ($data->labels[$i] === $class) $classSamples[] = $data->samples[$i];
            }
            $this->priors[$class] = count($classSamples) / $data->count();
            $this->mean[$class] = array_fill(0, $featureCount, 0);
            $this->var[$class] = array_fill(0, $featureCount, 0);
            for ($f = 0; $f < $featureCount; $f++) {
                $values = array_column($classSamples, $f);
                $this->mean[$class][$f] = array_sum($values) / max(1, count($values));
                $v = 0;
                foreach ($values as $val) $v += ($val - $this->mean[$class][$f]) ** 2;
                $this->var[$class][$f] = $v / max(1, count($values)) + 1e-9;
            }
        }
    }

    public function predict(array $features): string {
        $bestClass = ''; $bestProb = -INF;
        foreach ($this->classes as $class) {
            $logProb = log($this->priors[$class]);
            for ($f = 0; $f < count($features); $f++) {
                $mean = $this->mean[$class][$f];
                $var = $this->var[$class][$f];
                $logProb += -0.5 * log(2 * M_PI * $var) - ($features[$f] - $mean) ** 2 / (2 * $var);
            }
            if ($logProb > $bestProb) { $bestProb = $logProb; $bestClass = $class; }
        }
        return $bestClass;
    }

    public function accuracy(Dataset $data): float {
        $correct = 0;
        for ($i = 0; $i < $data->count(); $i++) {
            if ($this->predict($data->samples[$i]) === $data->labels[$i]) $correct++;
        }
        return $data->count() > 0 ? $correct / $data->count() : 0;
    }
}

class KNN {
    public function __construct(private int $k = 3) {}

    private array $trainSamples = []; private array $trainLabels = [];

    public function train(Dataset $data): void {
        $this->trainSamples = $data->samples;
        $this->trainLabels = $data->labels;
    }

    public function predict(array $features): string {
        $distances = [];
        for ($i = 0; $i < count($this->trainSamples); $i++) {
            $dist = 0;
            for ($f = 0; $f < count($features); $f++) {
                $diff = $features[$f] - $this->trainSamples[$i][$f];
                $dist += $diff * $diff;
            }
            $distances[] = ['dist' => sqrt($dist), 'label' => $this->trainLabels[$i]];
        }
        usort($distances, fn($a, $b) => $a['dist'] <=> $b['dist']);
        $neighbors = array_slice($distances, 0, min($this->k, count($distances)));
        $votes = [];
        foreach ($neighbors as $n) $votes[$n['label']] = ($votes[$n['label']] ?? 0) + 1;
        arsort($votes);
        return array_key_first($votes);
    }

    public function accuracy(Dataset $data): float {
        $correct = 0;
        for ($i = 0; $i < $data->count(); $i++) {
            if ($this->predict($data->samples[$i]) === $data->labels[$i]) $correct++;
        }
        return $data->count() > 0 ? $correct / $data->count() : 0;
    }
}

// 测试
echo "--- Generate Dataset ---\n";
$data = new Dataset();
mt_srand(42);
// 鸢尾花简化: 3类, 2特征
for ($i = 0; $i < 30; $i++) {
    $type = $i % 3;
    $baseX = [1.0, 4.0, 7.0][$type];
    $baseY = [0.5, 3.0, 5.5][$type];
    $data->add([$baseX + mt_rand(-20, 20) / 10, $baseY + mt_rand(-20, 20) / 10], ['A', 'B', 'C'][$type]);
}
echo "Dataset: {$data->count()} samples, {$data->featureCount} features, " . count($data->getLabels()) . " classes\n";

echo "\n--- Decision Tree ---\n";
$dt = new DecisionTree();
$dt->train($data);
echo "Train accuracy: " . number_format($dt->accuracy($data) * 100, 1) . "%\n";
$testSamples = [[1.2, 0.6], [4.1, 3.2], [7.3, 5.8], [2.5, 2.0]];
foreach ($testSamples as $s) echo "  predict(" . json_encode($s) . ") = " . $dt->predict($s) . "\n";

echo "\n--- Naive Bayes ---\n";
$nb = new NaiveBayes();
$nb->train($data);
echo "Train accuracy: " . number_format($nb->accuracy($data) * 100, 1) . "%\n";
foreach ($testSamples as $s) echo "  predict(" . json_encode($s) . ") = " . $nb->predict($s) . "\n";

echo "\n--- KNN (k=3) ---\n";
$knn = new KNN(3);
$knn->train($data);
echo "Train accuracy: " . number_format($knn->accuracy($data) * 100, 1) . "%\n";
foreach ($testSamples as $s) echo "  predict(" . json_encode($s) . ") = " . $knn->predict($s) . "\n";

echo "\n--- KNN with different k ---\n";
foreach ([1, 3, 5, 7] as $k) {
    $knn = new KNN($k);
    $knn->train($data);
    echo "  k=$k: accuracy=" . number_format($knn->accuracy($data) * 100, 1) . "%\n";
}

echo "\n--- Model Comparison ---\n";
$models = ['DecisionTree' => $dt, 'NaiveBayes' => $nb];
foreach ([1, 3, 5] as $k) $models["KNN(k=$k)"] = new KNN($k);
$models["KNN(k=$k)"]->train($data);
foreach ($models as $name => $model) {
    if ($name !== 'DecisionTree' && $name !== 'NaiveBayes') $model->train($data);
    echo "  $name: " . number_format($model->accuracy($data) * 100, 1) . "%\n";
}

echo "=== f115 Done ===\n";
