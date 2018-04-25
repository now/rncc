struct io_buffered_in {
        struct io_in self;
        struct io_in *next;
        size_t i;
        size_t n;
        char b[8192];
};

extern const struct io_in_fns io_buffered_in_fns;

#define IO_BUFFERED_IN_INIT(nxt) (struct io_buffered_in){ \
        .self.fs = &io_buffered_in_fns, \
        .next = nxt, \
        .n = 0, \
}

CONST struct io_buffered_in io_buffered_in_init(struct io_in *next);
