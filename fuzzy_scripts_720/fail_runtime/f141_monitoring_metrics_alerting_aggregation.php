<?php
// 极度混搭: 监控系统 + 指标 + 告警 + 聚合 + Dashboard
echo "=== f141: Monitoring + Metrics + Alerting + Aggregation ===\n";

class Metric {
    public function __construct(public string $name, public float $value, public array $labels = [], public float $timestamp = 0) {
        if ($this->timestamp === 0) $this->timestamp = microtime(true);
    }
}

class MetricStore {
    private array $metrics = [];
    private array $counters = [];
    private array $gauges = [];
    private array $histograms = [];

    public function incrementCounter(string $name, array $labels = [], int $by = 1): void {
        $key = $this->labelKey($name, $labels);
        $this->counters[$key] = ($this->counters[$key] ?? 0) + $by;
    }

    public function setGauge(string $name, float $value, array $labels = []): void {
        $key = $this->labelKey($name, $labels);
        $this->gauges[$key] = $value;
        $this->metrics[] = new Metric($name, $value, $labels);
    }

    public function observeHistogram(string $name, float $value, array $labels = []): void {
        $key = $this->labelKey($name, $labels);
        if (!isset($this->histograms[$key])) $this->histograms[$key] = ['count' => 0, 'sum' => 0, 'buckets' => []];
        $this->histograms[$key]['count']++;
        $this->histograms[$key]['sum'] += $value;
        $bucket = $this->getBucket($value);
        $this->histograms[$key]['buckets'][$bucket] = ($this->histograms[$key]['buckets'][$bucket] ?? 0) + 1;
    }

    private function getBucket(float $value): string {
        $thresholds = [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10];
        foreach ($thresholds as $t) if ($value <= $t) return "$t";
        return '+Inf';
    }

    private function labelKey(string $name, array $labels): string {
        ksort($labels);
        $parts = [];
        foreach ($labels as $k => $v) $parts[] = "$k=$v";
        return $name . '{' . implode(',', $parts) . '}';
    }

    public function getCounter(string $name, array $labels = []): int { return $this->counters[$this->labelKey($name, $labels)] ?? 0; }
    public function getGauge(string $name, array $labels = []): float { return $this->gauges[$this->labelKey($name, $labels)] ?? 0; }
    public function getHistogram(string $name, array $labels = []): ?array { return $this->histograms[$this->labelKey($name, $labels)] ?? null; }
    public function getAllMetrics(): array { return $this->metrics; }
    public function getCounters(): array { return $this->counters; }
    public function getGauges(): array { return $this->gauges; }
    public function getHistograms(): array { return $this->histograms; }
}

class Alert {
    public function __construct(public string $name, public string $condition, public float $threshold, public string $severity = 'warning') {}
}

class AlertManager {
    private array $alerts = [];
    private array $triggered = [];
    private array $history = [];

    public function addAlert(Alert $alert): void { $this->alerts[$alert->name] = $alert; }

    public function evaluate(MetricStore $store): array {
        $fired = [];
        foreach ($this->alerts as $alert) {
            $value = $this->extractValue($store, $alert);
            $triggered = $this->compare($value, $alert->condition, $alert->threshold);
            if ($triggered) {
                if (!isset($this->triggered[$alert->name])) {
                    $this->triggered[$alert->name] = ['since' => microtime(true), 'value' => $value, 'severity' => $alert->severity];
                    $fired[] = ['alert' => $alert->name, 'value' => $value, 'threshold' => $alert->threshold, 'severity' => $alert->severity];
                    $this->history[] = ['alert' => $alert->name, 'value' => $value, 'timestamp' => microtime(true), 'action' => 'fired'];
                } else {
                    $this->triggered[$alert->name]['value'] = $value;
                }
            } else {
                if (isset($this->triggered[$alert->name])) {
                    unset($this->triggered[$alert->name]);
                    $this->history[] = ['alert' => $alert->name, 'timestamp' => microtime(true), 'action' => 'resolved'];
                }
            }
        }
        return $fired;
    }

