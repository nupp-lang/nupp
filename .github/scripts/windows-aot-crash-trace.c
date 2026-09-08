#include <windows.h>
#include <dbghelp.h>
#include <stdio.h>
static char prefix[4096];
static LONG CALLBACK report(EXCEPTION_POINTERS *exception) {
    DWORD code = exception->ExceptionRecord->ExceptionCode;
    if (code != EXCEPTION_ACCESS_VIOLATION && code != EXCEPTION_ILLEGAL_INSTRUCTION) return EXCEPTION_CONTINUE_SEARCH;
    char path[4200], module[4096];
    HMODULE owner = NULL;
    DWORD64 rip = exception->ContextRecord->Rip;
    GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT, (LPCSTR)rip, &owner);
    GetModuleFileNameA(owner, module, sizeof(module));
    snprintf(path, sizeof(path), "%s.txt", prefix);
    FILE *log = fopen(path, "w");
    if (log) {
        fprintf(log, "code=%lx rip=%llx module=%s offset=%llx rsp=%llx rcx=%llx rdx=%llx r8=%llx fault=%llx\n", (unsigned long)code, rip, module, rip-(DWORD64)owner, exception->ContextRecord->Rsp, exception->ContextRecord->Rcx, exception->ContextRecord->Rdx, exception->ContextRecord->R8, (DWORD64)exception->ExceptionRecord->ExceptionInformation[1]);
        fclose(log);
    }
    snprintf(path, sizeof(path), "%s.dmp", prefix);
    HANDLE file = CreateFileA(path, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (file != INVALID_HANDLE_VALUE) {
        MINIDUMP_EXCEPTION_INFORMATION info;
        info.ThreadId = GetCurrentThreadId();
        info.ExceptionPointers = exception;
        info.ClientPointers = FALSE;
        MiniDumpWriteDump(GetCurrentProcess(), GetCurrentProcessId(), file, MiniDumpNormal, &info, NULL, NULL);
        CloseHandle(file);
    }
    return EXCEPTION_CONTINUE_SEARCH;
}
__declspec(dllexport) void trace_install(const char *value) {
    snprintf(prefix, sizeof(prefix), "%s", value);
    AddVectoredExceptionHandler(1, report);
}
