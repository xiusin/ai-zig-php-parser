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
const Attribute = types.Attribute;
const ReflectionClass = reflection.ReflectionClass;
const ReflectionMethod = reflection.ReflectionMethod;
const ReflectionProperty = reflection.ReflectionProperty;
const ReflectionAttribute = reflection.ReflectionAttribute;
const ReflectionSystem = reflection.ReflectionSystem;

test "Attribute creation and basic functionality" {
    const allocator = testing.allocator;

    // Create an attribute
    const attr_name = try PHPString.init(allocator, "TestAttribute");
    defer attr_name.deinit(allocator);

    const string_value = try Value.initString(allocator, "test");
    defer string_value.release(allocator);

    const args = [_]Value{
        Value.initInt(42),
        string_value,
    };

    const target = Attribute.AttributeTarget{
        .class = true,
        .method = true,
    };

    const attribute = Attribute.init(attr_name, &args, target);

    // Test attribute properties
    try testing.expect(std.mem.eql(u8, attribute.name.data, "TestAttribute"));
    try testing.expect(attribute.arguments.len == 2);
    try testing.expect(attribute.arguments[0].asInt() == 42);
    try testing.expect(std.mem.eql(u8, attribute.arguments[1].getAsString().data.data, "test"));

    // Test target checking
    try testing.expect(attribute.canBeAppliedTo(.class));
    try testing.expect(attribute.canBeAppliedTo(.method));
    try testing.expect(!attribute.canBeAppliedTo(.property));
    try testing.expect(!attribute.canBeAppliedTo(.parameter));
}

test "Class with attributes" {
    const allocator = testing.allocator;

    // Create a test class
    const class_name = try PHPString.init(allocator, "TestClass");
    defer class_name.deinit(allocator);

    var test_class = try PHPClass.init(allocator, class_name);
    defer test_class.deinit(allocator);

    // Create attributes for the class
    const attr1_name = try PHPString.init(allocator, "Deprecated");
    defer attr1_name.deinit(allocator);

    const attr2_name = try PHPString.init(allocator, "Route");
    defer attr2_name.deinit(allocator);

    const route_args = [_]Value{
        try Value.initString(allocator, "/api/test"),
    };
    defer route_args[0].release(allocator);

    // Allocate attributes array
    var attributes = try allocator.alloc(Attribute, 2);
    defer allocator.free(attributes);
    attributes[0] = Attribute.init(attr1_name, &[_]Value{}, .{ .class = true, .all = true });
    attributes[1] = Attribute.init(attr2_name, &route_args, .{ .class = true });

    test_class.attributes = attributes;

    // Test reflection
    const reflection_class = ReflectionClass.init(allocator, &test_class);

    // Test getting all attributes
    const all_attrs = try reflection_class.getAttributes(null);
    defer allocator.free(all_attrs);
    try testing.expect(all_attrs.len == 2);

    // Test filtering attributes
    const deprecated_attrs = try reflection_class.getAttributes("Deprecated");
    defer allocator.free(deprecated_attrs);
    try testing.expect(deprecated_attrs.len == 1);
    try testing.expect(std.mem.eql(u8, deprecated_attrs[0].name.data, "Deprecated"));

    const route_attrs = try reflection_class.getAttributes("Route");
    defer allocator.free(route_attrs);
    try testing.expect(route_attrs.len == 1);
    try testing.expect(std.mem.eql(u8, route_attrs[0].name.data, "Route"));
    try testing.expect(route_attrs[0].arguments.len == 1);

    // Test hasAttribute
    try testing.expect(reflection_class.hasAttribute("Deprecated"));
    try testing.expect(reflection_class.hasAttribute("Route"));
    try testing.expect(!reflection_class.hasAttribute("NonExistent"));
}

