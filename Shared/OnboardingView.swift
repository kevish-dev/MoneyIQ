import SwiftUI
import MoneyIQCore

struct OnboardingView: View {
    @Bindable var account: UserAccount
    @Environment(\.modelContext) private var modelContext

    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var mobileNumber: String = ""
    @State private var age: String = ""
    @State private var monthlyIncome: String = ""

    var body: some View {
        Form {
            Section("Profile") {
                TextField("First name", text: $firstName)
                TextField("Last name", text: $lastName)
                TextField("Mobile number", text: $mobileNumber)
                    #if os(iOS)
                    .keyboardType(.phonePad)
                    #endif
                TextField("Age", text: $age)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
            }

            Section("Income") {
                TextField("Monthly income", text: $monthlyIncome)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
            }

            Section {
                Button("Finish setup") {
                    save()
                }
                .disabled(firstName.isEmpty || lastName.isEmpty)
            }
        }
        .onAppear {
            firstName = account.firstName
            lastName = account.lastName
            mobileNumber = account.mobileNumber ?? ""
        }
        #if os(macOS)
        .padding()
        .frame(minWidth: 420, minHeight: 420)
        #endif
    }

    private func save() {
        account.firstName = firstName
        account.lastName = lastName
        account.mobileNumber = mobileNumber.isEmpty ? nil : mobileNumber
        account.age = Int(age)
        account.monthlyIncome = Decimal(string: monthlyIncome)
        try? modelContext.save()
    }
}
