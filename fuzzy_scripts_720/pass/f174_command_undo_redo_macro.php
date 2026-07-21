<?php
// 命令模式：命令封装、撤销/重做、宏命令、队列
echo "=== f174: Command Pattern + Undo/Redo + Macro ===\n";

interface Command {
    public function execute(): mixed;
    public function undo(): void;
    public function getName(): string;
}

class CommandHistory {
    private array $executed = [];
    private array $undone = [];
    private int $maxSize = 100;

    public function push(Command $cmd): void {
        $this->executed[] = $cmd;
        $this->undone = []; // 清空重做栈
        if (count($this->executed) > $this->maxSize) {
            array_shift($this->executed);
        }
    }

    public function undo(): ?Command {
        if (empty($this->executed)) return null;
        $cmd = array_pop($this->executed);
        $cmd->undo();
        $this->undone[] = $cmd;
        return $cmd;
    }

    public function redo(): ?Command {
        if (empty($this->undone)) return null;
        $cmd = array_pop($this->undone);
        $cmd->execute();
        $this->executed[] = $cmd;
        return $cmd;
    }

    public function canUndo(): bool { return !empty($this->executed); }
    public function canRedo(): bool { return !empty($this->undone); }
    public function getExecuted(): array { return $this->executed; }
    public function clear(): void { $this->executed = []; $this->undone = []; }
}

// 文本编辑器接收者
class TextEditor {
    private string $text = '';
    private array $lines = [];

    public function insertText(int $pos, string $text): void {
        $this->text = substr($this->text, 0, $pos) . $text . substr($this->text, $pos);
    }

    public function deleteText(int $pos, int $length): string {
        $deleted = substr($this->text, $pos, $length);
        $this->text = substr($this->text, 0, $pos) . substr($this->text, $pos + $length);
        return $deleted;
    }

    public function replaceText(int $pos, int $length, string $newText): string {
        $old = $this->deleteText($pos, $length);
        $this->insertText($pos, $newText);
        return $old;
    }

    public function getText(): string { return $this->text; }
    public function setText(string $text): void { $this->text = $text; }
    public function length(): int { return strlen($this->text); }
}

// 具体命令
class InsertCommand implements Command {
    public function __construct(
        private TextEditor $editor,
        private int $pos,
        private string $text,
    ) {}

    public function execute(): mixed {
        $this->editor->insertText($this->pos, $this->text);
        return null;
    }

    public function undo(): void {
        $this->editor->deleteText($this->pos, strlen($this->text));
    }

    public function getName(): string { return "Insert '$this->text' at $this->pos"; }
}

class DeleteCommand implements Command {
    private string $deleted = '';

    public function __construct(
        private TextEditor $editor,
        private int $pos,
        private int $length,
    ) {}

    public function execute(): mixed {
        $this->deleted = $this->editor->deleteText($this->pos, $this->length);
        return null;
    }

    public function undo(): void {
        $this->editor->insertText($this->pos, $this->deleted);
    }

    public function getName(): string { return "Delete $this->length chars at $this->pos"; }
}

class ReplaceCommand implements Command {
    private string $oldText = '';

    public function __construct(
        private TextEditor $editor,
        private int $pos,
        private int $length,
        private string $newText,
    ) {}

    public function execute(): mixed {
        $this->oldText = $this->editor->replaceText($this->pos, $this->length, $this->newText);
        return null;
    }

    public function undo(): void {
        $this->editor->replaceText($this->pos, strlen($this->newText), $this->oldText);
    }

    public function getName(): string { return "Replace $this->length chars at $this->pos with '$this->newText'"; }
}

// 宏命令
class MacroCommand implements Command {
    private array $commands;
    private string $name;

    public function __construct(string $name, array $commands) {
        $this->name = $name;
        $this->commands = $commands;
    }

    public function execute(): mixed {
        foreach ($this->commands as $cmd) $cmd->execute();
        return null;
    }

    public function undo(): void {
        // 按相反顺序撤销
        foreach (array_reverse($this->commands) as $cmd) $cmd->undo();
    }

    public function getName(): string { return "Macro: $this->name"; }
}

// 测试
echo "--- Text Editor with Undo/Redo ---\n";
$editor = new TextEditor();
$history = new CommandHistory();

$cmd1 = new InsertCommand($editor, 0, 'Hello');
$cmd2 = new InsertCommand($editor, 5, ' World');
$cmd3 = new InsertCommand($editor, 11, '!');

$history->push($cmd1); $cmd1->execute();
echo "  After 'Hello': '{$editor->getText()}'\n";

$history->push($cmd2); $cmd2->execute();
echo "  After ' World': '{$editor->getText()}'\n";

$history->push($cmd3); $cmd3->execute();
echo "  After '!': '{$editor->getText()}'\n";

echo "\n  Undo:\n";
$history->undo();
echo "  After undo: '{$editor->getText()}'\n";
$history->undo();
echo "  After undo: '{$editor->getText()}'\n";

echo "\n  Redo:\n";
$history->redo();
echo "  After redo: '{$editor->getText()}'\n";
$history->redo();
echo "  After redo: '{$editor->getText()}'\n";

echo "\n--- Delete and Replace ---\n";
$delCmd = new DeleteCommand($editor, 5, 6); // Delete " World"
$history->push($delCmd); $delCmd->execute();
echo "  After delete: '{$editor->getText()}'\n";

$repCmd = new ReplaceCommand($editor, 0, 5, 'Hi');
$history->push($repCmd); $repCmd->execute();
echo "  After replace: '{$editor->getText()}'\n";

echo "\n  Undo all:\n";
$history->undo();
echo "  After undo replace: '{$editor->getText()}'\n";
$history->undo();
echo "  After undo delete: '{$editor->getText()}'\n";

echo "\n--- Macro Command ---\n";
$editor->setText('');
$history->clear();

$macro = new MacroCommand('Greeting Setup', [
    new InsertCommand($editor, 0, 'Hello'),
    new InsertCommand($editor, 5, ', '),
    new InsertCommand($editor, 7, 'World'),
    new InsertCommand($editor, 12, '!'),
]);

$history->push($macro);
$macro->execute();
echo "  After macro: '{$editor->getText()}'\n";

$history->undo();
echo "  After macro undo: '{$editor->getText()}'\n";

$history->redo();
echo "  After macro redo: '{$editor->getText()}'\n";

echo "\n--- Command History ---\n";
echo "  Can undo: " . ($history->canUndo() ? 'Y' : 'N') . "\n";
echo "  Can redo: " . ($history->canRedo() ? 'Y' : 'N') . "\n";
echo "  Executed commands:\n";
foreach ($history->getExecuted() as $cmd) {
    echo "    - {$cmd->getName()}\n";
}

echo "=== f174 Done ===\n";
