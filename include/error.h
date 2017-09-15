// TODO Just use a buffer here, don’t require a malloc.  What would be
// an appropriate size?  What’s the maximum length of a reasonable
// error message?  Actually, a middle-road here is to provide a malloc
// that’s based on a static buffer.
struct error {
        struct location location;
        enum error_level {
                ERROR_LEVEL_NOTE,
                ERROR_LEVEL_ERROR
        } level;
        const char *message;
        bool message_is_static;
};

extern struct error error_oom;

#define ERROR_INIT(l, v, m) (struct error){ l, v, m, true }

int error_init(struct error *error, void *(*malloc)(size_t),
               const struct location *l, enum error_level v,
               const char *message, ...) PRINTF(5, 6);
void error_inits(struct error *error, const struct location *l,
                 enum error_level v, const char *message);
int error_initv(struct error *error, void *(*malloc)(size_t),
                const struct location *l, enum error_level v,
                const char *message, va_list args) PRINTF(5, 0);
int error_str(struct io_out *out, const struct error *error);
void error_free(struct error *error, void (*free)(void *));

struct errors {
        struct error *s;
        size_t n;
        size_t m;
        void *(*malloc)(size_t n);
};

#define ERRORS_INIT(m, malloc) (struct errors){ \
        (struct error[m]){ { .message_is_static = true } }, 0, (m), (malloc) \
}

struct errors errors_init(struct error *s, size_t m, void *(*malloc)(size_t n));
int errors_add(struct errors *errors, const struct location *l,
               enum error_level v, const char *message, ...) PRINTF(4, 5);
void errors_adds(struct errors *errors, const struct location *l,
                 enum error_level v, const char *message);
int errors_addv(struct errors *errors, const struct location *l,
                enum error_level v, const char *message,
                va_list args) PRINTF(4, 0);
void errors_push(struct errors *errors, struct error *error);
void errors_free(struct errors *errors, void (*free)(void *));

int error_level_str(struct io_out *out, enum error_level level);
