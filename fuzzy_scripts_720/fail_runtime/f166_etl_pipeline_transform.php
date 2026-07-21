<?php
// ETL 数据管道：提取、转换、加载、验证、过滤
echo "=== f166: ETL Pipeline + Transform + Validate ===\n";

// 数据源
class DataSource {
    public static function users(): array {
        return [
            ['id' => 1, 'name' => 'alice', 'email' => 'alice@test.com', 'age' => '30', 'dept' => 'eng', 'salary' => '50000'],
            ['id' => 2, 'name' => 'bob', 'email' => 'bob@test.com', 'age' => '25', 'dept' => 'sales', 'salary' => '45000'],
            ['id' => 3, 'name' => 'charlie', 'email' => 'invalid', 'age' => '35', 'dept' => 'eng', 'salary' => '60000'],
            ['id' => 4, 'name' => 'diana', 'email' => 'diana@test.com', 'age' => '-5', 'dept' => 'marketing', 'salary' => '55000'],
            ['id' => 5, 'name' => 'eve', 'email' => 'eve@test.com', 'age' => '32', 'dept' => 'eng', 'salary' => '70000'],
            ['id' => 6, 'name' => '', 'email' => 'frank@test.com', 'age' => '40', 'dept' => 'sales', 'salary' => '48000'],
            ['id' => 7, 'name' => 'grace', 'email' => 'grace@test.com', 'age' => '28', 'dept' => 'eng', 'salary' => '65000'],
            ['id' => 8, 'name' => 'henry', 'email' => 'henry@test.com', 'age' => '45', 'dept' => '', 'salary' => '0'],
        ];
    }

    public static function orders(): array {
        return [
            ['order_id' => 1001, 'user_id' => 1, 'product' => 'Laptop', 'qty' => 1, 'price' => 999.99, 'status' => 'completed'],
            ['order_id' => 1002, 'user_id' => 2, 'product' => 'Mouse', 'qty' => 2, 'price' => 25.50, 'status' => 'pending'],
            ['order_id' => 1003, 'user_id' => 1, 'product' => 'Keyboard', 'qty' => 1, 'price' => 75.00, 'status' => 'completed'],
            ['order_id' => 1004, 'user_id' => 3, 'product' => 'Monitor', 'qty' => 1, 'price' => 350.00, 'status' => 'cancelled'],
            ['order_id' => 1005, 'user_id' => 5, 'product' => 'Headphones', 'qty' => 3, 'price' => 99.99, 'status' => 'completed'],
            ['order_id' => 1006, 'user_id' => 7, 'product' => 'Webcam', 'qty' => 2, 'price' => 45.00, 'status' => 'completed'],
        ];
    }
}

// ETL 管道
class Pipeline {
    private array $steps = [];
    private array $errors = [];
    private array $stats = ['input' => 0, 'output' => 0, 'errors' => 0];

    public function addStep(callable $step, string $name = ''): self {
        $this->steps[] = ['fn' => $step, 'name' => $name];
        return $this;
    }

    public function process(array $data): array {
        $this->stats['input'] = count($data);
        $current = $data;

        foreach ($this->steps as $step) {
            $result = [];
            foreach ($current as $item) {
                try {
                    $processed = ($step['fn'])($item);
                    if ($processed !== null) {
                        $result[] = $processed;
                    }
                } catch (Exception $e) {
                    $this->errors[] = [
                        'step' => $step['name'],
                        'item' => $item,
                        'error' => $e->getMessage(),
                    ];
                    $this->stats['errors']++;
                }
            }
            $current = $result;
        }

        $this->stats['output'] = count($current);
        return $current;
    }

    public function getErrors(): array { return $this->errors; }
    public function getStats(): array { return $this->stats; }
}

