//! This struct represents a queueing semaphore. Processes that join the queue
//! will be granted access to the CS in that order.
const QueueingSemaphore = @This();

// **======================================**
// ||          <<<<< FIELDS >>>>>          ||
// **======================================**

head: u8 = 0,
tail: u8 = 0,
count: u8 = 0,
permits: usize,
leader_queue_sem: InterProcessSemaphore,
waiter_queue_sem: InterProcessSemaphore,
cs_sem: InterProcessSemaphore,
arr: [std.math.maxInt(u8) + 1]std.c.pid_t = [_]std.c.pid_t{-1} ** (std.math.maxInt(u8) + 1),

// **=======================================**
// ||          <<<<< IMPORTS >>>>>          ||
// **=======================================**

const std = @import("std");
// const CheckingSemaphore = @import("CheckingSemaphore.zig");
const InterProcessSemaphore = @import("InterProcessSemaphore.zig");

// **=======================================**
// ||          <<<<< METHODS >>>>>          ||
// **=======================================**

pub fn init(permits: usize) !QueueingSemaphore {
    return .{
        .permits = permits,
        .cs_sem = try .init(permits),
        .leader_queue_sem = try .init(1),
        .waiter_queue_sem = try .init(1),
    };
}

/// Adds the current process (via its PID) to the queue.
fn join(self: *QueueingSemaphore) !void {
    var waiting = true;
    while (waiting) {
        try self.waiter_queue_sem.wait();
        errdefer self.waiter_queue_sem.post();
        try self.leader_queue_sem.wait();
        errdefer self.leader_queue_sem.post();
        // Join the queue if there is room, otherwise keep waiting.
        if (self.count < std.math.maxInt(u8)) {
            self.arr[self.tail] = std.c.getpid();
            self.tail +%= 1;
            self.count +|= 1;
            waiting = false;
        }
        self.leader_queue_sem.post();
        self.waiter_queue_sem.post();
        if (waiting) {
            std.Thread.yield() catch {};
            std.Thread.sleep(1_000_000);
        }
    }
}

/// Joins the current process (via its PID) to the queue and blocks until it's
/// that process's turn.
pub fn wait(self: *QueueingSemaphore) !void {
    try self.join();

    var waiting = true;
    while (waiting) {
        try self.waiter_queue_sem.wait();
        errdefer self.waiter_queue_sem.post();
        try self.leader_queue_sem.wait();
        errdefer self.leader_queue_sem.post();
        if (self.arr[self.head] == std.c.getpid()) {
            waiting = false;
        }
        self.leader_queue_sem.post();
        self.waiter_queue_sem.post();

        if (waiting) {
            std.Thread.sleep(1_000_000);
        }
    }

    try self.cs_sem.wait();
    errdefer self.cs_sem.post();

    // Remove self from the head of the queue.
    try self.leader_queue_sem.wait();
    errdefer self.leader_queue_sem.post();
    if (self.arr[self.head] == std.c.getpid()) {
        self.arr[self.head] = -1;
        self.head +%= 1;
        self.count -|= 1;
    }
    self.leader_queue_sem.post();
}

/// Signals that this process has finished with the critical section.
pub fn post(self: *QueueingSemaphore) void {
    // Release the critical section semaphore.
    self.cs_sem.post();
}
