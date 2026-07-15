<?php
// 极度混搭: 指标收集 + 直方图 + 分位数 + 滑动窗口 + 统计聚合
echo "=== c045: MetricsCollect + Histogram + Quantile + SlidingWindow ===\n\n";

class Metric {
    public string $name;
    public array $values = [];
    public int $count = 0;
    public float $sum = 0;
    public float $min = 999999.0;
    public float $max = -999999.0;

    public function __construct(string $name) {
        $this->name = $name;
    }

    public function record(float $value): void {
        $this->values[] = $value;
        $this->count++;
        $this->sum += $value;
        if ($value < $this->min) $this->min = $value;
        if ($value > $this->max) $this->max = $value;
    }

    public function mean(): float {
        return $this->count > 0 ? $this->sum / $this->count : 0;
    }

    public function variance(): float {
        if ($this->count < 2) return 0;
        $m = $this->mean();
        $sumSq = 0;
        foreach ($this->values as $v) {
            $sumSq += ($v - $m) ** 2;
        }
        return $sumSq / ($this->count - 1);
    }

    public function stdDev(): float {
        return sqrt($this->variance());
    }

    public function median(): float {
        $sorted = $this->values;
        sort($sorted);
        $n = count($sorted);
        if ($n == 0) return 0;
        if ($n % 2 == 0) {
            return ($sorted[$n / 2 - 1] + $sorted[$n / 2]) / 2;
        }
        return $sorted[intdiv($n, 2)];
    }

    public function percentile(float $p): float {
        $sorted = $this->values;
        sort($sorted);
        $n = count($sorted);
        if ($n == 0) return 0;
        $index = ($p / 100) * ($n - 1);
        $lower = (int)floor($index);
        $upper = (int)ceil($index);
        if ($lower == $upper) return $sorted[$lower];
        $weight = $index - $lower;
        return $sorted[$lower] * (1 - $weight) + $sorted[$upper] * $weight;
    }

    public function summary(): array {
        return [
            'name' => $this->name,
            'count' => $this->count,
            'sum' => round($this->sum, 2),
            'min' => $this->count > 0 ? $this->min : 0,
            'max' => $this->count > 0 ? $this->max : 0,
            'mean' => round($this->mean(), 2),
            'median' => round($this->median(), 2),
            'stdDev' => round($this->stdDev(), 2),
            'p25' => round($this->percentile(25), 2),
            'p50' => round($this->percentile(50), 2),
            'p75' => round($this->percentile(75), 2),
            'p90' => round($this->percentile(90), 2),
            'p95' => round($this->percentile(95), 2),
            'p99' => round($this->percentile(99), 2),
        ];
    }
}

class Histogram {
    private array $buckets = [];
    private array $counts = [];
    private string $name;

    public function __construct(string $name, array $boundaries) {
        $this->name = $name;
        sort($boundaries);
        $this->buckets = $boundaries;
        $this->counts = array_fill(0, count($boundaries) + 1, 0);
    }

    public function observe(float $value): void {
        for ($i = 0; $i < count($this->buckets); $i++) {
            if ($value <= $this->buckets[$i]) {
                $this->counts[$i]++;
                return;
            }
        }
        $this->counts[count($this->buckets)]++;
    }

    public function getCumulative(): array {
        $result = [];
        $cumulative = 0;
        for ($i = 0; $i < count($this->buckets); $i++) {
            $cumulative += $this->counts[$i];
            $result[] = ['bucket' => $this->buckets[$i], 'count' => $this->counts[$i], 'cumulative' => $cumulative];
        }
        $cumulative += $this->counts[count($this->buckets)];
        $result[] = ['bucket' => 'inf', 'count' => $this->counts[count($this->buckets)], 'cumulative' => $cumulative];
        return $result;
    }

    public function getTotal(): int {
        return array_sum($this->counts);
    }
}

class SlidingWindowMetric {
    private int $windowSize;
    private array $data = [];
    private string $name;

    public function __construct(string $name, int $windowSize = 60) {
        $this->name = $name;
        $this->windowSize = $windowSize;
    }

    public function add(int $timestamp, float $value): void {
        $this->data[] = ['ts' => $timestamp, 'val' => $value];
        $this->cleanup($timestamp);
    }

