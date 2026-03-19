<?php
// 测试65: 属性(注解)与反射API的深度集成
// 测试目的：验证#[Attribute]的完整反射功能

#[Attribute(Attribute::TARGET_CLASS | Attribute::TARGET_METHOD)]
class Route {
    public function __construct(
        public string $path,
        public array $methods = ['GET'],
        public ?string $name = null
    ) {}
}

#[Attribute(Attribute::TARGET_PROPERTY)]
class Column {
    public function __construct(
        public string $type = 'string',
        public bool $nullable = false,
        public ?int $length = null,
        public ?string $default = null
    ) {}
}

#[Attribute(Attribute::TARGET_PARAMETER)]
class Inject {
    public function __construct(public string $serviceName) {}
}

#[Attribute(Attribute::TARGET_CLASS)]
class Table {
    public function __construct(public string $name) {}
}

// 使用属性的类
#[Table('users')]
class User {
    #[Column(type: 'int', nullable: false)]
    private ?int $id = null;
    
    #[Column(type: 'string', length: 255)]
    private string $name = '';
    
    #[Column(type: 'string', nullable: true)]
    private ?string $email = null;
    
    #[Route('/users', methods: ['GET', 'POST'], name: 'user_list')]
    public function list(): array {
        return [];
    }
    
    #[Route('/users/{id}', methods: ['GET'], name: 'user_get')]
    public function get(int $id): ?array {
        return null;
    }
    
    #[Route('/users', methods: ['POST'])]
    public function create(#[Inject('validator')] $validator): void {}
}

// 反射读取属性
$refClass = new ReflectionClass(User::class);

// 类属性
echo "Class attributes:\n";
$classAttrs = $refClass->getAttributes();
foreach ($classAttrs as $attr) {
    $instance = $attr->newInstance();
    if ($instance instanceof Table) {
        echo "  Table: {$instance->name}\n";
    }
}

// 属性上的属性
echo "\nProperty attributes:\n";
foreach ($refClass->getProperties() as $prop) {
    $colAttrs = $prop->getAttributes(Column::class);
    foreach ($colAttrs as $attr) {
        $col = $attr->newInstance();
        echo "  {$prop->getName()}: {$col->type}";
        if ($col->length) echo "({$col->length})";
        if ($col->nullable) echo " nullable";
        echo "\n";
    }
}

// 方法上的属性
echo "\nMethod attributes:\n";
foreach ($refClass->getMethods() as $method) {
    $routeAttrs = $method->getAttributes(Route::class);
    foreach ($routeAttrs as $attr) {
        $route = $attr->newInstance();
        echo "  {$method->getName()}: {$route->path} [" . implode(', ', $route->methods) . "]";
        if ($route->name) echo " name={$route->name}";
        echo "\n";
    }
}

// 参数上的属性
echo "\nParameter attributes:\n";
$createMethod = $refClass->getMethod('create');
foreach ($createMethod->getParameters() as $param) {
    $injectAttrs = $param->getAttributes(Inject::class);
    foreach ($injectAttrs as $attr) {
        $inject = $attr->newInstance();
        echo "  {$param->getName()}: Inject({$inject->serviceName})\n";
    }
}

// 属性类元信息
echo "\nAttribute metadata:\n";
$routeRef = new ReflectionClass(Route::class);
$routeAttr = $routeRef->getAttributes( Attribute::class)[0];
$routeAttrInstance = $routeAttr->newInstance();
echo "  Route targets: " . $routeAttrInstance->flags . "\n";

// 检查重复属性
#[Attribute(Attribute::TARGET_CLASS | Attribute::IS_REPEATABLE)]
class Middleware {
    public function __construct(public string $name) {}
}

#[Middleware('auth')]
#[Middleware('logging')]
#[Middleware('cache')]
class ProtectedController {
    public function action(): void {}
}

$protectedRef = new ReflectionClass(ProtectedController::class);
echo "\nRepeatable attributes:\n";
foreach ($protectedRef->getAttributes(Middleware::class) as $mw) {
    $instance = $mw->newInstance();
    echo "  Middleware: {$instance->name}\n";
}
?>