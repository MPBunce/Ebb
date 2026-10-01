//
//  EbbWidgetBundle.swift
//  EbbWidget
//

import SwiftUI
import WidgetKit

@main
struct EbbWidgetBundle: WidgetBundle {
    var body: some Widget {
        LauncherWidget()
        ClockWidget()
        YearWidget()
        LifeWidget()
        TimeSavedWidget()
        LockScreenWidget()
    }
}
