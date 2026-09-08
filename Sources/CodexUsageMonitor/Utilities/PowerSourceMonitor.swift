import Foundation
import IOKit.ps

enum PowerSourceMonitor {
    static var isOnBattery: Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue()
        else { return false }
        return (type as String) == (kIOPSBatteryPowerValue as String)
    }
}
