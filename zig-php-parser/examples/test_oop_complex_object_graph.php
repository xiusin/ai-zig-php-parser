<?php
// Complex object graph with bidirectional relationships
class Department {
    private $name;
    private $employees = [];
    private $manager;
    
    public function __construct($name) {
        $this->name = $name;
    }
    
    public function addEmployee(Employee $employee) {
        $this->employees[] = $employee;
        $employee->setDepartment($this);
    }
    
    public function removeEmployee(Employee $employee) {
        $key = array_search($employee, $this->employees, true);
        if ($key !== false) {
            unset($this->employees[$key]);
            $employee->setDepartment(null);
        }
    }
    
    public function getEmployees() {
        return $this->employees;
    }
    
    public function setManager(Employee $manager) {
        $this->manager = $manager;
        $manager->addManagedDepartment($this);
    }
    
    public function getManager() {
        return $this->manager;
    }
    
    public function getName() {
        return $this->name;
    }
    
    public function getEmployeeCount() {
        return count($this->employees);
    }
}

class Employee {
    private $id;
    private $name;
    private $department;
    private $managedDepartments = [];
    private $projects = [];
    
    public function __construct($id, $name) {
        $this->id = $id;
        $this->name = $name;
    }
    
    public function setDepartment(?Department $department) {
        $this->department = $department;
    }
    
    public function getDepartment() {
        return $this->department;
    }
    
    public function addManagedDepartment(Department $department) {
        if (!in_array($department, $this->managedDepartments, true)) {
            $this->managedDepartments[] = $department;
        }
    }
    
    public function getManagedDepartments() {
        return $this->managedDepartments;
    }
    
    public function addProject(Project $project) {
        if (!in_array($project, $this->projects, true)) {
            $this->projects[] = $project;
            $project->addMember($this);
        }
    }
    
    public function removeProject(Project $project) {
        $key = array_search($project, $this->projects, true);
        if ($key !== false) {
            unset($this->projects[$key]);
            $project->removeMember($this);
        }
    }
    
    public function getProjects() {
        return $this->projects;
    }
    
    public function getId() {
        return $this->id;
    }
    
    public function getName() {
        return $this->name;
    }
}

class Project {
    private $name;
    private $members = [];
    private $tasks = [];
    
    public function __construct($name) {
        $this->name = $name;
    }
    
    public function addMember(Employee $employee) {
        if (!in_array($employee, $this->members, true)) {
            $this->members[] = $employee;
        }
    }
    
    public function removeMember(Employee $employee) {
        $key = array_search($employee, $this->members, true);
        if ($key !== false) {
            unset($this->members[$key]);
        }
    }
    
    public function getMembers() {
        return $this->members;
    }
    
    public function addTask(Task $task) {
        $this->tasks[] = $task;
        $task->setProject($this);
    }
    
    public function getTasks() {
        return $this->tasks;
    }
    
    public function getName() {
        return $this->name;
    }
    
    public function getMemberCount() {
        return count($this->members);
    }
}

class Task {
    private $name;
    private $project;
    private $assignee;
    
    public function __construct($name) {
        $this->name = $name;
    }
    
    public function setProject(Project $project) {
        $this->project = $project;
    }
    
    public function setAssignee(Employee $employee) {
        $this->assignee = $employee;
    }
    
    public function getName() {
        return $this->name;
    }
    
    public function getProject() {
        return $this->project;
    }
    
    public function getAssignee() {
        return $this->assignee;
    }
}

// Build complex object graph
$engineering = new Department("Engineering");
$marketing = new Department("Marketing");
$sales = new Department("Sales");

$ceo = new Employee(1, "CEO");
$cto = new Employee(2, "CTO");
$cfo = new Employee(3, "CFO");
$dev1 = new Employee(4, "Developer 1");
$dev2 = new Employee(5, "Developer 2");
$dev3 = new Employee(6, "Developer 3");
$marketer1 = new Employee(7, "Marketer 1");
$sales1 = new Employee(8, "Sales Rep 1");

// Set department managers
$engineering->setManager($cto);
$marketing->setManager($cfo);
$sales->setManager($ceo);

// Add employees to departments
$engineering->addEmployee($dev1);
$engineering->addEmployee($dev2);
$engineering->addEmployee($dev3);
$marketing->addEmployee($marketer1);
$sales->addEmployee($sales1);

// Create projects
$project1 = new Project("Website Redesign");
$project2 = new Project("Mobile App");
$project3 = new Project("Marketing Campaign");

// Add employees to projects
$dev1->addProject($project1);
$dev2->addProject($project1);
$dev2->addProject($project2);
$dev3->addProject($project2);
$marketer1->addProject($project1);
$marketer1->addProject($project3);
$sales1->addProject($project3);

// Add tasks to projects
$task1 = new Task("Design Homepage");
$task2 = new Task("Implement API");
$task3 = new Task("Test Features");
$project1->addTask($task1);
$project1->addTask($task2);
$project1->addTask($task3);

$task1->setAssignee($dev1);
$task2->setAssignee($dev2);
$task3->setAssignee($dev3);

// Display object graph
echo "=== Department Overview ===\n";
echo "{$engineering->getName()}: {$engineering->getEmployeeCount()} employees\n";
echo "{$marketing->getName()}: {$marketing->getEmployeeCount()} employees\n";
echo "{$sales->getName()}: {$sales->getEmployeeCount()} employees\n";

echo "\n=== Project Overview ===\n";
echo "{$project1->getName()}: {$project1->getMemberCount()} members\n";
echo "{$project2->getName()}: {$project2->getMemberCount()} members\n";
echo "{$project3->getName()}: {$project3->getMemberCount()} members\n";

echo "\n=== Employee Overview ===\n";
foreach ([$dev1, $dev2, $dev3, $marketer1, $sales1] as $emp) {
    $dept = $emp->getDepartment();
    $deptName = $dept ? $dept->getName() : "None";
    $projectCount = count($emp->getProjects());
    echo "{$emp->getName()} (ID: {$emp->getId()}) - Dept: {$deptName}, Projects: {$projectCount}\n";
}

echo "\n=== Task Overview ===\n";
foreach ([$task1, $task2, $task3] as $task) {
    $project = $task->getProject();
    $assignee = $task->getAssignee();
    $projectName = $project ? $project->getName() : "None";
    $assigneeName = $assignee ? $assignee->getName() : "None";
    echo "{$task->getName()} - Project: {$projectName}, Assignee: {$assigneeName}\n";
}

echo "\nDone\n";