test "Method with attributes" {
    const allocator = testing.allocator;

    // Create a test class with a method
    const class_name = try PHPString.init(allocator, "TestClass");
    defer class_name.deinit(allocator);

    var test_class = try PHPClass.init(allocator, class_name);
    defer test_class.deinit(allocator);

    const method_name = try PHPString.init(allocator, "testMethod");
    defer method_name.deinit(allocator);

    var method = Method.init(method_name);

    // Create attributes for the method
    const attr_name = try PHPString.init(allocator, "PostMapping");

    const args = [_]Value{
        try Value.initString(allocator, "/users"),
    };

    // Allocate attributes array
    var attributes = try allocator.alloc(Attribute, 1);
    attributes[0] = Attribute.init(attr_name, &args, .{ .method = true });

    method.attributes = attributes;
    try test_class.methods.put("testMethod", method);

    // Test reflection
    const reflection_class = ReflectionClass.init(allocator, &test_class);
    const reflection_method = try reflection_class.getMethod("testMethod");

    // Test method attributes
    const method_attrs = try reflection_method.getAttributes(null);
    try testing.expect(method_attrs.len == 1);
    try testing.expect(std.mem.eql(u8, method_attrs[0].name.data, "PostMapping"));

    try testing.expect(reflection_method.hasAttribute("PostMapping"));
    try testing.expect(!reflection_method.hasAttribute("GetMapping"));

    // Clean up in correct order
    allocator.free(method_attrs);
    args[0].release(allocator);
    allocator.free(attributes);
    attr_name.deinit(allocator);
}

test "Property with attributes" {
    const allocator = testing.allocator;

    // Create a test class with a property
    const class_name = try PHPString.init(allocator, "TestClass");
    defer class_name.deinit(allocator);

    var test_class = try PHPClass.init(allocator, class_name);
    defer test_class.deinit(allocator);

    const property_name = try PHPString.init(allocator, "testProperty");
    defer property_name.deinit(allocator);

    var property = Property.init(property_name);

    // Create attributes for the property
    const attr_name = try PHPString.init(allocator, "Column");

    const args = [_]Value{
        try Value.initString(allocator, "user_name"),
        try Value.initString(allocator, "varchar(255)"),
    };

    var attributes = [_]Attribute{
        Attribute.init(attr_name, &args, .{ .property = true }),
    };

    property.attributes = &attributes;
    try test_class.properties.put("testProperty", property);

    // Test reflection
    const reflection_class = ReflectionClass.init(allocator, &test_class);
    const reflection_property = try reflection_class.getProperty("testProperty");

    // Test property attributes
    const property_attrs = try reflection_property.getAttributes(null);
    try testing.expect(property_attrs.len == 1);
    try testing.expect(std.mem.eql(u8, property_attrs[0].name.data, "Column"));
    try testing.expect(property_attrs[0].arguments.len == 2);

    try testing.expect(reflection_property.hasAttribute("Column"));
    try testing.expect(!reflection_property.hasAttribute("Table"));

    // Clean up in correct order
    allocator.free(property_attrs);
    args[0].release(allocator);
    args[1].release(allocator);
    attr_name.deinit(allocator);
}

test "Parameter with attributes" {
    const allocator = testing.allocator;

    // Create a method parameter with attributes
    const param_name = try PHPString.init(allocator, "userId");
    defer param_name.deinit(allocator);

    var parameter = Method.Parameter.init(param_name);

    // Create attributes for the parameter
    const attr_name = try PHPString.init(allocator, "PathVariable");

    const args = [_]Value{
        try Value.initString(allocator, "id"),
    };

    var attributes = [_]Attribute{
        Attribute.init(attr_name, &args, .{ .parameter = true }),
    };

    parameter.attributes = &attributes;

    // Create a dummy method for reflection
    const method_name = try PHPString.init(allocator, "testMethod");
    defer method_name.deinit(allocator);

    var parameters = [_]Method.Parameter{parameter};

    const method = Method{
        .name = method_name,
        .parameters = &parameters,
        .return_type = null,
        .modifiers = .{},
        .attributes = &[_]Attribute{},
        .body = null,
    };

    // Test reflection parameter
    const reflection_param = reflection.ReflectionParameter.init(allocator, &parameter, &method, 0);

    // Test parameter attributes
    const param_attrs = try reflection_param.getAttributes(null);
    try testing.expect(param_attrs.len == 1);
    try testing.expect(std.mem.eql(u8, param_attrs[0].name.data, "PathVariable"));

    try testing.expect(reflection_param.hasAttribute("PathVariable"));
    try testing.expect(!reflection_param.hasAttribute("RequestBody"));

    // Clean up in correct order
    allocator.free(param_attrs);
    args[0].release(allocator);
    attr_name.deinit(allocator);
}

