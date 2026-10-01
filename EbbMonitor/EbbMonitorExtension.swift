//
//  EbbMonitorExtension.swift
//  EbbMonitor
//
//  Raises and lowers shields when scheduled Screen Time intervals start and end,
//  and ends breather allowances once their usage time is spent.
//

import DeviceActivity
import Foundation

final class EbbMonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        switch activity {
        case .session:
            ShieldController.activate(.session)
        case .nightly:
            ShieldController.activate(.nightly)
        case .daily:
            // A new day: yesterday's allowances no longer apply.
            ShieldController.pruneAllowances()
        default:
            // Work periods repeat daily; only block on the chosen weekdays.
            if let period = WorkPeriod.period(for: activity), period.isEnabled, period.applies(on: .now) {
                ShieldController.activate(.work)
            }
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        switch activity {
        case .session:
            ShieldController.sessionEnd = nil
            ShieldController.deactivate(.session)
            // One-off sessions shouldn't repeat.
            DeviceActivityCenter().stopMonitoring([.session])
        case .nightly:
            ShieldController.deactivate(.nightly)
        case .daily:
            // Daily usage limits reset at midnight.
            ShieldController.deactivate(.dailyLimit)
        default:
            if WorkPeriod.period(for: activity) != nil {
                // Another period may still be running (overlapping schedules).
                ShieldController.reconcileWorkPeriods()
            } else if let slot = Allowance.slot(for: activity) {
                ShieldController.endAllowance(slot: slot)
                DeviceActivityCenter().stopMonitoring([activity])
            }
        }
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        if event == .dailyLimit {
            ShieldController.activate(.dailyLimit)
        } else if event == .allowanceUsed, let slot = Allowance.slot(for: activity) {
            // The user has used the app for as long as they chose: block it again.
            ShieldController.endAllowance(slot: slot)
            DeviceActivityCenter().stopMonitoring([activity])
        }
    }
}