    private function cleanup(int $now): void {
        $threshold = $now - $this->windowSize;
        $this->data = array_values(array_filter($this->data, fn($d) => $d['ts'] > $threshold));
    }

    public function getRate(int $now): float {
        $this->cleanup($now);
        return count($this->data);
    }

    public function getAvg(int $now): float {
        $this->cleanup($now);
        if (empty($this->data)) return 0;
        $sum = array_sum(array_column($this->data, 'val'));
        return $sum / count($this->data);
    }

    public function getMin(int $now): float {
        $this->cleanup($now);
        if (empty($this->data)) return 0;
        return min(array_column($this->data, 'val'));
    }

    public function getMax(int $now): float {
        $this->cleanup($now);
        if (empty($this->data)) return 0;
        return max(array_column($this->data, 'val'));
    }
}

class MetricsRegistry {
    private array $counters = [];
    private array $gauges = [];
    private array $metrics = [];

    public function incrementCounter(string $name, int $amount = 1): void {
        if (!isset($this->counters[$name])) $this->counters[$name] = 0;
        $this->counters[$name] += $amount;
    }

    public function setGauge(string $name, float $value): void {
        $this->gauges[$name] = $value;
    }

    public function observe(string $name, float $value): void {
        if (!isset($this->metrics[$name])) {
            $this->metrics[$name] = new Metric($name);
        }
        $this->metrics[$name]->record($value);
    }

    public function getCounters(): array {
        return $this->counters;
    }

    public function getGauges(): array {
        return $this->gauges;
    }

    public function getMetricSummary(string $name): ?array {
        return $this->metrics[$name]?->summary();
    }

    public function getAllSummaries(): array {
        $result = [];
        foreach ($this->metrics as $name => $m) {
            $result[$name] = $m->summary();
        }
        return $result;
    }
}

// === 测试 ===

echo "--- Metric Collection ---\n";
$metric = new Metric('response_time');
$values = [12.5, 15.3, 8.7, 22.1, 18.9, 10.2, 25.6, 14.8, 11.3, 19.7,
           16.4, 13.9, 20.5, 9.8, 17.2, 14.1, 12.8, 21.3, 15.7, 10.9];
foreach ($values as $v) $metric->record($v);

echo json_encode($metric->summary(), JSON_PRETTY_PRINT) . "\n";

echo "\n--- Histogram ---\n";
$hist = new Histogram('latency', [10, 15, 20, 25, 30]);
foreach ($values as $v) $hist->observe($v);

echo "Total: " . $hist->getTotal() . "\n";
foreach ($hist->getCumulative() as $b) {
    echo "  <= {$b['bucket']}: count={$b['count']} cumulative={$b['cumulative']}\n";
}

echo "\n--- Sliding Window ---\n";
$sw = new SlidingWindowMetric('requests_per_sec', 10);
for ($t = 1; $t <= 20; $t++) {
    $sw->add($t, $t * 1.5);
}

echo "At t=15: rate=" . $sw->getRate(15) . " avg=" . round($sw->getAvg(15), 2) . "\n";
echo "At t=20: rate=" . $sw->getRate(20) . " avg=" . round($sw->getAvg(20), 2) . "\n";
echo "At t=25: rate=" . $sw->getRate(25) . " avg=" . round($sw->getAvg(25), 2) . "\n";

echo "\n--- Metrics Registry ---\n";
$registry = new MetricsRegistry();
$registry->incrementCounter('http_requests_total');
$registry->incrementCounter('http_requests_total');
$registry->incrementCounter('http_requests_total', 5);
$registry->setGauge('memory_usage_mb', 256.5);
$registry->setGauge('active_connections', 42);

$latencyData = [5.2, 8.1, 12.3, 7.8, 15.6, 9.4, 11.2, 6.7, 13.9, 8.8];
foreach ($latencyData as $v) $registry->observe('http_latency', $v);

echo "Counters: " . json_encode($registry->getCounters()) . "\n";
echo "Gauges: " . json_encode($registry->getGauges()) . "\n";
echo "Latency summary:\n";
foreach ($registry->getMetricSummary('http_latency') as $k => $v) {
    echo "  $k: $v\n";
}

echo "\n=== c045 Done ===\n";
