struct io_fd_out {
        struct io_out self;
        int fd;
};

extern const struct io_out_fns io_fd_out_fns;

#define IO_FD_OUT_INIT(fd) (struct io_fd_out){ { &io_fd_out_fns }, fd }

struct io_fd_out io_fd_out_init(int fd);
