//! This struct represents a semaphore that is to be used for IPC.
const InterProcessSemaphore = @This();

// **======================================**
// ||          <<<<< FIELDS >>>>>          ||
// **======================================**

/// The number of "entities" the semaphore allows in at any given time.
permits: usize,
c_sem: std.c.sem_t,

// **=======================================**
// ||          <<<<< IMPORTS >>>>>          ||
// **=======================================**

const std = @import("std");

// **=======================================**
// ||          <<<<< METHODS >>>>>          ||
// **=======================================**

pub fn init(permits: usize) !InterProcessSemaphore {
    var self = InterProcessSemaphore{
        .permits = permits,
        .c_sem = undefined,
    };

    // Initialize the semaphore.
    const sem_init_result = std.c.sem_init(&self.c_sem, 1, @intCast(permits));
    if (sem_init_result != 0) {
        switch (std.posix.errno(sem_init_result)) {
            .INVAL => return error.INVAL,
            .NOSPC => return error.NOSPC,
            .NOSYS => return error.NOSYS,
            .PERM => return error.PERM,
            else => {},
        }
    }

    return self;
}

pub fn deinit(self: *InterProcessSemaphore) void {
    if (self.wait()) |_| {
        _ = std.c.sem_destroy(&self.c_sem);
    } else |_| {}
}

pub fn wait(self: *InterProcessSemaphore) !void {
    const result = std.c.sem_wait(&self.c_sem);
    if (result != 0) {
        switch (std.posix.errno(result)) {
            .INTR => return error.INTR,
            .INVAL => unreachable,
            else => {},
        }
    }
}

pub fn tryWait(self: *InterProcessSemaphore) bool {
    const result = std.c.sem_trywait(&self.c_sem);
    if (result != 0) {
        switch (std.posix.errno(result)) {
            .AGAIN, .INTR => return false,
            .INVAL => unreachable,
            else => {},
        }
        return false;
    } else return true;
}

pub fn timedWait(self: *InterProcessSemaphore, sec: u32, nsec: u32) bool {

    // Calculate the time spec for the operation.
    var ts: std.c.timespec = undefined;
    const ts_result = std.c.clock_gettime(std.c.CLOCK.REALTIME, &ts);
    if (ts_result != 0) {
        switch (std.posix.errno(ts_result)) {
            .FAULT, .INVAL, .NOTSUP, .NODEV, .PERM, .ACCES => unreachable,
            else => {},
        }
    }
    ts.sec += @intCast(sec + @divFloor(nsec + @as(u32, ts.nsec), 1_000_000_000));
    ts.nsec = @intCast((nsec + @as(u32, ts.nsec)) % 1_000_000_000);

    // Wait on the semaphore.
    const result = std.c.sem_timedwait(&self.c_sem, ts);
    if (result != 0) {
        switch (std.posix.errno(result)) {
            .INTR, .TIMEDOUT => return false,
            .INVAL => unreachable,
            else => {},
        }

        return false;
    } else return true;
}

pub fn post(self: *InterProcessSemaphore) void {
    // We do not care about the errors post would produce.
    _ = std.c.sem_post(&self.c_sem);
}
