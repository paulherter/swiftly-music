import Foundation
import Testing
@testable import SubsonicKit

@Suite("Stern für viele Lieder")
struct SternbuendelTests {

    @Test("star und unstar mit jeder Kennung als eigenem id, leer ohne Aufruf")
    func vieleKennungen() async throws {
        let attrappe = Attrappe(["star": ["ping"], "unstar": ["ping"]])
        let client = attrappe.client()
        try await client.sterne(lieder: ["l1", "l2", "l3"], an: true)
        try await client.sterne(lieder: [], an: true)
        try await client.sterne(lieder: ["l4"], an: false)
        #expect(attrappe.anfragen.count == 2)
        func kennungen(_ n: Int) -> [String] {
            let teile = URLComponents(url: attrappe.anfragen[n].url!, resolvingAgainstBaseURL: false)
            return (teile?.queryItems ?? []).filter { $0.name == "id" }.compactMap(\.value)
        }
        #expect(attrappe.anfragen[0].url?.lastPathComponent == "star.view")
        #expect(kennungen(0) == ["l1", "l2", "l3"])
        #expect(attrappe.anfragen[1].url?.lastPathComponent == "unstar.view")
        #expect(kennungen(1) == ["l4"])
    }
}
