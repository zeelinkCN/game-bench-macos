import AppKit
import Combine
import Foundation
import SwiftUI

// Build with PLAYBACK_PERFORMANCE_TESTS so the test exercises the production
// ContentView, controller status publication, emulator and frame presenter.
@main struct PlaybackPerformance {
    @MainActor static func main() throws {
        let app=NSApplication.shared
        let root=Bundle.main.bundleURL.pathExtension=="app" ? Bundle.main.bundleURL.deletingLastPathComponent() : URL(fileURLWithPath:CommandLine.arguments[0]).deletingLastPathComponent()
        let data=root.appendingPathComponent("PlaybackData-"+UUID().uuidString)
        setenv("GAMEBENCH_DATA_DIR",data.path,1)
        setenv("GAMEBENCH_NO_AUDIO","1",1)
        let library=GameLibrary()
        let catalog=(ProcessInfo.processInfo.environment["GAMEBENCH_LIBRARY_DIR"].map { URL(fileURLWithPath:$0) } ?? Bundle.main.resourceURL!.appendingPathComponent("Games")).appendingPathComponent("catalog.json")
        library.games=try JSONDecoder().decode([Game].self,from:Data(contentsOf:catalog))
        for i in library.games.indices { library.games[i].recognizeEdition() }
        let engine=Emulator()
        let controllers=ControllerCenter(monitorDevices:false)
        engine.game=library.games.first { $0.title.contains("雪人兄弟") } ?? .demo
        controllers.inGame=true
        let view=ContentView(library:library,engine:engine,controllers:controllers)
        var durations=[Double]()
        for _ in 0..<12 {
            let start=ProcessInfo.processInfo.systemUptime
            withExtendedLifetime(view.body) {}
            durations.append((ProcessInfo.processInfo.systemUptime-start)*1000)
        }
        let sorted=durations.sorted()
        print(String(format:"games=%d gameplay body median=%.2fms p95=%.2fms max=%.2fms",library.games.count,sorted[sorted.count/2],sorted[sorted.count-1],sorted.last!))
        precondition(sorted[sorted.count/2]<16.7,"Playing must never sort the full game library on every UI update")
        controllers.updateStatus(PadStatus(name:"测试",connected:true),at:0)
        var publications=0
        let subscription=controllers.objectWillChange.sink { publications+=1 }
        for n in 0..<1000 {
            controllers.updateStatus(PadStatus(name:"测试",connected:true,buttons:n%2==0 ? ["A"] : ["B"],leftX:Float(n%20)/20),at:0)
        }
        precondition(publications==0,"Raw gameplay input must not invalidate the player UI")
        controllers.modalOpen=true
        controllers.updateStatus(PadStatus(name:"测试",connected:true,buttons:["A"],leftX:1),at:0)
        precondition(publications==1 && controllers.pads[0].buttons.contains("A"),"Controller diagnostics must still receive live button/axis values")
        controllers.modalOpen=false
        controllers.updateStatus(PadStatus(name:"1P · 键盘",connected:false),at:0)
        precondition(!controllers.pads[0].connected && publications==2,"Connection changes must still be published during gameplay")
        subscription.cancel()
        print("PASS: gameplay input isolation, diagnostics updates and disconnection status")
        if CommandLine.arguments.contains("--body-only") { return }
        let delegate=PlaybackRun(library:library,engine:engine,controllers:controllers,root:root)
        app.setActivationPolicy(.regular)
        app.delegate=delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor final class PlaybackRun: NSObject, NSApplicationDelegate {
    let library: GameLibrary
    let engine: Emulator
    let controllers: ControllerCenter
    let root: URL
    var window: NSWindow!
    var inputTimer: Timer?
    var finishTimer: Timer?
    var started=0.0
    var inputTicks=0
    var scenarios=[Game]()
    var scenarioIndex=0
    var results=[[String:Any]]()
    var checksPassed=true
    init(library: GameLibrary,engine: Emulator,controllers: ControllerCenter,root: URL) {
        self.library=library; self.engine=engine; self.controllers=controllers; self.root=root
        scenarios=["雪人兄弟 (简)","坦克大战 (简)","超级玛丽1"].compactMap { title in library.games.first { $0.title==title } }
        precondition(scenarios.count==3)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        window=NSWindow(contentRect:NSRect(x:120,y:120,width:1180,height:790),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
        window.title="播放性能回归测试"
        window.contentView=NSHostingView(rootView:ContentView(library:library,engine:engine,controllers:controllers).preferredColorScheme(.dark))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps:true)
        engine.onLaunch={ [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline:.now()+1) { self?.startMeasurement() }
        }
        launchScenario()
    }
    func launchScenario() {
        let game=scenarios[scenarioIndex]
        // Prepare an isolated in-game state quickly; no user's ROM, save or
        // controller is modified. Repeated Start pulses skip intro screens.
        let core=Bundle.main.resourceURL!.appendingPathComponent("Cores/\(game.system.core)_libretro.dylib")
        precondition(gb_load(core.path,LibraryPaths.rom(game).path,LibraryPaths.bios.path,LibraryPaths.saves.path,"performance-fixture"))
        for _ in 0..<240 { gb_run() }
        for block in 0..<60 {
            gb_set_input(0,block%2==0 ? (1<<3)|(1<<8)|(1<<0) : 0)
            for _ in 0..<20 { gb_run() }
        }
        gb_set_input(0,0)
        for _ in 0..<300 { gb_run() }
        precondition(gb_save_state(LibraryPaths.saves.appendingPathComponent(game.id+".auto.state").path))
        gb_unload()
        engine.launch(game,resume:true)
    }
    func startMeasurement() {
        controllers.inGame=true
        inputTicks=0
        engine.presenter.resetStatistics()
        started=ProcessInfo.processInfo.systemUptime
        inputTimer=Timer(timeInterval:1.0/60,target:self,selector:#selector(simulateInput),userInfo:nil,repeats:true)
        RunLoop.main.add(inputTimer!,forMode:.common)
        finishTimer=Timer(timeInterval:8,target:self,selector:#selector(finishMeasurement),userInfo:nil,repeats:false)
        RunLoop.main.add(finishTimer!,forMode:.common)
    }
    @objc func simulateInput() {
        if engine.paused { engine.setPaused(false) }
        inputTicks+=1
        let n=inputTicks
        controllers.updateStatus(PadStatus(name:"回归测试手柄",detail:"模拟连续输入",connected:true,buttons:n%2==0 ? ["A","→"] : ["B","←"],leftX:n%2==0 ? 1 : -1),at:0)
        gb_set_input(0,n%120<60 ? (1<<7)|(1<<0) : (1<<6)|(1<<8))
        controllers.updateStatus(PadStatus(name:"回归测试 2P",connected:true,buttons:n%2==0 ? ["X"] : ["Y"],leftY:n%2==0 ? -1 : 1),at:1)
        gb_set_input(1,n%120<60 ? (1<<6)|(1<<0) : (1<<7)|(1<<8))
    }
    @objc func finishMeasurement() {
        inputTimer?.invalidate()
        let elapsed=ProcessInfo.processInfo.systemUptime-started
        let s=engine.presenter.statistics()
        let passed=Double(inputTicks)/elapsed>55 && Double(s.presentedFrames)/elapsed>55 && s.intervalP95MS<25 && s.intervalMaxMS<100
        checksPassed=checksPassed && passed
        let result: [String:Any] = ["game":scenarios[scenarioIndex].title,"passed":passed,"seconds":elapsed,"gameCount":library.games.count,"inputUpdates":inputTicks,"inputHz":Double(inputTicks)/elapsed,"coreSubmittedFPS":Double(s.submittedFrames)/elapsed,"presentedFPS":Double(s.presentedFrames)/elapsed,"replacedFrames":s.replacedFrames,"presentationP95MS":s.intervalP95MS,"presentationMaxMS":s.intervalMaxMS]
        results.append(result)
        let data=try! JSONSerialization.data(withJSONObject:["passed":checksPassed,"scenarios":results],options:[.prettyPrinted,.sortedKeys])
        try! data.write(to:root.appendingPathComponent("playback-performance-report.json"),options:.atomic)
        engine.shutdown()
        scenarioIndex+=1
        if scenarioIndex<scenarios.count { launchScenario(); return }
        NSApp.terminate(nil)
    }
}