    private function extractValue(MetricStore $store, Alert $alert): float {
        $parts = explode(':', $alert->name);
        $metricName = $parts[0];
        $type = $parts[1] ?? 'gauge';
        return match($type) {
            'counter' => $store->getCounter($metricName),
            'gauge' => $store->getGauge($metricName),
            default => $store->getGauge($metricName),
        };
    }

    private function compare(float $value, string $op, float $threshold): bool {
        return match($op) {
            '>' => $value > $threshold,
            '<' => $value < $threshold,
            '>=' => $value >= $threshold,
            '<=' => $value <= $threshold,
            '==' => $value == $threshold,
            default => false,
        };
    }

    public function getActiveAlerts(): array { return $this->triggered; }
    public function getHistory(): array { return $this->history; }
}

class MetricAggregator {
    public static function rate(array $metrics, string $name, float $window = 60): float {
        $now = microtime(true);
        $recent = array_filter($metrics, fn($m) => $m->name === $name && $m->timestamp > $now - $window);
        return count($recent) / $window;
    }

    public static function average(array $metrics, string $name): float {
        $filtered = array_filter($metrics, fn($m) => $m->name === $name);
        if (empty($filtered)) return 0;
        return array_sum(array_map(fn($m) => $m->value, $filtered)) / count($filtered);
    }

    public static function percentile(array $metrics, string $name, float $p): float {
        $filtered = array_values(array_filter($metrics, fn($m) => $m->name === $name));
        if (empty($filtered)) return 0;
        usort($filtered, fn($a, $b) => $a->value <=> $b->value);
        $idx = (int)(count($filtered) * $p / 100);
        return $filtered[min($idx, count($filtered) - 1)]->value;
    }

    public static function sum(array $metrics, string $name): float {
        return array_sum(array_map(fn($m) => $m->value, array_filter($metrics, fn($m) => $m->name === $name)));
    }

    public static function max(array $metrics, string $name): float {
        $filtered = array_filter($metrics, fn($m) => $m->name === $name);
        if (empty($filtered)) return 0;
        return max(array_map(fn($m) => $m->value, $filtered));
    }

    public static function min(array $metrics, string $name): float {
        $filtered = array_filter($metrics, fn($m) => $m->name === $name);
        if (empty($filtered)) return 0;
        return min(array_map(fn($m) => $m->value, $filtered));
    }
}

class Dashboard {
    private MetricStore $store;
    private AlertManager $alerts;

    public function __construct(MetricStore $store, AlertManager $alerts) {
        $this->store = $store;
        $this->alerts = $alerts;
    }

    public function render(): string {
        $output = "=== Dashboard ===\n";
        $output .= "Counters:\n";
        foreach ($this->store->getCounters() as $key => $value) {
            $output .= "  $key = $value\n";
        }
        $output .= "\nGauges:\n";
        foreach ($this->store->getGauges() as $key => $value) {
            $output .= "  $key = " . number_format($value, 2) . "\n";
        }
        $output .= "\nHistograms:\n";
        foreach ($this->store->getHistograms() as $key => $h) {
            $avg = $h['count'] > 0 ? $h['sum'] / $h['count'] : 0;
            $output .= "  $key: count={$h['count']} avg=" . number_format($avg, 4) . "s\n";
        }
        $active = $this->alerts->getActiveAlerts();
        $output .= "\nActive Alerts: " . count($active) . "\n";
        foreach ($active as $name => $info) {
            $output .= "  [$info[severity]] $name: value=" . number_format($info['value'], 2) . "\n";
        }
        return $output;
    }
}

// 测试
echo "--- Setup Monitoring ---\n";
$store = new MetricStore();
$alertMgr = new AlertManager();

