const std = @import("std");
const c = @import("c.zig").c;

const gpa = std.heap.c_allocator;
const log = std.log;

// Needed to get Zig to stop looking for a main function, even though I
// disabled the entry point of the executable. Not sure if this is a bug?
pub fn _start() void {}

var bullet_texture: *c.SDL_Texture = undefined;
var player_bullet_texture: *c.SDL_Texture = undefined;
var player_texture: *c.SDL_Texture = undefined;
var hitbox_texture: *c.SDL_Texture = undefined;
var option_texture: *c.SDL_Texture = undefined;

const Game = struct {
    step: u64,
    renderer: *c.SDL_Renderer,
    window: *c.SDL_Window,
    rand: std.Random.DefaultPrng,
    player: Player,
    bullets: std.ArrayListUnmanaged(Bullet),

    fn random(g: *Game) std.Random {
        return g.rand.random();
    }

    fn update(g: *Game) !void {
        g.step += 1;

        try g.player.update();

        for (g.bullets.items) |*bullet| {
            bullet.update();
        }

        if (g.step % 29 == 0) {
            for (0..16) |_| {
                const angle: f32 = g.random().float(f32) * 360;
                try g.bullets.append(std.heap.c_allocator, .{
                    .game = g,
                    .texture = bullet_texture,
                    .sprite = @intCast(g.step % 6),
                    .x = 370,
                    .y = 100,
                    .w = 10,
                    .h = 16,
                    .hit = 8,
                    .vx = @sin(std.math.degreesToRadians(angle)),
                    .vy = -@cos(std.math.degreesToRadians(angle)),
                    .player = false,
                    .dead = false,
                    .updateFn = &Bullet.updateHoming,
                });
            }
        }

        var i = g.bullets.items.len;
        while (i > 0) {
            i -= 1;
            const bullet = &g.bullets.items[i];
            if (!bullet.player) {
                const d = std.math.hypot(bullet.x - g.player.x, bullet.y - g.player.y);
                if (d <= bullet.hit + g.player.hit) {
                    bullet.dead = true;
                }
            }
            if (bullet.dead) {
                _ = g.bullets.swapRemove(i);
            }
        }
    }
};

const Bullet = struct {
    game: *Game,
    texture: *c.SDL_Texture,
    sprite: u32,
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    hit: f32,
    vx: f32,
    vy: f32,
    player: bool,
    dead: bool,
    updateFn: *const fn (b: *Bullet) void,

    fn updateConstant(b: *Bullet) void {
        b.x += b.vx;
        b.y += b.vy;
    }

    fn updateHoming(b: *Bullet) void {
        b.vx -= 0.0001 * (b.x - b.game.player.x);
        b.vy -= 0.0001 * (b.y - b.game.player.y);
        b.x += b.vx;
        b.y += b.vy;
    }

    const death_boundary = 50;

    fn update(b: *Bullet) void {
        b.updateFn(b);
        b.dead = b.x + b.w <= -death_boundary or
            b.x >= playfield_rect.w + death_boundary or
            b.y + b.h <= -death_boundary or
            b.y >= playfield_rect.h + death_boundary;
    }

    fn draw(b: Bullet) void {
        const sprite: f32 = @floatFromInt(b.sprite);
        const src: c.SDL_FRect = .{
            .x = sprite * b.w,
            .y = 0,
            .w = b.w,
            .h = b.h,
        };
        const dest: c.SDL_FRect = .{
            .x = b.x - b.w / 2,
            .y = b.y - b.h / 2,
            .w = b.w,
            .h = b.h,
        };
        _ = c.SDL_RenderTextureRotated(b.game.renderer, b.texture, &src, &dest, b.angle(), null, c.SDL_FLIP_NONE);
    }

    fn angle(b: Bullet) f32 {
        return std.math.radiansToDegrees(std.math.atan2(b.vx, -b.vy));
    }
};

