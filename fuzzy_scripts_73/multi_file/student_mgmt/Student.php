<?php
// 学生管理系统 - 学生模型
class Student {
    private array $grades = [];

    public function __construct(
        public readonly int $id,
        public readonly string $name,
        public readonly int $age,
        public readonly string $major
    ) {}

    public function addGrade(string $course, float $grade): void {
        $this->grades[$course] = $grade;
    }

    public function getGrade(string $course): ?float {
        return $this->grades[$course] ?? null;
    }

    public function getGrades(): array {
        return $this->grades;
    }

    public function getGPA(): float {
        if (empty($this->grades)) return 0.0;
        return array_sum($this->grades) / count($this->grades);
    }

    public function getLetterGrade(): string {
        $gpa = $this->getGPA();
        return match(true) {
            $gpa >= 90 => 'A',
            $gpa >= 80 => 'B',
            $gpa >= 70 => 'C',
            $gpa >= 60 => 'D',
            default => 'F',
        };
    }

    public function __toString(): string {
        return sprintf("[%d] %s (age: %d, major: %s, GPA: %.2f, grade: %s)",
            $this->id, $this->name, $this->age, $this->major,
            $this->getGPA(), $this->getLetterGrade());
    }
}

class StudentManager {
    private array $students = [];
    private int $nextId = 1;

    public function enroll(string $name, int $age, string $major): Student {
        $student = new Student($this->nextId++, $name, $age, $major);
        $this->students[$student->id] = $student;
        return $student;
    }

    public function find(int $id): ?Student {
        return $this->students[$id] ?? null;
    }

    public function findByMajor(string $major): array {
        return array_values(array_filter($this->students, fn($s) => $s->major === $major));
    }

    public function getTopStudents(int $n = 5): array {
        $sorted = $this->students;
        usort($sorted, fn($a, $b) => $b->getGPA() <=> $a->getGPA());
        return array_slice($sorted, 0, $n);
    }

    public function getClassAverage(): float {
        if (empty($this->students)) return 0.0;
        $gpas = array_map(fn($s) => $s->getGPA(), $this->students);
        return array_sum($gpas) / count($gpas);
    }

    public function count(): int {
        return count($this->students);
    }

    public function all(): array {
        return array_values($this->students);
    }
}
