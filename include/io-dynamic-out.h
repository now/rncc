struct io_dynamic_out {
        struct io_out self;
        void *(*realloc)(void *s, size_t n);
        char *s;
        size_t n;
        size_t m;
};

extern const struct io_out_fns io_dynamic_out_fns;

#define IO_DYNAMIC_OUT_INIT(realloc) (struct io_dynamic_out){ \
        { &io_dynamic_out_fns }, (realloc), NULL, 0, 0 \
}

struct io_dynamic_out io_dynamic_out_init(void *(*realloc)(void *s, size_t n));
int io_dynamic_out_expand(struct io_dynamic_out *o, size_t n);
