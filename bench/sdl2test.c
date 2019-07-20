// Check if SDL2 is OpenGL ES hardware accellerated

#include <SDL2/SDL.h>
#include <stdio.h>

int main(int argc, char* args[]) {
  SDL_Window* window = NULL;
  SDL_Renderer *renderer = NULL;
  SDL_RendererInfo info;
  
  if( SDL_Init(SDL_INIT_VIDEO) < 0 ) {
    fprintf(stderr, "could not initialize sdl2: %s\n", SDL_GetError());
    return 1;
  }

  window = SDL_CreateWindow("sdl2 test", 0, 0, 100, 100, 0);
  if( window == NULL ) {
    fprintf(stderr, "could not create window: %s\n", SDL_GetError());
    return 1;
  }

  renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED);
  if( renderer == NULL ) {
    fprintf(stderr, "could not create accellerated renderer: %s\n", SDL_GetError());
    return 1;
  }

  if( SDL_GetRendererInfo(renderer, &info) < 0 ) {
    fprintf(stderr, "could not getrenderer info: %s\n", SDL_GetError());
    return 1;
  }
  
  SDL_DestroyRenderer(renderer);
  SDL_DestroyWindow(window);
  SDL_Quit();
  fprintf(stderr, "accelleration test OK, renderer: %s\n", info.name);
  return 0;
}
