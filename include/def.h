#if defined __GNUC__ && defined __GNUC_MINOR__
#  define GNUC_GEQ(major, minor) \
        ((__GNUC__ << 16) + __GNUC_MINOR__ >= ((major) << 16) + (minor))
#else
#  define GNUC_GEQ(major, minor) 0
#endif

#if GNUC_GEQ(2, 0)
#  define LIKELY(expr) (__builtin_expect(!!(expr), 1))
#  define UNLIKELY(expr) (__builtin_expect(!!(expr), 0))
#else
#  define LIKELY(expr) (expr)
#  define UNLIKELY(expr) (expr)
#endif

#if GNUC_GEQ(2, 3)
#  define PRINTF(format_index, first_argument_index) \
        __attribute__((format(printf, format_index, first_argument_index)))
#  define UNUSED __attribute__((__unused__))
#else
#  define PRINTF(format_index, first_argument_index) /* PRINTF */
#  define UNUSED /* UNUSED */
#endif

#if GNUC_GEQ(2, 5)
#  define CONST __attribute__((__const__))
#else
#  define CONST /* CONST */
#endif

#if GNUC_GEQ(2, 97)
#  define PURE __attribute__((__pure__))
#else
#  define PURE /* PURE */
#endif

#if GNUC_GEQ(7)
#  define FALLTHROUGH __attribute__((__fallthrough__))
#else
#  define FALLTHROUGH /* FALLTHROUGH */((void)0)
#endif

#define lengthof(a) (sizeof(a) / sizeof((a)[0]))
#define fieldof(type, field) (((type *)0)->field)

#define list_for_each(type, item, list) \
        for (type *item = list; item != NULL; item = item->next)

#define list_for_each_safe(type, item, n, list) \
        for (type *item = list, *n = item != NULL ? item->next : NULL; \
             item != NULL; item = n, n = n != NULL ? n->next : NULL)

#define list_reverse(type, item, p, n, list) \
        for (type *item=list, *p = NULL, *n = item != NULL ? item->next : NULL; \
             item != NULL; \
             item->next = p, p = item, item = n, n = n != NULL ? n->next : NULL)
