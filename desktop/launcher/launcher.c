#define UNICODE
#define _UNICODE
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>
#include <objbase.h>
#include <strsafe.h>

static HWND window, cancelButton;
static HANDLE child, readyEvent, worker;
static DWORD launchError, resultCode;
static volatile LONG cancelled;
static BOOL handedOff, failed;
static HFONT bodyFont, titleFont;
static UINT dpi = 96;
static ULONGLONG started;
static WCHAR target[32768], directory[32768], *childCommand;

static int px(int dip) { return MulDiv(dip, (int)dpi, 96); }
static void setFonts(void) {
    if (bodyFont) DeleteObject(bodyFont);
    if (titleFont) DeleteObject(titleFont);
    bodyFont = CreateFontW(-px(14), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE, DEFAULT_CHARSET, 0, 0, CLEARTYPE_QUALITY, 0, L"Segoe UI");
    titleFont = CreateFontW(-px(22), 0, 0, 0, FW_SEMIBOLD, FALSE, FALSE, FALSE, DEFAULT_CHARSET, 0, 0, CLEARTYPE_QUALITY, 0, L"Segoe UI");
    SendMessageW(cancelButton, WM_SETFONT, (WPARAM)bodyFont, TRUE);
}
static void layout(void) {
    RECT client; GetClientRect(window, &client);
    MoveWindow(cancelButton, max(px(12), client.right - px(108)), max(px(12), client.bottom - px(46)), px(92), px(32), TRUE);
}
static void paint(HWND hwnd) {
    PAINTSTRUCT ps; HDC dc = BeginPaint(hwnd, &ps);
    RECT r; GetClientRect(hwnd, &r);
    HBRUSH background = CreateSolidBrush(RGB(13, 21, 33)); FillRect(dc, &r, background); DeleteObject(background);
    SetBkMode(dc, TRANSPARENT); SetTextColor(dc, RGB(235, 242, 249)); SelectObject(dc, titleFont);
    r.left = px(20); r.right -= px(20); r.top = px(18); r.bottom = px(55);
    DrawTextW(dc, failed ? L"Could not open HWID Checker" : L"Starting HWID Checker", -1, &r, DT_LEFT | DT_WORDBREAK | DT_NOPREFIX);
    SelectObject(dc, bodyFont); SetTextColor(dc, failed ? RGB(255, 200, 100) : RGB(101, 222, 207));
    WCHAR text[280];
    if (failed) StringCchPrintfW(text, 280, L"Startup stopped (code %lu). Repair the installation or extract the complete package again. Keep all its files together.", resultCode);
    else if (cancelled) StringCchCopyW(text, 280, L"Cancelling startup. Waiting for Windows to finish opening the application process…");
    else StringCchPrintfW(text, 280, L"Opening the desktop… %llu s\nWindows may take longer to verify files on the first launch.", (GetTickCount64() - started) / 1000);
    r.top = px(65); r.bottom = px(129); DrawTextW(dc, text, -1, &r, DT_LEFT | DT_WORDBREAK | DT_NOPREFIX);
    SetTextColor(dc, RGB(166, 190, 211)); r.top = px(139); r.bottom = px(180); r.right -= px(106);
    DrawTextW(dc, L"No scan starts automatically. Close to cancel before the desktop opens.", -1, &r, DT_LEFT | DT_WORDBREAK | DT_NOPREFIX);
    EndPaint(hwnd, &ps);
}
static DWORD WINAPI launch(LPVOID unused) {
    (void)unused;
    STARTUPINFOW si = { sizeof(si) }; PROCESS_INFORMATION pi = {0};
    si.dwFlags = STARTF_USESHOWWINDOW; si.wShowWindow = SW_SHOWNORMAL;
    BOOL ok = CreateProcessW(target, childCommand, NULL, NULL, FALSE, CREATE_SUSPENDED, NULL, directory, &si, &pi);
    DWORD error = ok ? 0 : GetLastError();
    if (ok) {
        if (InterlockedCompareExchange(&cancelled, 0, 0)) TerminateProcess(pi.hProcess, 0);
        else ResumeThread(pi.hThread);
        CloseHandle(pi.hThread);
    }
    PostMessageW(window, WM_APP + 1, (WPARAM)pi.hProcess, error);
    if (ok) {
        WaitForSingleObject(pi.hProcess, INFINITE);
        DWORD code = 1; GetExitCodeProcess(pi.hProcess, &code);
        PostMessageW(window, WM_APP + 2, code, 0);
    }
    return 0;
}
static void closeStartup(void) {
    if (failed) { DestroyWindow(window); return; }
    if (WaitForSingleObject(readyEvent, 0) == WAIT_OBJECT_0) { handedOff = TRUE; KillTimer(window, 1); ShowWindow(window, SW_HIDE); return; }
    if (handedOff) return;
    InterlockedExchange(&cancelled, 1);
    EnableWindow(cancelButton, FALSE);
    // Only this launcher's newly created child is cancelled; never an existing window.
    if (child) TerminateProcess(child, 0);
    InvalidateRect(window, NULL, FALSE);
}
static LRESULT CALLBACK wndProc(HWND hwnd, UINT msg, WPARAM w, LPARAM l) {
    switch (msg) {
    case WM_PAINT: paint(hwnd); return 0;
    case WM_ERASEBKGND: return 1;
    case WM_SIZE: if (cancelButton) layout(); return 0;
    case WM_DPICHANGED: {
        dpi = HIWORD(w); setFonts();
        RECT *r = (RECT*)l;
        SetWindowPos(hwnd, NULL, r->left, r->top, r->right-r->left, r->bottom-r->top, SWP_NOZORDER | SWP_NOACTIVATE);
        layout(); InvalidateRect(hwnd, NULL, TRUE); return 0;
    }
    case WM_APP + 1:
        child = (HANDLE)w; launchError = (DWORD)l;
        if (cancelled && child) TerminateProcess(child, 0);
        if (launchError) {
            KillTimer(hwnd, 1);
            resultCode = launchError; failed = TRUE;
            if (cancelled) { resultCode = 0; DestroyWindow(hwnd); }
            else { SetWindowTextW(cancelButton, L"Close"); InvalidateRect(hwnd, NULL, FALSE); }
        }
        return 0;
    case WM_APP + 2:
        resultCode = (DWORD)w;
        if (handedOff || cancelled || resultCode == 0) DestroyWindow(hwnd);
        else { failed = TRUE; KillTimer(hwnd, 1); SetWindowTextW(cancelButton, L"Close"); InvalidateRect(hwnd, NULL, FALSE); }
        return 0;
    case WM_TIMER:
        if (!handedOff && !cancelled && WaitForSingleObject(readyEvent, 0) == WAIT_OBJECT_0) {
            handedOff = TRUE; KillTimer(hwnd, 1); ShowWindow(hwnd, SW_HIDE);
        }
        if (!handedOff) InvalidateRect(hwnd, NULL, FALSE);
        return 0;
    case WM_COMMAND: if (LOWORD(w) == IDCANCEL) closeStartup(); return 0;
    case WM_CLOSE: closeStartup(); return 0;
    case WM_DESTROY: PostQuitMessage((int)resultCode); return 0;
    }
    return DefWindowProcW(hwnd, msg, w, l);
}
int WINAPI wWinMain(HINSTANCE instance, HINSTANCE previous, PWSTR args, int show) {
    (void)previous; (void)show;
    started = GetTickCount64();
    DWORD length = GetModuleFileNameW(NULL, directory, 32768);
    if (length == 0 || length >= 32767) return ERROR_BAD_PATHNAME;
    WCHAR *slash = wcsrchr(directory, L'\\'); if (!slash) return ERROR_BAD_PATHNAME; *slash = 0;
    if (FAILED(StringCchPrintfW(target, 32768, L"%s\\HWID Checker.App.exe", directory))) return ERROR_BAD_PATHNAME;
    size_t count = wcslen(target) + wcslen(args) + 5;
    if (count >= 32767) return ERROR_BAD_ARGUMENTS;
    childCommand = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, count * sizeof(WCHAR));
    if (!childCommand) return ERROR_NOT_ENOUGH_MEMORY;
    StringCchPrintfW(childCommand, count, L"\"%s\" %s", target, args);
    GUID guid; WCHAR guidText[40], eventName[80], pid[24], ticks[32];
    if (FAILED(CoCreateGuid(&guid))) return ERROR_GEN_FAILURE;
    StringFromGUID2(&guid, guidText, 40); guidText[37] = 0;
    StringCchPrintfW(eventName, 80, L"Local\\HWID-Startup-%s", guidText + 1);
    readyEvent = CreateEventW(NULL, TRUE, FALSE, eventName);
    if (!readyEvent) return (int)GetLastError();
    FILETIME creation, exitTime, kernel, user; ULARGE_INTEGER time;
    GetProcessTimes(GetCurrentProcess(), &creation, &exitTime, &kernel, &user);
    time.LowPart = creation.dwLowDateTime; time.HighPart = creation.dwHighDateTime;
    StringCchPrintfW(pid, 24, L"%lu", GetCurrentProcessId());
    StringCchPrintfW(ticks, 32, L"%llu", time.QuadPart + 504911232000000000ULL);
    SetEnvironmentVariableW(L"HWID_DESKTOP_READY_EVENT", eventName);
    SetEnvironmentVariableW(L"HWID_LAUNCHER_PID", pid);
    SetEnvironmentVariableW(L"HWID_LAUNCHER_START_TICKS", ticks);
    WNDCLASSW wc = {0}; wc.hInstance = instance; wc.lpfnWndProc = wndProc;
    wc.lpszClassName = L"HWID-EarlyStartup"; wc.hCursor = LoadCursorW(NULL, IDC_ARROW);
    wc.hIcon = LoadIconW(instance, MAKEINTRESOURCEW(101)); RegisterClassW(&wc);
    POINT cursor; GetCursorPos(&cursor); MONITORINFO monitor = { sizeof(monitor) };
    GetMonitorInfoW(MonitorFromPoint(cursor, MONITOR_DEFAULTTOPRIMARY), &monitor);
    window = CreateWindowExW(0, wc.lpszClassName, L"Starting HWID Checker", WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU,
        monitor.rcWork.left + 10, monitor.rcWork.top + 10, 480, 250, NULL, NULL, instance, NULL);
    if (!window) return (int)GetLastError();
    dpi = GetDpiForWindow(window); if (!dpi) dpi = 96;
    RECT size = { 0, 0, px(460), px(200) }; AdjustWindowRectExForDpi(&size, WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU, FALSE, 0, dpi);
    int width = min(size.right-size.left, monitor.rcWork.right-monitor.rcWork.left);
    int height = min(size.bottom-size.top, monitor.rcWork.bottom-monitor.rcWork.top);
    SetWindowPos(window, NULL, monitor.rcWork.left + (monitor.rcWork.right-monitor.rcWork.left-width)/2,
        monitor.rcWork.top + (monitor.rcWork.bottom-monitor.rcWork.top-height)/2, width, height, SWP_NOZORDER);
    cancelButton = CreateWindowW(L"BUTTON", L"Cancel", WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_PUSHBUTTON, 0, 0, 0, 0, window, (HMENU)IDCANCEL, instance, NULL);
    setFonts(); layout(); ShowWindow(window, SW_SHOW); UpdateWindow(window);
    SetTimer(window, 1, 150, NULL);
    worker = CreateThread(NULL, 0, launch, NULL, 0, NULL);
    if (!worker) PostMessageW(window, WM_APP + 1, 0, GetLastError());
    MSG msg; while (GetMessageW(&msg, NULL, 0, 0) > 0) { if (!IsDialogMessageW(window, &msg)) { TranslateMessage(&msg); DispatchMessageW(&msg); } }
    if (worker) { WaitForSingleObject(worker, INFINITE); CloseHandle(worker); }
    if (child) CloseHandle(child);
    CloseHandle(readyEvent); HeapFree(GetProcessHeap(), 0, childCommand);
    if (bodyFont) DeleteObject(bodyFont); if (titleFont) DeleteObject(titleFont);
    return (int)resultCode;
}
