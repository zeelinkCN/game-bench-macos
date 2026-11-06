#include "../Sources/Core/RetroBridge.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/stat.h>

static unsigned w,h;
static uint64_t hash(unsigned left,unsigned right) {
    const uint32_t *p=gb_frame(&w,&h); assert(p && w==256 && h>=224);
    uint64_t v=1469598103934665603ULL;
    for(unsigned y=70;y<210;y++) for(unsigned x=left;x<right;x++) v=(v^p[y*w+x])*1099511628211ULL;
    return v;
}
static void run(int n) { while(n-->0) gb_run(); }
int main(void) {
    setenv("GAMEBENCH_NO_AUDIO","1",1);
    mkdir("build/TestSaves",0755);
    assert(gb_load(".cache/cores/fceumm_libretro.dylib","Resources/Demo/StarPilot.nes","build/TestSaves","build/TestSaves","test"));
    printf("Core: %s; %.3f FPS\n",gb_core_name(),gb_fps());
    run(120);
    uint64_t left=hash(0,128),right=hash(128,256);
    assert(gb_save_state("build/TestSaves/check.state"));
    gb_set_input(0,1<<7); run(16); gb_set_input(0,0); run(1);
    assert(hash(0,128)!=left); assert(hash(128,256)==right);
    assert(gb_load_state("build/TestSaves/check.state")); run(1);
    assert(hash(0,128)==left); assert(hash(128,256)==right);
    gb_set_input(1,1<<6); run(16); gb_set_input(1,0); run(1);
    assert(hash(0,128)==left); assert(hash(128,256)!=right);
    gb_set_input(0,1<<7); gb_set_input(1,1<<6); run(10);
    assert(hash(0,128)!=left); assert(hash(128,256)!=right);
    gb_set_input(0,0); gb_set_input(1,0);
    assert(gb_load_state("build/TestSaves/check.state")); run(1);
    assert(gb_cheat_set(0,"0000:60")); run(3);
    assert(hash(0,128)!=left); assert(hash(128,256)==right);
    gb_cheat_reset();
    assert(gb_load_state("build/TestSaves/check.state")); run(2);
    assert(hash(0,128)==left);
    const uint32_t *p=gb_frame(&w,&h);
    FILE *f=fopen("build/demo-frame.ppm","wb"); assert(f);
    fprintf(f,"P6\n%u %u\n255\n",w,h);
    for(unsigned i=0;i<w*h;i++) { unsigned char rgb[]={p[i]>>16,p[i]>>8,p[i]}; fwrite(rgb,1,3,f); }
    fclose(f); gb_unload();
    assert(!gb_load("does-not-exist.dylib","Resources/Demo/StarPilot.nes","build/TestSaves","build/TestSaves","test"));
    assert(!gb_load(".cache/cores/fceumm_libretro.dylib","missing.nes","build/TestSaves","build/TestSaves","test"));
    // Load again after errors: callbacks, buffers, and option defaults must reset.
    assert(gb_load(".cache/cores/fceumm_libretro.dylib","Resources/Demo/StarPilot.nes","build/TestSaves","build/TestSaves","test"));
    run(120); assert(hash(0,128)==left); gb_unload();
    puts("PASS: video, independent 1P/2P, simultaneous play, save/load, cheats on/off, reload, errors");
}
