import Foundation
import Darwin

/// Memória do app: quanto está em uso e quanto o iOS ainda deixa usar antes de encerrar o app.
enum Medidor {
    static func usada() -> UInt64 {
        var info = task_vm_info_data_t()
        var n = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &info) { p in
            p.withMemoryRebound(to: integer_t.self, capacity: Int(n)) { q in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), q, &n)
            }
        }
        return r == KERN_SUCCESS ? UInt64(info.phys_footprint) : 0
    }

    static func livre() -> UInt64 { UInt64(os_proc_available_memory()) }

    static var totalDoAparelho: UInt64 { ProcessInfo.processInfo.physicalMemory }

    static func texto(_ b: UInt64) -> String {
        String(format: "%.2f GB", Double(b) / 1_073_741_824)
    }
}
