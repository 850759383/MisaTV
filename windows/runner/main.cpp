#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  // Disable Impeller: Flutter 3.47 defaults to the Impeller OpenGLESSDF backend on
  // Windows, whose SDF path keeps many full-window offscreen buffers alive for
  // rounded rectangles and gradients. Measured idle commit memory was 600+ MB
  // (a bare Flutter app on the same backend sits at ~170 MB); Skia stays far lower.
  // Keep this comment ASCII-only: the runner is compiled with /WX and C4819 would fail the build.
  project.set_impeller_switch(flutter::ImpellerSwitch::Disabled);

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"MisaTV", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  // Destroy the window before the FlutterViewController member below is
  // destroyed, so WM_DESTROY releases the engine while its view is still
  // attached. Without that ordering the exit path faulted inside
  // flutter_windows.dll (0xc0000005).
  window.Destroy();

  // Skip the rest of static teardown: WebView2 (coremessaging.dll) fail-fasts
  // while the DLLs detach, so every normal close was reported as an APPCRASH.
  // Windows Error Reporting answers each of those with a snapshot clone of this
  // process, which is what left unwakeable MisaTV.exe entries in the process
  // list (and kept the release folder locked). TerminateProcess is a plain exit,
  // so nothing gets queued.
  ::TerminateProcess(::GetCurrentProcess(), 0);
  return EXIT_SUCCESS;
}
