struct location {
        struct point {
                size_t line;
                size_t column;
        } first;
        struct point last;
};

#define LOCATION_NULL (struct location){ { 0, 0 }, { 0, 0 } }

static inline struct location
location_join(struct location a, struct location b)
{
        return (struct location){
                { a.first.line, a.first.column }, { b.last.line, b.last.column }
        };
}

static inline struct location
location_translate(struct location l, struct point p)
{
        return (struct location){
                { l.first.line + (p.line - 1), l.first.column + (p.column - 1) },
                { l.last.line + (p.line - 1), l.last.column + (p.column - 1) }
        };
}

int location_str(struct io_out *out, const struct location *l);
