<?php
// 极度混搭: 模板方法模式 + 算法骨架 + 钩子方法 + 数据处理管道
echo "=== f034: Template Method + Algorithm Skeleton + Hooks ===\n";

abstract class DataProcessor {
    public final function process(array $data): array {
        $data = $this->validate($data);
        $data = $this->transform($data);
        if ($this->shouldEnrich()) {
            $data = $this->enrich($data);
        }
        $data = $this->format($data);
        return $data;
    }

    abstract protected function validate(array $data): array;
    abstract protected function transform(array $data): array;
    abstract protected function format(array $data): array;

    protected function shouldEnrich(): bool { return false; }
    protected function enrich(array $data): array { return $data; }
}

class JsonDataProcessor extends DataProcessor {
    protected function validate(array $data): array {
        $errors = [];
        if (!isset($data['id'])) $errors[] = 'id missing';
        if (!isset($data['name'])) $errors[] = 'name missing';
        if (!empty($errors)) throw new InvalidArgumentException(implode(', ', $errors));
        return $data;
    }

    protected function transform(array $data): array {
        $data['name'] = strtoupper($data['name']);
        $data['processed_at'] = '2025-01-01';
        return $data;
    }

    protected function shouldEnrich(): bool { return true; }

    protected function enrich(array $data): array {
        $data['hash'] = hash('crc32b', $data['id'] . $data['name']);
        $data['metadata'] = ['source' => 'json', 'version' => '1.0'];
        return $data;
    }

    protected function format(array $data): array {
        return ['result' => $data, 'type' => 'json'];
    }
}

class CsvDataProcessor extends DataProcessor {
    protected function validate(array $data): array {
        if (count($data) === 0) throw new InvalidArgumentException('Empty data');
        return $data;
    }

    protected function transform(array $data): array {
        return array_map(fn($row) => array_map('trim', $row), $data);
    }

    protected function format(array $data): array {
        return ['result' => $data, 'type' => 'csv', 'rows' => count($data)];
    }
}

class XmlDataProcessor extends DataProcessor {
    private array $validated = [];

    protected function validate(array $data): array {
        foreach ($data as $key => $value) {
            if (is_string($value)) $this->validated[$key] = $value;
        }
        return $this->validated;
    }

    protected function transform(array $data): array {
        return array_map(fn($v) => '<' . 'val' . '>' . htmlspecialchars($v) . '</' . 'val' . '>', $data);
    }

    protected function format(array $data): array {
        return ['result' => $data, 'type' => 'xml'];
    }
}

// 测试
echo "--- JSON Processor ---\n";
$jsonProc = new JsonDataProcessor();
$result = $jsonProc->process(['id' => '123', 'name' => 'alice', 'extra' => 'data']);
echo json_encode($result) . "\n";

echo "\n--- CSV Processor ---\n";
$csvProc = new CsvDataProcessor();
$result = $csvProc->process([
    ['  alice  ', '  30  ', '  NYC  '],
    ['  bob  ', '  25  ', '  LA  '],
]);
echo json_encode($result) . "\n";

echo "\n--- XML Processor ---\n";
$xmlProc = new XmlDataProcessor();
$result = $xmlProc->process(['name' => 'Alice', 'city' => 'NYC', 'role' => 'admin']);
echo json_encode($result) . "\n";

echo "\n--- Validation Error ---\n";
try {
    $jsonProc->process(['name' => 'test']);
} catch (InvalidArgumentException $e) {
    echo "Caught: " . $e->getMessage() . "\n";
}

echo "=== f034 Done ===\n";
