#if DEBUG
import QuartzCore
import UIKit

/// A display-link frame counter, so "it feels laggy" can be answered with a number.
///
/// Prints one line every two seconds — average frame rate and the worst single frame in the
/// window. A `CADisplayLink` on the main thread is delayed by whatever blocks the main thread, so
/// the worst-frame figure is a direct read on main-thread stalls: anything over 16.7 ms dropped a
/// frame. Off unless `-tempusFPS 1` is passed, and DEBUG-only, so it costs nothing otherwise.
///
///     xcrun simctl launch --console-pty booted com.crescerestudios.tempus -tempusFPS 1 -tempusPhase concourse
///
/// Read it in the Simulator, but judge on a device and in Release: a Debug build in the Simulator
/// draws through the CPU and is several times slower than what ships.
final class FPSProbe {
    static let shared = FPSProbe()
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    private var frames = 0
    private var worst: Double = 0
    private var windowStart: CFTimeInterval = 0

    func startIfRequested() {
        guard UserDefaults.standard.string(forKey: "tempusFPS") != nil else { return }
        let l = CADisplayLink(target: self, selector: #selector(step))
        l.add(to: .main, forMode: .common)
        link = l
        windowStart = CACurrentMediaTime()
        last = windowStart
    }

    @objc private func step() {
        let now = CACurrentMediaTime()
        let dt = now - last
        last = now
        frames += 1
        worst = max(worst, dt)
        let elapsed = now - windowStart
        if elapsed >= 2 {
            let fps = Double(frames) / elapsed
            print(String(format: "[FPS] %.1f fps over %.1fs · worst frame %.1f ms",
                         fps, elapsed, worst * 1000))
            frames = 0
            worst = 0
            windowStart = now
        }
    }
}
#endif
