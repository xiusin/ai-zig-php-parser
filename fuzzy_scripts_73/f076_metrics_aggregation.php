<?php
// f076: 指标聚合 (Metrics Aggregation)
echo "=== Metrics Aggregation ===\n\n";

class Metric {
    public string $name;
    public float $value;
    public int $timestamp;
    public array $tags;

    public function __construct(string $name, float $value, int $timestamp, array $tags = []) {
        $this->name = $name;
        $this->value = $value;
        $this->timestamp = $timestamp;
        $this->tags = $tags;
    }
}

class MetricsAggregator {
    private array $metrics = [];
    private array $counters = [];
    private array $gauges = [];
    private array $histograms = [];

    public function increment(string $name, int $value = 1, array $tags = []): void {
        $key = $this->makeKey($name, $tags);
        if (!isset($this->counters[$key])) {
            $this->counters[$key] = ['name' => $name, 'value' => 0, 'tags' => $tags];
        }
        $this->counters[$key]['value'] += $value;
    }

    public function setGauge(string $name, float $value, array $tags = []): void {
        $key = $this->makeKey($name, $tags);
        $this->gauges[$key] = ['name' => $name, 'value' => $value, 'tags' => $tags];
    }

    public function observe(string $name, float $value, array $tags = []): void {
        $key = $this->makeKey($name, $tags);
        if (!isset($this->histograms[$key])) {
            $this->histograms[$key] = ['name' => $name, 'values' => [], 'tags' => $tags];
        }
        $this->histograms[$key]['values'][] = $value;
    }

    private function makeKey(string $name, array $tags): string {
        ksort($tags);
        $parts = [$name];
        foreach ($tags as $k => $v) {
            $parts[] = "$k=$v";
        }
        return implode('|', $parts);
    }

    public function getCounter(string $name, array $tags = []): int {
        $key = $this->makeKey($name, $tags);
        return $this->counters[$key]['value'] ?? 0;
    }

    public function getGauge(string $name, array $tags = []): float {
        $key = $this->makeKey($name, $tags);
        return $this->gauges[$key]['value'] ?? 0.0;
    }

    public function getHistogramStats(string $name, array $tags = []): array {
        $key = $this->makeKey($name, $tags);
        if (!isset($this->histograms[$key])) {
            return ['count' => 0, 'sum' => 0, 'avg' => 0, 'min' => 0, 'max' => 0, 'p50' => 0, 'p95' => 0, 'p99' => 0];
        }
        $values = $this->histograms[$key]['values'];
        sort($values);
        $count = count($values);
        $sum = array_sum($values);
        return [
            'count' => $count,
            'sum' => $sum,
            'avg' => $count > 0 ? $sum / $count : 0,
            'min' => $values[0],
            'max' => $values[$count - 1],
            'p50' => $this->percentile($values, 0.50),
            'p95' => $this->percentile($values, 0.95),
            'p99' => $this->percentile($values, 0.99),
        ];
    }

    private function percentile(array $sorted, float $p): float {
        $n = count($sorted);
        if ($n === 0) return 0;
        $idx = (int)ceil($p * $n) - 1;
        $idx = max(0, min($idx, $n - 1));
        return $sorted[$idx];
    }

    public function snapshot(): array {
        $result = ['counters' => [], 'gauges' => [], 'histograms' => []];
        foreach ($this->counters as $entry) {
            $result['counters'][] = $entry;
        }
        foreach ($this->gauges as $entry) {
            $result['gauges'][] = $entry;
        }
        foreach ($this->histograms as $entry) {
            $stats = $this->getHistogramStats($entry['name'], $entry['tags']);
            $result['histograms'][] = [
                'name' => $entry['name'],
                'tags' => $entry['tags'],
                'stats' => $stats,
            ];
        }
        return $result;
    }
}

// 测试
$agg = new MetricsAggregator();

echo "--- Counters ---\n";
$agg->increment('requests');
$agg->increment('requests');
$agg->increment('requests', 3);
$agg->increment('errors', 1, ['type' => '500']);
$agg->increment('errors', 2, ['type' => '404']);
$agg->increment('errors', 1, ['type' => '500']);

echo "requests: " . $agg->getCounter('requests') . "\n";
echo "errors[type=500]: " . $agg->getCounter('errors', ['type' => '500']) . "\n";
echo "errors[type=404]: " . $agg->getCounter('errors', ['type' => '404']) . "\n";

echo "\n--- Gauges ---\n";
$agg->setGauge('temperature', 23.5, ['room' => 'server']);
$agg->setGauge('temperature', 18.2, ['room' => 'office']);
$agg->setGauge('memory_usage', 65.8);
$agg->setGauge('temperature', 24.1, ['room' => 'server']);

echo "temperature[room=server]: " . $agg->getGauge('temperature', ['room' => 'server']) . "\n";
echo "temperature[room=office]: " . $agg->getGauge('temperature', ['room' => 'office']) . "\n";
echo "memory_usage: " . $agg->getGauge('memory_usage') . "\n";

echo "\n--- Histograms ---\n";
$latencies = [12.5, 15.3, 18.7, 22.1, 25.6, 30.2, 35.8, 42.1, 55.3, 68.7,
              12.8, 14.2, 19.5, 23.4, 28.9, 33.1, 38.5, 45.2, 58.6, 72.3];
foreach ($latencies as $lat) {
    $agg->observe('response_time', $lat);
}

$stats = $agg->getHistogramStats('response_time');
echo "Response time stats:\n";
echo "  count: {$stats['count']}\n";
printf("  sum: %.1f\n", $stats['sum']);
printf("  avg: %.2f\n", $stats['avg']);
printf("  min: %.1f\n", $stats['min']);
printf("  max: %.1f\n", $stats['max']);
printf("  p50: %.1f\n", $stats['p50']);
printf("  p95: %.1f\n", $stats['p95']);
printf("  p99: %.1f\n", $stats['p99']);

echo "\n--- Snapshot ---\n";
$snap = $agg->snapshot();
echo "Counters: " . count($snap['counters']) . "\n";
echo "Gauges: " . count($snap['gauges']) . "\n";
echo "Histograms: " . count($snap['histograms']) . "\n";
foreach ($snap['counters'] as $c) {
    $tagStr = '';
    foreach ($c['tags'] as $k => $v) $tagStr .= " $k=$v";
    echo "  {$c['name']}$tagStr = {$c['value']}\n";
}
