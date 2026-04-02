import Foundation

/// IRS Schedule E expense categories for rental properties
enum ExpenseCategory: String, CaseIterable, Codable, Identifiable {
    case advertising = "Advertising"
    case autoAndTravel = "Auto and travel"
    case cleaningAndMaintenance = "Cleaning and maintenance"
    case commissions = "Commissions"
    case insurance = "Insurance"
    case legalAndProfessionalFees = "Legal and other professional fees"
    case managementFees = "Management fees"
    case mortgageInterest = "Mortgage interest paid to banks, etc"
    case otherHOA = "Other (list) (HOA,etc)"
    case otherInterest = "Other interest"
    case repairs = "Repairs"
    case supplies = "Supplies"
    case taxes = "Taxes"
    case utilities = "Utilities"

    var id: String { rawValue }

    /// The folder name used in the file system
    var folderName: String { rawValue }

    /// Whether this category typically involves a principal/interest split
    var hasMortgageSplit: Bool {
        self == .mortgageInterest || self == .otherInterest
    }
}

/// Overhead expense categories (non-property-specific)
enum OverheadCategory: String, CaseIterable, Codable, Identifiable {
    case akb = "AKB"
    case advertising = "Advertising"
    case cash = "Cash"
    case overhead = "Overhead"
    case verizon = "Verizon"

    var id: String { rawValue }
    var folderName: String { rawValue }
}

/// Represents a rental property in the portfolio
struct Property: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var address: String
    var isActive: Bool

    /// The folder name used in the file system (matches property name)
    var folderName: String { name }

    init(id: UUID = UUID(), name: String, address: String = "", isActive: Bool = true) {
        self.id = id
        self.name = name
        self.address = address
        self.isActive = isActive
    }
}

/// Where an expense should be filed
enum ExpenseDestination: Codable, Hashable {
    case property(propertyId: UUID, category: ExpenseCategory)
    case overhead(category: OverheadCategory)

    /// The relative folder path from the tax year root
    func folderPath(properties: [Property]) -> String? {
        switch self {
        case .property(let propertyId, let category):
            guard let property = properties.first(where: { $0.id == propertyId }) else { return nil }
            return "Property Specific Files/\(property.folderName)/\(category.folderName)"
        case .overhead(let category):
            return "Overhead Expenses/\(category.folderName)"
        }
    }
}

/// Default properties matching Sam's portfolio
extension Property {
    static let sjtDefaults: [Property] = [
        Property(name: "105 Ross Ridge"),
        Property(name: "108 Beth Manor"),
        Property(name: "124 Sevarge"),
        Property(name: "1845 Tara"),
        Property(name: "1910 Winona"),
        Property(name: "210 Amanda"),
        Property(name: "217 Gardenia Ct"),
        Property(name: "224 Clubview"),
        Property(name: "2737 Sweetbriar"),
        Property(name: "317 County Road 82"),
        Property(name: "345 Janice"),
        Property(name: "35 Newton Lane"),
        Property(name: "4560 Landward"),
        Property(name: "4945 Caddell Street"),
        Property(name: "610 Wisteria Rd"),
        Property(name: "657 Thomas Avenue"),
        Property(name: "6633 Willow Springs"),
        Property(name: "68 Sevarge"),
        Property(name: "70 Acres - 10 Acre Lots"),
        Property(name: "702 Thomas Avenue"),
        Property(name: "713 Cranbrook"),
        Property(name: "722 Hillman Street"),
        Property(name: "8820 Bradley Road"),
        Property(name: "916 Skidmore"),
    ]
}
