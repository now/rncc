#include <stdarg.h>
#include <stddef.h>
#include <unistd.h>

#include <def.h>
#include <io-in.h>
#include <io-out.h>
#include <io-fd-out.h>

static ssize_t
io_fd_out_write(struct io_out *out, const char *s, size_t n)
{
        return write(((struct io_fd_out *)out)->fd, s, n);
}

static int
io_fd_out_close(struct io_out *out)
{
        return close(((struct io_fd_out *)out)->fd);
}

const struct io_out_fns io_fd_out_fns = {
        .write = io_fd_out_write,
        .close = io_fd_out_close
};

struct io_fd_out
io_fd_out_init(int fd)
{
        return IO_FD_OUT_INIT(fd);
}
