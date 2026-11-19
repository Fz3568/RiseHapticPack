/* Loads RiseHapticTrigger.dll like REFramework would and drives it through the command file. */
#include <windows.h>
#include <stdio.h>
#include <string.h>

static void cmd(const char *line) {
    FILE *f = fopen("reframework/data/RiseHapticPack_trigger.txt", "wb");
    fputs(line, f);
    fclose(f);
}

int main(int argc, char **argv) {
    char dir[MAX_PATH];
    GetModuleFileNameA(NULL, dir, MAX_PATH);
    *strrchr(dir, 92) = 0;
    SetCurrentDirectoryA(dir);
    cmd("1 0 0 0 1 0 0 0 1 end\n");
    HMODULE m = LoadLibraryA(argv[1]);
    printf("LoadLibrary: %s\n", m ? "ok" : "FAILED");
    if (!m)
        return 1;
    Sleep(2600);
    cmd("2 1.000 0.000 0.200 0.800 0 0 0 1 end\n");
    Sleep(700);
    cmd("3 1.000 0.200 0.000 1.000 0 0 0 1 end\n");
    Sleep(700);
    cmd("4 0 0 0 1 0 0 0 1 end\n");
    Sleep(1300);
    FILE *f = fopen("reframework/data/RiseHapticPack_bridge.txt", "rb");
    char buf[1024] = { 0 };
    if (f) {
        fread(buf, 1, sizeof(buf) - 1, f);
        fclose(f);
    }
    printf("status file:\n%s\n", buf);
    FreeLibrary(m);
    printf("FreeLibrary done\n");
    return 0;
}
