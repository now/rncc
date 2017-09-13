#include <stdarg.h>
#include <stdbool.h>
#include <string.h>
#include <unistd.h>

#include <def.h>
#include <io-in.h>
#include <io-out.h>
#include <io-buffered-in.h>
#include <io-buffered-out.h>
#include <io-fd-in.h>
#include <io-fd-out.h>
#include <io-std.h>

#ifndef __has_feature
#  define __has_feature(a) false
#endif

enum {
        SANITIZE_ADDRESS =
#if defined __SANITIZE_ADDRESS__ || __has_feature(address_sanitizer)
        true
#else
        false
#endif
};

struct io_out *io_stderr = &IO_FD_OUT_INIT(STDERR_FILENO).self;

struct io_in *io_stdin =
        &IO_BUFFERED_IN_INIT(&IO_FD_IN_INIT(STDIN_FILENO).self).self;

struct io_out *io_stdout =
        &IO_BUFFERED_OUT_INIT(&IO_FD_OUT_INIT(STDOUT_FILENO).self).self;

int
io_std_close(const char *argv0)
{
        int r;
        if ((r = io_out_close(io_stdout)) < 0) {
                io_print(io_stderr, "%s: <stdout>: %s\n", argv0, strerror(-r));
                io_out_close(io_stderr);
                return r;
        }
        return SANITIZE_ADDRESS ? 0 : io_out_close(io_stderr);
}
