//
//  PlusStore.swift
//  Ebb
//
//  Buys and restores Ebb Plus, a one-time (non-consumable) in-app purchase,
//  and keeps `EbbPlus.isActive` (shared with the widgets) in step with what the App Store says you own.
//

import Foundation
import Observation
import StoreKit

@Observable
final class PlusStore {
    static let shared = PlusStore()

    /// Must match the in-app purchase set up in App Store Connect.
    static let productID = "mpbunce.ebb.plus"

    private(set) var product: Product?
    private(set) var isPurchasing = false
    private(set) var isRestoring = false
    /// Set when loading, buying or restoring fails, for the Plus screen to show.
    var errorMessage: String?

    private var updates: Task<Void, Never>?
    /// Told when Plus turns on or off, so app widget limits and widgets update.
    private weak var launcher: LauncherStore?
    /// Mirrors `EbbPlus.isActive` so SwiftUI views update when it changes.
    private(set) var isActive = EbbPlus.isActive

    /// Loads the product, checks what's owned, and listens for purchases made elsewhere
    /// (another device, Ask to Buy approvals, refunds).
    func start(launcher: LauncherStore) {
        self.launcher = launcher
        guard updates == nil else { return }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(result)
            }
        }
        Task {
            await loadProduct()
            await refreshEntitlement()
        }
    }

    func loadProduct() async {
        guard product == nil else { return }
        do {
            product = try await Product.products(for: [Self.productID]).first
        } catch {
            errorMessage = "Couldn't reach the App Store. Check your connection and try again."
        }
    }

    func purchase() async {
        if product == nil { await loadProduct() }
        guard let product else {
            errorMessage = "Ebb Plus isn't available right now. Try again later."
            return
        }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let result):
                await handle(result)
            case .pending:
                // Ask to Buy or a payment check; Transaction.updates delivers it later.
                errorMessage = "Your purchase is waiting for approval."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = "The purchase didn't go through. You haven't been charged."
        }
    }

    /// Restore Purchases: syncs with the App Store (may ask the user to sign in).
    func restore() async {
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await AppStore.sync()
        } catch {
            errorMessage = "Couldn't restore purchases. Check your connection and try again."
        }
        await refreshEntitlement()
        if !EbbPlus.isActive {
            errorMessage = "No Ebb Plus purchase was found for this Apple Account."
        }
    }

    /// Unlocks Plus if a verified, unrefunded purchase exists. Release builds also lock it
    /// again when there isn't one (for example after a refund).
    func refreshEntitlement() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                owned = true
            }
        }
        apply(owned: owned)
    }

    private func handle(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else { return }
        await transaction.finish()
        if transaction.productID == Self.productID {
            await refreshEntitlement()
        }
    }

    private func apply(owned: Bool) {
        #if DEBUG
        // Keep the developer preview switch working when nothing has been bought.
        if owned { setActive(true) }
        #else
        setActive(owned)
        #endif
    }

    /// Turns Plus on or off for the app and widgets (also used by the developer switch).
    func setActive(_ active: Bool) {
        EbbPlus.isActive = active
        isActive = active
        launcher?.refreshPlan()
    }
}
