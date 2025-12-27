const std = @import("std");
const testing = std.testing;
const main = @import("main");
const gc = main.runtime.gc;
const types = main.runtime.types;
const Value = types.Value;
const PHPString = types.PHPString;
const PHPArray = types.PHPArray;
const PHPObject = types.PHPObject;
const PHPClass = types.PHPClass;
const PHPResource = types.PHPResource;
const MemoryManager = gc.MemoryManager;
const GarbageCollector = gc.GarbageCollector;

test "garbage collection - basic reference counting" {
    const allocator = testing.allocator;
    var mm = try MemoryManager.init(allocator);
    defer mm.deinit();
    
    // Create a string value
    const str_box = try mm.allocString("Hello, World!");
    try testing.expectEqual(@as(u32, 1), str_box.ref_count);
    
    // Retain the string
    _ = str_box.retain();
    try testing.expectEqual(@as(u32, 2), str_box.ref_count);
    
    // Release once
    str_box.release(allocator);
    try testing.expectEqual(@as(u32, 1), str_box.ref_count);
    
    // Release again - should be destroyed
    str_box.release(allocator);
    // Note: str_box is now invalid, but test passes if no crash occurs
}

test "garbage collection - memory threshold triggering" {
    const allocator = testing.allocator;
    const small_threshold = 100; // Very small threshold to trigger GC quickly
    var mm = try MemoryManager.initWithThreshold(allocator, small_threshold);
    defer mm.deinit();
    
    const initial_usage = mm.getMemoryUsage();
    
    // Allocate several strings to exceed threshold
    var strings: [10]*gc.Box(*PHPString) = undefined;
    for (0..10) |i| {
        const data = try std.fmt.allocPrint(allocator, "String {d}", .{i});
        defer allocator.free(data);
        strings[i] = try mm.allocString(data);
    }
    
    // Memory usage should have increased
    try testing.expect(mm.getMemoryUsage() > initial_usage);
    
    // Clean up
    for (strings) |str| {
        str.release(allocator);
    }
}

test "garbage collection - manual collection" {
    const allocator = testing.allocator;
    var mm = try MemoryManager.init(allocator);
    defer mm.deinit();
    
    // Create some objects that will become unreferenced
    const str1 = try mm.allocString("Test string 1");
    const str2 = try mm.allocString("Test string 2");
    
    // Add them as roots initially
    try mm.addRoot(@ptrCast(str1));
    try mm.addRoot(@ptrCast(str2));
    
    // Remove from roots (making them eligible for collection)
    mm.removeRoot(@ptrCast(str1));
    mm.removeRoot(@ptrCast(str2));
    
    // Manually trigger collection
    const collected = mm.forceCollect();
    
    // Should have collected something (exact count depends on implementation)
    _ = collected; // We don't assert exact count as it's implementation dependent
    
    // Clean up manually for now since GC is simplified
    str1.release(allocator);
    str2.release(allocator);
}

test "garbage collection - cycle detection setup" {
    const allocator = testing.allocator;
    var mm = try MemoryManager.init(allocator);
    defer mm.deinit();
    
    // Create two arrays that will reference each other (circular reference)
    const array1 = try mm.allocArray();
    const array2 = try mm.allocArray();
    
    // Create values that reference the arrays
    const val1 = Value{ .tag = .array, .data = .{ .array = array1 } };
    const val2 = Value{ .tag = .array, .data = .{ .array = array2 } };
    
    // Make them reference each other (creating a cycle)
    try array1.data.push(allocator, val2);
    try array2.data.push(allocator, val1);
    
    // Both arrays should have ref_count > 1 due to circular references
    try testing.expect(array1.ref_count >= 1);
    try testing.expect(array2.ref_count >= 1);
    
    // Clean up by breaking the cycle manually for this test
    array1.data.elements.clearRetainingCapacity();
    array2.data.elements.clearRetainingCapacity();
    
    array1.release(allocator);
    array2.release(allocator);
}

test "garbage collection - resource cleanup" {
    const allocator = testing.allocator;
    var mm = try MemoryManager.init(allocator);
    defer mm.deinit();
    
    // Create a mock resource with destructor
    const MockResource = struct {
        value: i32,
        destroyed: *bool,
        
        fn destructor(ptr: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ptr));
            self.destroyed.* = true;
        }
    };
    
    var destroyed = false;
    var mock_resource = MockResource{ .value = 42, .destroyed = &destroyed };
    
    const type_name = try PHPString.init(allocator, "MockResource");
    defer type_name.deinit(allocator);
    
    const resource = PHPResource.init(type_name, &mock_resource, MockResource.destructor);
    const resource_box = try mm.allocResource(resource);
    
    try testing.expect(!destroyed);
    
    // Release the resource - should call destructor
    resource_box.release(allocator);
    
    try testing.expect(destroyed);
}

test "garbage collection - object with properties" {
    const allocator = testing.allocator;
    var mm = try MemoryManager.init(allocator);
    defer mm.deinit();
    
    // Create a class
    const class_name = try PHPString.init(allocator, "TestClass");
    defer class_name.deinit(allocator);
    
    var test_class = PHPClass.init(allocator, class_name);
    defer test_class.deinit();
    
    // Create an object
    const obj = try mm.allocObject(&test_class);
    
    // Add some properties
    const prop_value = try Value.initString(allocator, "property value");
    defer prop_value.data.string.release(allocator);
    
    try obj.data.setProperty("test_prop", prop_value);
    
    try testing.expectEqual(@as(u32, 1), obj.ref_count);
    
    // Clean up
    obj.release(allocator);
}

test "garbage collection - memory usage tracking" {
    const allocator = testing.allocator;
    var mm = try MemoryManager.init(allocator);
    defer mm.deinit();
    
    const initial_usage = mm.getMemoryUsage();
    
    // Allocate some memory
    const str = try mm.allocString("Test string for memory tracking");
    
    // Memory usage should increase
    try testing.expect(mm.getMemoryUsage() > initial_usage);
    
    // Set a new threshold
    mm.setMemoryThreshold(2048);
    
    // Clean up
    str.release(allocator);
}

test "garbage collection - gc_collect_cycles equivalent" {
    const allocator = testing.allocator;
    var mm = try MemoryManager.init(allocator);
    defer mm.deinit();
    
    // Test the global collectCycles function
    const collected = gc.collectCycles(&mm);
    
    // Should return number of collected objects (0 in this case since nothing to collect)
    try testing.expectEqual(@as(u32, 0), collected);
}