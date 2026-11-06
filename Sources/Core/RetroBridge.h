#pragma once
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>

bool gb_load(const char *core_path, const char *rom_path, const char *system_dir,
             const char *save_dir, const char *save_key);
void gb_unload(void);
const char *gb_error(void);
const char *gb_core_name(void);
void gb_run(void);
void gb_reset(void);
void gb_set_input(unsigned port, uint16_t mask);
const uint32_t *gb_frame(unsigned *width, unsigned *height);
double gb_fps(void);
double gb_aspect(void);
void gb_audio_pause(bool paused);
bool gb_save_state(const char *path);
bool gb_load_state(const char *path);
void gb_cheat_reset(void);
bool gb_cheat_set(unsigned index, const char *code);
