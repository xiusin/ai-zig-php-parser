<?php
// 学生管理系统 - 课程模型
class Course {
    private array $enrolledStudents = [];
    private array $assignments = [];

    public function __construct(
        public readonly string $code,
        public readonly string $name,
        public readonly int $credits,
        public readonly string $instructor
    ) {}

    public function enroll(Student $student): bool {
        if (isset($this->enrolledStudents[$student->id])) {
            return false; // already enrolled
        }
        $this->enrolledStudents[$student->id] = $student;
        return true;
    }

    public function unenroll(int $studentId): bool {
        if (!isset($this->enrolledStudents[$studentId])) {
            return false;
        }
        unset($this->enrolledStudents[$studentId]);
        return true;
    }

    public function addAssignment(string $name, float $maxScore = 100): void {
        $this->assignments[$name] = ['max_score' => $maxScore, 'submissions' => []];
    }

    public function submitAssignment(string $name, int $studentId, float $score): bool {
        if (!isset($this->assignments[$name])) return false;
        if (!isset($this->enrolledStudents[$studentId])) return false;
        $this->assignments[$name]['submissions'][$studentId] = $score;
        return true;
    }

    public function getAssignmentScore(string $name, int $studentId): ?float {
        return $this->assignments[$name]['submissions'][$studentId] ?? null;
    }

    public function getAverageScore(string $name): float {
        if (!isset($this->assignments[$name])) return 0.0;
        $scores = array_values($this->assignments[$name]['submissions']);
        if (empty($scores)) return 0.0;
        return array_sum($scores) / count($scores);
    }

    public function getEnrolledCount(): int {
        return count($this->enrolledStudents);
    }

    public function getStudents(): array {
        return array_values($this->enrolledStudents);
    }

    public function __toString(): string {
        return sprintf("[%s] %s (%d credits, Instructor: %s, Enrolled: %d)",
            $this->code, $this->name, $this->credits, $this->instructor, $this->getEnrolledCount());
    }
}

class CourseCatalog {
    private array $courses = [];

    public function add(Course $course): void {
        $this->courses[$course->code] = $course;
    }

    public function get(string $code): ?Course {
        return $this->courses[$code] ?? null;
    }

    public function getByInstructor(string $instructor): array {
        return array_values(array_filter($this->courses, fn($c) => $c->instructor === $instructor));
    }

    public function count(): int {
        return count($this->courses);
    }

    public function all(): array {
        return array_values($this->courses);
    }
}
