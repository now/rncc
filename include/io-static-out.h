struct io_static_out {
        struct io_out self;
        char *s;
        size_t n;
        size_t m;
};

extern const struct io_out_fns io_static_out_fns;

#define IO_STATIC_OUT_INIT(b) io_static_out_init((char[b]){ 0 }, (b))

struct io_static_out io_static_out_init(char *s, size_t m);
