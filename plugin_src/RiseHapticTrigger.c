/*
 * RiseHapticTrigger.dll - DualSense adaptive-trigger bridge for Rise Haptic Pack.
 *
 * Monster Hunter Rise has no native DualSense support, so the pad goes through Steam Input as an XInput pad and the
 * game cannot reach the triggers. The Lua mod writes the wanted effects to reframework/data/RiseHapticPack_trigger.txt;
 * this plugin (loaded by REFramework from reframework/plugins) sends them straight to the DualSense over HID, USB or
 * Bluetooth. Only the two trigger-effect bits of the output report are set, so rumble, haptics and lights stay Steam's.
 *
 * Command line: "<seq> <Rpower> <Rfreq> <Rstart> <Rend> <Lpower> <Lfreq> <Lstart> <Lend> end"   (all 0..1)
 * Status file:  reframework/data/RiseHapticPack_bridge.txt  (key=value lines, rewritten every second)
 *
 * Steam Input hides the physical pad from the game process (GameOverlayRenderer64 filters device enumeration and
 * opens), so the pad is looked up three ways (SetupAPI, CfgMgr32, the DeviceClasses registry key) and opened with
 * CreateFileW, falling back to ntdll!NtCreateFile.
 *
 * Build: gcc -O2 -shared -static-libgcc -o RiseHapticTrigger.dll RiseHapticTrigger.c -lsetupapi -lhid -lcfgmgr32
 */
#include <windows.h>
#include <winternl.h>
#include <setupapi.h>
#include <cfgmgr32.h>
#include <hidsdi.h>
#include <hidpi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

#define VERSION "0.1.1"
#define SONY_VID 0x054C
#define REFRESH_MS 300   /* re-send active effects: Steam may overwrite the triggers */
#define POLL_MS 4
#define SCAN_MS 1500

typedef struct {
    float power, frequency, start, finish;
} Effect;

typedef struct {
    HANDLE handle;
    int bluetooth;
    int out_len;
    unsigned char seq;
    unsigned short pid;
} Pad;

static volatile LONG g_stop = 0;
static HANDLE g_thread = NULL;
static wchar_t g_command_path[MAX_PATH];
static wchar_t g_status_path[MAX_PATH];
static Pad g_pad = { INVALID_HANDLE_VALUE, 0, 0, 0, 0 };
static CRITICAL_SECTION g_lock;

static unsigned long long g_sent = 0, g_errors = 0, g_commands = 0;
static DWORD g_last_error = 0;
static const char *g_note = "starting";
static int g_focused = 1;

/* ---- CRC32 (Bluetooth output reports) ---------------------------------------------------------------------- */
static unsigned int crc_table[256];

static void crc_init(void) {
    for (unsigned int i = 0; i < 256; ++i) {
        unsigned int c = i;
        for (int k = 0; k < 8; ++k)
            c = (c & 1) ? 0xEDB88320u ^ (c >> 1) : c >> 1;
        crc_table[i] = c;
    }
}

static unsigned int crc_update(unsigned int crc, const unsigned char *data, size_t len) {
    for (size_t i = 0; i < len; ++i)
        crc = crc_table[(crc ^ data[i]) & 0xFF] ^ (crc >> 8);
    return crc;
}

/* ---- Trigger effect encoding (DualSense firmware modes, as documented by Nielk1) ------------------------------ */
static int clampi(int v, int lo, int hi) { return v < lo ? lo : (v > hi ? hi : v); }
static int roundf_i(float v) { return (int)(v + (v >= 0 ? 0.5f : -0.5f)); }

static void put_zones(unsigned char *dest, unsigned short active, unsigned int values) {
    dest[1] = (unsigned char)(active & 0xFF);
    dest[2] = (unsigned char)(active >> 8);
    dest[3] = (unsigned char)(values & 0xFF);
    dest[4] = (unsigned char)((values >> 8) & 0xFF);
    dest[5] = (unsigned char)((values >> 16) & 0xFF);
    dest[6] = (unsigned char)((values >> 24) & 0xFF);
}

