//! This struct represents a semaphore that is to be used for IPC.
const InterProcessSemaphore = @This();

// **======================================**
// ||          <<<<< FIELDS >>>>>          ||
// **======================================**

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
            .INVAL => return error.INVAL,
            .NOSPC => return error.NOSPC,
            .NOSYS => return error.NOSYS,
            .DEADLK => return error.DEADLK,
            .INTR => return error.INTR,
            else => {},
        }
    }
}

pub fn trywait(self: *InterProcessSemaphore) !void {
    const result = std.c.sem_trywait(&self.c_sem);
    if (result != 0) {
        switch (std.posix.errno(result)) {
            .INVAL => return error.INVAL,
            .NOSPC => return error.NOSPC,
            .NOSYS => return error.NOSYS,
            .DEADLK => return error.DEADLK,
            .INTR => return error.INTR,
            else => {},
        }
    }
}

pub fn post(self: *InterProcessSemaphore) void {
    // We do not care about the errors post would produce.
    _ = std.c.sem_post(&self.c_sem);
}
