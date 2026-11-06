#include "RetroBridge.h"
#include "libretro.h"
#include <AudioToolbox/AudioToolbox.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdatomic.h>
#include <pthread.h>
#include <stdarg.h>
#include <unistd.h>

// libretro cores have process-wide state. All core calls run on one serial queue.
static void *library;
static bool initialized, loaded;
static char error_text[2048], core_name[256], system_path[4096], save_path[4096], sram_path[8192];
static void *rom_data;
static uint32_t *pixels;
static size_t pixel_capacity;
static unsigned frame_width, frame_height;
static enum retro_pixel_format pixel_format;
static struct retro_system_av_info av;
static _Atomic uint16_t inputs[4];
static unsigned rotation;

static void (*core_init)(void), (*core_deinit)(void), (*core_run)(void), (*core_reset)(void), (*core_unload)(void);
static bool (*core_load)(const struct retro_game_info *);
static void (*core_info)(struct retro_system_info *), (*core_av)(struct retro_system_av_info *);
static void (*set_environment)(retro_environment_t);
static void (*set_video)(retro_video_refresh_t);
static void (*set_audio)(retro_audio_sample_t);
static void (*set_batch)(retro_audio_sample_batch_t);
static void (*set_poll)(retro_input_poll_t);
static void (*set_input)(retro_input_state_t);
static void (*set_port)(unsigned, unsigned);
static size_t (*state_size)(void), (*memory_size)(unsigned);
static void *(*memory_data)(unsigned);
static bool (*serialize)(void *, size_t), (*unserialize)(const void *, size_t);
static unsigned (*api_version)(void);
static void (*cheat_reset)(void), (*cheat_set)(unsigned,bool,const char *);

// Options are copied because a core may supply temporary option arrays.
static struct { char key[160]; char value[256]; } options[512];
static size_t option_count;
static void option(const char *key, const char *value) {
    if (!key || !value || option_count >= 512) return;
    for (size_t i=0; i<option_count; i++) if (!strcmp(options[i].key,key)) return;
    snprintf(options[option_count].key,160,"%s",key);
    snprintf(options[option_count++].value,256,"%s",value);
}
static void log_core(enum retro_log_level level, const char *fmt, ...) {
    if (level < RETRO_LOG_WARN) return;
    va_list args; va_start(args,fmt); vfprintf(stderr,fmt,args); va_end(args);
}
static bool environment(unsigned cmd, void *data) {
    switch(cmd) {
        case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT:
            pixel_format=*(enum retro_pixel_format *)data;
            return pixel_format<=RETRO_PIXEL_FORMAT_RGB565;
        case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY: *(const char **)data=system_path; return true;
        case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY: *(const char **)data=save_path; return true;
        case RETRO_ENVIRONMENT_GET_CORE_ASSETS_DIRECTORY: *(const char **)data=system_path; return true;
        case RETRO_ENVIRONMENT_GET_CAN_DUPE: *(bool *)data=true; return true;
        case RETRO_ENVIRONMENT_GET_INPUT_BITMASKS: return true;
        case RETRO_ENVIRONMENT_GET_LOG_INTERFACE: ((struct retro_log_callback *)data)->log=log_core; return true;
        case RETRO_ENVIRONMENT_GET_LANGUAGE: *(unsigned *)data=RETRO_LANGUAGE_ENGLISH; return true;
        case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE: *(bool *)data=false; return true;
        case RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION: *(unsigned *)data=2; return true;
        case RETRO_ENVIRONMENT_SET_VARIABLES: {
            const struct retro_variable *v=data;
            for (;v && v->key; v++) {
                const char *p=strchr(v->value,';');
                if (!p) continue;
                p++; while(*p==' ') p++;
                char buf[256]; snprintf(buf,sizeof buf,"%s",p);
                char *end=strchr(buf,'|'); if(end) *end=0;
                option(v->key,buf);
            } return true;
        }
        case RETRO_ENVIRONMENT_SET_CORE_OPTIONS:
        case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_INTL: {
            const struct retro_core_option_definition *d = cmd==RETRO_ENVIRONMENT_SET_CORE_OPTIONS ? data : ((struct retro_core_options_intl *)data)->us;
            for (;d && d->key;d++) option(d->key,d->default_value ? d->default_value : d->values[0].value);
            return true;
        }
        case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2:
        case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2_INTL: {
            const struct retro_core_options_v2 *v=cmd==RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2 ? data : ((struct retro_core_options_v2_intl *)data)->us;
            const struct retro_core_option_v2_definition *d=v ? v->definitions : NULL;
            for (;d && d->key;d++) option(d->key,d->default_value ? d->default_value : d->values[0].value);
            return true;
        }
        case RETRO_ENVIRONMENT_GET_VARIABLE: {
            struct retro_variable *v=data;
            for(size_t i=0;i<option_count;i++) if(!strcmp(v->key,options[i].key)) { v->value=options[i].value; return true; }
            v->value=NULL; return false;
        }
        case RETRO_ENVIRONMENT_SET_ROTATION: rotation=*(unsigned *)data%4; return true;
        case RETRO_ENVIRONMENT_SET_GEOMETRY: av.geometry=*(struct retro_game_geometry *)data; return true;
        case RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO: av=*(struct retro_system_av_info *)data; return true;
        case RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS:
        case RETRO_ENVIRONMENT_SET_CONTROLLER_INFO:
        case RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME:
        case RETRO_ENVIRONMENT_SET_SUBSYSTEM_INFO:
        case RETRO_ENVIRONMENT_SET_CORE_OPTIONS_DISPLAY: return true;
        default: return false;
    }
}

