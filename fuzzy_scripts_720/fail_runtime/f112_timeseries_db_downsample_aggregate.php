<?php
// 极度混搭: 时序数据库 + 写入 + 查询 + 降采样 + 聚合
echo "=== f112: TimeSeries DB + Write + Query + Downsampling ===\n";

class TimeSeriesPoint {
    public function __construct(public int $timestamp, public float $value, public array $tags = []) {}
}

class TimeSeries {
    private array $points = [];
    private array $tagIndex = []; // tag_value => [indices]

    public function write(TimeSeriesPoint $point): void {
        $this->points[] = $point;
        foreach ($point->tags as $key => $value) {
            $tagKey = "$key=$value";
            if (!isset($this->tagIndex[$tagKey])) $this->tagIndex[$tagKey] = [];
            $this->tagIndex[$tagKey][] = count($this->points) - 1;
        }
    }

    public function writeBatch(array $points): void {
        foreach ($points as $p) $this->write($p);
    }

    public function query(int $start, int $end, array $tagFilters = []): array {
        $result = [];
        foreach ($this->points as $p) {
            if ($p->timestamp < $start || $p->timestamp > $end) continue;
            $match = true;
            foreach ($tagFilters as $key => $value) {
                if (!isset($p->tags[$key]) || $p->tags[$key] !== $value) { $match = false; break; }
            }
            if ($match) $result[] = $p;
        }
        return $result;
    }

    public function aggregate(int $start, int $end, string $func, int $interval = 60, array $tagFilters = []): array {
        $points = $this->query($start, $end, $tagFilters);
        $buckets = [];
        foreach ($points as $p) {
            $bucket = (int)($p->timestamp / $interval) * $interval;
            if (!isset($buckets[$bucket])) $buckets[$bucket] = [];
            $buckets[$bucket][] = $p->value;
        }
        $result = [];
        foreach ($buckets as $time => $values) {
            $agg = match($func) {
                'avg' => array_sum($values) / count($values),
                'sum' => array_sum($values),
                'min' => min($values),
                'max' => max($values),
                'count' => (float)count($values),
                'first' => $values[0],
                'last' => $values[count($values) - 1],
                'median' => $this->median($values),
                'stddev' => $this->stddev($values),
                default => 0.0,
            };
            $result[] = ['time' => (int)$time, 'value' => round($agg, 4), 'count' => count($values)];
        }
        usort($result, fn($a, $b) => $a['time'] <=> $b['time']);
        return $result;
    }

    private function median(array $values): float {
        sort($values);
        $n = count($values);
        return $n % 2 === 0 ? ($values[$n/2-1] + $values[$n/2]) / 2 : $values[(int)($n/2)];
    }

    private function stddev(array $values): float {
        $mean = array_sum($values) / count($values);
        $variance = array_sum(array_map(fn($v) => ($v - $mean) ** 2, $values)) / count($values);
        return sqrt($variance);
    }

    public function downsample(int $interval, string $func): self {
        $new = new self();
        $buckets = [];
        foreach ($this->points as $p) {
            $bucket = (int)($p->timestamp / $interval) * $interval;
            if (!isset($buckets[$bucket])) $buckets[$bucket] = [];
            $buckets[$bucket][] = $p;
        }
        foreach ($buckets as $time => $pts) {
            $values = array_map(fn($p) => $p->value, $pts);
            $agg = match($func) {
                'avg' => array_sum($values) / count($values),
                'min' => min($values),
                'max' => max($values),
                'sum' => array_sum($values),
                default => array_sum($values) / count($values),
            };
            $new->write(new TimeSeriesPoint($time, $agg, $pts[0]->tags));
        }
        return $new;
    }

    public function getStats(): array {
        $values = array_map(fn($p) => $p->value, $this->points);
        return [
            'count' => count($this->points),
            'min' => empty($values) ? 0 : min($values),
            'max' => empty($values) ? 0 : max($values),
            'avg' => empty($values) ? 0 : array_sum($values) / count($values),
            'tags' => count($this->tagIndex),
        ];
    }

    public function getPoints(): array { return $this->points; }
}

class MetricRegistry {
    private array $series = [];

