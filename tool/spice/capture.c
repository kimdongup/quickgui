#include <spice-client.h>
#include <gdk-pixbuf/gdk-pixbuf.h>
#include <stdio.h>
#include <string.h>

static GMainLoop *loop;
static SpiceDisplayChannel *display;
static SpiceInputsChannel *inputs;
static const char *output;
static int result = 1;

static gboolean send_key(gpointer unused) {
    if (inputs) spice_inputs_channel_key_press_and_release(inputs, 0x25);
    return G_SOURCE_REMOVE;
}

static gboolean capture(gpointer unused) {
    SpiceDisplayPrimary primary;
    if (!display || !spice_display_channel_get_primary(SPICE_CHANNEL(display), 0, &primary)) {
        fprintf(stderr, "No primary surface received\n");
        g_main_loop_quit(loop);
        return G_SOURCE_REMOVE;
    }
    if (primary.format != SPICE_SURFACE_FMT_32_xRGB ||
        primary.width <= 0 || primary.height <= 0) {
        fprintf(stderr, "Unsupported surface format %d\n", primary.format);
        g_main_loop_quit(loop);
        return G_SOURCE_REMOVE;
    }
    GdkPixbuf *image = gdk_pixbuf_new(GDK_COLORSPACE_RGB, FALSE, 8,
                                    primary.width, primary.height);
    guchar *pixels = gdk_pixbuf_get_pixels(image);
    int stride = gdk_pixbuf_get_rowstride(image);
    unsigned nonzero = 0;
    for (int y = 0; y < primary.height; y++) {
        for (int x = 0; x < primary.width; x++) {
            const guchar *src = primary.data + y * primary.stride + x * 4;
            guchar *dst = pixels + y * stride + x * 3;
            dst[0] = src[2]; dst[1] = src[1]; dst[2] = src[0];
            if (dst[0] || dst[1] || dst[2]) nonzero++;
        }
    }
    GError *error = NULL;
    if (gdk_pixbuf_save(image, output, "png", &error, NULL) && nonzero) {
        printf("SPICE frame: %dx%d, %u nonblack pixels, saved %s\n",
               primary.width, primary.height, nonzero, output);
        result = 0;
    } else {
        fprintf(stderr, "Capture failed: %s\n", error ? error->message : "empty frame");
    }
    g_clear_error(&error);
    g_object_unref(image);
    g_main_loop_quit(loop);
    return G_SOURCE_REMOVE;
}

static void channel_new(SpiceSession *session, SpiceChannel *channel, gpointer data) {
    gint type, id;
    g_object_get(channel, "channel-type", &type, "channel-id", &id, NULL);
    printf("SPICE channel type=%d id=%d\n", type, id);
    if (type == SPICE_CHANNEL_DISPLAY && id == 0 && !display)
        display = g_object_ref(SPICE_DISPLAY_CHANNEL(channel));
    if (type == SPICE_CHANNEL_INPUTS && !inputs)
        inputs = g_object_ref(SPICE_INPUTS_CHANNEL(channel));
    if (type == SPICE_CHANNEL_DISPLAY || type == SPICE_CHANNEL_INPUTS ||
        type == SPICE_CHANNEL_CURSOR)
        spice_channel_connect(channel);
}

int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IONBF, 0);
    if ((argc != 3 && argc != 4) || (argc == 4 && strcmp(argv[3], "--send-k"))) return 2;
    output = argv[2];
    loop = g_main_loop_new(NULL, FALSE);
    SpiceSession *session = spice_session_new();
    g_object_set(session, "uri", argv[1], "enable-audio", FALSE, NULL);
    g_signal_connect(session, "channel-new", G_CALLBACK(channel_new), NULL);
    if (!spice_session_connect(session)) return 3;
    if (argc == 4) g_timeout_add_seconds(2, send_key, NULL);
    g_timeout_add_seconds(5, capture, NULL);
    g_main_loop_run(loop);
    spice_session_disconnect(session);
    g_clear_object(&display);
    g_clear_object(&inputs);
    g_object_unref(session);
    g_main_loop_unref(loop);
    return result;
}
