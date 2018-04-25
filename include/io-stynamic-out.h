struct io_stynamic_out {
        struct io_out self;
        void *(*realloc)(void *s, size_t n);
        char *s;
        size_t n;
        size_t m;
};

extern const struct io_out_fns io_stynamic_out_fns;

#define IO_STYNAMIC_OUT_INIT(b, r) io_stynamic_out_init((char[b]){ 0 }, (b), (r))

CONST struct io_stynamic_out io_stynamic_out_init(char *s, size_t m,
                                                  void *(*realloc)(void *s,
                                                                   size_t n));
PURE bool io_stynamic_is_dynamic(struct io_stynamic_out *o);
