const std = @import("std");
const testing = std.testing;
const types = @import("runtime/types.zig");
const reflection = @import("runtime/reflection.zig");
const VM = @import("runtime/vm.zig").VM;
const Value = types.Value;
const PHPClass = types.PHPClass;
const PHPObject = types.PHPObject;
const PHPString = types.PHPString;
const Method = types.Method;
const Property = types.Property;
const ReflectionClass = reflection.ReflectionClass;
const ReflectionMethod = reflection.ReflectionMethod;
const ReflectionProperty = reflection.ReflectionProperty;
const ReflectionFunction = reflection.ReflectionFunction;
const ReflectionSystem = reflection.ReflectionSystem;

test "ReflectionClass basic functionality" {
    const allocator = testing.allocator;
    
    // Create a test class
    const class_name = try PHPString.init(allocator, "TestClass");
    defer class_name.deinit(allocator);
    
    var test_class = PHPClass.init(allocator, class_name);
    defer test_class.deinit();
    
    // Add a method
    const method_name = try PHPString.init(allocator, "testMethod");
    defer method_name.deinit(allocator);
    
    var method = Method.init(method_name);
    method.modifiers.visibility = .public;
    try test_class.methods.put("testMethod", method);
    
    // Add a property
    const property_name = try PHPString.init(allocator, "testProperty");
    defer property_name.deinit(allocator);
    
    var property = Property.init(property_name);
    property.modifiers.visibility = .public;
    property.default_value = Value.initInt(42);
    try test_class.properties.put("testProperty", property);
    
    // Create reflection class
    var reflection_class = ReflectionClass.init(allocator, &test_class);
    
    // Test getName
    const name = reflection_class.getName();
    try testing.expect(std.mem.eql(u8, name.data, "TestClass"));
    
    // Test hasMethod
    try testing.expect(reflection_class.hasMethod("testMethod"));
    try testing.expect(!reflection_class.hasMethod("nonExistentMethod"));
    
    // Test hasProperty
    try testing.expect(reflection_class.hasProperty("testProperty"));
    try testing.expect(!reflection_class.hasProperty("nonExistentProperty"));
    
    // Test getMethod
    const reflected_method = try reflection_class.getMethod("testMethod");
    try testing.expect(std.mem.eql(u8, reflected_method.getName().data, "testMethod"));
    try testing.expect(reflected_method.isPublic());
    
    // Test getProperty
    const reflected_property = try reflection_class.getProperty("testProperty");
    try testing.expect(std.mem.eql(u8, reflected_property.getName().data, "testProperty"));
    try testing.expect(reflected_property.isPublic());
    try testing.expect(reflected_property.hasDefaultValue());
    
    // Test class modifiers
    try testing.expect(!reflection_class.isAbstract());
    try testing.expect(!reflection_class.isFinal());
    try testing.expect(reflection_class.isInstantiable());
}

test "ReflectionMethod functionality" {
    const allocator = testing.allocator;
    
    // Create a test class with a method
    const class_name = try PHPString.init(allocator, "TestClass");
    defer class_name.deinit(allocator);
    
    var test_class = PHPClass.init(allocator, class_name);
    defer test_class.deinit();
    
    const method_name = try PHPString.init(allocator, "testMethod");
    defer method_name.deinit(allocator);
    
    var method = Method.init(method_name);
    method.modifiers.visibility = .protected;
    method.modifiers.is_static = true;
    method.modifiers.is_final = true;
    
    // Add parameters
    const param_name = try PHPString.init(allocator, "param1");
    defer param_name.deinit(allocator);
    
    var parameter = Method.Parameter.init(param_name);
    parameter.default_value = Value.initNull();
    
    var parameters = try allocator.alloc(Method.Parameter, 1);
    defer allocator.free(parameters);
    parameters[0] = parameter;
    method.parameters = parameters;
    
    try test_class.methods.put("testMethod", method);
    
    // Create reflection method
    const reflected_method = ReflectionMethod.init(allocator, &method, &test_class);
    
    // Test method properties
    try testing.expect(std.mem.eql(u8, reflected_method.getName().data, "testMethod"));
    try testing.expect(!reflected_method.isPublic());
    try testing.expect(reflected_method.isProtected());
    try testing.expect(!reflected_method.isPrivate());
    try testing.expect(reflected_method.isStatic());
    try testing.expect(reflected_method.isFinal());
    try testing.expect(!reflected_method.isAbstract());
    
    // Test parameters
    const params = try reflected_method.getParameters();
    defer allocator.free(params);
    try testing.expect(params.len == 1);
    try testing.expect(std.mem.eql(u8, params[0].getName().data, "param1"));
    try testing.expect(params[0].hasDefaultValue());
    try testing.expect(params[0].isOptional());
    
    try testing.expect(reflected_method.getNumberOfParameters() == 1);
    try testing.expect(reflected_method.getNumberOfRequiredParameters() == 0); // Has default value
}

