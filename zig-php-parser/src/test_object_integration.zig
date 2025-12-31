const std = @import("std");
const testing = std.testing;
const types = @import("runtime/types.zig");
const VM = @import("runtime/vm.zig").VM;
const gc = @import("runtime/gc.zig");

// Helper function to properly release a Value
fn releaseValue(value: types.Value, allocator: std.mem.Allocator) void {
    value.release(allocator);
}

test "Object system integration with VM" {
    const allocator = testing.allocator;

    var vm = try VM.init(allocator);
    defer vm.deinit();

    // Create a test class with properties and methods
    const class_name = try types.PHPString.init(allocator, "Person");
    defer class_name.deinit(allocator);

    const php_class = try allocator.create(types.PHPClass);
    php_class.* = try types.PHPClass.init(allocator, class_name);

    // Add a property
    const name_prop_name = try types.PHPString.init(allocator, "name");
    defer name_prop_name.deinit(allocator);

    var name_property = types.Property.init(name_prop_name);
    name_property.modifiers.visibility = .public;
    name_property.default_value = try types.Value.initString(allocator, "Unknown");
    defer if (name_property.default_value) |val| {
        releaseValue(val, allocator);
    };

    try php_class.properties.put("name", name_property);

    // Add an age property
    const age_prop_name = try types.PHPString.init(allocator, "age");
    defer age_prop_name.deinit(allocator);

    var age_property = types.Property.init(age_prop_name);
    age_property.modifiers.visibility = .public;
    age_property.default_value = types.Value.initInt(0);

    try php_class.properties.put("age", age_property);

    // Add a constructor method
    const constructor_name = try types.PHPString.init(allocator, "__construct");
    defer constructor_name.deinit(allocator);

    const constructor_method = types.Method.init(constructor_name);
    try php_class.methods.put("__construct", constructor_method);

    // Register the class
    try vm.defineClass("Person", php_class);

    // Create an object
    const person_object = try vm.createObject("Person");
    try testing.expect(person_object.getTag() == .object);

    // Test property access
    const name_value = try vm.getObjectProperty(person_object, "name");
    try testing.expect(name_value.getTag() == .string);
    try testing.expect(std.mem.eql(u8, name_value.getAsString().data.data, "Unknown"));

    const age_value = try vm.getObjectProperty(person_object, "age");
    try testing.expect(age_value.getTag() == .integer);
    try testing.expect(age_value.asInt() == 0);

    // Test property setting
    const new_name = try types.Value.initString(allocator, "John Doe");
    defer releaseValue(new_name, allocator);
    try vm.setObjectProperty(person_object, "name", new_name);

    const updated_name = try vm.getObjectProperty(person_object, "name");
    try testing.expect(std.mem.eql(u8, updated_name.getAsString().data.data, "John Doe"));

    // Test method checking
    try testing.expect(person_object.getAsObject().data.class.hasMethod("__construct"));
    try testing.expect(!person_object.getAsObject().data.class.hasMethod("nonExistentMethod"));

    // Clean up
    person_object.getAsObject().data.deinit(allocator);
    allocator.destroy(person_object.getAsObject().data);
    allocator.destroy(person_object.getAsObject());
}

