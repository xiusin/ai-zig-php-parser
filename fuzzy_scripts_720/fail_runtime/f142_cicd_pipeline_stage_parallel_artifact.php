<?php
// 极度混搭: CI/CD + 流水线 + 阶段 + 并行 + 产物
echo "=== f142: CICD + Pipeline + Stage + Parallel + Artifact ===\n";

class PipelineStep {
    public string $status = 'pending';
    public float $duration = 0;
    public ?string $output = null;
    public array $artifacts = [];

    public function __construct(public string $name, public $command, public array $dependsOn = []) {}
}

class PipelineStage {
    public array $steps = [];
    public string $status = 'pending';
    public float $startTime = 0;
    public float $endTime = 0;

    public function __construct(public string $name, public bool $parallel = false) {}

    public function addStep(PipelineStep $step): self { $this->steps[$step->name] = $step; return $this; }

    public function execute(): bool {
        $this->status = 'running';
        $this->startTime = microtime(true);
        $allSuccess = true;

        if ($this->parallel) {
            // 模拟并行执行
            $results = [];
            foreach ($this->steps as $step) {
                $step->status = 'running';
                $start = microtime(true);
                try {
                    $cmd = $step->command;
                    $result = is_callable($cmd) ? $cmd() : true;
                    $step->status = $result ? 'success' : 'failed';
                    $step->output = $result ? 'OK' : 'FAILED';
                    if (!$result) $allSuccess = false;
                    $step->duration = microtime(true) - $start;
                } catch (Exception $e) {
                    $step->status = 'failed';
                    $step->output = $e->getMessage();
                    $step->duration = microtime(true) - $start;
                    $allSuccess = false;
                }
            }
        } else {
            foreach ($this->steps as $step) {
                $step->status = 'running';
                $start = microtime(true);
                try {
                    $cmd = $step->command;
                    $result = is_callable($cmd) ? $cmd() : true;
                    $step->status = $result ? 'success' : 'failed';
                    $step->output = $result ? 'OK' : 'FAILED';
                    if (!$result) { $allSuccess = false; break; }
                    $step->duration = microtime(true) - $start;
                } catch (Exception $e) {
                    $step->status = 'failed';
                    $step->output = $e->getMessage();
                    $step->duration = microtime(true) - $start;
                    $allSuccess = false;
                    break;
                }
            }
        }

        $this->endTime = microtime(true);
        $this->status = $allSuccess ? 'success' : 'failed';
        return $allSuccess;
    }

    public function getDuration(): float { return $this->endTime - $this->startTime; }
}

class Pipeline {
    public array $stages = [];
    public string $status = 'pending';
    public array $artifacts = [];
    public array $env = [];
    public float $startTime = 0;
    public float $endTime = 0;

    public function __construct(public string $name, public string $trigger = 'push') {}

    public function addStage(PipelineStage $stage): self { $this->stages[$stage->name] = $stage; return $this; }
    public function setEnv(string $key, string $value): self { $this->env[$key] = $value; return $this; }

    public function run(): bool {
        $this->status = 'running';
        $this->startTime = microtime(true);
        echo "Pipeline '{$this->name}' started (trigger: {$this->trigger})\n";

        foreach ($this->stages as $stage) {
            echo "\n--- Stage: {$stage->name} ---\n";
            $success = $stage->execute();
            foreach ($stage->steps as $step) {
                $icon = match($step->status) {
                    'success' => '✓', 'failed' => '✗', 'running' => '→', default => '○'
                };
                echo "  $icon {$step->name} (" . number_format($step->duration * 1000, 0) . "ms): {$step->output}\n";
            }
            if (!$success) {
                $this->status = 'failed';
                $this->endTime = microtime(true);
                echo "\nPipeline FAILED at stage '{$stage->name}'\n";
                return false;
            }
        }

        $this->status = 'success';
        $this->endTime = microtime(true);
        echo "\nPipeline '{$this->name}' completed successfully in " . number_format(($this->endTime - $this->startTime) * 1000, 0) . "ms\n";
        return true;
    }

    public function getDuration(): float { return $this->endTime - $this->startTime; }
    public function getStatus(): string { return $this->status; }
}

class ArtifactManager {
    private array $artifacts = [];

    public function store(string $name, string $content, array $metadata = []): void {
        $this->artifacts[$name] = ['content' => $content, 'size' => strlen($content), 'metadata' => $metadata, 'timestamp' => microtime(true)];
    }

    public function get(string $name): ?array { return $this->artifacts[$name] ?? null; }
    public function list(): array { return array_keys($this->artifacts); }
    public function totalSize(): int { return array_sum(array_map(fn($a) => $a['size'], $this->artifacts)); }
}

