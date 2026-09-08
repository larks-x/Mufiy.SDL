#include <SDL3/SDL.h>
#include <stdio.h>

int main(int argc, char *argv[])
{
    if (!SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS)) {
        fprintf(stderr, "SDL_Init failed: %s\n", SDL_GetError());
        return 1;
    }

    SDL_Window *window = SDL_CreateWindow("Emoji Test - Unicode DLL", 640, 480, SDL_WINDOW_RESIZABLE);
    if (!window) {
        fprintf(stderr, "SDL_CreateWindow failed: %s\n", SDL_GetError());
        return 1;
    }

    SDL_StartTextInput(window);

    printf("Window created. Click the window, then use Win+. to open emoji panel and pick an emoji.\n");
    printf("Close the window (Alt+F4) to exit.\n\n");

    int running = 1;
    SDL_Event event;
    while (running && SDL_WaitEvent(&event)) {
        switch (event.type) {
        case SDL_EVENT_QUIT:
            running = 0;
            break;
        case SDL_EVENT_WINDOW_CLOSE_REQUESTED:
            running = 0;
            break;
        case SDL_EVENT_TEXT_INPUT: {
            const char *text = event.text.text;
            int len = (int)SDL_strlen(text);
            printf("SDL_TEXT_INPUT: len=%d  hex=", len);
            for (int i = 0; i < len && i < 16; i++) {
                printf("%02X ", (unsigned char)text[i]);
            }
            printf("  text=\"%s\"\n", text);
            break;
        }
        case SDL_EVENT_TEXT_EDITING: {
            const char *text = event.edit.text;
            int len = (int)SDL_strlen(text);
            printf("SDL_TEXT_EDITING: len=%d  hex=", len);
            for (int i = 0; i < len && i < 16; i++) {
                printf("%02X ", (unsigned char)text[i]);
            }
            printf("  text=\"%s\"\n", text);
            break;
        }
        default:
            break;
        }
    }

    SDL_StopTextInput(window);
    SDL_DestroyWindow(window);
    SDL_Quit();
    return 0;
}
