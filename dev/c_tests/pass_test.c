/* Exercises each lookup pass and the NtCreateFile open of RiseHapticTrigger.c on its own. */
#include "../../plugin_src/RiseHapticTrigger.c"

static void report(const char *label, int ok) {
    printf("%-28s %s  note=%s  last_error=0x%lx  paths=%lu\n", label, ok ? "FOUND" : "none ", g_note,
           (unsigned long)g_last_error, g_paths_seen);
    if (ok) {
        unsigned char off[11] = { 0x05 };
        printf("    write test: %s\n", send_triggers(off, off) ? "ok" : "FAILED");
        pad_close();
    }
}

int main(void) {
    crc_init();
    GUID hid_guid;
    HidD_GetHidGuid(&hid_guid);
    g_paths_seen = 0;
    report("pass 1 (SetupAPI)", scan_setupapi(&hid_guid));
    g_paths_seen = 0;
    report("pass 2 (CfgMgr32)", scan_cfgmgr(&hid_guid));
    g_paths_seen = 0;
    report("pass 3 (registry)", scan_registry());
    /* NtCreateFile directly on the registry-derived path of the present pad. */
    HKEY key;
    wchar_t name[512];
    int nt_ok = 0;
    if (RegOpenKeyExW(HKEY_LOCAL_MACHINE,
                      L"SYSTEM\\CurrentControlSet\\Control\\DeviceClasses\\{4d1e55b2-f16f-11cf-88cb-001111000030}", 0,
                      KEY_READ, &key) == ERROR_SUCCESS) {
        for (DWORD i = 0; !nt_ok; ++i) {
            DWORD len = 512;
            if (RegEnumKeyExW(key, i, name, &len, NULL, NULL, NULL, NULL) != ERROR_SUCCESS)
                break;
            wchar_t lower[1024], path[600];
            _snwprintf(path, 600, L"\\\\?\\%ls", name + 4);
            if (!is_dualsense_path(path, lower, 1024))
                continue;
            HANDLE h = nt_open(path, GENERIC_READ | GENERIC_WRITE);
            if (h != INVALID_HANDLE_VALUE) {
                g_pad.handle = h;
                g_pad.out_len = 48;
                g_pad.bluetooth = 0;
                unsigned char off[11] = { 0x05 };
                printf("NtCreateFile open: ok (%ls)\n    write test: %s\n", path, send_triggers(off, off) ? "ok" : "FAILED");
                pad_close();
                nt_ok = 1;
            }
        }
        RegCloseKey(key);
    }
    if (!nt_ok)
        printf("NtCreateFile open: FAILED (last_error=0x%lx)\n", (unsigned long)g_last_error);
    return 0;
}
