using System;
using System.Runtime.InteropServices;
using SDL;
using static SDL.SDL3;

unsafe
{
    if (!SDL_Init(SDL_InitFlags.Video | SDL_InitFlags.Events))
    {
        Console.Error.WriteLine($"SDL_Init failed: {SDL_GetError()}");
        return;
    }

    var window = SDL_CreateWindow("Mica Test", 800, 600, SDL_WindowFlags.Borderless | SDL_WindowFlags.Resizable | SDL_WindowFlags.HighPixelDensity);
    if (window.IsNull)
    {
        Console.Error.WriteLine($"SDL_CreateWindow failed: {SDL_GetError()}");
        SDL_Quit();
        return;
    }

    var props = SDL_GetWindowProperties(window);
    var hwnd = SDL_GetPointerProperty(props, SDL_PROP_WINDOW_WIN32_HWND_POINTER, 0);
    if (hwnd != 0)
    {
        // Step 1: 临时移除会导致 DWM 绘制控制按钮的样式
        var style = Win32.GetWindowLongPtr(hwnd, Win32.GWL_STYLE);
        Win32.SetWindowLongPtr(hwnd, Win32.GWL_STYLE,
            style & ~(nint)(Win32.WS_MINIMIZEBOX | Win32.WS_MAXIMIZEBOX | Win32.WS_SYSMENU));
        Win32.SetWindowPos(hwnd, 0, 0, 0, 0, 0,
            Win32.SWP_FRAMECHANGED | Win32.SWP_NOMOVE | Win32.SWP_NOSIZE | Win32.SWP_NOZORDER);

        // Step 2: 开启 DWM 材质（此时 DWM 检测不到按钮样式，不会画按钮）
        int darkMode = 1;
        Win32.DwmSetWindowAttribute(hwnd, 20, &darkMode, 4); // DWMWA_USE_IMMERSIVE_DARK_MODE

        int backdropType = 2; // DWMSBT_MAINWINDOW = Mica
        int hr = Win32.DwmSetWindowAttribute(hwnd, 38, &backdropType, 4); // DWMWA_SYSTEMBACKDROP_TYPE
        if (hr != 0)
        {
            int micaPolicy = 1;
            Win32.DwmSetWindowAttribute(hwnd, 1029, &micaPolicy, 4); // DWMWA_MICA 回退
        }

        // Step 3: 加回 WS_MINIMIZEBOX，保留系统最小化功能，按钮不会重新出现
        style = Win32.GetWindowLongPtr(hwnd, Win32.GWL_STYLE);
        Win32.SetWindowLongPtr(hwnd, Win32.GWL_STYLE, style | (nint)Win32.WS_MINIMIZEBOX);
        Win32.SetWindowPos(hwnd, 0, 0, 0, 0, 0,
            Win32.SWP_FRAMECHANGED | Win32.SWP_NOMOVE | Win32.SWP_NOSIZE | Win32.SWP_NOZORDER);

        // 可选：小圆角
        int cornerPreference = 2; // DWMWCP_ROUNDSMALL
        Win32.DwmSetWindowAttribute(hwnd, 33, &cornerPreference, 4); // DWMWA_WINDOW_CORNER_PREFERENCE

        // 延伸 DWM 框架到客户区
        Win32.MARGINS margins = new() { left = -1, right = -1, top = -1, bottom = -1 };
        Win32.DwmExtendFrameIntoClientArea(hwnd, ref margins);
    }

    SDL_SetWindowPosition(window, 200, 200);
    SDL_ShowWindow(window);

    bool dragging = false;
    int dragStartX = 0, dragStartY = 0;
    ulong lastClickTime = 0;

    SDL_Event ev;
    while (SDL_WaitEvent(&ev))
    {
        switch (ev.type)
        {
            case SDL_EventType.Quit:
                goto done;

            case SDL_EventType.MouseButtonDown:
                if (ev.button.Button == SDL_Button.Left)
                {
                    ulong now = SDL_GetTicks();
                    if (now - lastClickTime < 400)
                        goto done;
                    lastClickTime = now;
                    dragging = true;
                    dragStartX = (int)ev.button.x;
                    dragStartY = (int)ev.button.y;
                }
                break;

            case SDL_EventType.MouseButtonUp:
                if (ev.button.Button == SDL_Button.Left)
                    dragging = false;
                break;

            case SDL_EventType.MouseMotion:
                if (dragging)
                {
                    SDL_GetWindowPosition(window, out int wx, out int wy);
                    SDL_SetWindowPosition(window, (int)(wx + ev.motion.x - dragStartX), (int)(wy + ev.motion.y - dragStartY));
                }
                break;
        }
    }

done:
    SDL_DestroyWindow(window);
    SDL_Quit();
}

static class Win32
{
    public const int GWL_STYLE = -16;
    public const long WS_MINIMIZEBOX = 0x20000;
    public const long WS_MAXIMIZEBOX = 0x10000;
    public const long WS_SYSMENU = 0x80000;
    public const int SWP_FRAMECHANGED = 0x20;
    public const int SWP_NOMOVE = 0x2;
    public const int SWP_NOSIZE = 0x1;
    public const int SWP_NOZORDER = 0x4;

    [StructLayout(LayoutKind.Sequential)]
    public struct MARGINS { public int left; public int right; public int top; public int bottom; }

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern nint GetWindowLongPtr(nint hWnd, int nIndex);

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern nint SetWindowLongPtr(nint hWnd, int nIndex, nint dwNewLong);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool SetWindowPos(nint hWnd, nint hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);

    [DllImport("dwmapi.dll")]
    public static extern unsafe int DwmSetWindowAttribute(nint hwnd, uint dwAttribute, void* pvAttribute, uint cbAttribute);

    [DllImport("dwmapi.dll")]
    public static extern int DwmExtendFrameIntoClientArea(nint hwnd, ref MARGINS pMarInset);
}