/* Effect { power, frequency, start, end } -> 11 trigger bytes (mode + 10 parameters). */
static void encode_effect(const Effect *e, unsigned char out[11]) {
    memset(out, 0, 11);
    if (e->power <= 0.001f && e->frequency <= 0.001f) {
        out[0] = 0x05; /* off */
        return;
    }
    int start = clampi(roundf_i(e->start * 9.0f), 0, 9);
    int finish = clampi(roundf_i(e->finish * 9.0f), 0, 9);
    if (finish < start) { int t = start; start = finish; finish = t; }
    int strength = clampi(roundf_i(e->power * 8.0f), 1, 8);
    unsigned short active = 0;
    unsigned int values = 0;

    if (e->frequency > 0.001f) {
        /* Vibration (0x26): amplitude per zone, frequency in Hz. */
        for (int i = start; i <= finish; ++i) {
            active |= (unsigned short)(1u << i);
            values |= (unsigned int)((strength - 1) & 7) << (3 * i);
        }
        out[0] = 0x26;
        put_zones(out, active, values);
        out[9] = (unsigned char)clampi(roundf_i(5.0f + e->frequency * 195.0f), 1, 255);
        return;
    }
    if (start >= 2 && finish <= 8 && finish > start && (finish - start) <= 3) {
        /* Weapon (0x25): resistance that gives way at the end - a click. */
        unsigned short zones = (unsigned short)((1u << start) | (1u << finish));
        out[0] = 0x25;
        out[1] = (unsigned char)(zones & 0xFF);
        out[2] = (unsigned char)(zones >> 8);
        out[3] = (unsigned char)(strength - 1);
        return;
    }
    /* Feedback (0x21): resistance in zones start..finish. */
    for (int i = start; i <= finish; ++i) {
        active |= (unsigned short)(1u << i);
        values |= (unsigned int)((strength - 1) & 7) << (3 * i);
    }
    out[0] = 0x21;
    put_zones(out, active, values);
}

/* ---- HID device ---------------------------------------------------------------------------------------------- */
static void pad_close(void) {
    if (g_pad.handle != INVALID_HANDLE_VALUE)
        CloseHandle(g_pad.handle);
    g_pad.handle = INVALID_HANDLE_VALUE;
}

typedef NTSTATUS(NTAPI *NtCreateFile_fn)(PHANDLE, ACCESS_MASK, POBJECT_ATTRIBUTES, PIO_STATUS_BLOCK, PLARGE_INTEGER,
                                         ULONG, ULONG, ULONG, ULONG, PVOID, ULONG);
typedef VOID(NTAPI *RtlInitUnicodeString_fn)(PUNICODE_STRING, PCWSTR);

static char g_note_buf[160];
static unsigned long g_paths_seen = 0;

static int is_dualsense_path(const wchar_t *path, wchar_t *lower, size_t lower_len) {
    wcsncpy(lower, path, lower_len - 1);
    lower[lower_len - 1] = 0;
    _wcslwr(lower);
    return wcsstr(lower, L"vid_054c") && (wcsstr(lower, L"pid_0ce6") || wcsstr(lower, L"pid_0df2"));
}

/* ntdll!NtCreateFile: not filtered by Steam's CreateFileW hook. "\?\hid#..." -> "\??\hid#...". */
static HANDLE nt_open(const wchar_t *path, ACCESS_MASK access) {
    HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
    NtCreateFile_fn nt_create = ntdll ? (NtCreateFile_fn)(void *)GetProcAddress(ntdll, "NtCreateFile") : NULL;
    RtlInitUnicodeString_fn init = ntdll ? (RtlInitUnicodeString_fn)(void *)GetProcAddress(ntdll, "RtlInitUnicodeString") : NULL;
    if (!nt_create || !init)
        return INVALID_HANDLE_VALUE;
    wchar_t nt_path[1100];
    if (wcsncmp(path, L"\\\\?\\", 4) == 0 || wcsncmp(path, L"\\\\.\\", 4) == 0)
        _snwprintf(nt_path, 1100, L"\\??\\%ls", path + 4);
    else
        _snwprintf(nt_path, 1100, L"%ls", path);
    nt_path[1099] = 0;
    UNICODE_STRING name;
    init(&name, nt_path);
    OBJECT_ATTRIBUTES attributes;
    InitializeObjectAttributes(&attributes, &name, OBJ_CASE_INSENSITIVE, NULL, NULL);
    IO_STATUS_BLOCK io;
    HANDLE h = INVALID_HANDLE_VALUE;
    NTSTATUS status = nt_create(&h, access | SYNCHRONIZE, &attributes, &io, NULL, FILE_ATTRIBUTE_NORMAL,
                                FILE_SHARE_READ | FILE_SHARE_WRITE, FILE_OPEN,
                                FILE_SYNCHRONOUS_IO_NONALERT | FILE_NON_DIRECTORY_FILE, NULL, 0);
    if (status < 0) {
        g_last_error = (DWORD)status;
        return INVALID_HANDLE_VALUE;
    }
    return h;
}

