/*
 * Probe 1 -- does the iOS Simulator on a GitHub runner actually render OpenGL ES?
 *
 * The NSR Reader port answered "the simulator works" for Qt/Metal. 0 A.D. is
 * SDL2 + OpenGL ES, and nothing about a headless arm64 macOS VM promises that
 * Apple's GLES-over-Metal path renders there. So: one triangle, then read the
 * middle pixel back with glReadPixels and write what came out where CI can
 * fetch it. A screenshot alone would not distinguish "renders" from "black".
 *
 * The app keeps drawing afterwards so `simctl io screenshot` has something to
 * catch; CI decides on the report file, not on the picture.
 *
 * SPDX-License-Identifier: MIT
 */

#include <SDL.h>
#include <SDL_opengles2.h>

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

/* The triangle's colour: 1.0, 0.6, 0.0 -> 255, 153, 0. Nothing else on screen
 * is anywhere near it, so a tolerance of a few counts is plenty. */
#define WANT_R 255
#define WANT_G 153
#define WANT_B 0
#define TOLERANCE 8

static FILE *report;

static void say(const char *format, ...)
{
    va_list args;
    va_start(args, format);
    vfprintf(stdout, format, args);
    va_end(args);
    fputc('\n', stdout);
    fflush(stdout);
    if (report) {
        va_start(args, format);
        vfprintf(report, format, args);
        va_end(args);
        fputc('\n', report);
        fflush(report);
    }
}

/* In the simulator HOME is the app's data container -- the same place
 * `xcrun simctl get_app_container <id> data` prints. */
static void open_report(void)
{
    const char *home = getenv("HOME");
    char path[1024];
    if (!home)
        return;
    snprintf(path, sizeof(path), "%s/Documents", home);
    mkdir(path, 0755);
    snprintf(path, sizeof(path), "%s/Documents/probe.txt", home);
    report = fopen(path, "w");
}

static GLuint compile(GLenum kind, const char *source)
{
    GLuint shader = glCreateShader(kind);
    GLint ok = 0;
    glShaderSource(shader, 1, &source, NULL);
    glCompileShader(shader);
    glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[1024] = { 0 };
        glGetShaderInfoLog(shader, sizeof(log) - 1, NULL, log);
        say("SHADER_ERROR=%s", log);
        return 0;
    }
    return shader;
}

static const char *VERTEX_SOURCE =
    "attribute vec2 position;\n"
    "void main() { gl_Position = vec4(position, 0.0, 1.0); }\n";

static const char *FRAGMENT_SOURCE =
    "precision mediump float;\n"
    "void main() { gl_FragColor = vec4(1.0, 0.6, 0.0, 1.0); }\n";

int main(int argc, char *argv[])
{
    SDL_Window *window;
    SDL_GLContext context;
    GLuint program, buffer;
    GLint position;
    unsigned char pixel[4] = { 0, 0, 0, 0 };
    int width = 0, height = 0;
    int good;
    Uint32 started;
    static const GLfloat TRIANGLE[] = {
        -0.8f, -0.8f,
         0.8f, -0.8f,
         0.0f,  0.8f,
    };

    (void) argc;
    (void) argv;
    open_report();
    say("PROBE=gles");

    if (SDL_Init(SDL_INIT_VIDEO) != 0) {
        say("RESULT=fail SDL_Init: %s", SDL_GetError());
        return 1;
    }
    say("SDL_VERSION=%d.%d.%d", SDL_MAJOR_VERSION, SDL_MINOR_VERSION, SDL_PATCHLEVEL);
    say("SDL_VIDEO_DRIVER=%s", SDL_GetCurrentVideoDriver());

    SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_ES);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 2);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 0);
    SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);

    window = SDL_CreateWindow("0ad-ios probe", SDL_WINDOWPOS_UNDEFINED,
                              SDL_WINDOWPOS_UNDEFINED, 0, 0,
                              SDL_WINDOW_OPENGL | SDL_WINDOW_FULLSCREEN |
                              SDL_WINDOW_ALLOW_HIGHDPI);
    if (!window) {
        say("RESULT=fail SDL_CreateWindow: %s", SDL_GetError());
        return 1;
    }
    context = SDL_GL_CreateContext(window);
    if (!context) {
        say("RESULT=fail SDL_GL_CreateContext: %s", SDL_GetError());
        return 1;
    }
    SDL_GL_GetDrawableSize(window, &width, &height);
    say("DRAWABLE=%dx%d", width, height);
    say("GL_VENDOR=%s", (const char *) glGetString(GL_VENDOR));
    say("GL_RENDERER=%s", (const char *) glGetString(GL_RENDERER));
    say("GL_VERSION=%s", (const char *) glGetString(GL_VERSION));
    say("GLSL_VERSION=%s", (const char *) glGetString(GL_SHADING_LANGUAGE_VERSION));

    program = glCreateProgram();
    glAttachShader(program, compile(GL_VERTEX_SHADER, VERTEX_SOURCE));
    glAttachShader(program, compile(GL_FRAGMENT_SHADER, FRAGMENT_SOURCE));
    glLinkProgram(program);
    glUseProgram(program);
    position = glGetAttribLocation(program, "position");

    glGenBuffers(1, &buffer);
    glBindBuffer(GL_ARRAY_BUFFER, buffer);
    glBufferData(GL_ARRAY_BUFFER, sizeof(TRIANGLE), TRIANGLE, GL_STATIC_DRAW);
    glEnableVertexAttribArray((GLuint) position);
    glVertexAttribPointer((GLuint) position, 2, GL_FLOAT, GL_FALSE, 0, NULL);

    glViewport(0, 0, width, height);
    glClearColor(0.05f, 0.05f, 0.15f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
    glDrawArrays(GL_TRIANGLES, 0, 3);

    /* Read before the swap: this is the back buffer we just drew into. */
    glReadPixels(width / 2, height / 2, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
    say("GL_ERROR=0x%04x", glGetError());
    say("CENTER_PIXEL=%u,%u,%u", pixel[0], pixel[1], pixel[2]);

    good = abs((int) pixel[0] - WANT_R) <= TOLERANCE &&
           abs((int) pixel[1] - WANT_G) <= TOLERANCE &&
           abs((int) pixel[2] - WANT_B) <= TOLERANCE;
    say("EXPECTED_PIXEL=%u,%u,%u", WANT_R, WANT_G, WANT_B);
    say("RESULT=%s", good ? "ok" : "fail");
    SDL_GL_SwapWindow(window);

    /* Keep drawing so the screenshot has something to catch, and keep pumping
     * events so the watchdog stays happy. */
    started = SDL_GetTicks();
    while (SDL_GetTicks() - started < 30000) {
        SDL_Event event;
        while (SDL_PollEvent(&event))
            ;
        glClear(GL_COLOR_BUFFER_BIT);
        glDrawArrays(GL_TRIANGLES, 0, 3);
        SDL_GL_SwapWindow(window);
        SDL_Delay(16);
    }
    return good ? 0 : 1;
}
