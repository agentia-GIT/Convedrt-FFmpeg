/* Lanceur Convert-ToHEVC : script PowerShell embarque (ressource RCDATA 100), ecrit dans %TEMP%,
   execute par Windows PowerShell (STA, sans console), puis supprime. */


#include <windows.h>
#include <stdio.h>
#include <wchar.h>

#ifndef APP_TAG
#define APP_TAG L"V7a"
#endif

static void fail(const wchar_t *msg) {
    MessageBoxW(NULL, msg, L"Convert-ToHEVC", MB_OK | MB_ICONERROR);
}

int WINAPI wWinMain(HINSTANCE hInst, HINSTANCE hPrev, PWSTR cmd, int show) {
    wchar_t exe[MAX_PATH * 2], dir[MAX_PATH * 2], tmp[MAX_PATH * 2], ps1[MAX_PATH * 4], sys[MAX_PATH * 2], psexe[MAX_PATH * 4];
    wchar_t cl[MAX_PATH * 10];
    DWORD n = GetModuleFileNameW(NULL, exe, (DWORD)(sizeof(exe) / sizeof(exe[0])));
    if (n == 0) { fail(L"Impossible de determiner le dossier de l'application."); return 1; }
    wcscpy(dir, exe);
    wchar_t *sl = wcsrchr(dir, L'\\');
    if (sl) *sl = 0;
    SetEnvironmentVariableW(L"HEVC_APPDIR", dir);

    HRSRC r = FindResourceW(NULL, MAKEINTRESOURCEW(100), RT_RCDATA);
    HGLOBAL g = r ? LoadResource(NULL, r) : NULL;
    const void *data = g ? LockResource(g) : NULL;
    DWORD size = r ? SizeofResource(NULL, r) : 0;
    if (!data || !size) { fail(L"Script integre introuvable."); return 1; }

    GetTempPathW((DWORD)(sizeof(tmp) / sizeof(tmp[0])), tmp);
    swprintf(ps1, sizeof(ps1) / sizeof(ps1[0]), L"%lsConvert-ToHEVC_" APP_TAG L"_%lu.ps1", tmp, (unsigned long)GetCurrentProcessId());
    HANDLE h = CreateFileW(ps1, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_TEMPORARY, NULL);
    if (h == INVALID_HANDLE_VALUE) { fail(L"Impossible d'ecrire le script temporaire."); return 1; }
    DWORD wr = 0;
    BOOL ok = WriteFile(h, data, size, &wr, NULL);
    CloseHandle(h);
    if (!ok || wr != size) { DeleteFileW(ps1); fail(L"Ecriture du script temporaire incomplete."); return 1; }

    GetSystemDirectoryW(sys, (UINT)(sizeof(sys) / sizeof(sys[0])));
    swprintf(psexe, sizeof(psexe) / sizeof(psexe[0]), L"%ls\\WindowsPowerShell\\v1.0\\powershell.exe", sys);
    if (GetFileAttributesW(psexe) == INVALID_FILE_ATTRIBUTES) {
        DeleteFileW(ps1);
        fail(L"Windows PowerShell est introuvable sur ce systeme.");
        return 1;
    }
    swprintf(cl, sizeof(cl) / sizeof(cl[0]), L"\"%ls\" -NoProfile -NonInteractive -ExecutionPolicy Bypass -STA -File \"%ls\"", psexe, ps1);

    /* stderr de PowerShell redirige vers un fichier : une erreur de syntaxe / de chargement est ensuite affichee */
    wchar_t errp[MAX_PATH * 4];
    swprintf(errp, sizeof(errp) / sizeof(errp[0]), L"%lsConvert-ToHEVC_" APP_TAG L"_%lu.err", tmp, (unsigned long)GetCurrentProcessId());
    SECURITY_ATTRIBUTES sa; ZeroMemory(&sa, sizeof(sa)); sa.nLength = sizeof(sa); sa.bInheritHandle = TRUE;
    HANDLE hErr = CreateFileW(errp, GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, &sa, CREATE_ALWAYS, FILE_ATTRIBUTE_TEMPORARY, NULL);
    HANDLE hNul = CreateFileW(L"NUL", GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, &sa, OPEN_EXISTING, 0, NULL);

    STARTUPINFOW si; PROCESS_INFORMATION pi;
    ZeroMemory(&si, sizeof(si)); si.cb = sizeof(si);
    ZeroMemory(&pi, sizeof(pi));
    BOOL redirect = (hErr != INVALID_HANDLE_VALUE && hNul != INVALID_HANDLE_VALUE);
    if (redirect) {
        si.dwFlags = STARTF_USESTDHANDLES;
        si.hStdInput = hNul; si.hStdOutput = hErr; si.hStdError = hErr;
    }
    if (!CreateProcessW(psexe, cl, NULL, NULL, redirect, CREATE_NO_WINDOW, NULL, dir, &si, &pi)) {
        if (hErr != INVALID_HANDLE_VALUE) CloseHandle(hErr);
        if (hNul != INVALID_HANDLE_VALUE) CloseHandle(hNul);
        DeleteFileW(errp); DeleteFileW(ps1);
        fail(L"Impossible de lancer Windows PowerShell.");
        return 1;
    }
    if (hErr != INVALID_HANDLE_VALUE) CloseHandle(hErr);
    if (hNul != INVALID_HANDLE_VALUE) CloseHandle(hNul);
    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD code = 0;
    GetExitCodeProcess(pi.hProcess, &code);
    CloseHandle(pi.hProcess); CloseHandle(pi.hThread);
    DeleteFileW(ps1);

    if (code != 0) {
        /* texte d'erreur eventuel (code page OEM de la console) */
        HANDLE hr = CreateFileW(errp, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, 0, NULL);
        if (hr != INVALID_HANDLE_VALUE) {
            char raw[2048]; DWORD got = 0;
            if (ReadFile(hr, raw, sizeof(raw) - 1, &got, NULL) && got > 0) {
                wchar_t wtxt[2200]; wchar_t msg[2600];
                int wl = MultiByteToWideChar(CP_OEMCP, 0, raw, (int)got, wtxt, (int)(sizeof(wtxt) / sizeof(wtxt[0])) - 1);
                if (wl > 0) {
                    wtxt[wl] = 0;
                    swprintf(msg, sizeof(msg) / sizeof(msg[0]), L"Convert-ToHEVC s'est arrete (code %lu) :\n\n%ls", (unsigned long)code, wtxt);
                    fail(msg);
                }
            }
            CloseHandle(hr);
        }
    }
    DeleteFileW(errp);
    return (int)code;
}