const Player = struct {
    game: *Game,
    texture: *c.SDL_Texture,
    hitbox_texture: *c.SDL_Texture,
    sprite: u32,
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    hit: f32,
    focus: bool,
    fire: bool,
    right: bool,
    left: bool,
    down: bool,
    up: bool,

    fn handleEvent(p: *Player, event: *c.SDL_Event) void {
        switch (event.type) {
            c.SDL_EVENT_KEY_DOWN => switch (event.key.key) {
                c.SDLK_RIGHT => p.right = true,
                c.SDLK_LEFT => p.left = true,
                c.SDLK_DOWN => p.down = true,
                c.SDLK_UP => p.up = true,
                c.SDLK_LSHIFT => p.focus = true,
                c.SDLK_Z => p.fire = true,
                else => {},
            },
            c.SDL_EVENT_KEY_UP => switch (event.key.key) {
                c.SDLK_RIGHT => p.right = false,
                c.SDLK_LEFT => p.left = false,
                c.SDLK_DOWN => p.down = false,
                c.SDLK_UP => p.up = false,
                c.SDLK_LSHIFT => p.focus = false,
                c.SDLK_Z => p.fire = false,
                else => {},
            },
            else => {},
        }
    }

    fn update(p: *Player) !void {
        const vx, const vy = p.v();
        p.x = std.math.clamp(p.x + vx, p.w / 2, playfield_rect.w - p.w / 2);
        p.y = std.math.clamp(p.y + vy, p.h / 2, playfield_rect.h - p.h / 2);
        if (p.fire and p.game.step % 8 == 0) {
            const option_x, const option_y = p.optionPos();
            try p.game.bullets.append(gpa, .{
                .game = p.game,
                .texture = player_bullet_texture,
                .sprite = 0,
                .x = option_x,
                .y = option_y,
                .w = 32,
                .h = 16,
                .hit = 16,
                .vx = 0,
                .vy = -10,
                .player = true,
                .dead = false,
                .updateFn = &Bullet.updateConstant,
            });
        }
    }

    fn draw(p: Player) void {
        const sprite: f32 = @floatFromInt(p.sprite);
        const src: c.SDL_FRect = .{
            .x = sprite * p.w,
            .y = 0,
            .w = p.w,
            .h = p.h,
        };
        const dest: c.SDL_FRect = .{
            .x = p.x - p.w / 2,
            .y = p.y - p.h / 2,
            .w = p.w,
            .h = p.h,
        };
        _ = c.SDL_RenderTexture(p.game.renderer, p.texture, &src, &dest);

        const option_x, const option_y = p.optionPos();
        const option_src: c.SDL_FRect = .{
            .x = 0,
            .y = 0,
            .w = 24,
            .h = 24,
        };
        const option_dest: c.SDL_FRect = .{
            .x = option_x - 12,
            .y = option_y - 12,
            .w = 24,
            .h = 24,
        };
        _ = c.SDL_RenderTexture(p.game.renderer, option_texture, &option_src, &option_dest);

        if (p.focus) {
            const hitbox_src: c.SDL_FRect = .{
                .x = 0,
                .y = 0,
                .w = 64,
                .h = 64,
            };
            const hitbox_dest: c.SDL_FRect = .{
                .x = p.x - 32,
                .y = p.y - 32,
                .w = 64,
                .h = 64,
            };
            _ = c.SDL_RenderTexture(p.game.renderer, p.hitbox_texture, &hitbox_src, &hitbox_dest);
        }
    }

    fn optionPos(p: Player) struct { f32, f32 } {
        return .{ p.x, p.y - p.h / 2 - 16 };
    }

    fn v(p: Player) struct { f32, f32 } {
        const magnitude: f32 = if (p.focus) 3 else 6;
        const dir_x: f32 = if (p.right == p.left)
            0
        else if (p.right)
            1
        else
            -1;
        const dir_y: f32 = if (p.down == p.up)
            0
        else if (p.down)
            1
        else
            -1;
        if (dir_x == 0 and dir_y == 0) return .{ 0, 0 };
        const div = std.math.hypot(dir_x, dir_y);
        return .{ magnitude * dir_x / div, magnitude * dir_y / div };
    }
};

var last_step: u64 = 0;
const step_rate = 1000 / 60;
const game_rect: c.SDL_Rect = .{
    .x = 0,
    .y = 0,
    .w = 1280,
    .h = 960,
};
const playfield_rect: c.SDL_Rect = .{
    .x = 20,
    .y = 20,
    .w = 740,
    .h = 920,
};

const Result = enum(c.SDL_AppResult) {
    @"continue" = c.SDL_APP_CONTINUE,
    success = c.SDL_APP_SUCCESS,
    failure = c.SDL_APP_FAILURE,
};

