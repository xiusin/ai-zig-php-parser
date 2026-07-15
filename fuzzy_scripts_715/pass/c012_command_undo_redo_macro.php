<?php
// 极度混搭: 命令模式 + 撤销/重做 + 宏录制 + 异常恢复 + 序列化
echo "=== c012: Command Pattern + Undo/Redo + Macro + Exception Recovery ===\n\n";

interface Command {
    public function execute(): mixed;
    public function undo(): void;
    public function getDescription(): string;
}

class CommandHistory {
    private array $undoStack = [];
    private array $redoStack = [];
    private int $maxSize;

    public function __construct(int $maxSize = 50) {
        $this->maxSize = $maxSize;
    }

    public function push(Command $cmd): mixed {
        try {
            $result = $cmd->execute();
            $this->undoStack[] = $cmd;
            if (count($this->undoStack) > $this->maxSize) {
                array_shift($this->undoStack);
            }
            $this->redoStack = [];
            return $result;
        } catch (Exception $e) {
            echo "  [ERROR] {$cmd->getDescription()}: {$e->getMessage()}\n";
            throw $e;
        }
    }

    public function undo(): bool {
        if (empty($this->undoStack)) return false;
        $cmd = array_pop($this->undoStack);
        $cmd->undo();
        $this->redoStack[] = $cmd;
        return true;
    }

    public function redo(): bool {
        if (empty($this->redoStack)) return false;
        $cmd = array_pop($this->redoStack);
        $cmd->execute();
        $this->undoStack[] = $cmd;
        return true;
    }

    public function canUndo(): bool {
        return !empty($this->undoStack);
    }

    public function canRedo(): bool {
        return !empty($this->redoStack);
    }

    public function getHistory(): array {
        return array_map(fn($c) => $c->getDescription(), $this->undoStack);
    }
}

class TextEditor {
    private string $text = '';
    private CommandHistory $history;

    public function __construct() {
        $this->history = new CommandHistory();
    }

    public function insert(string $text): void {
        $this->history->push(new class($this, $text) implements Command {
            private TextEditor $editor;
            private string $text;
            private int $prevLen;

            public function __construct(TextEditor $editor, string $text) {
                $this->editor = $editor;
                $this->text = $text;
            }

            public function execute(): mixed {
                $this->prevLen = strlen($this->editor->getText());
                $this->editor->appendText($this->text);
                return null;
            }

            public function undo(): void {
                $this->editor->truncateTo($this->prevLen);
            }

            public function getDescription(): string {
                return "insert('$this->text')";
            }
        });
    }

    public function delete(int $len): void {
        $this->history->push(new class($this, $len) implements Command {
            private TextEditor $editor;
            private int $len;
            private string $deleted = '';

            public function __construct(TextEditor $editor, int $len) {
                $this->editor = $editor;
                $this->len = $len;
            }

            public function execute(): mixed {
                $text = $this->editor->getText();
                $this->deleted = substr($text, -$this->len);
                $this->editor->truncateTo(strlen($text) - $this->len);
                return $this->deleted;
            }

            public function undo(): void {
                $this->editor->appendText($this->deleted);
            }

            public function getDescription(): string {
                return "delete($this->len)";
            }
        });
    }

    public function replace(string $from, string $to): void {
        $this->history->push(new class($this, $from, $to) implements Command {
            private TextEditor $editor;
            private string $from;
            private string $to;
            private string $prevText = '';

            public function __construct(TextEditor $editor, string $from, string $to) {
                $this->editor = $editor;
                $this->from = $from;
                $this->to = $to;
            }

            public function execute(): mixed {
                $this->prevText = $this->editor->getText();
                $newText = str_replace($this->from, $this->to, $this->prevText);
                $this->editor->setText($newText);
                return null;
            }

            public function undo(): void {
                $this->editor->setText($this->prevText);
            }

            public function getDescription(): string {
                return "replace('$this->from', '$this->to')";
            }
        });
    }

    public function undo(): bool { return $this->history->undo(); }
    public function redo(): bool { return $this->history->redo(); }
    public function canUndo(): bool { return $this->history->canUndo(); }
    public function canRedo(): bool { return $this->history->canRedo(); }
    public function getText(): string { return $this->text; }
    public function getHistory(): array { return $this->history->getHistory(); }

    // Internal methods for command access
    public function appendText(string $t): void { $this->text .= $t; }
    public function truncateTo(int $len): void { $this->text = substr($this->text, 0, $len); }
    public function setText(string $t): void { $this->text = $t; }
}

class MacroCommand implements Command {
    private array $commands = [];
    private string $description;

    public function __construct(string $description) {
        $this->description = $description;
    }

    public function add(Command $cmd): self {
        $this->commands[] = $cmd;
        return $this;
    }

    public function execute(): mixed {
        $results = [];
        foreach ($this->commands as $cmd) {
            $results[] = $cmd->execute();
        }
        return $results;
    }

    public function undo(): void {
        $reversed = array_reverse($this->commands);
        foreach ($reversed as $cmd) {
            $cmd->undo();
        }
    }

    public function getDescription(): string {
        return $this->description . " [" . count($this->commands) . " commands]";
    }
}

// === 测试 ===

echo "--- Basic Edit Operations ---\n";
$editor = new TextEditor();
$editor->insert("Hello");
$editor->insert(" World");
echo "Text: " . $editor->getText() . "\n";
$editor->insert("!");
echo "Text: " . $editor->getText() . "\n";

echo "\n--- Undo/Redo ---\n";
$editor->undo();
echo "After undo: " . $editor->getText() . "\n";
$editor->undo();
echo "After undo: " . $editor->getText() . "\n";
$editor->redo();
echo "After redo: " . $editor->getText() . "\n";

echo "\n--- Delete ---\n";
$editor->insert("!!!");
echo "Text: " . $editor->getText() . "\n";
$editor->delete(3);
echo "After delete 3: " . $editor->getText() . "\n";
$editor->undo();
echo "After undo delete: " . $editor->getText() . "\n";

echo "\n--- Replace ---\n";
$editor->replace("Hello", "Hi");
echo "After replace: " . $editor->getText() . "\n";
$editor->undo();
echo "After undo replace: " . $editor->getText() . "\n";

echo "\n--- History ---\n";
foreach ($editor->getHistory() as $i => $desc) {
    echo "  [$i] $desc\n";
}

echo "\n=== c012 Done ===\n";
