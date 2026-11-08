import AppKit
import Foundation
import QuartzCore
import SwiftUI

final class FramePresenter {
    private let lock=NSLock()
    private var latestFrame: CGImage?
    private var submitted: UInt64=0
    private var displayed: UInt64=0
    var smooth=false
    func submit(_ image: CGImage) {
        lock.lock()
        latestFrame=image
        submitted &+= 1
        lock.unlock()
    }
    func newestFrame() -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        guard displayed != submitted else { return nil }
        displayed=submitted
        return latestFrame
    }
    func currentFrame() -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        return latestFrame
    }
}

final class PixelView: NSView {
    weak var presenter: FramePresenter?
    private var displayLink: CADisplayLink?
    override init(frame: NSRect) {
        super.init(frame:frame); wantsLayer=true
        layer?.backgroundColor=NSColor.black.cgColor
        layer?.contentsGravity = .resize
        layer?.magnificationFilter = .nearest
        layer?.minificationFilter = .nearest
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        displayLink?.invalidate(); displayLink=nil
        guard window != nil else { return }
        let link=displayLink(target:self,selector:#selector(drawLatestFrame(_:)))
        link.add(to:.main,forMode:.common)
        displayLink=link
    }
    @objc private func drawLatestFrame(_ link: CADisplayLink) {
        guard let image=presenter?.newestFrame() else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contents=image
        CATransaction.commit()
    }
    deinit { displayLink?.invalidate() }
}

struct GameScreen: NSViewRepresentable {
    let presenter: FramePresenter
    var smooth: Bool
    func makeNSView(context: Context) -> PixelView {
        let view=PixelView(frame:.zero); view.presenter=presenter; view.layer?.contents=presenter.currentFrame()
        return view
    }
    func updateNSView(_ view: PixelView, context: Context) {
        view.presenter=presenter
        view.layer?.magnificationFilter=smooth ? .linear : .nearest
        view.layer?.minificationFilter=smooth ? .linear : .nearest
    }
}

enum ScreenMode: String, CaseIterable, Identifiable {
    case original="原始比例", integer="像素整数倍", fill="铺满屏幕"
    var id: String { rawValue }
}

final class Emulator: ObservableObject {
    @Published var game: Game?
    @Published var loading=false
    @Published var paused=false
    @Published var error: String?
    @Published var toast: String?
    @Published var fps=0
    @Published var coreName=""
    @Published var cheats=[GameCheat]()
    @Published var aspect=4.0/3.0
    @Published var sourceWidth=256
    @Published var sourceHeight=240
    let presenter=FramePresenter()
    let queue=DispatchQueue(label:"GameBench.Emulation",qos:.userInteractive)
    private var timer: DispatchSourceTimer?
    private var current: Game?
    private var frames=0
    private var statTime=ProcessInfo.processInfo.systemUptime
    var onLaunch: ((Game)->Void)?