static void video(const void *data, unsigned width, unsigned height, size_t pitch) {
    if(!data || data==RETRO_HW_FRAME_BUFFER_VALID || !width || !height || width>4096 || height>4096) return;
    size_t count=(size_t)width*height;
    if(count>pixel_capacity) {
        uint32_t *next=realloc(pixels,count*sizeof(uint32_t));
        if(!next) return;
        pixels=next; pixel_capacity=count;
    }
    unsigned out_w=(rotation&1) ? height : width;
    unsigned out_h=(rotation&1) ? width : height;
    for(unsigned y=0;y<height;y++) for(unsigned x=0;x<width;x++) {
        const uint8_t *row=(const uint8_t *)data+y*pitch;
        uint32_t p;
        if(pixel_format==RETRO_PIXEL_FORMAT_XRGB8888) p=((const uint32_t *)row)[x]|0xff000000;
        else {
            uint16_t c=((const uint16_t *)row)[x];
            unsigned r,g,b;
            if(pixel_format==RETRO_PIXEL_FORMAT_RGB565) { r=(c>>11)&31; g=(c>>5)&63; b=c&31; g=(g<<2)|(g>>4); }
            else { r=(c>>10)&31; g=(c>>5)&31; b=c&31; g=(g<<3)|(g>>2); }
            r=(r<<3)|(r>>2); b=(b<<3)|(b>>2);
            p=0xff000000|(r<<16)|(g<<8)|b;
        }
        unsigned ox=x,oy=y;
        if(rotation==1) { ox=y; oy=width-1-x; }
        if(rotation==2) { ox=width-1-x; oy=height-1-y; }
        if(rotation==3) { ox=height-1-y; oy=x; }
        pixels[(size_t)oy*out_w+ox]=p;
    }
    frame_width=out_w; frame_height=out_h;
}

