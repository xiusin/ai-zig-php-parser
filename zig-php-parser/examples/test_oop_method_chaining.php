<?php
// Method chaining (fluent interface)
class QueryBuilder {
    private $select = [];
    private $from = null;
    private $where = [];
    private $orderBy = [];
    private $limit = null;
    private $offset = null;
    
    public function select($columns) {
        if (is_array($columns)) {
            $this->select = array_merge($this->select, $columns);
        } else {
            $this->select[] = $columns;
        }
        return $this;
    }
    
    public function from($table) {
        $this->from = $table;
        return $this;
    }
    
    public function where($condition) {
        $this->where[] = $condition;
        return $this;
    }
    
    public function orderBy($column, $direction = 'ASC') {
        $this->orderBy[] = "{$column} {$direction}";
        return $this;
    }
    
    public function limit($limit) {
        $this->limit = $limit;
        return $this;
    }
    
    public function offset($offset) {
        $this->offset = $offset;
        return $this;
    }
    
    public function build() {
        $sql = "SELECT ";
        
        if (empty($this->select)) {
            $sql .= "*";
        } else {
            $sql .= implode(', ', $this->select);
        }
        
        $sql .= " FROM {$this->from}";
        
        if (!empty($this->where)) {
            $sql .= " WHERE " . implode(' AND ', $this->where);
        }
        
        if (!empty($this->orderBy)) {
            $sql .= " ORDER BY " . implode(', ', $this->orderBy);
        }
        
        if ($this->limit !== null) {
            $sql .= " LIMIT {$this->limit}";
        }
        
        if ($this->offset !== null) {
            $sql .= " OFFSET {$this->offset}";
        }
        
        return $sql;
    }
}

class HTMLBuilder {
    private $tagName;
    private $attributes = [];
    private $content = '';
    private $children = [];
    
    public function __construct($tagName) {
        $this->tagName = $tagName;
    }
    
    public static function create($tagName) {
        return new self($tagName);
    }
    
    public function attr($name, $value) {
        $this->attributes[$name] = $value;
        return $this;
    }
    
    public function text($content) {
        $this->content = $content;
        return $this;
    }
    
    public function add($child) {
        $this->children[] = $child;
        return $this;
    }
    
    public function render() {
        $html = "<{$this->tagName}";
        
        foreach ($this->attributes as $name => $value) {
            $html .= " {$name}=\"{$value}\"";
        }
        
        $html .= ">";
        
        if (!empty($this->content)) {
            $html .= $this->content;
        }
        
        foreach ($this->children as $child) {
            $html .= $child->render();
        }
        
        $html .= "</{$this->tagName}>";
        
        return $html;
    }
}

class Logger {
    private $prefix = '';
    private $filters = [];
    
    public function withPrefix($prefix) {
        $this->prefix = $prefix;
        return $this;
    }
    
    public function addFilter($filter) {
        $this->filters[] = $filter;
        return $this;
    }
    
    public function log($message) {
        $filtered = $this->applyFilters($message);
        $timestamp = date('Y-m-d H:i:s');
        echo "[{$timestamp}] [{$this->prefix}] {$filtered}\n";
        return $this;
    }
    
    private function applyFilters($message) {
        foreach ($this->filters as $filter) {
            $message = $filter($message);
        }
        return $message;
    }
}

// Test method chaining
echo "=== Method Chaining Testing ===\n";

// Test QueryBuilder
$query = (new QueryBuilder())
    ->select(['id', 'name', 'email'])
    ->from('users')
    ->where('status = "active"')
    ->where('age > 18')
    ->orderBy('name', 'ASC')
    ->limit(10)
    ->offset(20);

echo "SQL Query: " . $query->build() . "\n\n";

// Test HTMLBuilder
$html = HTMLBuilder::create('div')
    ->attr('class', 'container')
    ->attr('id', 'main')
    ->add(HTMLBuilder::create('h1')->text('Hello World'))
    ->add(HTMLBuilder::create('p')->text('This is a paragraph.'));

echo "HTML: " . $html->render() . "\n\n";

// Test Logger
(new Logger())
    ->withPrefix('APP')
    ->addFilter(fn($msg) => strtoupper($msg))
    ->log('Application started')
    ->log('Processing data')
    ->log('Application finished');

echo "\nDone\n";
