const std = @import("std");
const testing = std.testing;
const main = @import("main");
const types = main.runtime.types;
const VM = main.runtime.vm.VM;

test "PHPClass creation and basic functionality" {
    const allocator = testing.allocator;
    
    // Create a class name
    const class_name = try types.PHPString.init(allocator, "TestClass");
    defer class_name.deinit(allocator);
    
    // Create a class
    var php_class = types.PHPClass.init(allocator, class_name);
    defer php_class.deinit();
    
    // Test basic class properties
    try testing.expect(std.mem.eql(u8, php_class.name.data, "TestClass"));
    try testing.expect(php_class.parent == null);
    try testing.expect(!php_class.modifiers.is_abstract);
    try testing.expect(!php_class.modifiers.is_final);
    try testing.expect(!php_class.modifiers.is_readonly);
}

test "PHPClass property management" {
    const allocator = testing.allocator;
    
    const class_name = try types.PHPString.init(allocator, "TestClass");
    defer class_name.deinit(allocator);
    
    var php_class = types.PHPClass.init(allocator, class_name);
    defer php_class.deinit();
    
    // Add a property
    const prop_name = try types.PHPString.init(allocator, "testProperty");
    defer prop_name.deinit(allocator);
    
    var property = types.Property.init(prop_name);
    property.modifiers.visibility = .public;
    property.default_value = types.Value.initInt(42);
    
    try php_class.properties.put("testProperty", property);
    
    // Test property retrieval
    try testing.expect(php_class.hasProperty("testProperty"));
    try testing.expect(!php_class.hasProperty("nonExistentProperty"));
    
    const retrieved_prop = php_class.getProperty("testProperty");
    try testing.expect(retrieved_prop != null);
    try testing.expect(retrieved_prop.?.modifiers.visibility == .public);
    try testing.expect(retrieved_prop.?.default_value.?.tag == .integer);
    try testing.expect(retrieved_prop.?.default_value.?.data.integer == 42);
}

test "PHPClass method management" {
    const allocator = testing.allocator;
    
    const class_name = try types.PHPString.init(allocator, "TestClass");
    defer class_name.deinit(allocator);
    
    var php_class = types.PHPClass.init(allocator, class_name);
    defer php_class.deinit();
    
    // Add a method
    const method_name = try types.PHPString.init(allocator, "testMethod");
    defer method_name.deinit(allocator);
    
    var method = types.Method.init(method_name);
    method.modifiers.visibility = .public;
    
    try php_class.methods.put("testMethod", method);
    
    // Test method retrieval
    try testing.expect(php_class.hasMethod("testMethod"));
    try testing.expect(!php_class.hasMethod("nonExistentMethod"));
    
    const retrieved_method = php_class.getMethod("testMethod");
    try testing.expect(retrieved_method != null);
    try testing.expect(retrieved_method.?.modifiers.visibility == .public);
}

test "PHPObject creation and property access" {
    const allocator = testing.allocator;
    
    // Create a class
    const class_name = try types.PHPString.init(allocator, "TestClass");
    defer class_name.deinit(allocator);
    
    var php_class = types.PHPClass.init(allocator, class_name);
    defer php_class.deinit();
    
    // Add a property to the class
    const prop_name = try types.PHPString.init(allocator, "testProperty");
    defer prop_name.deinit(allocator);
    
    var property = types.Property.init(prop_name);
    property.default_value = types.Value.initInt(100);
    try php_class.properties.put("testProperty", property);
    
    // Create an object
    var php_object = types.PHPObject.init(allocator, &php_class);
    defer php_object.deinit();
    
    // Test property access
    const prop_value = try php_object.getProperty("testProperty");
    try testing.expect(prop_value.tag == .integer);
    try testing.expect(prop_value.data.integer == 100);
    
    // Test property setting
    try php_object.setProperty("testProperty", types.Value.initInt(200));
    const updated_value = try php_object.getProperty("testProperty");
    try testing.expect(updated_value.data.integer == 200);
    
    // Test dynamic property
    try php_object.setProperty("dynamicProperty", types.Value.initInt(300));
    const dynamic_value = try php_object.getProperty("dynamicProperty");
    try testing.expect(dynamic_value.data.integer == 300);
}

test "PHPObject method checking" {
    const allocator = testing.allocator;
    
    // Create a class with a method
    const class_name = try types.PHPString.init(allocator, "TestClass");
    defer class_name.deinit(allocator);
    
    var php_class = types.PHPClass.init(allocator, class_name);
    defer php_class.deinit();
    
    const method_name = try types.PHPString.init(allocator, "testMethod");
    defer method_name.deinit(allocator);
    
    const method = types.Method.init(method_name);
    try php_class.methods.put("testMethod", method);
    
    // Create an object
    var php_object = types.PHPObject.init(allocator, &php_class);
    defer php_object.deinit();
    
    // Test method checking
    try testing.expect(php_object.hasMethod("testMethod"));
    try testing.expect(!php_object.hasMethod("nonExistentMethod"));
}

