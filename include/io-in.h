struct io_in {
        const struct io_in_fns {
                ssize_t (*read)(void *p, size_t n, struct io_in *o);
                int (*close)(struct io_in *in);
        } *fs;
};

ssize_t io_read(void *p, size_t n, struct io_in *in);
ssize_t io_read_once(void *p, size_t n, struct io_in *in);
int io_in_close(struct io_in *in);
