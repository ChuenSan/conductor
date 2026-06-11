#if canImport(Darwin)
import Darwin
#endif
import Foundation

/// 读取某个进程的命令行（exec 路径 + argv），用于判断某个终端 pane 里在跑哪个 Agent。
/// 走 `sysctl(KERN_PROCARGS2)`，只取 exec 路径与参数，忽略环境变量以降低误判。
public enum ProcessInspector {
    /// 返回 `pid` 的累计 CPU 时间（user + system，秒）；失败返回 nil。
    /// 两次采样做差 ÷ 间隔即得占用率——用来判断 agent 是否在「思考」
    /// （活跃生成时 spinner/流式输出持续耗 CPU，空闲等输入时趋近 0）。
    public static func cpuTimeSeconds(pid: Int32) -> Double? {
        #if canImport(Darwin)
        guard pid > 0 else { return nil }
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.stride)
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { return nil }
        // pti_total_* 是 mach 时间单位，需 timebase 换算成纳秒
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let ticks = info.pti_total_user &+ info.pti_total_system
        let nanos = Double(ticks) * Double(timebase.numer) / Double(timebase.denom)
        return nanos / 1_000_000_000
        #else
        return nil
        #endif
    }

    /// 返回 `pid` 的「exec 路径 + 各 argv」用空格连接的小写串；失败返回 nil。
    public static func commandLine(pid: Int32) -> String? {
        #if canImport(Darwin)
        guard pid > 0 else { return nil }

        var argMax: Int32 = 0
        var sizeMax = MemoryLayout<Int32>.size
        var mibMax = [CTL_KERN, KERN_ARGMAX]
        if sysctl(&mibMax, 2, &argMax, &sizeMax, nil, 0) != 0 || argMax <= 0 {
            argMax = 262_144   // 兜底上限
        }

        var size = Int(argMax)
        var buffer = [CChar](repeating: 0, count: size)
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        if sysctl(&mib, 3, &buffer, &size, nil, 0) != 0 { return nil }
        guard size > MemoryLayout<Int32>.size else { return nil }

        // 前 4 字节是 argc。
        var argc: Int32 = 0
        withUnsafeMutableBytes(of: &argc) { dst in
            buffer.withUnsafeBytes { src in
                dst.copyBytes(from: UnsafeRawBufferPointer(start: src.baseAddress, count: MemoryLayout<Int32>.size))
            }
        }

        return buffer.withUnsafeBufferPointer { raw -> String? in
            guard let base = raw.baseAddress else { return nil }
            let total = size
            var index = MemoryLayout<Int32>.size

            func readCString() -> String? {
                guard index < total else { return nil }
                let start = index
                while index < total, base[index] != 0 { index += 1 }
                let length = index - start
                guard length > 0 else { return "" }
                let bytes = UnsafeRawBufferPointer(start: base + start, count: length)
                return String(bytes: bytes, encoding: .utf8)
            }

            // exec 路径
            guard let execPath = readCString() else { return nil }
            // 跳过 exec_path 后的连续 \0 对齐填充
            while index < total, base[index] == 0 { index += 1 }

            var tokens: [String] = [execPath]
            var collected: Int32 = 0
            while collected < argc, index < total {
                if let arg = readCString() { tokens.append(arg) }
                index += 1   // 跳过分隔 \0
                collected += 1
            }

            return tokens.joined(separator: " ").lowercased()
        }
        #else
        return nil
        #endif
    }
}
