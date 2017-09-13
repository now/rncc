int format(char **output, void *(*malloc)(size_t), const char *format,
           ...) PRINTF(3, 4);
int formatv(char **output, void *(*malloc)(size_t), const char *format,
            va_list args) PRINTF(3, 0);