test "ReflectionAttribute functionality" {
    const allocator = testing.allocator;

    // Create an attribute
    const attr_name = try PHPString.init(allocator, "TestAttribute");
    defer attr_name.deinit(allocator);

    const args = [_]Value{
        Value.initInt(42),
        try Value.initString(allocator, "test"),
    };
    defer args[1].release(allocator);

    const target = Attribute.AttributeTarget{
        .class = true,
        .method = true,
    };

    const attribute = Attribute.init(attr_name, &args, target);

    // Create reflection attribute
    const reflection_attr = ReflectionAttribute.init(allocator, &attribute);

    // Test reflection attribute methods
    try testing.expect(std.mem.eql(u8, reflection_attr.getName().data, "TestAttribute"));

    const attr_args = reflection_attr.getArguments();
    try testing.expect(attr_args.len == 2);
    try testing.expect(attr_args[0].asInt() == 42);
    try testing.expect(std.mem.eql(u8, attr_args[1].getAsString().data.data, "test"));

    const attr_target = reflection_attr.getTarget();
    try testing.expect(attr_target.class);
    try testing.expect(attr_target.method);
    try testing.expect(!attr_target.property);

    // Test canBeAppliedTo
    try testing.expect(reflection_attr.canBeAppliedTo(.class));
    try testing.expect(reflection_attr.canBeAppliedTo(.method));
    try testing.expect(!reflection_attr.canBeAppliedTo(.property));

    // Test flags
    const flags = reflection_attr.getFlags();
    try testing.expect((flags & 0x01) != 0); // class flag
    try testing.expect((flags & 0x02) != 0); // method flag
    try testing.expect((flags & 0x04) == 0); // property flag should not be set
}

test "Attribute instantiation" {
    const allocator = testing.allocator;

    // Create an attribute
    const attr_name = try PHPString.init(allocator, "TestAttribute");
    defer attr_name.deinit(allocator);

    const args = [_]Value{
        Value.initInt(42),
    };

    const target = Attribute.AttributeTarget{
        .class = true,
    };

    const attribute = Attribute.init(attr_name, &args, target);

    // Test instantiation
    const instance = try attribute.instantiate(allocator);
    defer {
        instance.deinit(allocator);
        allocator.destroy(instance);
    }

    try testing.expect(std.mem.eql(u8, instance.class.name.data, "TestAttribute"));
}

test "ReflectionSystem attribute support" {
    const allocator = testing.allocator;

    // Create VM
    var vm = try VM.init(allocator);
    defer vm.deinit();

    // Create reflection system
    var reflection_system = ReflectionSystem.init(allocator, vm);

    // Create an attribute class
    const target = Attribute.AttributeTarget{
        .class = true,
        .method = true,
    };

    const attr_class = try reflection_system.createAttributeClass("TestAttribute", target);

    // Test reflection
    const reflection_class = try reflection_system.getClass("TestAttribute");
    try testing.expect(std.mem.eql(u8, reflection_class.getName().data, "TestAttribute"));
    try testing.expect(reflection_class.isFinal()); // Attribute classes should be final
    try testing.expect(reflection_class.hasProperty("target"));

    // Test the target property
    const target_property = try reflection_class.getProperty("target");
    try testing.expect(target_property.isReadonly());
    try testing.expect(target_property.hasDefaultValue());

    _ = attr_class; // Suppress unused variable warning
}