#define AUDIO_CAPACITY 65536
static int16_t audio_ring[AUDIO_CAPACITY*2];
static size_t audio_read,audio_write,audio_count;
static pthread_mutex_t audio_lock=PTHREAD_MUTEX_INITIALIZER;
static AudioQueueRef audio_queue;
static bool audio_muted;
static size_t audio_batch(const int16_t *data,size_t frames) {
    if(audio_muted) return frames;
    pthread_mutex_lock(&audio_lock);
    for(size_t i=0;i<frames && audio_count<AUDIO_CAPACITY;i++) {
        audio_ring[audio_write*2]=data[i*2]; audio_ring[audio_write*2+1]=data[i*2+1];
        audio_write=(audio_write+1)%AUDIO_CAPACITY; audio_count++;
    }
    pthread_mutex_unlock(&audio_lock); return frames;
}
static void audio_sample(int16_t left,int16_t right) { int16_t p[]={left,right}; audio_batch(p,1); }
static void audio_callback(void *user,AudioQueueRef q,AudioQueueBufferRef buffer) {
    (void)user;
    int16_t *out=buffer->mAudioData;
    size_t n=buffer->mAudioDataBytesCapacity/4;
    pthread_mutex_lock(&audio_lock);
    for(size_t i=0;i<n;i++) {
        if(audio_count) { out[i*2]=audio_ring[audio_read*2]; out[i*2+1]=audio_ring[audio_read*2+1]; audio_read=(audio_read+1)%AUDIO_CAPACITY; audio_count--; }
        else { out[i*2]=out[i*2+1]=0; }
    }
    pthread_mutex_unlock(&audio_lock);
    buffer->mAudioDataByteSize=(UInt32)(n*4); AudioQueueEnqueueBuffer(q,buffer,0,NULL);
}
static void start_audio(void) {
    // A headless smoke test should not open the user's audio device.
    audio_muted=getenv("GAMEBENCH_NO_AUDIO")!=NULL;
    if(audio_muted) return;
    AudioStreamBasicDescription f={0};
    f.mSampleRate=av.timing.sample_rate>0 ? av.timing.sample_rate : 48000;
    f.mFormatID=kAudioFormatLinearPCM; f.mFormatFlags=kLinearPCMFormatFlagIsSignedInteger|kLinearPCMFormatFlagIsPacked;
    f.mBytesPerPacket=4; f.mFramesPerPacket=1; f.mBytesPerFrame=4; f.mChannelsPerFrame=2; f.mBitsPerChannel=16;
    if(AudioQueueNewOutput(&f,audio_callback,NULL,NULL,NULL,0,&audio_queue)!=noErr) { audio_queue=NULL; return; }
    for(int i=0;i<3;i++) {
        AudioQueueBufferRef b;
        if(AudioQueueAllocateBuffer(audio_queue,2048,&b)==noErr) audio_callback(NULL,audio_queue,b);
    }
    AudioQueueStart(audio_queue,NULL);
}
void gb_audio_pause(bool paused) {
    if(!audio_queue) return;
    if(paused) AudioQueuePause(audio_queue);
    else {
        pthread_mutex_lock(&audio_lock); audio_read=audio_write=audio_count=0; pthread_mutex_unlock(&audio_lock);
        AudioQueueStart(audio_queue,NULL);
    }
}
static void poll_input(void) {}
static int16_t input_state(unsigned port,unsigned device,unsigned index,unsigned id) {
    (void)index;
    if(port>=4 || (device&RETRO_DEVICE_MASK)!=RETRO_DEVICE_JOYPAD) return 0;
    uint16_t mask=atomic_load(&inputs[port]);
    if(id==RETRO_DEVICE_ID_JOYPAD_MASK) return (int16_t)mask;
    return id<16 ? ((mask>>id)&1) : 0;
}
void gb_set_input(unsigned port,uint16_t mask) { if(port<4) atomic_store(&inputs[port],mask); }

