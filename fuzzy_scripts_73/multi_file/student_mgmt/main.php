<?php
// 学生管理系统 - 入口文件
require_once __DIR__ . '/Student.php';
require_once __DIR__ . '/Course.php';

// 创建学生管理器
$sm = new StudentManager();

// 注册学生
$alice = $sm->enroll("Alice", 20, "Computer Science");
$bob = $sm->enroll("Bob", 22, "Mathematics");
$charlie = $sm->enroll("Charlie", 21, "Computer Science");
$diana = $sm->enroll("Diana", 19, "Physics");

echo "=== 学生列表 ===\n";
foreach ($sm->all() as $student) {
    echo $student . "\n";
}
echo "总计: " . $sm->count() . " 名学生\n\n";

// 添加成绩
$alice->addGrade("CS101", 95.5);
$alice->addGrade("CS102", 88.0);
$bob->addGrade("MATH101", 76.5);
$bob->addGrade("MATH102", 82.0);
$charlie->addGrade("CS101", 91.0);
$charlie->addGrade("CS102", 78.5);
$diana->addGrade("PHYS101", 89.0);

echo "=== 成绩信息 ===\n";
echo "Alice GPA: " . sprintf("%.2f", $alice->getGPA()) . " (" . $alice->getLetterGrade() . ")\n";
echo "Bob GPA: " . sprintf("%.2f", $bob->getGPA()) . " (" . $bob->getLetterGrade() . ")\n";
echo "Charlie GPA: " . sprintf("%.2f", $charlie->getGPA()) . " (" . $charlie->getLetterGrade() . ")\n";
echo "Diana GPA: " . sprintf("%.2f", $diana->getGPA()) . " (" . $diana->getLetterGrade() . ")\n";
echo "班级平均: " . sprintf("%.2f", $sm->getClassAverage()) . "\n\n";

// 创建课程目录
$catalog = new CourseCatalog();

$cs101 = new Course("CS101", "Introduction to Programming", 3, "Dr. Smith");
$cs102 = new Course("CS102", "Data Structures", 4, "Dr. Jones");
$math101 = new Course("MATH101", "Calculus I", 4, "Dr. Brown");
$phys101 = new Course("PHYS101", "Physics I", 4, "Dr. Wilson");

$catalog->add($cs101);
$catalog->add($cs102);
$catalog->add($math101);
$catalog->add($phys101);

echo "=== 课程列表 ===\n";
foreach ($catalog->all() as $course) {
    echo $course . "\n";
}
echo "总计: " . $catalog->count() . " 门课程\n\n";

// 选课
$cs101->enroll($alice);
$cs101->enroll($charlie);
$cs102->enroll($alice);
$cs102->enroll($charlie);
$math101->enroll($bob);
$phys101->enroll($diana);

echo "=== 选课情况 ===\n";
echo "CS101 选课人数: " . $cs101->getEnrolledCount() . "\n";
echo "CS102 选课人数: " . $cs102->getEnrolledCount() . "\n";
echo "MATH101 选课人数: " . $math101->getEnrolledCount() . "\n";
echo "PHYS101 选课人数: " . $phys101->getEnrolledCount() . "\n\n";

// 添加作业和提交成绩
$cs101->addAssignment("Homework 1", 100);
$cs101->addAssignment("Midterm", 100);
$cs101->submitAssignment("Homework 1", $alice->id, 95.0);
$cs101->submitAssignment("Homework 1", $charlie->id, 88.5);
$cs101->submitAssignment("Midterm", $alice->id, 92.0);
$cs101->submitAssignment("Midterm", $charlie->id, 85.0);

echo "=== 作业成绩 ===\n";
echo "CS101 Homework 1 平均分: " . sprintf("%.2f", $cs101->getAverageScore("Homework 1")) . "\n";
echo "CS101 Midterm 平均分: " . sprintf("%.2f", $cs101->getAverageScore("Midterm")) . "\n";
echo "Alice CS101 Homework 1: " . sprintf("%.1f", $cs101->getAssignmentScore("Homework 1", $alice->id)) . "\n";
echo "Charlie CS101 Midterm: " . sprintf("%.1f", $cs101->getAssignmentScore("Midterm", $charlie->id)) . "\n\n";

// 测试退课
echo "=== 退课测试 ===\n";
echo "退课前 CS101 人数: " . $cs101->getEnrolledCount() . "\n";
$cs101->unenroll($charlie->id);
echo "退课后 CS101 人数: " . $cs101->getEnrolledCount() . "\n";
echo "重复退课: " . ($cs101->unenroll($charlie->id) ? "成功" : "失败（已退课）") . "\n\n";

// 按专业查找学生
echo "=== 按专业查找 ===\n";
$csStudents = $sm->findByMajor("Computer Science");
echo "Computer Science 专业学生: " . count($csStudents) . " 人\n";
foreach ($csStudents as $s) {
    echo "  - " . $s->name . "\n";
}

echo "\n=== 按教师查找课程 ===\n";
$smithCourses = $catalog->getByInstructor("Dr. Smith");
echo "Dr. Smith 的课程: " . count($smithCourses) . " 门\n";
foreach ($smithCourses as $c) {
    echo "  - " . $c->code . ": " . $c->name . "\n";
}

echo "\n完成。\n";
