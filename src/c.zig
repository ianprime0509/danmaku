pub const c = @cImport({
    @cDefine("SDL_MAIN_USE_CALLBACKS", {});
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_main.h");
    @cInclude("SDL3_image/SDL_image.h");
});
