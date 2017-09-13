#include <stdarg.h>
#include <stddef.h>
#include <unistd.h>

#include <def.h>
#include <io-in.h>
#include <io-out.h>

int
io_out_close(struct io_out *out)
{
        return out->fs->close(out);
}
