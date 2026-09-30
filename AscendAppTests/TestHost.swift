import Darwin
import Testing

/// Facts about the machine the test host runs on.
enum TestHost {
    /// Whether the host runs under a hypervisor - CI's `macos` runners are virtual Macs, and an
    /// Apple Silicon developer machine is not. The simulator shares the host kernel, so the sysctl
    /// answers for the Mac underneath it.
    static let isVirtualMachine: Bool = {
        var present: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("kern.hv_vmm_present", &present, &size, nil, 0) == 0 && present == 1
    }()

    /// Why a test that hosts the RealityKit Mountain does not run on a virtual Mac.
    static let realityKitVirtualGPUReason: Comment =
        "RealityKit's render thread asserts on virtualized GPUs - see #629"
}
