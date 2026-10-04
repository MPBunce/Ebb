//
//  PlusPurchaseTests.swift
//  EbbTests
//
//  Buys and restores Ebb Plus against the local StoreKit configuration (EbbPlus.storekit),
//  so the purchase flow is checked without App Store Connect.
//

import Foundation
import StoreKit
import StoreKitTest
import Testing
@testable import Ebb

@MainActor
@Suite(.serialized)
struct PlusPurchaseTests {
    private func makeSession() throws -> SKTestSession {
        let session = try SKTestSession(configurationFileNamed: "EbbPlus")
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        return session
    }

    @Test func productLoads() async throws {
        _ = try makeSession()
        let product = try #require(try await Product.products(for: [PlusStore.productID]).first)
        #expect(product.displayName == "Ebb Plus")
        #expect(product.type == .nonConsumable)
        #expect(product.price == Decimal(string: "9.99"))
    }

    @Test func buyingUnlocksPlus() async throws {
        _ = try makeSession()
        let store = PlusStore.shared
        store.setActive(false)
        #expect(!EbbPlus.isActive)

        await store.purchase()

        #expect(store.errorMessage == nil)
        #expect(EbbPlus.isActive)
        #expect(store.isActive)
        #expect(EbbPlus.maxAppWidgets == EbbPlus.plusAppWidgets)
    }

    @Test func restoreFindsAnEarlierPurchase() async throws {
        let session = try makeSession()
        try await session.buyProduct(identifier: PlusStore.productID)
        let store = PlusStore.shared
        store.setActive(false)

        await store.refreshEntitlement()

        #expect(EbbPlus.isActive)
    }

    @Test func nothingOwnedStaysLocked() async throws {
        _ = try makeSession()
        let store = PlusStore.shared
        store.setActive(false)

        await store.refreshEntitlement()

        #expect(!EbbPlus.isActive)
        store.setActive(true)
    }
}
