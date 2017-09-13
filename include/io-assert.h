#if defined __GNUC__ && defined __GNUC_MINOR__
#  define IO_GNUC_GEQ(major, minor) \
        ((__GNUC__ << 16) + __GNUC_MINOR__ >= ((major) << 16) + (minor))
#else
#  define IO_GNUC_GEQ(major, minor) 0
#endif

#if IO_GNUC_GEQ(2, 0)
#  define IO_LIKELY(expr) (__builtin_expect(!!(expr), 1))
#  define IO_UNLIKELY(expr) (__builtin_expect(!!(expr), 0))
#else
#  define IO_LIKELY(expr) (expr)
#  define IO_UNLIKELY(expr) (expr)
#endif

#if IO_GNUC_GEQ(2, 3)
#  define IO_PRINTF(format_index, first_argument_index) \
        __attribute__((format(printf, format_index, first_argument_index)))
#else
#  define IO_PRINTF(format_index, first_argument_index) /* IO_PRINTF */
#endif

#ifdef NDEBUG
#  define assert(expr) ((void)0)
#  define verify(expr) (expr)
#else
#  define assert(expr) \
        (IO_LIKELY(expr) ? \
         (void)0 : \
         _io_assert_print(__FILE__, __LINE__, __func__, #expr, NULL))
#  define verify(expr) \
        (IO_LIKELY(expr) ? \
         (void)0 : \
         _io_assert_print(__FILE__, __LINE__, __func__, #expr, NULL))
#endif
#define require(expr) \
        (IO_LIKELY(expr) ? \
         (void)0 : \
         _io_assert_print(__FILE__, __LINE__, __func__, #expr, NULL))
#define vrequire(expr, ...) (IO_LIKELY(expr) ? (void)0 : fail(__VA_ARGS__)
#define fail(...) _io_assert_print(__FILE__, __LINE__, __func__, "", __VA_ARGS__)

_Noreturn void _io_assert_print(const char *file, unsigned int line,
                                const char *function, const char *expr,
                                const char *message,
                                ...) IO_PRINTF(5, 6);
