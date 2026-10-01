//
//  ShieldConfigurationExtension.swift
//  EbbShield
//
//  The calm screen shown in place of a blocked app.
//

import ManagedSettings
import ManagedSettingsUI
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        makeConfiguration()
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration()
    }

    private func makeConfiguration() -> ShieldConfiguration {
        let defaults = AppGroup.defaults
        let custom = defaults.string(forKey: AppGroup.Key.shieldTitle).flatMap { $0.isEmpty ? nil : $0 }
        let customSubtitle = defaults.string(forKey: AppGroup.Key.shieldSubtitle).flatMap { $0.isEmpty ? nil : $0 }

        let isWork = ShieldController.activeReasons.contains(.work)
        let title = isWork ? "Work time" : (custom ?? "Let it ebb.")
        let subtitle = isWork
            ? "Only your work apps are open right now. If you really need this one, take a breath first."
            : (customSubtitle ?? "This app is resting right now. Take a breath and come back to what matters.")

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterialDark,
            backgroundColor: .black,
            icon: UIImage(systemName: isWork ? "briefcase" : "water.waves"),
            title: .init(text: title, color: .white),
            subtitle: .init(text: subtitle, color: .lightGray),
            primaryButtonLabel: .init(text: "Close", color: .black),
            primaryButtonBackgroundColor: .white,
            secondaryButtonLabel: .init(text: "Take a breath", color: .white)
        )
    }
}
