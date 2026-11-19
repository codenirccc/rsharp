module X = X64

type abi = Win64 | SysV

type fmt = Pe | MachO | Elf

type t = { abi : abi; fmt : fmt; name : string; ext : string }

let windows = { abi = Win64; fmt = Pe; name = "windows-x86_64"; ext = ".exe" }
let macos = { abi = SysV; fmt = MachO; name = "macos-x86_64"; ext = "" }
let linux = { abi = SysV; fmt = Elf; name = "linux-x86_64"; ext = "" }

let parse s =
  match String.lowercase_ascii s with
  | "windows" | "win" | "win64" | "pe" -> Some windows
  | "macos" | "mac" | "darwin" | "osx" | "macho" -> Some macos
  | "linux" | "elf" | "gnu" | "glibc" -> Some linux
  | _ -> None

let host =
  if Sys.win32 then windows
  else if Sys.file_exists "/System/Library/CoreServices/SystemVersion.plist" then macos
  else linux

let shadow t = match t.abi with Win64 -> 32 | SysV -> 0

let int_regs t =
  match t.abi with
  | Win64 -> [| X.rcx; X.rdx; X.r8; X.r9 |]
  | SysV -> [| X.rdi; X.rsi; X.rdx; X.rcx; X.r8; X.r9 |]

let int_budget t = Array.length (int_regs t)
let float_budget t = match t.abi with Win64 -> 4 | SysV -> 8

let sret_reg t = match t.abi with Win64 -> X.rcx | SysV -> X.rdi

let lib_system = "/usr/lib/libSystem.B.dylib"
let lib_curl = "/usr/lib/libcurl.4.dylib"
let lib_cf = "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation"
let lib_security = "/System/Library/Frameworks/Security.framework/Security"
let lib_objc = "/usr/lib/libobjc.A.dylib"
let lib_appkit = "/System/Library/Frameworks/AppKit.framework/AppKit"
let lib_cg = "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"

let lib_c = "libc.so.6"
let lib_m = "libm.so.6"
let lib_dl = "libdl.so.2"
let lib_pthread = "libpthread.so.0"
let lib_rt = "librt.so.1"

let tags_win =
  [
    ("kernel32", "kernel32.dll");
    ("msvcrt", "msvcrt.dll");
    ("winhttp", "winhttp.dll");
    ("ws2_32", "ws2_32.dll");
    ("user32", "user32.dll");
    ("advapi32", "advapi32.dll");
    ("shell32", "shell32.dll");
    ("ole32", "ole32.dll");
    ("bcrypt", "bcrypt.dll");
    ("crypt32", "crypt32.dll");
    ("ntdll", "ntdll.dll");
    ("gdi32", "gdi32.dll");
    ("opengl32", "opengl32.dll");
    ("vulkan", "vulkan-1.dll");
  ]

let tags_mac =
  [
    ("system", lib_system);
    ("libsystem", lib_system);
    ("curl", lib_curl);
    ("corefoundation", lib_cf);
    ("security", lib_security);
    ("objc", lib_objc);
    ("appkit", lib_appkit);
    ("coregraphics", lib_cg);
  ]

let tags_linux =
  [
    ("libc", lib_c);
    ("c", lib_c);
    ("system", lib_c);
    ("libm", lib_m);
    ("m", lib_m);
    ("dl", lib_dl);
    ("libdl", lib_dl);
    ("pthread", lib_pthread);
    ("rt", lib_rt);
    ("crypto", "libcrypto.so.3");
    ("ssl", "libssl.so.3");
    ("curl", "libcurl.so.4");
    ("z", "libz.so.1");
    ("x11", "libX11.so.6");
    ("vulkan", "libvulkan.so.1");
  ]