static HANDLE open_path(const wchar_t *path, const char **method) {
    DWORD share = FILE_SHARE_READ | FILE_SHARE_WRITE;
    HANDLE h = CreateFileW(path, GENERIC_READ | GENERIC_WRITE, share, NULL, OPEN_EXISTING, 0, NULL);
    if (h == INVALID_HANDLE_VALUE)
        h = CreateFileW(path, GENERIC_WRITE, share, NULL, OPEN_EXISTING, 0, NULL);
    if (h != INVALID_HANDLE_VALUE) {
        *method = "CreateFile";
        return h;
    }
    g_last_error = GetLastError();
    h = nt_open(path, GENERIC_READ | GENERIC_WRITE);
    if (h == INVALID_HANDLE_VALUE)
        h = nt_open(path, GENERIC_WRITE);
    *method = "NtCreateFile";
    return h;
}

/* Opens path if it is a DualSense; fills g_pad. */
static int try_path(const wchar_t *path, int pass) {
    wchar_t lower[1024];
    ++g_paths_seen;
    if (!is_dualsense_path(path, lower, 1024))
        return 0;
    const char *method = "";
    HANDLE h = open_path(path, &method);
    if (h == INVALID_HANDLE_VALUE) {
        snprintf(g_note_buf, sizeof(g_note_buf), "DualSense found (pass %d) but cannot be opened", pass);
        g_note = g_note_buf;
        return 0;
    }
    PHIDP_PREPARSED_DATA pre = NULL;
    HIDP_CAPS caps;
    memset(&caps, 0, sizeof(caps));
    if (HidD_GetPreparsedData(h, &pre)) {
        HidP_GetCaps(pre, &caps);
        HidD_FreePreparsedData(pre);
    }
    g_pad.handle = h;
    g_pad.out_len = caps.OutputReportByteLength;
    g_pad.bluetooth = wcsstr(lower, L"00001124-0000-1000-8000-00805f9b34fb") != NULL || caps.OutputReportByteLength >= 78;
    g_pad.pid = wcsstr(lower, L"pid_0df2") ? 0x0DF2 : 0x0CE6;
    snprintf(g_note_buf, sizeof(g_note_buf), "DualSense open (%s, pass %d, %s)", g_pad.bluetooth ? "Bluetooth" : "USB",
             pass, method);
    g_note = g_note_buf;
    return 1;
}

