import XCTest
@testable import Roam

final class ExpenseTests: XCTestCase {
    func testDecimalTotalsAndCurrencySeparation() throws {
        var day = TravelDay()
        day.items = [PlanItem(title: "午餐", category: .expense, amount: ExpenseMoney.parse("0.10"), currency: "CNY"),
                     PlanItem(title: "门票", category: .expense, amount: ExpenseMoney.parse("0.20"), currency: "CNY"),
                     PlanItem(title: "交通", category: .expense, amount: 500, currency: "JPY")]
        XCTAssertEqual(day.expenseTotals["CNY"], Decimal(string: "0.30"))
        XCTAssertEqual(day.expenseTotals["JPY"], 500)
        day.items[0].amount = 10
        XCTAssertEqual(day.expenseTotals["CNY"], Decimal(string: "10.20"))
        day.items.remove(at: 1)
        XCTAssertEqual(day.expenseTotals["CNY"], 10)
        let data = try JSONEncoder().encode(day)
        XCTAssertEqual(try JSONDecoder().decode(TravelDay.self, from: data), day)
    }
    func testExistingItemsDecodeAndInvalidAmountsAreRejected() throws {
        let old = Data(#"{"id":"55555555-5555-5555-5555-555555555555","title":"门票","detail":"","time":"","category":"逛什么"}"#.utf8)
        let item = try JSONDecoder().decode(PlanItem.self, from: old)
        XCTAssertNil(item.amount)
        XCTAssertEqual(TravelDay(items: [item]).expenseTotals, [:])
        for value in ["", "-1", "NaN", "1.234", "12abc", "1,000", "10000000000"] { XCTAssertNil(ExpenseMoney.parse(value), value) }
        XCTAssertEqual(ExpenseMoney.parse("0"), 0)
        XCTAssertEqual(ExpenseMoney.parse(" 12.50 "), Decimal(string: "12.5"))
    }
    func testExpenseSurvivesCloudEncoding() throws {
        var trip = Trip(destination: "测试", country: "中国", startDate: Date(), cover: "", days: [TravelDay(), TravelDay()])
        let expense = PlanItem(title: "餐费", category: .expense, amount: 25, currency: "CNY")
        trip.days[0].items.append(expense)
        var cloud = CloudLibrary()
        cloud.trips[trip.id.uuidString] = CloudTripVersion(trip: trip)
        let decoded = try JSONDecoder().decode(CloudLibrary.self, from: JSONEncoder().encode(cloud))
        XCTAssertEqual(decoded.visible.first?.days.first?.expenseTotals["CNY"], 25)
    }
}