let fixed_win =
  [
    ("ExitProcess", "kernel32.dll");
    ("GetStdHandle", "kernel32.dll");
    ("WriteFile", "kernel32.dll");
    ("ReadFile", "kernel32.dll");
    ("CreateFileA", "kernel32.dll");
    ("CloseHandle", "kernel32.dll");
    ("GetFileSizeEx", "kernel32.dll");
    ("Sleep", "kernel32.dll");
    ("GetTickCount64", "kernel32.dll");
    ("GetSystemTimeAsFileTime", "kernel32.dll");
    ("QueryPerformanceCounter", "kernel32.dll");
    ("QueryPerformanceFrequency", "kernel32.dll");
    ("GetCurrentProcessId", "kernel32.dll");
    ("OutputDebugStringA", "kernel32.dll");
    ("printf", "msvcrt.dll");
    ("puts", "msvcrt.dll");
    ("putchar", "msvcrt.dll");
    ("malloc", "msvcrt.dll");
    ("free", "msvcrt.dll");
    ("calloc", "msvcrt.dll");
    ("realloc", "msvcrt.dll");
    ("memcpy", "msvcrt.dll");
    ("memmove", "msvcrt.dll");
    ("memset", "msvcrt.dll");
    ("sprintf", "msvcrt.dll");
    ("_snprintf", "msvcrt.dll");
    ("strlen", "msvcrt.dll");
    ("strcmp", "msvcrt.dll");
    ("strncmp", "msvcrt.dll");
    ("strcpy", "msvcrt.dll");
    ("strncpy", "msvcrt.dll");
    ("strstr", "msvcrt.dll");
    ("atoi", "msvcrt.dll");
    ("atof", "msvcrt.dll");
    ("qsort", "msvcrt.dll");
    ("time", "msvcrt.dll");
    ("rand", "msvcrt.dll");
    ("srand", "msvcrt.dll");
    ("fopen", "msvcrt.dll");
    ("freopen", "msvcrt.dll");
    ("fclose", "msvcrt.dll");
    ("fread", "msvcrt.dll");
    ("fwrite", "msvcrt.dll");
    ("fseek", "msvcrt.dll");
    ("ftell", "msvcrt.dll");
    ("fflush", "msvcrt.dll");
    ("fgets", "msvcrt.dll");
    ("fputs", "msvcrt.dll");
    ("remove", "msvcrt.dll");
    ("rename", "msvcrt.dll");
    ("system", "msvcrt.dll");
    ("getenv", "msvcrt.dll");
  ]

let fixed_mac =
  [
    ("printf", lib_system);
    ("puts", lib_system);
    ("putchar", lib_system);
    ("malloc", lib_system);
    ("free", lib_system);
    ("calloc", lib_system);
    ("realloc", lib_system);
    ("memcpy", lib_system);
    ("memmove", lib_system);
    ("memset", lib_system);
    ("sprintf", lib_system);
    ("snprintf", lib_system);
    ("strlen", lib_system);
    ("strcmp", lib_system);
    ("strncmp", lib_system);
    ("strcpy", lib_system);
    ("strncpy", lib_system);
    ("strstr", lib_system);
    ("atoi", lib_system);
    ("atof", lib_system);
    ("qsort", lib_system);
    ("time", lib_system);
    ("rand", lib_system);
    ("srand", lib_system);
    ("fopen", lib_system);
    ("freopen", lib_system);
    ("fclose", lib_system);
    ("fread", lib_system);
    ("fwrite", lib_system);
    ("fseek", lib_system);
    ("ftell", lib_system);
    ("fflush", lib_system);
    ("fgets", lib_system);
    ("fputs", lib_system);
    ("remove", lib_system);
    ("rename", lib_system);
    ("system", lib_system);
    ("getenv", lib_system);
    ("getpid", lib_system);
    ("nanosleep", lib_system);
    ("usleep", lib_system);
    ("mmap", lib_system);
    ("munmap", lib_system);
    ("mach_absolute_time", lib_system);
    ("mach_timebase_info", lib_system);
  ]

