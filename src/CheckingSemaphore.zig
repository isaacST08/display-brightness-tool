check_timeout: u64 = 30_000_000,
sem: Semaphore = .{ .permits = 1 },

const CheckingSemaphore = @This();

const std = @import("std");
const Semaphore = std.Thread.Semaphore;

pub fn init(permits: usize, check_timeout: u64) CheckingSemaphore {
    return CheckingSemaphore{
        .check_timeout = check_timeout,
        .sem = .{ .permits = permits },
    };
}

pub fn post(self: *CheckingSemaphore) void {
    self.sem.post();
}

pub fn wait(self: *CheckingSemaphore) void {
    var waiting = true;
    while (waiting) {
        // If we acquire the semaphore, then add this processes id to the
        // queue.
        // Acquire the semaphore, timing out to check again cyclically.
        if (self.sem.timedWait(self.check_timeout)) |_| {
            waiting = false;
        }
        // If we timed out waiting for the semaphore, try again.
        else |_| {}
    }
}
