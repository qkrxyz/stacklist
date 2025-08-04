pub fn StackList(comptime T: type, stack: []T) type {
    return extern struct {
        const Self = @This();

        capacity: u32,
        len: u32,
        heap: [*]T,

        pub inline fn allocated(self: *const Self) bool {
            if (stack.len == 0) return true;

            return self.capacity > stack.len;
        }

        pub const empty = Self{
            .capacity = stack.len,
            .len = 0,
            .heap = undefined,
        };

        pub fn initComptime(value: []const T) Self {
            std.debug.assert(@inComptime());
            return Self{
                .capacity = @intCast(value.len),
                .len = @intCast(value.len),
                .heap = @constCast(value.ptr),
            };
        }

        pub fn deinit(self: *const Self, allocator: std.mem.Allocator) void {
            if (self.allocated()) allocator.free(self.heap[0..self.capacity]);
        }

        pub fn at(self: *const Self, index: usize) ?*T {
            if (index >= self.len) return null;

            return @constCast(&self.slice()[index]); // `@constCast` is always safe
        }

        pub fn slice(self: *const Self) []T {
            return if (self.allocated())
                self.heap[0..self.len]
            else
                stack[0..self.len];
        }

        pub fn ensureTotalCapacity(self: *Self, new_capacity: u32, allocator: std.mem.Allocator) !void {
            const on_heap = self.allocated();
            const old = self.slice();

            // Should go back to the stack; free all heap-allocated memory.
            if (new_capacity <= stack.len) {
                if (on_heap) {
                    @memcpy(stack[0..stack.len], old[0..stack.len]);
                    allocator.free(old);
                }
                self.capacity = stack.len;

                return;
            }

            // Don't remap unallocated memory.
            //
            // Reference implementation:
            // https://ziglang.org/documentation/master/std/#std.array_list.ArrayListAligned.ensureTotalCapacityPrecise
            if (on_heap) {
                if (allocator.remap(
                    self.heap[0..self.len],
                    new_capacity,
                )) |new| {
                    self.heap = new.ptr;
                    self.capacity = new_capacity;

                    return;
                }
            }

            const new = try allocator.alloc(T, new_capacity);

            @memcpy(new[0..self.len], old);
            if (on_heap) allocator.free(old);

            self.heap = new.ptr;
            self.capacity = new_capacity;
        }

        pub fn append(self: *Self, value: T, allocator: std.mem.Allocator) !void {
            const length = self.len;

            try ensureTotalCapacity(self, length + 1, allocator);
            self.len += 1;

            if (self.allocated()) {
                self.heap[length] = value;
            } else {
                stack[length] = value;
            }
        }

        pub fn appendSlice(self: *Self, value: []const T, allocator: std.mem.Allocator) !void {
            const length = self.len;

            try ensureTotalCapacity(self, length + @as(u32, @intCast(value.len)), allocator);

            if (self.allocated()) {
                @memcpy(self.heap[length..self.capacity], value);
            } else {
                @memcpy(stack[length .. length + value.len], value);
            }

            self.len += @intCast(value.len);
        }

        pub fn orderedRemove(self: *Self, index: u32) T {
            const s = self.slice();

            const old = s[index];
            @memmove(s[index .. s.len - 1], s[index + 1 ..]);

            self.len -= 1;

            return old;
        }
    };
}

const std = @import("std");
