/* Opens the DualSense the same way RiseHapticTrigger.dll does, sends an R2 wall for 3 s, then frees the triggers. */
#include "../../plugin_src/RiseHapticTrigger.c"

int main(void) {
    crc_init();
    InitializeCriticalSection(&g_lock);
    if (!pad_open()) {
        printf("open failed: note=%s last_error=%lu\n", g_note, (unsigned long)g_last_error);
        return 1;
    }
    printf("open ok: %s out_len=%d bluetooth=%d pid=%04x\n", g_note, g_pad.out_len, g_pad.bluetooth, g_pad.pid);
    Effect wall = { 1.0f, 0.0f, 0.0f, 1.0f }, off = { 0 };
    unsigned char r[11], l[11];
    encode_effect(&wall, r);
    encode_effect(&off, l);
    printf("wall bytes:");
    for (int i = 0; i < 11; ++i) printf(" %02x", r[i]);
    printf("\n");
    for (int i = 0; i < 10; ++i) {
        int ok = send_triggers(r, l);
        if (i == 0) printf("first send: %s (last_error=%lu)\n", ok ? "ok" : "FAILED", (unsigned long)g_last_error);
        Sleep(300);
    }
    send_off();
    printf("sent=%llu errors=%llu last_error=%lu; triggers freed\n", g_sent, g_errors, (unsigned long)g_last_error);
    pad_close();
    return 0;
}
