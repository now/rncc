#include <stddef.h>
#include <unistd.h>

#include <def.h>
#include <io-in.h>
#include <io-fd-in.h>

static ssize_t
io_fd_in_read(void *p, size_t n, struct io_in *in)
{
        return read(((struct io_fd_in *)in)->fd, p, n);
}

static int
io_fd_in_close(struct io_in *in)
{
        return close(((struct io_fd_in *)in)->fd);
}

const struct io_in_fns io_fd_in_fns = {
        .read = io_fd_in_read,
        .close = io_fd_in_close
};

struct io_fd_in
io_fd_in_init(int fd)
{
        return IO_FD_IN_INIT(fd);
}
