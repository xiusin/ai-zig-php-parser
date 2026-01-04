<?php
// Composite pattern
interface FileSystemComponent {
    public function getName(): string;
    public function getSize(): int;
    public function add(FileSystemComponent $component): void;
    public function remove(FileSystemComponent $component): void;
    public function getChild($name): ?FileSystemComponent;
    public function display($indent = 0): string;
}

class File implements FileSystemComponent {
    private $name;
    private $size;
    
    public function __construct($name, $size) {
        $this->name = $name;
        $this->size = $size;
    }
    
    public function getName(): string {
        return $this->name;
    }
    
    public function getSize(): int {
        return $this->size;
    }
    
    public function add(FileSystemComponent $component): void {
        throw new RuntimeException("Cannot add to a file");
    }
    
    public function remove(FileSystemComponent $component): void {
        throw new RuntimeException("Cannot remove from a file");
    }
    
    public function getChild($name): ?FileSystemComponent {
        return null;
    }
    
    public function display($indent = 0): string {
        return str_repeat('  ', $indent) . "📄 {$this->name} ({$this->size} bytes)\n";
    }
}

class Directory implements FileSystemComponent {
    private $name;
    private $children = [];
    
    public function __construct($name) {
        $this->name = $name;
    }
    
    public function getName(): string {
        return $this->name;
    }
    
    public function getSize(): int {
        $total = 0;
        foreach ($this->children as $child) {
            $total += $child->getSize();
        }
        return $total;
    }
    
    public function add(FileSystemComponent $component): void {
        $this->children[$component->getName()] = $component;
    }
    
    public function remove(FileSystemComponent $component): void {
        unset($this->children[$component->getName()]);
    }
    
    public function getChild($name): ?FileSystemComponent {
        return $this->children[$name] ?? null;
    }
    
    public function display($indent = 0): string {
        $output = str_repeat('  ', $indent) . "📁 {$this->name}/\n";
        
        foreach ($this->children as $child) {
            $output .= $child->display($indent + 1);
        }
        
        return $output;
    }
}

class FileSystemVisitor {
    public function visit(FileSystemComponent $component): void {
        echo $component->display();
    }
    
    public function traverse(FileSystemComponent $component, int $depth = 0): void {
        echo $component->display($depth);
        
        if ($component instanceof Directory) {
            foreach ($component->getChildNames() as $name) {
                if ($child = $component->getChild($name)) {
                    $this->traverse($child, $depth + 1);
                }
            }
        }
    }
    
    public function calculateTotalSize(FileSystemComponent $component): int {
        return $component->getSize();
    }
    
    public function findByName(FileSystemComponent $component, string $name): ?FileSystemComponent {
        if ($component->getName() === $name) {
            return $component;
        }
        
        if ($component instanceof Directory) {
            foreach ($component->getChildNames() as $childName) {
                if ($child = $component->getChild($childName)) {
                    $result = $this->findByName($child, $name);
                    if ($result) {
                        return $result;
                    }
                }
            }
        }
        
        return null;
    }
}

// Test composite pattern
echo "=== Composite Pattern Testing ===\n";

$root = new Directory("root");
$home = new Directory("home");
$user = new Directory("user");
$documents = new Directory("documents");
$pictures = new Directory("pictures");

$root->add($home);
$home->add($user);
$user->add($documents);
$user->add($pictures);

$documents->add(new File("readme.txt", 1024));
$documents->add(new File("notes.txt", 2048));
$pictures->add(new File("photo1.jpg", 512000));
$pictures->add(new File("photo2.jpg", 768000));

echo "File System Structure:\n";
echo $root->display();

echo "\nTotal size of root: " . $root->getSize() . " bytes\n";
echo "Total size of documents: " . $documents->getSize() . " bytes\n";
echo "Total size of pictures: " . $pictures->getSize() . " bytes\n";

$visitor = new FileSystemVisitor();
echo "\nSearching for 'photo1.jpg':\n";
$found = $visitor->findByName($root, "photo1.jpg");
if ($found) {
    echo "Found: {$found->getName()} ({$found->getSize()} bytes)\n";
}

echo "\nDone\n";