struct io_fd_in {
        struct io_in self;
        int fd;
};

extern const struct io_in_fns io_fd_in_fns;

#define IO_FD_IN_INIT(fd) (struct io_fd_in){ { &io_fd_in_fns }, fd }

CONST struct io_fd_in io_fd_in_init(int fd);
