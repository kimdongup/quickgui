#include <spice-client.h>
#include <gdk-pixbuf/gdk-pixbuf.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

static GMainLoop *loop;
static SpiceDisplayChannel *display;
static SpiceInputsChannel *inputs;
static const char *output;
static int result = 1;
static SpiceMainChannel *main_channel;
static int click_x = -1, click_y = -1;
static gboolean input_required, input_sent;
static guint key_code = 0x25;
static int display_id;

static gboolean request_client_mouse(gpointer unused) {
    if (main_channel) spice_main_channel_request_mouse_mode(main_channel, SPICE_MOUSE_MODE_CLIENT);
    return G_SOURCE_REMOVE;
}

static gboolean click_pointer(gpointer unused) {
    gint mode = 0;
    if (main_channel) g_object_get(main_channel, "mouse-mode", &mode, NULL);
    SpiceDisplayPrimary primary;
    if (!inputs || mode != SPICE_MOUSE_MODE_CLIENT || !display ||
        !spice_display_channel_get_primary(SPICE_CHANNEL(display), 0, &primary) ||
        click_x >= primary.width || click_y >= primary.height) {
        fprintf(stderr, "Absolute SPICE pointer unavailable; no click sent\n");
        return G_SOURCE_REMOVE;
    }
    spice_inputs_channel_position(inputs, click_x, click_y, display_id, 0);
    spice_inputs_channel_button_press(inputs, SPICE_MOUSE_BUTTON_LEFT, SPICE_MOUSE_BUTTON_MASK_LEFT);
    spice_inputs_channel_button_release(inputs, SPICE_MOUSE_BUTTON_LEFT, 0);
    input_sent = TRUE;
    printf("SPICE pointer click: %d,%d\n", click_x, click_y);
    return G_SOURCE_REMOVE;
}

static gboolean send_key(gpointer unused) {
    if (inputs) {
        spice_inputs_channel_key_press_and_release(inputs, key_code);
        input_sent = TRUE;
        printf("SPICE key sent: 0x%x\n", key_code);
    }
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
        result = input_required && !input_sent ? 1 : 0;
    } else {
        fprintf(stderr, "Capture failed (display %d, %dx%d): %s\n", display_id, primary.width, primary.height, error ? error->message : "empty frame");
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
    if (type == SPICE_CHANNEL_MAIN && !main_channel)
        main_channel = g_object_ref(SPICE_MAIN_CHANNEL(channel));
    if (type == SPICE_CHANNEL_DISPLAY && id == display_id && !display)
        display = g_object_ref(SPICE_DISPLAY_CHANNEL(channel));
    if (type == SPICE_CHANNEL_INPUTS && !inputs)
        inputs = g_object_ref(SPICE_INPUTS_CHANNEL(channel));
    if (type == SPICE_CHANNEL_DISPLAY || type == SPICE_CHANNEL_INPUTS ||
        type == SPICE_CHANNEL_CURSOR)
        spice_channel_connect(channel);
}

int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IONBF, 0);
    gboolean key = FALSE, click = FALSE;
    if (argc < 3) return 2;
    for (int i = 3; i < argc; i++) {
        if (!strcmp(argv[i], "--send-k")) key = TRUE;
        else if (!strcmp(argv[i], "--wake")) { key = TRUE; key_code = 0x2a; }
        else if (!strcmp(argv[i], "--display-id") && i + 1 < argc) {
            char *end;
            long id = strtol(argv[++i], &end, 10);
            if (!*argv[i] || *end || id < 0 || id > 15) return 2;
            display_id = (int)id;
        } else if (!strcmp(argv[i], "--click") && i + 2 < argc) {
            char *end_x, *end_y;
            long x = strtol(argv[i+1], &end_x, 10), y = strtol(argv[i+2], &end_y, 10);
            if (!*argv[i+1] || !*argv[i+2] || *end_x || *end_y || x < 0 || y < 0 || x > 16383 || y > 16383) return 2;
            click_x = (int)x; click_y = (int)y; click = TRUE; i += 2;
        } else return 2;
    }
    input_required = key || click;
    output = argv[2];
    loop = g_main_loop_new(NULL, FALSE);
    SpiceSession *session = spice_session_new();
    g_object_set(session, "uri", argv[1], "enable-audio", FALSE, NULL);
    g_signal_connect(session, "channel-new", G_CALLBACK(channel_new), NULL);
    if (!spice_session_connect(session)) return 3;
    if (key) g_timeout_add_seconds(2, send_key, NULL);
    if (click) {
        g_timeout_add_seconds(1, request_client_mouse, NULL);
        g_timeout_add_seconds(3, click_pointer, NULL);
    }
    g_timeout_add_seconds(5, capture, NULL);
    g_main_loop_run(loop);
    spice_session_disconnect(session);
    g_clear_object(&main_channel);
    g_clear_object(&display);
    g_clear_object(&inputs);
    g_object_unref(session);
    g_main_loop_unref(loop);
    return result;
}