test "Class inheritance functionality" {
    const allocator = testing.allocator;

    // Create parent class
    const parent_name = try types.PHPString.init(allocator, "Animal");
    defer parent_name.deinit(allocator);

    var parent_class = try types.PHPClass.init(allocator, parent_name);
    defer parent_class.deinit(allocator);

    // Add property to parent
    const species_name = try types.PHPString.init(allocator, "species");
    defer species_name.deinit(allocator);

    var species_property = types.Property.init(species_name);
    species_property.modifiers.visibility = .protected;
    species_property.default_value = try types.Value.initString(allocator, "Unknown");
    defer if (species_property.default_value) |val| {
        releaseValue(val, allocator);
    };

    try parent_class.properties.put("species", species_property);

    // Add method to parent
    const speak_name = try types.PHPString.init(allocator, "speak");
    defer speak_name.deinit(allocator);

    const speak_method = types.Method.init(speak_name);
    try parent_class.methods.put("speak", speak_method);

    // Create child class
    const child_name = try types.PHPString.init(allocator, "Dog");
    defer child_name.deinit(allocator);

    var child_class = try types.PHPClass.init(allocator, child_name);
    child_class.parent = &parent_class;
    defer child_class.deinit(allocator);

    // Add child-specific property
    const breed_name = try types.PHPString.init(allocator, "breed");
    defer breed_name.deinit(allocator);

    var breed_property = types.Property.init(breed_name);
    breed_property.default_value = try types.Value.initString(allocator, "Mixed");
    defer if (breed_property.default_value) |val| {
        releaseValue(val, allocator);
    };

    try child_class.properties.put("breed", breed_property);

    // Test inheritance
    try testing.expect(child_class.isInstanceOf(&parent_class));
    try testing.expect(child_class.isInstanceOf(&child_class));
    try testing.expect(!parent_class.isInstanceOf(&child_class));

    // Test inherited property access
    try testing.expect(child_class.hasProperty("species")); // From parent
    try testing.expect(child_class.hasProperty("breed")); // Own property
    try testing.expect(!parent_class.hasProperty("breed")); // Parent doesn't have child property

    // Test inherited method access
    try testing.expect(child_class.hasMethod("speak")); // From parent
    try testing.expect(!parent_class.hasMethod("bark")); // Non-existent method

    // Create objects
    var parent_object = try types.PHPObject.init(allocator, &parent_class);
    defer parent_object.deinit(allocator);

    var child_object = try types.PHPObject.init(allocator, &child_class);
    defer child_object.deinit(allocator);

    // Test object inheritance
    try testing.expect(child_object.class.isInstanceOf(&parent_class));
    try testing.expect(child_object.class.isInstanceOf(&child_class));
    try testing.expect(!parent_object.class.isInstanceOf(&child_class));

    // Test property access on child object
    const species_value = try child_object.getProperty("species");
    try testing.expect(species_value.getTag() == .string);
    try testing.expect(std.mem.eql(u8, species_value.getAsString().data.data, "Unknown"));

    const breed_value = try child_object.getProperty("breed");
    try testing.expect(breed_value.getTag() == .string);
    try testing.expect(std.mem.eql(u8, breed_value.getAsString().data.data, "Mixed"));
}

test "Property hooks basic functionality" {
    const allocator = testing.allocator;

    // Create a property with hooks
    const prop_name = try types.PHPString.init(allocator, "value");
    defer prop_name.deinit(allocator);

    var property = types.Property.init(prop_name);

    // Test initial state
    try testing.expect(!property.hasGetHook());
    try testing.expect(!property.hasSetHook());
    try testing.expect(property.getGetHook() == null);
    try testing.expect(property.getSetHook() == null);

    // Create hooks
    const get_hook = types.PropertyHook.init(.get, null);
    const set_hook = types.PropertyHook.init(.set, null);

    // Verify hook types
    try testing.expect(get_hook.type == .get);
    try testing.expect(set_hook.type == .set);
}

test "Magic method identification" {
    const allocator = testing.allocator;

    // Test various magic methods
    const magic_methods = [_][]const u8{
        "__construct",
        "__destruct",
        "__get",
        "__set",
        "__call",
        "__toString",
        "__clone",
        "__invoke",
        "__serialize",
        "__unserialize",
    };

    for (magic_methods) |method_name| {
        const php_name = try types.PHPString.init(allocator, method_name);
        defer php_name.deinit(allocator);

        const method = types.Method.init(php_name);
        try testing.expect(method.isMagicMethod());

        if (std.mem.eql(u8, method_name, "__construct")) {
            try testing.expect(method.isConstructor());
        } else {
            try testing.expect(!method.isConstructor());
        }

        if (std.mem.eql(u8, method_name, "__destruct")) {
            try testing.expect(method.isDestructor());
        } else {
            try testing.expect(!method.isDestructor());
        }
    }

    // Test non-magic method
    const regular_name = try types.PHPString.init(allocator, "regularMethod");
    defer regular_name.deinit(allocator);

    const regular_method = types.Method.init(regular_name);
    try testing.expect(!regular_method.isMagicMethod());
    try testing.expect(!regular_method.isConstructor());
    try testing.expect(!regular_method.isDestructor());
}
