struct io_out {
        const struct io_out_fns {
                ssize_t (*write)(struct io_out *out, const char *s, size_t n);
                int (*close)(struct io_out *out);
        } *fs;
};

int io_write(struct io_out *out, const char *s, size_t n);
// TODO Add
// int io_write_once(struct io_out *out, const char *s, size_t n);
int io_out_close(struct io_out *out);

ssize_t io_feed(struct io_out *out, struct io_in *in);
int io_print(struct io_out *out, const char *format, ...) PRINTF(2, 3);
int io_printv(struct io_out *out, const char *format, va_list args) PRINTF(2, 0);
int io_write_z(struct io_out *out, const char *s);