class PipelineReport {
    public static function generate(Pipeline $pipeline): string {
        $report = "=== Pipeline Report ===\n";
        $report .= "Name: {$pipeline->name}\n";
        $report .= "Status: {$pipeline->status}\n";
        $report .= "Duration: " . number_format($pipeline->getDuration() * 1000, 0) . "ms\n";
        $report .= "Stages: " . count($pipeline->stages) . "\n\n";

        $totalSteps = 0; $successSteps = 0; $failedSteps = 0;
        foreach ($pipeline->stages as $stage) {
            $report .= "Stage: {$stage->name} [{$stage->status}]\n";
            foreach ($stage->steps as $step) {
                $totalSteps++;
                if ($step->status === 'success') $successSteps++;
                elseif ($step->status === 'failed') $failedSteps++;
                $report .= "  {$step->status}: {$step->name}\n";
            }
            $report .= "\n";
        }
        $report .= "Summary: $successSteps/$totalSteps steps passed";
        if ($failedSteps > 0) $report .= ", $failedSteps failed";
        $report .= "\n";
        return $report;
    }
}

// 测试
echo "--- Build Pipeline ---\n";
$pipeline = new Pipeline('build-deploy', 'push');
$pipeline->setEnv('NODE_ENV', 'production');
$pipeline->setEnv('DOCKER_REGISTRY', 'registry.example.com');

// Stage 1: Checkout & Install
$stage1 = new PipelineStage('checkout');
$stage1->addStep(new PipelineStep('checkout', fn() => true));
$stage1->addStep(new PipelineStep('install-deps', fn() => true));
$pipeline->addStage($stage1);

// Stage 2: Lint & Test (parallel)
$stage2 = new PipelineStage('quality', true);
$stage2->addStep(new PipelineStep('lint', fn() => true));
$stage2->addStep(new PipelineStep('unit-tests', fn() => true));
$stage2->addStep(new PipelineStep('type-check', fn() => true));
$pipeline->addStage($stage2);

// Stage 3: Build
$stage3 = new PipelineStage('build');
$stage3->addStep(new PipelineStep('build-app', fn() => true));
$stage3->addStep(new PipelineStep('build-docker', fn() => true));
$pipeline->addStage($stage3);

// Stage 4: Deploy
$stage4 = new PipelineStage('deploy');
$stage4->addStep(new PipelineStep('deploy-staging', fn() => true));
$stage4->addStep(new PipelineStep('integration-tests', fn() => true));
$stage4->addStep(new PipelineStep('deploy-production', fn() => true));
$pipeline->addStage($stage4);

$pipeline->run();

echo "\n" . PipelineReport::generate($pipeline);

echo "\n--- Pipeline with Failure ---\n";
$pipeline2 = new Pipeline('failing-pipeline', 'manual');
$failStage1 = new PipelineStage('build');
$failStage1->addStep(new PipelineStep('compile', fn() => true));
$failStage1->addStep(new PipelineStep('test', fn() => false)); // Will fail
$failStage1->addStep(new PipelineStep('package', fn() => true));
$pipeline2->addStage($failStage1);

$pipeline2->run();

echo "\n" . PipelineReport::generate($pipeline2);

echo "\n--- Artifact Management ---\n";
$artifacts = new ArtifactManager();
$artifacts->store('app-binary', str_repeat('binary-data-', 100), ['type' => 'executable', 'platform' => 'linux-amd64']);
$artifacts->store('docker-image', str_repeat('layer-', 50), ['type' => 'docker', 'tag' => 'v1.2.3']);
$artifacts->store('test-report', '{"tests": 100, "passed": 98, "failed": 2}', ['type' => 'json', 'format' => 'junit']);

echo "Artifacts:\n";
foreach ($artifacts->list() as $name) {
    $art = $artifacts->get($name);
    echo "  $name: {$art['size']} bytes, type={$art['metadata']['type']}\n";
}
echo "Total size: " . $artifacts->totalSize() . " bytes\n";

echo "\n--- Conditional Pipeline ---\n";
$conditionalPipeline = new Pipeline('conditional', 'pull_request');
$condStage = new PipelineStage('check');
$condStage->addStep(new PipelineStep('validate-pr', fn() => true));
$condStage->addStep(new PipelineStep('check-labels', fn() => true));
$conditionalPipeline->addStage($condStage);

$testStage = new PipelineStage('test', true);
$testStage->addStep(new PipelineStep('unit', fn() => true));
$testStage->addStep(new PipelineStep('integration', fn() => true));
$testStage->addStep(new PipelineStep('e2e', fn() => true));
$conditionalPipeline->addStage($testStage);

$conditionalPipeline->run();
echo "\n" . PipelineReport::generate($conditionalPipeline);

echo "=== f142 Done ===\n";
