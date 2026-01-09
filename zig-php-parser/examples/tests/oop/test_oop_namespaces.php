<?php
// Namespaces
namespace App\Models;

class User {
    private $id;
    private $name;
    private $email;
    
    public function __construct($id, $name, $email) {
        $this->id = $id;
        $this->name = $name;
        $this->email = $email;
    }
    
    public function getId() {
        return $this->id;
    }
    
    public function getName() {
        return $this->name;
    }
    
    public function getEmail() {
        return $this->email;
    }
    
    public function toArray() {
        return [
            'id' => $this->id,
            'name' => $this->name,
            'email' => $this->email,
        ];
    }
}

namespace App\Services;

use App\Models\User;

class UserService {
    private $users = [];
    
    public function createUser($id, $name, $email) {
        $user = new User($id, $name, $email);
        $this->users[$id] = $user;
        return $user;
    }
    
    public function getUser($id) {
        return $this->users[$id] ?? null;
    }
    
    public function getAllUsers() {
        return array_values($this->users);
    }
    
    public function deleteUser($id) {
        if (isset($this->users[$id])) {
            unset($this->users[$id]);
            return true;
        }
        return false;
    }
}

namespace App\Repositories;

use App\Models\User;

class UserRepository {
    private $storage = [];
    
    public function save(User $user) {
        $this->storage[$user->getId()] = $user->toArray();
    }
    
    public function find($id) {
        return $this->storage[$id] ?? null;
    }
    
    public function findAll() {
        return array_values($this->storage);
    }
}

namespace App\Controllers;

use App\Services\UserService;

class UserController {
    private $userService;
    
    public function __construct(UserService $userService) {
        $this->userService = $userService;
    }
    
    public function create($name, $email) {
        $id = count($this->userService->getAllUsers()) + 1;
        return $this->userService->createUser($id, $name, $email);
    }
    
    public function show($id) {
        return $this->userService->getUser($id);
    }
    
    public function index() {
        return $this->userService->getAllUsers();
    }
}

namespace {
    // Global namespace
    use App\Controllers\UserController;
    use App\Services\UserService;
    use App\Repositories\UserRepository;
    
    echo "=== Namespace Testing ===\n";
    
    // Create service
    $userService = new UserService();
    
    // Create controller
    $controller = new UserController($userService);
    
    // Create users
    echo "Creating users...\n";
    $user1 = $controller->create("John Doe", "john@example.com");
    $user2 = $controller->create("Jane Smith", "jane@example.com");
    $user3 = $controller->create("Bob Johnson", "bob@example.com");
    
    echo "User 1: {$user1->getName()} ({$user1->getEmail()})\n";
    echo "User 2: {$user2->getName()} ({$user2->getEmail()})\n";
    echo "User 3: {$user3->getName()} ({$user3->getEmail()})\n";
    
    // List all users
    echo "\nAll users:\n";
    $users = $controller->index();
    foreach ($users as $user) {
        echo "  {$user->getName()} ({$user->getEmail()})\n";
    }
    
    // Get specific user
    echo "\nGet user 2:\n";
    $user = $controller->show(2);
    if ($user) {
        echo "  {$user->getName()} ({$user->getEmail()})\n";
    }
    
    // Use repository
    echo "\n=== Repository Testing ===\n";
    $repository = new UserRepository();
    foreach ($users as $user) {
        $repository->save($user);
    }
    
    echo "Find user 1:\n";
    $found = $repository->find(1);
    print_r($found);
    
    echo "\nFind all:\n";
    $all = $repository->findAll();
    foreach ($all as $u) {
        echo "  {$u['name']} ({$u['email']})\n";
    }
    
    echo "\nDone\n";
}