$alertMgr->addAlert(new Alert('cpu_usage:gauge', '>', 80, 'critical'));
$alertMgr->addAlert(new Alert('memory_usage:gauge', '>', 90, 'critical'));
$alertMgr->addAlert(new Alert('error_rate:counter', '>', 100, 'warning'));
$alertMgr->addAlert(new Alert('queue_depth:gauge', '>', 1000, 'warning'));

echo "\n--- Simulate Metrics ---\n";
$scenarios = [
    ['cpu' => 50, 'memory' => 60, 'errors' => 10, 'queue' => 100],
    ['cpu' => 75, 'memory' => 80, 'errors' => 50, 'queue' => 500],
    ['cpu' => 85, 'memory' => 92, 'errors' => 120, 'queue' => 1500],
    ['cpu' => 70, 'memory' => 75, 'errors' => 30, 'queue' => 200],
    ['cpu' => 60, 'memory' => 65, 'errors' => 5, 'queue' => 50],
];

foreach ($scenarios as $i => $s) {
    echo "\n--- Scenario " . ($i + 1) . " ---\n";
    $store->setGauge('cpu_usage', $s['cpu'], ['host' => 'server1']);
    $store->setGauge('memory_usage', $s['memory'], ['host' => 'server1']);
    $store->incrementCounter('error_rate', ['service' => 'api'], $s['errors']);
    $store->setGauge('queue_depth', $s['queue'], ['queue' => 'tasks']);
    $store->observeHistogram('request_duration', 0.05 + $i * 0.02, ['endpoint' => '/api/users']);
    $store->observeHistogram('request_duration', 0.1 + $i * 0.03, ['endpoint' => '/api/users']);
    $store->observeHistogram('request_duration', 0.2 + $i * 0.05, ['endpoint' => '/api/orders']);

    $fired = $alertMgr->evaluate($store);
    echo "  CPU: {$s['cpu']}% Mem: {$s['memory']}% Errors: {$s['errors']} Queue: {$s['queue']}\n";
    if (!empty($fired)) {
        echo "  ALERTS FIRED:\n";
        foreach ($fired as $f) echo "    [{$f['severity']}] {$f['alert']}: {$f['value']} > {$f['threshold']}\n";
    } else {
        echo "  No new alerts\n";
    }
    echo "  Active alerts: " . count($alertMgr->getActiveAlerts()) . "\n";
}

echo "\n--- Dashboard ---\n";
$dashboard = new Dashboard($store, $alertMgr);
echo $dashboard->render();

echo "\n--- Metric Aggregation ---\n";
$allMetrics = $store->getAllMetrics();
echo "CPU average: " . number_format(MetricAggregator::average($allMetrics, 'cpu_usage'), 1) . "%\n";
echo "CPU max: " . number_format(MetricAggregator::max($allMetrics, 'cpu_usage'), 1) . "%\n";
echo "CPU min: " . number_format(MetricAggregator::min($allMetrics, 'cpu_usage'), 1) . "%\n";
echo "Memory p95: " . number_format(MetricAggregator::percentile($allMetrics, 'memory_usage', 95), 1) . "%\n";
echo "Queue sum: " . MetricAggregator::sum($allMetrics, 'queue_depth') . "\n";

echo "\n--- Alert History ---\n";
foreach ($alertMgr->getHistory() as $h) {
    echo "  {$h['action']}: {$h['alert']}\n";
}

echo "\n--- Histogram Details ---\n";
foreach ($store->getHistograms() as $key => $h) {
    echo "$key:\n";
    echo "  Count: {$h['count']}\n";
    echo "  Sum: " . number_format($h['sum'], 4) . "s\n";
    echo "  Avg: " . number_format($h['sum'] / $h['count'], 4) . "s\n";
    echo "  Buckets:\n";
    foreach ($h['buckets'] as $bucket => $count) {
        $bar = str_repeat('█', $count);
        echo "    $bucket: $count $bar\n";
    }
}

echo "=== f141 Done ===\n";