static bool write_file(const char *path,const void *data,size_t size) {
    char temporary[8192]; snprintf(temporary,sizeof temporary,"%s.tmp",path);
    FILE *f=fopen(temporary,"wb"); if(!f) return false;
    bool ok=fwrite(data,1,size,f)==size;
    if(fclose(f)!=0) ok=false;
    if(ok && rename(temporary,path)==0) return true;
    unlink(temporary); return false;
}
static void save_sram(void) {
    if(!loaded || !memory_size || !memory_data) return;
    size_t n=memory_size(RETRO_MEMORY_SAVE_RAM); void *p=memory_data(RETRO_MEMORY_SAVE_RAM);
    if(p && n && n<64*1024*1024 && !write_file(sram_path,p,n)) fprintf(stderr,"Cannot save SRAM: %s\n",sram_path);
}
void gb_unload(void) {
    if(audio_queue) { AudioQueueStop(audio_queue,true); AudioQueueDispose(audio_queue,true); audio_queue=NULL; }
    pthread_mutex_lock(&audio_lock); audio_read=audio_write=audio_count=0; pthread_mutex_unlock(&audio_lock);
    if(loaded) { save_sram(); core_unload(); loaded=false; }
    if(initialized) { core_deinit(); initialized=false; }
    if(library) { dlclose(library); library=NULL; }
    free(rom_data); rom_data=NULL;
    free(pixels); pixels=NULL; pixel_capacity=0; frame_width=frame_height=0;
    for(unsigned i=0;i<4;i++) atomic_store(&inputs[i],0);
}
#define SYMBOL(field,name) do { *(void **)(&field)=dlsym(library,name); if(!field) { snprintf(error_text,sizeof error_text,"核心缺少接口：%s",name); gb_unload(); return false; } } while(0)
bool gb_load(const char *core_path,const char *rom_path,const char *system_dir,const char *save_dir,const char *save_key) {
    gb_unload(); error_text[0]=0; core_name[0]=0; option_count=0; rotation=0;
    memset(&av,0,sizeof av); pixel_format=RETRO_PIXEL_FORMAT_0RGB1555;
    snprintf(system_path,sizeof system_path,"%s",system_dir);
    snprintf(save_path,sizeof save_path,"%s",save_dir);
    snprintf(sram_path,sizeof sram_path,"%s/%s.srm",save_dir,save_key);
    library=dlopen(core_path,RTLD_NOW|RTLD_LOCAL);
    if(!library) { snprintf(error_text,sizeof error_text,"无法载入核心：%s",dlerror()); return false; }
    SYMBOL(core_init,"retro_init"); SYMBOL(core_deinit,"retro_deinit"); SYMBOL(core_run,"retro_run");
    SYMBOL(core_reset,"retro_reset"); SYMBOL(core_unload,"retro_unload_game"); SYMBOL(core_load,"retro_load_game");
    SYMBOL(core_info,"retro_get_system_info"); SYMBOL(core_av,"retro_get_system_av_info");
    SYMBOL(set_environment,"retro_set_environment"); SYMBOL(set_video,"retro_set_video_refresh");
    SYMBOL(set_audio,"retro_set_audio_sample"); SYMBOL(set_batch,"retro_set_audio_sample_batch");
    SYMBOL(set_poll,"retro_set_input_poll"); SYMBOL(set_input,"retro_set_input_state");
    SYMBOL(set_port,"retro_set_controller_port_device"); SYMBOL(api_version,"retro_api_version");
    SYMBOL(state_size,"retro_serialize_size"); SYMBOL(serialize,"retro_serialize"); SYMBOL(unserialize,"retro_unserialize");
    SYMBOL(memory_size,"retro_get_memory_size"); SYMBOL(memory_data,"retro_get_memory_data");
    SYMBOL(cheat_reset,"retro_cheat_reset"); SYMBOL(cheat_set,"retro_cheat_set");
    if(api_version()!=RETRO_API_VERSION) { snprintf(error_text,sizeof error_text,"模拟器接口版本不兼容"); gb_unload(); return false; }
    set_environment(environment); set_video(video); set_audio(audio_sample); set_batch(audio_batch); set_poll(poll_input); set_input(input_state);
    core_init(); initialized=true;
    struct retro_system_info info={0}; core_info(&info);
    snprintf(core_name,sizeof core_name,"%s %s",info.library_name ? info.library_name : "libretro",info.library_version ? info.library_version : "");
    struct retro_game_info game={0}; game.path=rom_path;
    FILE *f=fopen(rom_path,"rb");
    if(!f) { snprintf(error_text,sizeof error_text,"找不到游戏文件，请重新导入。"); gb_unload(); return false; }
    fseek(f,0,SEEK_END); long size=ftell(f); rewind(f);
    if(size<=0 || size>512L*1024*1024) { fclose(f); snprintf(error_text,sizeof error_text,"游戏文件为空或超过 512 MB。"); gb_unload(); return false; }
    if(!info.need_fullpath) {
        rom_data=malloc((size_t)size);
        if(!rom_data || fread(rom_data,1,(size_t)size,f)!=(size_t)size) { fclose(f); snprintf(error_text,sizeof error_text,"读取游戏文件失败。"); gb_unload(); return false; }
        game.data=rom_data; game.size=(size_t)size;
    }
    fclose(f);
    if(!core_load(&game)) { snprintf(error_text,sizeof error_text,"核心无法运行这个文件。街机 ZIP 需与 FBNeo 的 ROM 版本匹配，部分游戏还需要 BIOS。"); gb_unload(); return false; }
    loaded=true;
    for(unsigned i=0;i<2;i++) set_port(i,RETRO_DEVICE_JOYPAD);
    core_av(&av);
    if(av.timing.fps<1 || av.timing.fps>240) av.timing.fps=60;
    size_t n=memory_size(RETRO_MEMORY_SAVE_RAM); void *p=memory_data(RETRO_MEMORY_SAVE_RAM);
    if(p && n) { FILE *s=fopen(sram_path,"rb"); if(s) { fread(p,1,n,s); fclose(s); } }
    start_audio(); return true;
}
void gb_run(void) { if(loaded) core_run(); }
void gb_reset(void) { if(loaded) core_reset(); }
const char *gb_error(void) { return error_text; }
const char *gb_core_name(void) { return core_name; }
const uint32_t *gb_frame(unsigned *w,unsigned *h) { *w=frame_width; *h=frame_height; return pixels; }
double gb_fps(void) { return av.timing.fps>0 ? av.timing.fps : 60; }
double gb_aspect(void) {
    double a=av.geometry.aspect_ratio;
    if(a<=0 && av.geometry.base_height) a=(double)av.geometry.base_width/av.geometry.base_height;
    if(a<=0) a=4.0/3.0;
    return rotation&1 ? 1/a : a;
}
bool gb_save_state(const char *path) {
    if(!loaded) return false;
    size_t n=state_size(); if(!n || n>128*1024*1024) return false;
    void *p=malloc(n); if(!p) return false;
    bool ok=serialize(p,n) && write_file(path,p,n); free(p); save_sram(); return ok;
}
bool gb_load_state(const char *path) {
    if(!loaded) return false;
    FILE *f=fopen(path,"rb"); if(!f) return false;
    fseek(f,0,SEEK_END); long n=ftell(f); rewind(f);
    if(n<=0 || n>128*1024*1024) { fclose(f); return false; }
    void *p=malloc((size_t)n); if(!p) { fclose(f); return false; }
    bool ok=fread(p,1,(size_t)n,f)==(size_t)n && unserialize(p,(size_t)n);
    free(p); fclose(f); return ok;
}
void gb_cheat_reset(void) { if(loaded && cheat_reset) cheat_reset(); }
bool gb_cheat_set(unsigned index,const char *code) {
    if(!loaded || !cheat_set || !code || strlen(code)>900) return false;
    cheat_set(index,true,code); return true;
}
