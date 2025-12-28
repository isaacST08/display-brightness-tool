//! This struct represents a process queue. At the end of the queue is a
//! critical section.

head: u8 = 0,
tail: u8 = 0,
count: u8 = 0,
queue_sem: CheckingSemaphore = CheckingSemaphore.init(1, 30_000_000),
cs_sem: CheckingSemaphore = CheckingSemaphore.init(1, 30_000_000),
arr: [std.math.maxInt(u8) + 1]std.c.pid_t = [_]std.c.pid_t{-1} ** (std.math.maxInt(u8) + 1),

const ProcQueue = @This();

const std = @import("std");
const CheckingSemaphore = @import("CheckingSemaphore.zig");

/// Adds the current process (via its PID) to the queue.
pub fn join(self: *ProcQueue) void {
    var waiting = true;
    while (waiting) {
        self.queue_sem.wait();
        // Join the queue if there is room, otherwise keep waiting.
        if (self.count < std.math.maxInt(u8)) {
            self.arr[self.tail] = std.c.getpid();
            self.tail +%= 1;
            self.count +|= 1;
            waiting = false;
        }
        self.queue_sem.post();
        if (waiting) {
            std.Thread.sleep(1_000_000);
        }
    }
}

/// Joins the current process (via its PID) to the queue and blocks until it's
/// the processes turn.
pub fn wait(self: *ProcQueue) void {
    self.join();

    var waiting = true;
    while (waiting) {
        self.queue_sem.wait();
        if (self.arr[self.head] == std.c.getpid()) {
            waiting = false;
            // self.arr[self.head] = -1;
            // self.head +%= 1;
            // self.count -|= 1;
            // return true;
        }
        self.queue_sem.post();

        if (waiting) {
            std.Thread.sleep(1_000_000);
        }
    }

    self.cs_sem.wait();
}

/// Signals that this process has finished with the critical section rewarded
/// at the end of this queue. Removes this process from the queue and frees the
/// critical section for the next process.
pub fn signal(self: *ProcQueue) void {
    // Remove self from the head of the queue.
    self.queue_sem.wait();
    if (self.arr[self.head] == std.c.getpid()) {
        self.arr[self.head] = -1;
        self.head +%= 1;
        self.count -|= 1;
    }
    self.queue_sem.post();

    // Release the critical section semaphore.
    self.cs_sem.post();
}