export fn SDL_AppInit(game: **Game, argc: c_int, argv: [*][*:0]u8) Result {
    _ = argc;
    _ = argv;

    _ = c.SDL_SetAppMetadata("Danmaku", "0.0.0", "dev.ianjohnson.Danmaku");

    if (!c.SDL_Init(c.SDL_INIT_VIDEO)) {
        log.err("failed to initialize SDL: {s}", .{c.SDL_GetError()});
        return .failure;
    }

    var window: ?*c.SDL_Window = null;
    var renderer: ?*c.SDL_Renderer = null;
    if (!c.SDL_CreateWindowAndRenderer("Danmaku", game_rect.w, game_rect.h, 0, &window, &renderer)) {
        log.err("failed to create window and renderer: {s}", .{c.SDL_GetError()});
        return .failure;
    }

    _ = c.SDL_SetRenderVSync(renderer, 1);
    _ = c.SDL_SetRenderLogicalPresentation(renderer, game_rect.w, game_rect.h, c.SDL_LOGICAL_PRESENTATION_LETTERBOX);

    bullet_texture = c.IMG_LoadTexture(renderer, "assets/bullet-rice.png") orelse {
        c.SDL_Log("Failed to load texture: %s", c.SDL_GetError());
        return .failure;
    };

    player_bullet_texture = c.IMG_LoadTexture(renderer, "assets/kappa-cutter.png") orelse {
        c.SDL_Log("Failed to load texture: %s", c.SDL_GetError());
        return .failure;
    };
    _ = c.SDL_SetTextureAlphaModFloat(player_bullet_texture, 0.5);

    player_texture = c.IMG_LoadTexture(renderer, "assets/nitori.png") orelse {
        c.SDL_Log("Failed to load texture: %s", c.SDL_GetError());
        return .failure;
    };

    hitbox_texture = c.IMG_LoadTexture(renderer, "assets/hitbox.png") orelse {
        c.SDL_Log("Failed to load texture: %s", c.SDL_GetError());
        return .failure;
    };

    option_texture = c.IMG_LoadTexture(renderer, "assets/option.png") orelse {
        c.SDL_Log("Failed to load texture: %s", c.SDL_GetError());
        return .failure;
    };

    game.* = gpa.create(Game) catch {
        log.err("out of memory", .{});
        return .failure;
    };
    game.*.* = .{
        .step = 0,
        .renderer = renderer.?,
        .window = window.?,
        .rand = .init(0),
        .player = .{
            .game = game.*,
            .texture = player_texture,
            .hitbox_texture = hitbox_texture,
            .sprite = 0,
            .x = 370,
            .y = 700,
            .w = 40,
            .h = 64,
            .hit = 6,
            .focus = false,
            .fire = false,
            .right = false,
            .left = false,
            .down = false,
            .up = false,
        },
        .bullets = .empty,
    };

    last_step = c.SDL_GetTicks();

    return .@"continue";
}

export fn SDL_AppEvent(game: *Game, event: *c.SDL_Event) Result {
    if (event.type == c.SDL_EVENT_QUIT) return .success;
    game.player.handleEvent(event);
    return .@"continue";
}

export fn SDL_AppIterate(game: *Game) Result {
    _ = c.SDL_SetRenderDrawColorFloat(game.renderer, 0.5, 0.5, 0.5, c.SDL_ALPHA_OPAQUE_FLOAT);
    _ = c.SDL_RenderClear(game.renderer);

    _ = c.SDL_SetRenderViewport(game.renderer, &playfield_rect);

    _ = c.SDL_SetRenderDrawColorFloat(game.renderer, 0.9, 0.9, 0.9, c.SDL_ALPHA_OPAQUE_FLOAT);
    _ = c.SDL_RenderFillRect(game.renderer, &.{
        .x = 0,
        .y = 0,
        .w = playfield_rect.w,
        .h = playfield_rect.h,
    });

    const now = c.SDL_GetTicks();
    while (now - last_step >= step_rate) {
        game.update() catch return .failure;
        last_step += step_rate;
    }

    game.player.draw();
    for (game.bullets.items) |bullet| {
        bullet.draw();
    }

    _ = c.SDL_RenderPresent(game.renderer);

    c.SDL_Delay(10);

    return .@"continue";
}

export fn SDL_AppQuit(game: *Game, result: Result) void {
    _ = game;
    _ = result;
}