    public function getSeries(string $name): TimeSeries {
        if (!isset($this->series[$name])) $this->series[$name] = new TimeSeries();
        return $this->series[$name];
    }

    public function record(string $metric, float $value, array $tags = []): void {
        $this->getSeries($metric)->write(new TimeSeriesPoint(time(), $value, $tags));
    }

    public function getAllMetrics(): array { return array_keys($this->series); }
}

// 测试
echo "--- Write Time Series Data ---\n";
$ts = new TimeSeries();
$baseTime = 1000000;
// 写入100个数据点
for ($i = 0; $i < 100; $i++) {
    $value = 50 + sin($i / 10) * 20 + mt_rand(-5, 5);
    $tags = ['host' => $i % 2 === 0 ? 'server1' : 'server2', 'region' => $i < 50 ? 'us' : 'eu'];
    $ts->write(new TimeSeriesPoint($baseTime + $i * 60, $value, $tags));
}
echo "Stats: " . json_encode($ts->getStats()) . "\n";

echo "\n--- Query Range ---\n";
$results = $ts->query($baseTime, $baseTime + 600, ['host' => 'server1']);
echo "Points from server1 in first 10 min: " . count($results) . "\n";
foreach (array_slice($results, 0, 5) as $p) {
    echo "  t={$p->timestamp} val=" . number_format($p->value, 2) . " tags=" . json_encode($p->tags) . "\n";
}

echo "\n--- Aggregation (avg per 5 min) ---\n";
$agg = $ts->aggregate($baseTime, $baseTime + 600, 'avg', 300);
foreach ($agg as $a) {
    echo "  t={$a['time']} avg=" . $a['value'] . " count={$a['count']}\n";
}

echo "\n--- Aggregation (max per 5 min) ---\n";
$aggMax = $ts->aggregate($baseTime, $baseTime + 600, 'max', 300);
foreach ($aggMax as $a) echo "  t={$a['time']} max={$a['value']} count={$a['count']}\n";

echo "\n--- Aggregation (median per 10 min) ---\n";
$aggMed = $ts->aggregate($baseTime, $baseTime + 1200, 'median', 600);
foreach ($aggMed as $a) echo "  t={$a['time']} median={$a['value']} count={$a['count']}\n";

echo "\n--- Aggregation (stddev per 10 min) ---\n";
$aggStd = $ts->aggregate($baseTime, $baseTime + 1200, 'stddev', 600);
foreach ($aggStd as $a) echo "  t={$a['time']} stddev={$a['value']} count={$a['count']}\n";

echo "\n--- Downsampling ---\n";
$downsampled = $ts->downsample(600, 'avg'); // 10分钟降采样
echo "Original points: " . count($ts->getPoints()) . "\n";
echo "Downsampled points: " . count($downsampled->getPoints()) . "\n";
echo "Downsampled stats: " . json_encode($downsampled->getStats()) . "\n";
foreach (array_slice($downsampled->getPoints(), 0, 5) as $p) {
    echo "  t={$p->timestamp} val=" . number_format($p->value, 2) . "\n";
}

echo "\n--- Tag-based Query ---\n";
$server1Data = $ts->query($baseTime, $baseTime + 6000, ['host' => 'server1', 'region' => 'us']);
echo "server1 + us data: " . count($server1Data) . " points\n";
$server2Data = $ts->query($baseTime, $baseTime + 6000, ['host' => 'server2']);
echo "server2 data: " . count($server2Data) . " points\n";

echo "\n--- Metric Registry ---\n";
$registry = new MetricRegistry();
$registry->record('cpu.usage', 45.5, ['host' => 'web1']);
$registry->record('cpu.usage', 52.3, ['host' => 'web1']);
$registry->record('cpu.usage', 38.1, ['host' => 'web2']);
$registry->record('memory.usage', 72.0, ['host' => 'web1']);
$registry->record('memory.usage', 68.5, ['host' => 'web2']);
$registry->record('requests.rate', 1500, ['endpoint' => '/api']);

echo "Metrics: " . implode(', ', $registry->getAllMetrics()) . "\n";
foreach ($registry->getAllMetrics() as $metric) {
    echo "  $metric: " . json_encode($registry->getSeries($metric)->getStats()) . "\n";
}

echo "=== f112 Done ===\n";
