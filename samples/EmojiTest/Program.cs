using System;
using SDL;
using static SDL.SDL3;

unsafe
{
    if (!SDL_Init(SDL_InitFlags.Video | SDL_InitFlags.Events))
    {
        Console.Error.WriteLine($"SDL_Init failed: {SDL_GetError()}");
        return 1;
    }

    var window = SDL_CreateWindow("Emoji Test - C# Binding", 640, 480, SDL_WindowFlags.Resizable);
    if (window.IsNull)
    {
        Console.Error.WriteLine($"SDL_CreateWindow failed: {SDL_GetError()}");
        return 1;
    }

    SDL_StartTextInput(window);

    Console.WriteLine("Window created. Click the window, then use Win+. to open emoji panel and pick an emoji.");
    Console.WriteLine("Close the window to exit.");
    Console.WriteLine();

    bool running = true;
    SDL_Event ev;
    while (running)
    {
        if (!SDL_WaitEvent(&ev))
            break;

        switch (ev.type)
        {
            case SDL_EventType.Quit:
                running = false;
                break;
            case SDL_EventType.WindowCloseRequested:
                running = false;
                break;
            case SDL_EventType.TextInput:
            {
                Console.Write("SDL_TEXT_INPUT | raw_bytes=");
                byte* rawPtr = ev.text.text;
                if (rawPtr != null)
                {
                    byte* p = rawPtr;
                    for (int i = 0; i < 8; i++)
                    {
                        byte b = p[i];
                        if (b == 0) break;
                        Console.Write($"{b:X2} ");
                    }
                }

                var text = ev.text.GetText() ?? "(null)";
                Console.Write($"| strlen(bytes)={(text != null ? System.Text.Encoding.UTF8.GetByteCount(text) : 0)}");
                Console.Write($"| chars={text.Length}");
                Console.Write(" | codepoints=");
                foreach (char c in text)
                {
                    Console.Write($"U+{(int)c:X4} ");
                }

                if (text == "\U0001F923")
                    Console.Write(" | MATCH: 🤣");
                else if (text == "??")
                    Console.Write(" | MISMATCH: literal ??");

                Console.WriteLine();
                break;
            }
            case SDL_EventType.TextEditing:
            {
                var text = ev.edit.GetText() ?? "(null)";
                Console.Write($"SDL_TEXT_EDITING: len={text.Length} codepoints=");
                foreach (char c in text)
                    Console.Write($"U+{(int)c:X4} ");
                Console.WriteLine();
                break;
            }
        }
    }

    SDL_StopTextInput(window);
    SDL_DestroyWindow(window);
    SDL_Quit();
    return 0;
}