    func launch(_ game: Game, resume: Bool=true) {
        guard !loading else { return }
        let core=Bundle.main.resourceURL!.appendingPathComponent("Cores/\(game.system.core)_libretro.dylib")
        let rom=LibraryPaths.rom(game)
        if rom.pathExtension.lowercased()=="fds" && !FileManager.default.fileExists(atPath:LibraryPaths.bios.appendingPathComponent("disksys.rom").path) {
            error="这个磁碟机版本需要 disksys.rom。请把 BIOS 放进设置中的 BIOS 目录，再启动游戏。"; return
        }
        loading=true; error=nil
        queue.async { [self] in
            self.stopCore()
            guard gb_load(core.path,rom.path,LibraryPaths.bios.path,LibraryPaths.saves.path,game.id) else {
                let message=String(cString:gb_error())
                DispatchQueue.main.async { self.loading=false; self.game=nil; self.error=message }
                return
            }
            self.current=game
            let auto=LibraryPaths.saves.appendingPathComponent(game.id+".auto.state")
            var resumeFailed=false
            if resume && FileManager.default.fileExists(atPath:auto.path) { resumeFailed = !gb_load_state(auto.path) }
            let cheats=CheatFiles.read(game)
            CheatFiles.apply(cheats)
            let rate=gb_fps(), aspect=gb_aspect(), name=String(cString:gb_core_name())
            self.frames=0; self.statTime=ProcessInfo.processInfo.systemUptime
            let timer=DispatchSource.makeTimerSource(queue:self.queue)
            timer.schedule(deadline:.now(),repeating:.nanoseconds(Int(1_000_000_000/rate)),leeway:.microseconds(300))
            timer.setEventHandler { [weak self] in self?.tick() }
            self.timer=timer
            DispatchQueue.main.async {
                self.game=game; self.paused=false; self.loading=false; self.coreName=name; self.aspect=aspect; self.cheats=cheats
                self.onLaunch?(game)
                if resumeFailed { self.showToast("旧的自动存档无法读取，已从头开始") }
            }
            timer.resume()
        }
    }
    private func tick() {
        gb_run(); frames+=1
        var w: UInt32=0,h: UInt32=0
        if let pixels=gb_frame(&w,&h),w>0,h>0 {
            let data=Data(bytes:pixels,count:Int(w*h)*4)
            let provider=CGDataProvider(data:data as CFData)!
            let info=CGBitmapInfo(rawValue:CGImageAlphaInfo.noneSkipFirst.rawValue).union(.byteOrder32Little)
            if let image=CGImage(width:Int(w),height:Int(h),bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:Int(w)*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:info,provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent) {
                presenter.submit(image)
                let width=Int(w),height=Int(h),a=gb_aspect()
                if sourceWidth != width || sourceHeight != height || abs(aspect-a)>0.001 {
                    DispatchQueue.main.async {
                        if self.sourceWidth != width { self.sourceWidth=width }
                        if self.sourceHeight != height { self.sourceHeight=height }
                        if abs(self.aspect-a)>0.001 { self.aspect=a }
                    }
                }
            }
        }
        let now=ProcessInfo.processInfo.systemUptime
        if now-statTime>=1 {
            let measured=Int((Double(frames)/(now-statTime)).rounded())
            DispatchQueue.main.async { self.fps=measured }
            frames=0; statTime=now
        }
    }
    func togglePause() { setPaused(!paused) }
    func setPaused(_ value: Bool) {
        guard game != nil, paused != value else { return }
        paused=value
        queue.async { [self] in
            if value { self.timer?.setEventHandler {}; gb_audio_pause(true) }
            else { gb_audio_pause(false); self.statTime=ProcessInfo.processInfo.systemUptime; self.frames=0; self.timer?.setEventHandler { [weak self] in self?.tick() } }
        }
    }
    func stop() {
        guard !loading else { return }
        loading=true
        queue.async {
            let saved=self.stopCore()
            DispatchQueue.main.async { self.game=nil; self.paused=false; self.loading=false; if !saved { self.error="自动存档失败，请检查磁盘空间和保存目录权限。" } }
        }
    }
    @discardableResult private func stopCore() -> Bool {
        timer?.cancel(); timer=nil
        var saved=true
        if let game=current { saved=gb_save_state(LibraryPaths.saves.appendingPathComponent(game.id+".auto.state").path) }
        gb_unload(); current=nil
        return saved
    }
    func quickSave() {
        guard let game=game else { return }
        queue.async {
            let ok=gb_save_state(LibraryPaths.state(game).path)
            DispatchQueue.main.async { self.showToast(ok ? "已保存进度" : "这个核心未能保存进度") }
        }
    }
    func quickLoad() {
        guard let game=game else { return }
        queue.async {
            let ok=gb_load_state(LibraryPaths.state(game).path)
            DispatchQueue.main.async { self.showToast(ok ? "已读取进度" : "没有可用的手动存档") }
        }
    }
    func reset() {
        queue.async { gb_reset() }
        showToast("游戏已重启")
    }
    func showToast(_ s: String) {
        toast=s
        DispatchQueue.main.asyncAfter(deadline:.now()+3) { if self.toast==s { self.toast=nil } }
    }
    func addPreset(_ values: [GameCheat]) {
        for cheat in values where !cheats.contains(where:{ $0.code==cheat.code }) { cheats.append(cheat) }
        persistCheats()
    }
    func setCheat(_ id: UUID, enabled: Bool) {
        guard let i=cheats.firstIndex(where:{ $0.id==id }) else { return }
        cheats[i].enabled=enabled; persistCheats()
    }
    func deleteCheat(_ id: UUID) { cheats.removeAll { $0.id==id }; persistCheats() }
    func disableCheats() { for i in cheats.indices { cheats[i].enabled=false }; persistCheats() }
    private func persistCheats() {
        guard let game=game else { return }
        do { try CheatFiles.write(cheats,game:game) }
        catch { self.error="保存金手指失败："+error.localizedDescription }
        let values=cheats
        queue.async { CheatFiles.apply(values) }
    }
    func shutdown() { _=queue.sync { self.stopCore() } }
}