/* Pass 1: SetupAPI. */
static int scan_setupapi(const GUID *hid_guid) {
    HDEVINFO set = SetupDiGetClassDevsW(hid_guid, NULL, NULL, DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
    if (set == INVALID_HANDLE_VALUE)
        return 0;
    int found = 0;
    SP_DEVICE_INTERFACE_DATA iface;
    iface.cbSize = sizeof(iface);
    for (DWORD index = 0; !found && SetupDiEnumDeviceInterfaces(set, NULL, hid_guid, index, &iface); ++index) {
        DWORD size = 0;
        SetupDiGetDeviceInterfaceDetailW(set, &iface, NULL, 0, &size, NULL);
        if (size == 0)
            continue;
        SP_DEVICE_INTERFACE_DETAIL_DATA_W *detail = (SP_DEVICE_INTERFACE_DETAIL_DATA_W *)malloc(size);
        if (!detail)
            continue;
        detail->cbSize = sizeof(SP_DEVICE_INTERFACE_DETAIL_DATA_W);
        if (SetupDiGetDeviceInterfaceDetailW(set, &iface, detail, size, NULL, NULL))
            found = try_path(detail->DevicePath, 1);
        free(detail);
    }
    SetupDiDestroyDeviceInfoList(set);
    return found;
}

/* Pass 2: CfgMgr32 interface list. */
static int scan_cfgmgr(GUID *hid_guid) {
    ULONG length = 0;
    if (CM_Get_Device_Interface_List_SizeW(&length, hid_guid, NULL, CM_GET_DEVICE_INTERFACE_LIST_PRESENT) != CR_SUCCESS ||
        length == 0)
        return 0;
    wchar_t *list = (wchar_t *)calloc(length + 1, sizeof(wchar_t));
    if (!list)
        return 0;
    int found = 0;
    if (CM_Get_Device_Interface_ListW(hid_guid, NULL, list, length, CM_GET_DEVICE_INTERFACE_LIST_PRESENT) == CR_SUCCESS) {
        for (wchar_t *p = list; !found && *p; p += wcslen(p) + 1)
            found = try_path(p, 2);
    }
    free(list);
    return found;
}

/* Pass 3: HKLM\...\DeviceClasses\{HID}\##?#HID#VID_054C&PID_0CE6...  ->  \?\HID#VID_054C&PID_0CE6... */
static int scan_registry(void) {
    HKEY key;
    if (RegOpenKeyExW(HKEY_LOCAL_MACHINE,
                      L"SYSTEM\\CurrentControlSet\\Control\\DeviceClasses\\{4d1e55b2-f16f-11cf-88cb-001111000030}", 0,
                      KEY_READ, &key) != ERROR_SUCCESS)
        return 0;
    int found = 0;
    wchar_t name[512];
    for (DWORD index = 0; !found; ++index) {
        DWORD name_len = 512;
        if (RegEnumKeyExW(key, index, name, &name_len, NULL, NULL, NULL, NULL) != ERROR_SUCCESS)
            break;
        if (wcsncmp(name, L"##?#", 4) != 0)
            continue;
        wchar_t path[600];
        _snwprintf(path, 600, L"\\\\?\\%ls", name + 4);
        path[599] = 0;
        found = try_path(path, 3);
    }
    RegCloseKey(key);
    return found;
}

static int pad_open(void) {
    GUID hid_guid;
    HidD_GetHidGuid(&hid_guid);
    g_paths_seen = 0;
    g_last_error = 0;
    g_note = "no DualSense found";
    if (scan_setupapi(&hid_guid) || scan_cfgmgr(&hid_guid) || scan_registry())
        return 1;
    return 0;
}

static int write_report(unsigned char *buf, int len) {
    DWORD written = 0;
    if (WriteFile(g_pad.handle, buf, (DWORD)len, &written, NULL))
        return 1;
    g_last_error = GetLastError();
    if (HidD_SetOutputReport(g_pad.handle, buf, (ULONG)len))
        return 1;
    g_last_error = GetLastError();
    return 0;
}

/* Sends both trigger effects; nothing else in the report is marked valid. */
static int send_triggers(const unsigned char right[11], const unsigned char left[11]) {
    if (g_pad.handle == INVALID_HANDLE_VALUE)
        return 0;
    unsigned char buf[600];
    int ok;
    memset(buf, 0, sizeof(buf));
    if (!g_pad.bluetooth) {
        int len = g_pad.out_len > 0 && g_pad.out_len <= (int)sizeof(buf) ? g_pad.out_len : 48;
        buf[0] = 0x02;
        buf[1] = 0x0C; /* valid_flag0: right (0x04) + left (0x08) trigger effect */
        memcpy(buf + 11, right, 11);
        memcpy(buf + 22, left, 11);
        ok = write_report(buf, len);
    } else {
        buf[0] = 0x31;
        buf[1] = (unsigned char)(g_pad.seq << 4);
        g_pad.seq = (unsigned char)((g_pad.seq + 1) & 0x0F);
        buf[2] = 0x10;
        buf[3] = 0x0C;
        memcpy(buf + 13, right, 11);
        memcpy(buf + 24, left, 11);
        unsigned char seed = 0xA2;
        unsigned int crc = crc_update(0xFFFFFFFFu, &seed, 1);
        crc = ~crc_update(crc, buf, 74);
        buf[74] = (unsigned char)(crc & 0xFF);
        buf[75] = (unsigned char)((crc >> 8) & 0xFF);
        buf[76] = (unsigned char)((crc >> 16) & 0xFF);
        buf[77] = (unsigned char)((crc >> 24) & 0xFF);
        ok = write_report(buf, 78);
        if (!ok && g_pad.out_len > 78 && g_pad.out_len <= (int)sizeof(buf))
            ok = write_report(buf, g_pad.out_len);
    }
    if (ok)
        ++g_sent;
    else
        ++g_errors;
    return ok;
}

static void send_off(void) {
    unsigned char off[11];
    memset(off, 0, sizeof(off));
    off[0] = 0x05;
    send_triggers(off, off);
}

/* ---- Command / status files ---------------------------------------------------------------------------------- */
static int read_command(long *seq, Effect *right, Effect *left) {
    FILE *f = _wfopen(g_command_path, L"rb");
    if (!f)
        return 0;
    char text[256];
    size_t n = fread(text, 1, sizeof(text) - 1, f);
    fclose(f);
    text[n] = 0;
    char marker[8] = { 0 };
    int got = sscanf(text, "%ld %f %f %f %f %f %f %f %f %7s", seq, &right->power, &right->frequency, &right->start,
                     &right->finish, &left->power, &left->frequency, &left->start, &left->finish, marker);
    return got == 10 && strcmp(marker, "end") == 0;
}

static void write_status(void) {
    FILE *f = _wfopen(g_status_path, L"wb");
    if (!f)
        return;
    fprintf(f, "version=%s\nopen=%d\nbluetooth=%d\npid=%04x\nout_len=%d\nsent=%llu\nerrors=%llu\ncommands=%llu\n"
               "last_error=%lu\nfocused=%d\npaths_seen=%lu\nnote=%s\ntick=%lu\n",
            VERSION, g_pad.handle != INVALID_HANDLE_VALUE, g_pad.bluetooth, g_pad.pid, g_pad.out_len, g_sent,
            g_errors, g_commands, (unsigned long)g_last_error, g_focused, g_paths_seen, g_note, (unsigned long)GetTickCount());
    fclose(f);
}

static int effect_is_off(const Effect *e) { return e->power <= 0.001f && e->frequency <= 0.001f; }

static int game_has_focus(void) {
    HWND window = GetForegroundWindow();
    DWORD pid = 0;
    if (window)
        GetWindowThreadProcessId(window, &pid);
    return pid == GetCurrentProcessId();
}

static DWORD WINAPI worker(LPVOID unused) {
    (void)unused;
    long last_seq = -1;
    Effect right = { 0 }, left = { 0 };
    unsigned char right_bytes[11], left_bytes[11];
    DWORD last_scan = 0, last_send = 0, last_status = 0;
    int active = 0, was_focused = 1;
    Sleep(1000);
    while (!g_stop) {
        DWORD now = GetTickCount();
        EnterCriticalSection(&g_lock);
        if (g_pad.handle == INVALID_HANDLE_VALUE && now - last_scan >= SCAN_MS) {
            last_scan = now;
            if (pad_open())
                last_seq = -1; /* re-send the current command to the new pad */
        }
        long seq = 0;
        Effect r, l;
        if (read_command(&seq, &r, &l) && seq != last_seq) {
            last_seq = seq;
            right = r;
            left = l;
            ++g_commands;
            encode_effect(&right, right_bytes);
            encode_effect(&left, left_bytes);
            active = !(effect_is_off(&right) && effect_is_off(&left));
            last_send = 0; /* send now */
        }
        /* Alt-tabbed out: the triggers go free until the game is back in front. */
        g_focused = game_has_focus();
        if (g_focused != was_focused) {
            was_focused = g_focused;
            last_send = 0;
        }
        /* Send on change; while focused, re-send active effects every REFRESH_MS. Unfocused: one "off", no refresh. */
        int refresh = g_focused && active && now - last_send >= REFRESH_MS;
        if (g_pad.handle != INVALID_HANDLE_VALUE && last_seq >= 0 && (last_send == 0 || refresh)) {
            int ok;
            if (g_focused)
                ok = send_triggers(right_bytes, left_bytes);
            else {
                send_off();
                ok = 1;
            }
            last_send = now ? now : 1;
            if (!ok && (g_last_error == ERROR_DEVICE_NOT_CONNECTED || g_last_error == ERROR_GEN_FAILURE ||
                        g_last_error == ERROR_INVALID_HANDLE || g_errors % 50 == 49)) {
                g_note = "write failed, reopening";
                pad_close();
            }
        }
        LeaveCriticalSection(&g_lock);
        if (now - last_status >= 1000) {
            last_status = now;
            write_status();
        }
        Sleep(POLL_MS);
    }
    return 0;
}

/* ---- Entry point --------------------------------------------------------------------------------------------- */
static void build_paths(void) {
    wchar_t exe[MAX_PATH];
    DWORD n = GetModuleFileNameW(NULL, exe, MAX_PATH);
    if (n == 0 || n >= MAX_PATH)
        exe[0] = 0;
    wchar_t *slash = wcsrchr(exe, L'\\');
    if (slash)
        slash[1] = 0;
    _snwprintf(g_command_path, MAX_PATH, L"%lsreframework\\data\\RiseHapticPack_trigger.txt", exe);
    _snwprintf(g_status_path, MAX_PATH, L"%lsreframework\\data\\RiseHapticPack_bridge.txt", exe);
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID reserved) {
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(instance);
        InitializeCriticalSection(&g_lock);
        crc_init();
        build_paths();
        g_thread = CreateThread(NULL, 0, worker, NULL, 0, NULL);
    } else if (reason == DLL_PROCESS_DETACH) {
        g_stop = 1;
        if (reserved == NULL && g_thread) {
            WaitForSingleObject(g_thread, 200);
        }
        /* Leave the pad with free triggers when the game closes. */
        if (g_pad.handle != INVALID_HANDLE_VALUE) {
            send_off();
            pad_close();
        }
    }
    return TRUE;
}