test "Property hooks functionality" {
    const allocator = testing.allocator;
    
    const prop_name = try types.PHPString.init(allocator, "hookedProperty");
    defer prop_name.deinit(allocator);
    
    var property = types.Property.init(prop_name);
    
    // Test initial state
    try testing.expect(!property.hasGetHook());
    try testing.expect(!property.hasSetHook());
    
    // Add hooks (simplified - in real implementation these would have actual bodies)
    const get_hook = types.PropertyHook.init(.get, null);
    const set_hook = types.PropertyHook.init(.set, null);
    
    // In a real implementation, we'd allocate and manage the hooks array
    // For this test, we'll just verify the hook structure works
    try testing.expect(get_hook.type == .get);
    try testing.expect(set_hook.type == .set);
}

test "Magic method detection" {
    const allocator = testing.allocator;
    
    // Test constructor detection
    const construct_name = try types.PHPString.init(allocator, "__construct");
    defer construct_name.deinit(allocator);
    
    const construct_method = types.Method.init(construct_name);
    try testing.expect(construct_method.isConstructor());
    try testing.expect(construct_method.isMagicMethod());
    
    // Test destructor detection
    const destruct_name = try types.PHPString.init(allocator, "__destruct");
    defer destruct_name.deinit(allocator);
    
    const destruct_method = types.Method.init(destruct_name);
    try testing.expect(destruct_method.isDestructor());
    try testing.expect(destruct_method.isMagicMethod());
    
    // Test regular method
    const regular_name = try types.PHPString.init(allocator, "regularMethod");
    defer regular_name.deinit(allocator);
    
    const regular_method = types.Method.init(regular_name);
    try testing.expect(!regular_method.isConstructor());
    try testing.expect(!regular_method.isDestructor());
    try testing.expect(!regular_method.isMagicMethod());
}

test "Class inheritance checking" {
    const allocator = testing.allocator;
    
    // Create parent class
    const parent_name = try types.PHPString.init(allocator, "ParentClass");
    defer parent_name.deinit(allocator);
    
    var parent_class = types.PHPClass.init(allocator, parent_name);
    defer parent_class.deinit();
    
    // Create child class
    const child_name = try types.PHPString.init(allocator, "ChildClass");
    defer child_name.deinit(allocator);
    
    var child_class = types.PHPClass.init(allocator, child_name);
    child_class.parent = &parent_class;
    defer child_class.deinit();
    
    // Test inheritance
    try testing.expect(child_class.isInstanceOf(&parent_class));
    try testing.expect(child_class.isInstanceOf(&child_class));
    try testing.expect(!parent_class.isInstanceOf(&child_class));
}

test "VM class registration and object creation" {
    const allocator = testing.allocator;
    
    var vm = try VM.init(allocator);
    defer vm.deinit();
    
    // Create and register a class
    const class_name = try types.PHPString.init(allocator, "TestClass");
    defer class_name.deinit(allocator);
    
    const php_class = try allocator.create(types.PHPClass);
    php_class.* = types.PHPClass.init(allocator, class_name);
    
    try vm.defineClass("TestClass", php_class);
    
    // Test class retrieval
    const retrieved_class = vm.getClass("TestClass");
    try testing.expect(retrieved_class != null);
    try testing.expect(std.mem.eql(u8, retrieved_class.?.name.data, "TestClass"));
    
    // Test object creation
    const object_value = try vm.createObject("TestClass");
    try testing.expect(object_value.tag == .object);
    try testing.expect(std.mem.eql(u8, object_value.data.object.data.class.name.data, "TestClass"));
    
    // Clean up the object manually for this test
    object_value.data.object.data.deinit();
    allocator.destroy(object_value.data.object.data);
    allocator.destroy(object_value.data.object);
}

test "Object toString functionality" {
    const allocator = testing.allocator;
    
    // Create a class
    const class_name = try types.PHPString.init(allocator, "TestClass");
    defer class_name.deinit(allocator);
    
    var php_class = types.PHPClass.init(allocator, class_name);
    defer php_class.deinit();
    
    // Create an object
    var php_object = types.PHPObject.init(allocator, &php_class);
    defer php_object.deinit();
    
    // Test toString
    const str_result = try php_object.toString(allocator);
    defer str_result.deinit(allocator);
    
    try testing.expect(std.mem.startsWith(u8, str_result.data, "Object(TestClass)"));
}

test "Object cloning" {
    const allocator = testing.allocator;
    
    // Create a class
    const class_name = try types.PHPString.init(allocator, "TestClass");
    defer class_name.deinit(allocator);
    
    var php_class = types.PHPClass.init(allocator, class_name);
    defer php_class.deinit();
    
    // Create an object with properties
    var original_object = types.PHPObject.init(allocator, &php_class);
    defer original_object.deinit();
    
    try original_object.setProperty("testProp", types.Value.initInt(42));
    
    // Clone the object
    const cloned_object = try original_object.clone(allocator);
    defer {
        cloned_object.deinit();
        allocator.destroy(cloned_object);
    }
    
    // Test that clone has same class and properties
    try testing.expect(cloned_object.class == original_object.class);
    
    const cloned_prop = try cloned_object.getProperty("testProp");
    try testing.expect(cloned_prop.data.integer == 42);
    
    // Test that modifying clone doesn't affect original
    try cloned_object.setProperty("testProp", types.Value.initInt(100));
    const original_prop = try original_object.getProperty("testProp");
    try testing.expect(original_prop.data.integer == 42);
}