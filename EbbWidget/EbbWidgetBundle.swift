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
        SpacerWidget()
        ClockWidget()
        YearWidget()
        LifeWidget()
        TimeSavedWidget()
        LockScreenWidget()
    }
}
