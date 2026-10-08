/* The macOS Limelog crash, without Apple headers.

   RtpAudioQueue logs queue->blockHead fields and then sets blockHead to
   NULL. Andy's Limelog macro evaluated those fields inside dispatch_async,
   on the main thread, after the pointer was cleared. The fix formats the
   line before the hop. This file queues the finished text, drops the
   pointer, then delivers.
*/
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static char g_logged[256];
static int g_logged_count;
static char* g_pending[4];
static int g_pending_count;

static void deliver(const char* format, ...)
{
    va_list ap;

    va_start(ap, format);
    vsnprintf(g_logged, sizeof(g_logged), format, ap);
    va_end(ap);
    g_logged_count++;
}

static void enqueue(char* copy)
{
    if (g_pending_count >= 4) {
        fprintf(stderr, "FAIL queue full\n");
        exit(1);
    }
    g_pending[g_pending_count++] = copy;
}

static void drain(void)
{
    int i;

    for (i = 0; i < g_pending_count; i++) {
        deliver("%s", g_pending[i]);
        free(g_pending[i]);
        g_pending[i] = NULL;
    }
    g_pending_count = 0;
}

#define Limelog(s, ...) \
    do { \
        char _limelogBuf[4096]; \
        if (snprintf(_limelogBuf, sizeof(_limelogBuf), s, ##__VA_ARGS__) >= 0) { \
            char *_limelogCopy = strdup(_limelogBuf); \
            if (_limelogCopy != NULL) { \
                enqueue(_limelogCopy); \
            } \
        } \
    } while (0)

struct Block {
    unsigned base;
    unsigned data;
    unsigned fec;
};

struct Queue {
    struct Block* blockHead;
};

static int fail(const char* label)
{
    fprintf(stderr, "FAIL %s (logged=%s count=%d)\n", label, g_logged, g_logged_count);
    return 1;
}

int main(void)
{
    struct Queue queue;
    struct Block block;

    block.base = 1000;
    block.data = 4;
    block.fec = 2;
    queue.blockHead = &block;

    Limelog("Unable to recover audio data block %u to %u (%u+%u=%u received < %u needed)\n",
            queue.blockHead->base,
            queue.blockHead->base + 8 - 1,
            queue.blockHead->data,
            queue.blockHead->fec,
            queue.blockHead->data + queue.blockHead->fec,
            8);
    Limelog("Audio packet queue overflow\n");

    /* The receive thread drops the block before the main queue runs. */
    queue.blockHead = NULL;
    if (g_logged_count != 0) {
        return fail("delivery must wait until the main queue runs");
    }
    drain();
    if (g_logged_count != 2) {
        return fail("both lines should be delivered");
    }
    if (strstr(g_logged, "Audio packet queue overflow") == NULL) {
        return fail("second line was not delivered");
    }

    g_logged_count = 0;
    g_logged[0] = '\0';
    queue.blockHead = &block;
    Limelog("Unable to recover audio data block %u (%u received)\n",
            queue.blockHead->base,
            queue.blockHead->data);
    queue.blockHead = NULL;
    drain();
    if (g_logged_count != 1) {
        return fail("drain count");
    }
    if (strstr(g_logged, "1000") == NULL || strstr(g_logged, "(4 received)") == NULL) {
        return fail("values were not captured before blockHead was cleared");
    }
    if (strstr(g_logged, "%u") != NULL) {
        return fail("format string was delivered unexpanded");
    }

    Limelog("literal percent %% stays\n");
    drain();
    if (strstr(g_logged, "literal percent % stays") == NULL) {
        return fail("percent was interpreted twice");
    }
    return 0;
}
