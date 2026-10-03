//
//  PlusStoreTests.swift
//  EbbTests
//
//  Buys Ebb Plus against a local StoreKit configuration (no real App Store).
//

import StoreKitTest
import Testing
@testable import Ebb

@MainActor
@Suite(.serialized)
struct PlusStoreTests {
    @Test func purchaseUnlocksPlus() async throws {
        let session = try SKTestSession(configurationFileNamed: "EbbPlus")
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true

        let store = PlusStore.shared
        store.setActive(false)
        await store.loadProduct()
        #expect(store.product?.id == PlusStore.productID)

        await store.purchase()
        #expect(store.errorMessage == nil)
        #expect(store.isActive)
        // Widgets read the App Group copy.
        #expect(EbbPlus.isActive)

        store.setActive(false)
        await store.refreshEntitlement()
        #expect(EbbPlus.isActive)
    }
}
