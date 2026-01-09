<?php
// Exception handling with custom exceptions
class ValidationException extends Exception {}
class DatabaseException extends Exception {}
class NotFoundException extends Exception {}

class User {
    private $id;
    private $name;
    private $email;
    
    public function __construct($id, $name, $email) {
        $this->id = $id;
        $this->name = $name;
        $this->email = $email;
    }
    
    public function validate() {
        if (empty($this->name)) {
            throw new ValidationException("Name cannot be empty");
        }
        
        if (empty($this->email) || !strpos($this->email, '@')) {
            throw new ValidationException("Invalid email address");
        }
        
        if ($this->id <= 0) {
            throw new ValidationException("Invalid ID");
        }
        
        return true;
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
}

class UserRepository {
    private $users = [];
    
    public function __construct() {
        // Initialize with some users
        $this->users[1] = new User(1, "John Doe", "john@example.com");
        $this->users[2] = new User(2, "Jane Smith", "jane@example.com");
    }
    
    public function find($id) {
        if (!isset($this->users[$id])) {
            throw new NotFoundException("User with ID {$id} not found");
        }
        return $this->users[$id];
    }
    
    public function save(User $user) {
        try {
            $user->validate();
            $this->users[$user->getId()] = $user;
            return true;
        } catch (ValidationException $e) {
            throw new DatabaseException("Failed to save user: " . $e->getMessage());
        }
    }
    
    public function delete($id) {
        if (!isset($this->users[$id])) {
            throw new NotFoundException("User with ID {$id} not found");
        }
        unset($this->users[$id]);
        return true;
    }
}

class UserService {
    private $repository;
    
    public function __construct(UserRepository $repository) {
        $this->repository = $repository;
    }
    
    public function getUser($id) {
        try {
            $user = $this->repository->find($id);
            return $user;
        } catch (NotFoundException $e) {
            throw new Exception("User service error: " . $e->getMessage());
        }
    }
    
    public function createUser($id, $name, $email) {
        $user = new User($id, $name, $email);
        return $this->repository->save($user);
    }
    
    public function deleteUser($id) {
        return $this->repository->delete($id);
    }
}

// Test exception handling
$repository = new UserRepository();
$service = new UserService($repository);

try {
    echo "Finding user 1...\n";
    $user = $service->getUser(1);
    echo "Found: {$user->getName()} ({$user->getEmail()})\n";
} catch (Exception $e) {
    echo "Error: " . $e->getMessage() . "\n";
}

try {
    echo "Finding user 99...\n";
    $user = $service->getUser(99);
    echo "Found: {$user->getName()}\n";
} catch (Exception $e) {
    echo "Error: " . $e->getMessage() . "\n";
}

try {
    echo "Creating valid user...\n";
    $service->createUser(3, "Bob Wilson", "bob@example.com");
    echo "User created successfully\n";
} catch (Exception $e) {
    echo "Error: " . $e->getMessage() . "\n";
}

try {
    echo "Creating invalid user (empty name)...\n";
    $service->createUser(4, "", "test@example.com");
    echo "User created successfully\n";
} catch (Exception $e) {
    echo "Error: " . $e->getMessage() . "\n";
}

try {
    echo "Creating invalid user (invalid email)...\n";
    $service->createUser(5, "Test User", "invalid-email");
    echo "User created successfully\n";
} catch (Exception $e) {
    echo "Error: " . $e->getMessage() . "\n";
}

try {
    echo "Deleting user 2...\n";
    $service->deleteUser(2);
    echo "User deleted successfully\n";
} catch (Exception $e) {
    echo "Error: " . $e->getMessage() . "\n";
}

try {
    echo "Deleting user 99...\n";
    $service->deleteUser(99);
    echo "User deleted successfully\n";
} catch (Exception $e) {
    echo "Error: " . $e->getMessage() . "\n";
}

// Nested try-catch
try {
    try {
        echo "Nested exception test...\n";
        $user = new User(-1, "Test", "test@example.com");
        $user->validate();
    } catch (ValidationException $e) {
        throw new Exception("Validation failed in nested block: " . $e->getMessage());
    }
} catch (Exception $e) {
    echo "Caught outer exception: " . $e->getMessage() . "\n";
}

echo "Done\n";