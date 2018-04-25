struct io_buffered_out {
        struct io_out self;
        struct io_out *next;
        size_t n;
        char b[8192];
};

extern const struct io_out_fns io_buffered_out_fns;

#define IO_BUFFERED_OUT_INIT(nxt) (struct io_buffered_out){ \
        .self.fs = &io_buffered_out_fns, \
        .next = nxt, \
        .n = 0, \
}

CONST struct io_buffered_out io_buffered_out_init(struct io_out *next);
