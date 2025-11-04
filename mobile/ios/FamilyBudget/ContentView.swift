import SwiftUI

struct ContentView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var familyName = ""
    @State private var currency = "RUB"
    @State private var status = "Создайте владельца семьи"
    @State private var categories: [String] = []
    @State private var isLoading = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(status)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    registrationCard
                    if !categories.isEmpty {
                        categoryCard
                    }
                }
                .padding()
            }
            .navigationTitle("Family Budget")
        }
    }

    private var registrationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Имя", text: $name)
                .textFieldStyle(.roundedBorder)
            TextField("Email", text: $email)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.emailAddress)
            SecureField("Пароль", text: $password)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 12) {
                TextField("Валюта", text: $currency)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.characters)
                TextField("Семья", text: $familyName)
                    .textFieldStyle(.roundedBorder)
            }
            Button(action: register) {
                HStack {
                    if isLoading {
                        ProgressView()
                    }
                    Text("Создать семью")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSubmit)
        }
        .padding()
        .background(.thinMaterial)
        .cornerRadius(16)
    }

    private var categoryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Базовые категории")
                .font(.headline)
            ForEach(categories, id: \.self) { category in
                Text("• \(category)")
                    .font(.subheadline)
            }
        }
        .padding()
        .background(.thinMaterial)
        .cornerRadius(16)
    }

    private var canSubmit: Bool {
        !isLoading && !email.isEmpty && !password.isEmpty && !name.isEmpty
    }

    private func register() {
        guard let url = URL(string: "http://localhost:8080/api/v1/users") else { return }
        isLoading = true
        status = "Отправка данных..."

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = RegisterRequest(
            email: email,
            password: password,
            name: name,
            locale: "ru-RU",
            currency: currency,
            familyName: familyName.isEmpty ? nil : familyName
        )

        request.httpBody = try? JSONEncoder().encode(payload)

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false
            }
            if let error = error {
                DispatchQueue.main.async {
                    status = "Ошибка: \(error.localizedDescription)"
                }
                return
            }
            guard
                let data = data,
                let registerResponse = try? JSONDecoder().decode(RegisterResponse.self, from: data)
            else {
                DispatchQueue.main.async {
                    status = "Некорректный ответ сервера"
                }
                return
            }

            DispatchQueue.main.async {
                status = "Профиль создан для \(registerResponse.user.name)"
            }

            loadCategories(userId: registerResponse.user.id)
        }.resume()
    }

    private func loadCategories(userId: String) {
        guard let url = URL(string: "http://localhost:8080/api/v1/users/\(userId)/categories") else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard
                let data = data,
                let response = try? JSONDecoder().decode(CategoryList.self, from: data)
            else { return }
            DispatchQueue.main.async {
                categories = response.categories.map(\.name)
            }
        }.resume()
    }
}

private struct RegisterRequest: Codable {
    let email: String
    let password: String
    let name: String
    let locale: String
    let currency: String
    let familyName: String?

    enum CodingKeys: String, CodingKey {
        case email, password, name, locale, currency
        case familyName = "family_name"
    }
}

private struct RegisterResponse: Codable {
    let user: User
    let family: Family
}

private struct User: Codable {
    let id: String
    let name: String
}

private struct Family: Codable {
    let id: String
    let name: String
}

private struct CategoryList: Codable {
    let categories: [Category]
}

private struct Category: Codable {
    let id: String
    let name: String
}