// 转换函数
$transforms = [
    'normalizeName' => fn($row) => array_merge($row, ['name' => ucfirst(trim($row['name']))]),
    'validateEmail' => function($row) {
        if (!filter_var($row['email'], FILTER_VALIDATE_EMAIL)) {
            throw new Exception("Invalid email: {$row['email']}");
        }
        return $row;
    },
    'validateAge' => function($row) {
        $age = (int)$row['age'];
        if ($age < 0 || $age > 150) {
            throw new Exception("Invalid age: {$row['age']}");
        }
        return array_merge($row, ['age' => $age]);
    },
    'validateName' => function($row) {
        if (empty(trim($row['name']))) {
            throw new Exception("Empty name");
        }
        return $row;
    },
    'validateDept' => function($row) {
        if (empty($row['dept'])) {
            $row['dept'] = 'unassigned';
        }
        return $row;
    },
    'castSalary' => function($row) {
        $salary = (float)$row['salary'];
        if ($salary <= 0) {
            $row['salary'] = 0.0;
            $row['salary_warning'] = true;
        } else {
            $row['salary'] = $salary;
            $row['salary_warning'] = false;
        }
        return $row;
    },
    'addComputedFields' => function($row) {
        $row['annual_salary'] = $row['salary'] * 12;
        $row['name_upper'] = strtoupper($row['name']);
        $row['domain'] = explode('@', $row['email'])[1] ?? 'unknown';
        return $row;
    },
];

// 测试
echo "--- ETL Pipeline: User Data ---\n";
$pipeline = new Pipeline();
$pipeline
    ->addStep($transforms['validateName'], 'validate_name')
    ->addStep($transforms['normalizeName'], 'normalize_name')
    ->addStep($transforms['validateEmail'], 'validate_email')
    ->addStep($transforms['validateAge'], 'validate_age')
    ->addStep($transforms['validateDept'], 'validate_dept')
    ->addStep($transforms['castSalary'], 'cast_salary')
    ->addStep($transforms['addComputedFields'], 'add_computed');

$cleanData = $pipeline->process(DataSource::users());

echo "  Input: {$pipeline->getStats()['input']} records\n";
echo "  Output: {$pipeline->getStats()['output']} records\n";
echo "  Errors: {$pipeline->getStats()['errors']}\n";

echo "\n  Clean records:\n";
foreach ($cleanData as $row) {
    $warning = $row['salary_warning'] ? ' [WARN: zero salary]' : '';
    echo "    {$row['name']} ({$row['age']}) - {$row['email']} - {$row['dept']} - \${$row['salary']}/mo = \${$row['annual_salary']}/yr$warning\n";
}

echo "\n  Errors:\n";
foreach ($pipeline->getErrors() as $error) {
    echo "    [{$error['step']}] {$error['error']} (id: " . ($error['item']['id'] ?? '?') . ")\n";
}

echo "\n--- ETL Pipeline: Order Data ---\n";
$orderPipeline = new Pipeline();
$orderPipeline
    ->addStep(function($order) {
        $order['total'] = $order['qty'] * $order['price'];
        return $order;
    }, 'calculate_total')
    ->addStep(function($order) {
        $order['total_formatted'] = '$' . number_format($order['total'], 2);
        return $order;
    }, 'format_total')
    ->addStep(function($order) {
        $order['priority'] = match($order['status']) {
            'completed' => 'normal',
            'pending' => 'high',
            'cancelled' => 'low',
            default => 'unknown',
        };
        return $order;
    }, 'set_priority');

$processedOrders = $orderPipeline->process(DataSource::orders());

echo "  Processed orders:\n";
foreach ($processedOrders as $order) {
    echo "    #{$order['order_id']} user={$order['user_id']} {$order['product']} x{$order['qty']} = {$order['total_formatted']} [{$order['status']}] priority={$order['priority']}\n";
}

echo "\n--- Aggregation ---\n";
$orderByUser = [];
foreach ($processedOrders as $order) {
    $uid = $order['user_id'];
    if (!isset($orderByUser[$uid])) {
        $orderByUser[$uid] = ['count' => 0, 'total' => 0.0, 'products' => []];
    }
    $orderByUser[$uid]['count']++;
    $orderByUser[$uid]['total'] += $order['total'];
    $orderByUser[$uid]['products'][] = $order['product'];
}

echo "  Orders by user:\n";
foreach ($orderByUser as $uid => $data) {
    echo "    User $uid: {$data['count']} orders, \${$data['total']}, products: " . implode(', ', $data['products']) . "\n";
}

$statusCounts = array_count_values(array_map(fn($o) => $o['status'], $processedOrders));
echo "\n  Status counts:\n";
foreach ($statusCounts as $status => $count) {
    echo "    $status: $count\n";
}

$totalRevenue = array_sum(array_map(fn($o) => $o['status'] === 'completed' ? $o['total'] : 0, $processedOrders));
echo "\n  Total revenue (completed): $" . number_format($totalRevenue, 2) . "\n";

echo "=== f166 Done ===\n";