test "ReflectionProperty functionality" {
    const allocator = testing.allocator;
    
    // Create a test class with a property
    const class_name = try PHPString.init(allocator, "TestClass");
    defer class_name.deinit(allocator);
    
    var test_class = PHPClass.init(allocator, class_name);
    defer test_class.deinit();
    
    const property_name = try PHPString.init(allocator, "testProperty");
    defer property_name.deinit(allocator);
    
    var property = Property.init(property_name);
    property.modifiers.visibility = .private;
    property.modifiers.is_static = true;
    property.modifiers.is_readonly = true;
    property.default_value = Value.initInt(123);
    
    try test_class.properties.put("testProperty", property);
    
    // Create reflection property
    const reflected_property = ReflectionProperty.init(allocator, &property, &test_class);
    
    // Test property attributes
    try testing.expect(std.mem.eql(u8, reflected_property.getName().data, "testProperty"));
    try testing.expect(!reflected_property.isPublic());
    try testing.expect(!reflected_property.isProtected());
    try testing.expect(reflected_property.isPrivate());
    try testing.expect(reflected_property.isStatic());
    try testing.expect(reflected_property.isReadonly());
    
    // Test default value
    try testing.expect(reflected_property.hasDefaultValue());
    const default_value = reflected_property.getDefaultValue().?;
    try testing.expect(default_value.tag == .integer);
    try testing.expect(default_value.data.integer == 123);
}

test "ReflectionSystem integration" {
    const allocator = testing.allocator;
    
    // Create VM
    var vm = try VM.init(allocator);
    defer vm.deinit();
    
    // Create a test class
    const class_name = try PHPString.init(allocator, "TestClass");
    defer class_name.deinit(allocator);
    
    var test_class = try allocator.create(PHPClass);
    test_class.* = PHPClass.init(allocator, class_name);
    
    // Add method
    const method_name = try PHPString.init(allocator, "testMethod");
    defer method_name.deinit(allocator);
    
    var method = Method.init(method_name);
    try test_class.methods.put("testMethod", method);
    
    // Register class with VM
    try vm.defineClass("TestClass", test_class);
    
    // Test reflection system
    const reflection_class = try vm.getReflectionClass("TestClass");
    try testing.expect(std.mem.eql(u8, reflection_class.getName().data, "TestClass"));
    try testing.expect(reflection_class.hasMethod("testMethod"));
    
    // Test getting method through reflection system
    const reflection_method = try vm.getReflectionMethod("TestClass", "testMethod");
    try testing.expect(std.mem.eql(u8, reflection_method.getName().data, "testMethod"));
}

test "ReflectionObject functionality" {
    const allocator = testing.allocator;
    
    // Create a test class
    const class_name = try PHPString.init(allocator, "TestClass");
    defer class_name.deinit(allocator);
    
    var test_class = PHPClass.init(allocator, class_name);
    defer test_class.deinit();
    
    // Create an object
    var object = PHPObject.init(allocator, &test_class);
    defer object.deinit();
    
    // Set some properties
    try object.setProperty("prop1", Value.initInt(42));
    try object.setProperty("prop2", try Value.initString(allocator, "test"));
    
    // Create reflection object
    const reflection_object = reflection.ReflectionObject.init(allocator, &object);
    
    // Test reflection object
    try testing.expect(std.mem.eql(u8, reflection_object.getClassName().data, "TestClass"));
    try testing.expect(reflection_object.hasProperty("prop1"));
    try testing.expect(reflection_object.hasProperty("prop2"));
    try testing.expect(!reflection_object.hasProperty("nonExistent"));
    
    // Test getting property names
    const property_names = try reflection_object.getPropertyNames();
    defer allocator.free(property_names);
    try testing.expect(property_names.len == 2);
    
    // Clean up string value
    object.properties.get("prop2").?.data.string.data.deinit(allocator);
}

test "Class inheritance reflection" {
    const allocator = testing.allocator;
    
    // Create parent class
    const parent_name = try PHPString.init(allocator, "ParentClass");
    defer parent_name.deinit(allocator);
    
    var parent_class = PHPClass.init(allocator, parent_name);
    defer parent_class.deinit();
    
    const parent_method_name = try PHPString.init(allocator, "parentMethod");
    defer parent_method_name.deinit(allocator);
    
    const parent_method = Method.init(parent_method_name);
    try parent_class.methods.put("parentMethod", parent_method);
    
    // Create child class
    const child_name = try PHPString.init(allocator, "ChildClass");
    defer child_name.deinit(allocator);
    
    var child_class = PHPClass.init(allocator, child_name);
    defer child_class.deinit();
    child_class.parent = &parent_class;
    
    const child_method_name = try PHPString.init(allocator, "childMethod");
    defer child_method_name.deinit(allocator);
    
    const child_method = Method.init(child_method_name);
    try child_class.methods.put("childMethod", child_method);
    
    // Test reflection
    var reflection_child = ReflectionClass.init(allocator, &child_class);
    
    // Child should have both its own method and parent method
    try testing.expect(reflection_child.hasMethod("childMethod"));
    try testing.expect(reflection_child.hasMethod("parentMethod"));
    
    // Test parent class reflection
    const parent_reflection = reflection_child.getParentClass();
    try testing.expect(parent_reflection != null);
    if (parent_reflection) |parent| {
        try testing.expect(std.mem.eql(u8, parent.getName().data, "ParentClass"));
    }
    
    // Test inheritance check
    try testing.expect(reflection_child.isSubclassOf(&ReflectionClass.init(allocator, &parent_class)));
}

