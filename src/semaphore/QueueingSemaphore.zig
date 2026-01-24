//! This struct represents a queueing semaphore. Processes that join the queue
//! will be granted access to the CS in that order.
const QueueingSemaphore = @This();

// **======================================**
// ||          <<<<< FIELDS >>>>>          ||
// **======================================**

permits: usize,
cs_sem: InterProcessSemaphore,
queue: Queue,

// **=======================================**
// ||          <<<<< IMPORTS >>>>>          ||
// **=======================================**

const std = @import("std");
const InterProcessSemaphore = @import("InterProcessSemaphore.zig");

// **=========================================**
// ||          <<<<< VARIABLES >>>>>          ||
// **=========================================**

// ----- SHORT-HANDS -----
const pid_t = std.c.pid_t;
const getpid = std.c.getpid;

// ----- STRUCTS -----

const Queue = struct {
    // ----- FIELDS -----
    head: u8 = 0,
    tail: u8 = 0,
    count: u8 = 0,

    leader_sem: InterProcessSemaphore,
    waiter_sem: InterProcessSemaphore,

    arr: [std.math.maxInt(u8) + 1]pid_t = [_]pid_t{-1} ** (std.math.maxInt(u8) + 1),

    // ----- METHODS -----

    pub fn init() !Queue {
        return .{
            .leader_sem = try .init(1),
            .waiter_sem = try .init(1),
        };
    }

    fn _add(self: *Queue, val: pid_t) void {
        self.arr[self.tail] = val;
        self.tail +%= 1;
        self.count +|= 1;
    }

    fn _peek(self: *Queue) pid_t {
        return self.arr[self.head];
    }

    fn _pop(self: *Queue) pid_t {
        const val = self._peek();

        self.arr[self.head] = -1;
        self.head +%= 1;
        self.count -|= 1;

        return val;
    }

    pub fn join(self: *Queue) void {
        var waiting = true;
        while (waiting) : ({
            std.Thread.yield() catch {};
            std.Thread.sleep(1_000_000); // 1 millisecond.
        }) {
            self.waiter_sem.wait() catch continue;
            defer self.waiter_sem.post();
            {
                self.leader_sem.wait() catch continue;
                defer self.leader_sem.post();

                // Join the queue if there is room, otherwise keep waiting.
                if (self.count < std.math.maxInt(u8)) {
                    self._add(getpid());
                    waiting = false;
                }
            }
        }
    }

    pub fn peek(self: *Queue) !pid_t {
        try self.leader_sem.wait();
        defer self.leader_sem.post();

        return self._peek();
    }

    pub fn pop(self: *Queue) !pid_t {
        try self.leader_sem.wait();
        defer self.leader_sem.post();

        return self._pop();
    }

    pub fn leave(self: *Queue) !void {
        try self.leader_sem.wait();
        defer self.leader_sem.post();

        if (self._peek() == std.c.getpid()) {
            _ = self._pop();
        }
    }

    pub fn getCount(self: *Queue) !u8 {
        try self.leader_sem.wait();
        defer self.leader_sem.post();

        return self.count;
    }

    pub fn skipable(self: *Queue) bool {
        self.waiter_sem.wait() catch return false;
        defer self.waiter_sem.post();
        self.leader_sem.wait() catch return false;
        defer self.leader_sem.post();

        return (self.count == 0);
    }
};

// **=======================================**
// ||          <<<<< METHODS >>>>>          ||
// **=======================================**

pub fn init(permits: usize) !QueueingSemaphore {
    return .{
        .permits = permits,
        .cs_sem = try .init(permits),
        .queue = try .init(),
    };
}

/// Joins the current process (via its PID) to the queue and blocks until it's
/// that process's turn.
pub fn wait(self: *QueueingSemaphore) !void {
    self.queue.join();

    // Wait until it is this process's turn.
    var waiting = true;
    while (waiting) : (std.Thread.sleep(1_000_000)) {
        if ((self.queue.peek() catch continue) == getpid()) {
            waiting = false;
        }
    }

    // Acquire the critical section semaphore.
    try self.cs_sem.wait();
    errdefer self.cs_sem.post();

    // Remove self from the head of the queue (try twice).
    try (self.queue.leave() catch self.queue.leave());
}

pub fn tryWait(self: *QueueingSemaphore) bool {
    return (self.queue.skipable() and self.cs_sem.tryWait());
}

/// Signals that this process has finished with the critical section.
pub fn post(self: *QueueingSemaphore) void {
    self.cs_sem.post();
}

/// Gets the number of "entities" currently waiting to join the semaphore
/// queue.
pub fn count(self: *QueueingSemaphore) !u8 {
    return try self.queue.getCount();
}
