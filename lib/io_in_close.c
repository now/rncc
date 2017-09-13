#include <stdarg.h>
#include <stddef.h>
#include <unistd.h>

#include <def.h>
#include <io-in.h>

int
io_in_close(struct io_in *in)
{
        return in->fs->close(in);
}
