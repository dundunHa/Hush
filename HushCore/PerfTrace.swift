import Foundation

public enum PerfTrace {
    public static var counters: [String: Int] = [:]
    
    public static func measure(_ name: String) {
        counters[name, default: 0] += 1
        #if DEBUG
        print("[PerfTrace] \(name): \(counters[name]!)")
        #endif
    }
    
    public static func reset() {
        counters.removeAll()
    }
}
