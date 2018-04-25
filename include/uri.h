struct uri {
        struct uri_string {
                const char *s;
                size_t n;
        } scheme;
        struct uri_string userinfo;
        struct uri_string host;
        long port;
        struct uri_string path;
        struct uri_string query;
        struct uri_string fragment;
};

#define URI_INIT (struct uri){ \
                {NULL,0}, {NULL,0}, {NULL,0}, -1, {NULL,0}, {NULL,0}, {NULL,0} \
        }

int uri_parse(struct uri *uri, struct errors *errors, const char **s_end,
              const char *s, size_t n);
PURE int uri_string_cmp(const struct uri_string *a, const struct uri_string *b);
PURE int uri_cmp(const struct uri *a, const struct uri *b);