let fixed_linux =
  [
    ("printf", lib_c);
    ("puts", lib_c);
    ("putchar", lib_c);
    ("malloc", lib_c);
    ("free", lib_c);
    ("calloc", lib_c);
    ("realloc", lib_c);
    ("memcpy", lib_c);
    ("memmove", lib_c);
    ("memset", lib_c);
    ("sprintf", lib_c);
    ("snprintf", lib_c);
    ("strlen", lib_c);
    ("strcmp", lib_c);
    ("strncmp", lib_c);
    ("strcpy", lib_c);
    ("strncpy", lib_c);
    ("strstr", lib_c);
    ("atoi", lib_c);
    ("atof", lib_c);
    ("qsort", lib_c);
    ("time", lib_c);
    ("rand", lib_c);
    ("srand", lib_c);
    ("fopen", lib_c);
    ("freopen", lib_c);
    ("fclose", lib_c);
    ("fread", lib_c);
    ("fwrite", lib_c);
    ("fseek", lib_c);
    ("ftell", lib_c);
    ("fflush", lib_c);
    ("fgets", lib_c);
    ("fputs", lib_c);
    ("remove", lib_c);
    ("rename", lib_c);
    ("system", lib_c);
    ("getenv", lib_c);
    ("getpid", lib_c);
    ("nanosleep", lib_c);
    ("usleep", lib_c);
    ("read", lib_c);
    ("write", lib_c);
    ("open", lib_c);
    ("close", lib_c);
    ("lseek", lib_c);
    ("dlopen", lib_dl);
    ("dlsym", lib_dl);
    ("dlerror", lib_dl);
    ("dlclose", lib_dl);
  ]

let windows_only =
  [
    "ExitProcess";
    "GetStdHandle";
    "WriteFile";
    "ReadFile";
    "CreateFileA";
    "CloseHandle";
    "GetFileSizeEx";
    "Sleep";
    "GetTickCount64";
    "GetSystemTimeAsFileTime";
    "QueryPerformanceCounter";
    "QueryPerformanceFrequency";
    "GetCurrentProcessId";
    "OutputDebugStringA";
  ]

let table_of t = match t.fmt with Pe -> tags_win | MachO -> tags_mac | Elf -> tags_linux

let is_file_tag s =
  String.exists (fun c -> c = '.' || c = '/' || c = '\\' || c = '-') s

let basename s =
  let n = String.length s in
  let i = ref (n - 1) in
  while !i >= 0 && s.[!i] <> '/' && s.[!i] <> '\\' do
    decr i
  done;
  String.sub s (!i + 1) (n - !i - 1)

let lib_of ?lib (t : t) name =
  match lib with
  | Some tag when is_file_tag tag -> (
      match t.fmt with Pe -> basename tag | MachO | Elf -> tag)
  | Some tag -> (
      let key = String.lowercase_ascii tag in
      let table = table_of t in
      match List.assoc_opt key table with
      | Some l -> l
      | None ->
          let known = String.concat ", " (List.map fst table) in
          failwith
            (Printf.sprintf
               "no library tagged '%s' for %s; the tags are %s, or name the file, e.g. \
                extern \"python312.dll\""
               tag t.name known))
  | None -> (
      match t.fmt with
      | Pe -> (
          match List.assoc_opt name fixed_win with
          | Some dll -> dll
          | None -> failwith (Printf.sprintf "no DLL provides '%s' - tag it, e.g. extern \"user32\" fn %s(...)" name name))
      | MachO -> (
          match List.assoc_opt name fixed_mac with
          | Some dylib -> dylib
          | None ->
              if List.mem name windows_only then
                failwith
                  (Printf.sprintf
                     "'%s' is a Windows import; use mach_absolute_time() and the exit syscall \
                      for a macOS build"
                     name)
              else
                failwith
                  (Printf.sprintf
                     "no library provides '%s' on macOS - tag it, e.g. extern \"system\" fn %s(...)"
                     name name))
      | Elf -> (
          match List.assoc_opt name fixed_linux with
          | Some lib -> lib
          | None ->
              if List.mem name windows_only then
                failwith
                  (Printf.sprintf
                     "'%s' is a Windows import; use clock_gettime() and the exit syscall for a \
                      Linux build"
                     name)
              else
                failwith
                  (Printf.sprintf
                     "no library provides '%s' on Linux - tag it, e.g. extern \"libc\" fn %s(...)"
                     name name)))