test "ReflectionType functionality" {
    const allocator = testing.allocator;
    
    // Create a type info
    const type_name = try PHPString.init(allocator, "string");
    defer type_name.deinit(allocator);
    
    var type_info = types.TypeInfo.init(type_name);
    type_info.is_nullable = true;
    
    // Create reflection type
    const reflection_type = reflection.ReflectionType.init(allocator, &type_info);
    
    // Test type properties
    try testing.expect(std.mem.eql(u8, reflection_type.getName().data, "string"));
    try testing.expect(reflection_type.allowsNull());
    try testing.expect(reflection_type.isBuiltin());
    
    // Test toString
    const type_string = try reflection_type.toString(allocator);
    defer type_string.deinit(allocator);
    try testing.expect(std.mem.eql(u8, type_string.data, "?string"));
}

test "Reflection builtin functions" {
    const allocator = testing.allocator;
    
    // Create VM
    var vm = try VM.init(allocator);
    defer vm.deinit();
    
    // Create a test class
    const class_name = try PHPString.init(allocator, "TestClass");
    defer class_name.deinit(allocator);
    
    var test_class = try allocator.create(PHPClass);
    test_class.* = PHPClass.init(allocator, class_name);
    
    // Add method and property
    const method_name = try PHPString.init(allocator, "testMethod");
    defer method_name.deinit(allocator);
    
    const method = Method.init(method_name);
    try test_class.methods.put("testMethod", method);
    
    const property_name = try PHPString.init(allocator, "testProperty");
    defer property_name.deinit(allocator);
    
    var property = Property.init(property_name);
    property.default_value = Value.initInt(42);
    try test_class.properties.put("testProperty", property);
    
    // Register class
    try vm.defineClass("TestClass", test_class);
    
    // Test class_exists
    const class_name_value = try Value.initString(allocator, "TestClass");
    const class_exists_fn: *const fn (*VM, []const Value) anyerror!Value = @ptrCast(@alignCast(vm.global.get("class_exists").?.data.builtin_function));
    const exists_result = try class_exists_fn(vm, &[_]Value{class_name_value});
    try testing.expect(exists_result.toBool());
    
    // Test non-existent class
    const non_existent_class = try Value.initString(allocator, "NonExistentClass");
    const not_exists_result = try class_exists_fn(vm, &[_]Value{non_existent_class});
    try testing.expect(!not_exists_result.toBool());
    
    // Create an object for testing
    const object_value = try vm.createObject("TestClass");
    
    // Test get_class
    const get_class_fn: *const fn (*VM, []const Value) anyerror!Value = @ptrCast(@alignCast(vm.global.get("get_class").?.data.builtin_function));
    const get_class_result = try get_class_fn(vm, &[_]Value{object_value});
    try testing.expect(std.mem.eql(u8, get_class_result.data.string.data.data, "TestClass"));
    
    // Test method_exists
    const method_name_value = try Value.initString(allocator, "testMethod");
    const method_exists_fn: *const fn (*VM, []const Value) anyerror!Value = @ptrCast(@alignCast(vm.global.get("method_exists").?.data.builtin_function));
    const method_exists_result = try method_exists_fn(vm, &[_]Value{ object_value, method_name_value });
    try testing.expect(method_exists_result.toBool());
    
    // Test property_exists
    const property_name_value = try Value.initString(allocator, "testProperty");
    const property_exists_fn: *const fn (*VM, []const Value) anyerror!Value = @ptrCast(@alignCast(vm.global.get("property_exists").?.data.builtin_function));
    const property_exists_result = try property_exists_fn(vm, &[_]Value{ object_value, property_name_value });
    try testing.expect(property_exists_result.toBool());
    
    // Clean up string values
    class_name_value.data.string.data.deinit(allocator);
    non_existent_class.data.string.data.deinit(allocator);
    get_class_result.data.string.data.deinit(allocator);
    method_name_value.data.string.data.deinit(allocator);
    property_name_value.data.string.data.deinit(allocator);
}