test "Multiple attributes on same element" {
    const allocator = testing.allocator;

    // Create a test class
    const class_name = try PHPString.init(allocator, "TestClass");
    defer class_name.deinit(allocator);

    var test_class = try PHPClass.init(allocator, class_name);
    defer test_class.deinit(allocator);

    // Create multiple attributes
    const attr1_name = try PHPString.init(allocator, "Deprecated");
    const attr2_name = try PHPString.init(allocator, "Route");
    const attr3_name = try PHPString.init(allocator, "Middleware");

    const route_args = [_]Value{
        try Value.initString(allocator, "/api/test"),
    };

    const middleware_args = [_]Value{
        try Value.initString(allocator, "auth"),
        try Value.initString(allocator, "cors"),
    };

    var attributes = [_]Attribute{
        Attribute.init(attr1_name, &[_]Value{}, .{ .class = true }),
        Attribute.init(attr2_name, &route_args, .{ .class = true }),
        Attribute.init(attr3_name, &middleware_args, .{ .class = true }),
    };

    test_class.attributes = &attributes;

    // Test reflection
    const reflection_class = ReflectionClass.init(allocator, &test_class);

    // Test getting all attributes
    const all_attrs = try reflection_class.getAttributes(null);
    try testing.expect(all_attrs.len == 3);

    // Test that all attributes are present
    try testing.expect(reflection_class.hasAttribute("Deprecated"));
    try testing.expect(reflection_class.hasAttribute("Route"));
    try testing.expect(reflection_class.hasAttribute("Middleware"));

    // Test getting specific attribute with arguments
    const middleware_attrs = try reflection_class.getAttributes("Middleware");
    try testing.expect(middleware_attrs.len == 1);
    try testing.expect(middleware_attrs[0].arguments.len == 2);
    try testing.expect(std.mem.eql(u8, middleware_attrs[0].arguments[0].getAsString().data.data, "auth"));
    try testing.expect(std.mem.eql(u8, middleware_attrs[0].arguments[1].getAsString().data.data, "cors"));

    // Clean up in correct order
    allocator.free(middleware_attrs);
    allocator.free(all_attrs);
    middleware_args[0].release(allocator);
    middleware_args[1].release(allocator);
    route_args[0].release(allocator);
    attr3_name.deinit(allocator);
    attr2_name.deinit(allocator);
    attr1_name.deinit(allocator);
}

test "Attribute target validation" {
    const allocator = testing.allocator;

    // Create attributes with different targets
    const attr_name = try PHPString.init(allocator, "TestAttribute");
    defer attr_name.deinit(allocator);

    const class_only_attr = Attribute.init(attr_name, &[_]Value{}, .{ .class = true });
    const method_only_attr = Attribute.init(attr_name, &[_]Value{}, .{ .method = true });
    const property_only_attr = Attribute.init(attr_name, &[_]Value{}, .{ .property = true });
    const all_targets_attr = Attribute.init(attr_name, &[_]Value{}, .{ .all = true });

    // Test class-only attribute
    try testing.expect(class_only_attr.canBeAppliedTo(.class));
    try testing.expect(!class_only_attr.canBeAppliedTo(.method));
    try testing.expect(!class_only_attr.canBeAppliedTo(.property));
    try testing.expect(!class_only_attr.canBeAppliedTo(.parameter));
    try testing.expect(!class_only_attr.canBeAppliedTo(.function));
    try testing.expect(!class_only_attr.canBeAppliedTo(.constant));

    // Test method-only attribute
    try testing.expect(!method_only_attr.canBeAppliedTo(.class));
    try testing.expect(method_only_attr.canBeAppliedTo(.method));
    try testing.expect(!method_only_attr.canBeAppliedTo(.property));

    // Test property-only attribute
    try testing.expect(!property_only_attr.canBeAppliedTo(.class));
    try testing.expect(!property_only_attr.canBeAppliedTo(.method));
    try testing.expect(property_only_attr.canBeAppliedTo(.property));

    // Test all-targets attribute
    try testing.expect(all_targets_attr.canBeAppliedTo(.class));
    try testing.expect(all_targets_attr.canBeAppliedTo(.method));
    try testing.expect(all_targets_attr.canBeAppliedTo(.property));
    try testing.expect(all_targets_attr.canBeAppliedTo(.parameter));
    try testing.expect(all_targets_attr.canBeAppliedTo(.function));
    try testing.expect(all_targets_attr.canBeAppliedTo(.constant));
}
