import SwiftUI

struct ContentView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var familyName = ""
    @State private var currency = "RUB"
    @State private var status = "Создайте владельца семьи"
    @State private var user: User? = nil
    @State private var family: Family? = nil
    @State private var categories: [Category] = []
    @State private var isLoading = false
    @State private var categoryName = ""
    @State private var categoryType: CategoryType = .expense
    @State private var categoryColor = "#0EA5E9"
    @State private var categoryDescription = ""
    @State private var categoryParentId: String? = nil
    @State private var editingCategoryId: String? = nil
    @State private var categoryMessage = ""
    @State private var isSavingCategory = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(status)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    registrationCard
                    categoryManagement
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

    private var categoryManagement: some View {
        Group {
            if let user = user {
                VStack(alignment: .leading, spacing: 16) {
                    Text(family?.name ?? "")
                        .font(.headline)
                    categoryForm(userId: user.id)
                    categoryLists(userId: user.id)
                }
                .padding()
                .background(.thinMaterial)
                .cornerRadius(16)
            }
        }
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
                user = registerResponse.user
                family = registerResponse.family
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
                categories = response.categories.sorted { lhs, rhs in
                    if lhs.isArchived == rhs.isArchived {
                        return lhs.name < rhs.name
                    }
                    return !lhs.isArchived && rhs.isArchived
                }
            }
        }.resume()
    }

    private func saveCategory(for userId: String) {
        guard !categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            categoryMessage = "Название категории обязательно"
            return
        }
        let isEditing = editingCategoryId != nil
        let endpoint: String
        if let editingCategoryId {
            endpoint = "http://localhost:8080/api/v1/users/\(userId)/categories/\(editingCategoryId)"
        } else {
            endpoint = "http://localhost:8080/api/v1/users/\(userId)/categories"
        }
        guard let url = URL(string: endpoint) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = isEditing ? "PUT" : "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = CategoryPayload(
            name: categoryName,
            type: categoryType.rawValue,
            color: categoryColor,
            description: categoryDescription.isEmpty ? nil : categoryDescription,
            parentId: categoryParentId
        )

        request.httpBody = try? JSONEncoder().encode(payload)
        isSavingCategory = true
        categoryMessage = ""

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isSavingCategory = false
            }
            if let error = error {
                DispatchQueue.main.async {
                    categoryMessage = "Ошибка: \(error.localizedDescription)"
                }
                return
            }
            guard
                let data = data,
                let response = try? JSONDecoder().decode(CategoryResponse.self, from: data)
            else {
                DispatchQueue.main.async {
                    categoryMessage = "Некорректный ответ сервера"
                }
                return
            }
            DispatchQueue.main.async {
                let category = response.category
                categories.removeAll { $0.id == category.id }
                categories.append(category)
                categories.sort { lhs, rhs in
                    if lhs.isArchived == rhs.isArchived {
                        return lhs.name < rhs.name
                    }
                    return !lhs.isArchived && rhs.isArchived
                }
                categoryMessage = isEditing ? "Категория обновлена" : "Категория создана"
                resetCategoryForm()
            }
        }.resume()
    }

    private func archiveCategory(userId: String, category: Category, archived: Bool) {
        guard let url = URL(string: "http://localhost:8080/api/v1/users/\(userId)/categories/\(category.id)/archive") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(CategoryArchiveRequest(archived: archived))

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                DispatchQueue.main.async {
                    categoryMessage = "Ошибка: \(error.localizedDescription)"
                }
                return
            }
            guard
                let data = data,
                let response = try? JSONDecoder().decode(CategoryResponse.self, from: data)
            else { return }
            DispatchQueue.main.async {
                let category = response.category
                categories = categories.map { $0.id == category.id ? category : $0 }
                categories.sort { lhs, rhs in
                    if lhs.isArchived == rhs.isArchived {
                        return lhs.name < rhs.name
                    }
                    return !lhs.isArchived && rhs.isArchived
                }
                categoryMessage = archived ? "Категория архивирована" : "Категория восстановлена"
                if archived && editingCategoryId == category.id {
                    resetCategoryForm()
                }
            }
        }.resume()
    }

    private func resetCategoryForm() {
        categoryName = ""
        categoryType = .expense
        categoryColor = "#0EA5E9"
        categoryDescription = ""
        categoryParentId = nil
        editingCategoryId = nil
    }

    @ViewBuilder
    private func categoryForm(userId: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(editingCategoryId == nil ? "Новая категория" : "Редактирование категории")
                .font(.headline)
            TextField("Название", text: $categoryName)
                .textFieldStyle(.roundedBorder)
            Picker("Тип", selection: $categoryType) {
                ForEach(CategoryType.allCases, id: \.self) { type in
                    Text(type.localizedTitle).tag(type)
                }
            }
            .pickerStyle(.segmented)
            TextField("Цвет", text: $categoryColor)
                .textFieldStyle(.roundedBorder)
            TextField("Описание", text: $categoryDescription)
                .textFieldStyle(.roundedBorder)
            Menu("Родительская категория: \(parentName)") {
                Button("Без родителя") {
                    categoryParentId = nil
                }
                ForEach(activeCategories.filter { $0.id != editingCategoryId }) { category in
                    Button(category.name) {
                        categoryParentId = category.id
                    }
                }
            }
            HStack {
                Button(action: { saveCategory(for: userId) }) {
                    if isSavingCategory {
                        ProgressView()
                    }
                    Text(editingCategoryId == nil ? "Создать" : "Сохранить")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSavingCategory)

                if editingCategoryId != nil {
                    Button("Отмена", action: resetCategoryForm)
                        .buttonStyle(.bordered)
                        .disabled(isSavingCategory)
                }
            }
            if !categoryMessage.isEmpty {
                Text(categoryMessage)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func categoryLists(userId: String) -> some View {
        let active = activeCategories
        let archived = archivedCategories
        if active.isEmpty && archived.isEmpty {
            Text("Добавьте первую категорию, чтобы фиксировать движения средств")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        if !active.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Активные")
                    .font(.headline)
                ForEach(active) { category in
                    categoryRow(userId: userId, category: category, archived: false)
                }
            }
        }
        if !archived.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Архив")
                    .font(.headline)
                ForEach(archived) { category in
                    categoryRow(userId: userId, category: category, archived: true)
                }
            }
        }
    }

    private func categoryRow(userId: String, category: Category, archived: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(category.name)
                    .font(.subheadline)
                    .bold()
                Spacer()
                Text(category.localizedType)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if let description = category.description, !description.isEmpty {
                Text(description)
                    .font(.footnote)
            }
            HStack {
                if !archived {
                    Button("Изменить") {
                        editingCategoryId = category.id
                        categoryName = category.name
                        categoryType = CategoryType(rawValue: category.type) ?? .expense
                        categoryColor = category.color
                        categoryDescription = category.description ?? ""
                        categoryParentId = category.parentId
                    }
                    .buttonStyle(.bordered)
                }
                if !category.isSystem {
                    Button(archived ? "Вернуть" : "Архивировать") {
                        archiveCategory(userId: userId, category: category, archived: !archived)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }

    private var activeCategories: [Category] {
        categories.filter { !$0.isArchived }
    }

    private var archivedCategories: [Category] {
        categories.filter { $0.isArchived }
    }

    private var parentName: String {
        if let id = categoryParentId, let category = categories.first(where: { $0.id == id }) {
            return category.name
        }
        return "Без родителя"
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

private struct Category: Codable, Identifiable {
    let id: String
    let familyId: String
    let parentId: String?
    let name: String
    let type: String
    let color: String
    let description: String?
    let isSystem: Bool
    let isArchived: Bool
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case familyId = "family_id"
        case parentId = "parent_id"
        case name
        case type
        case color
        case description
        case isSystem = "is_system"
        case isArchived = "is_archived"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var localizedType: String {
        switch type {
        case "income": return "Доход"
        case "transfer": return "Перевод"
        default: return "Расход"
        }
    }
}

private struct CategoryPayload: Codable {
    let name: String
    let type: String
    let color: String
    let description: String?
    let parentId: String?

    enum CodingKeys: String, CodingKey {
        case name, type, color, description
        case parentId = "parent_id"
    }
}

private struct CategoryResponse: Codable {
    let category: Category
}

private struct CategoryArchiveRequest: Codable {
    let archived: Bool
}

private enum CategoryType: String, CaseIterable {
    case income
    case expense
    case transfer

    var localizedTitle: String {
        switch self {
        case .income: return "Доход"
        case .expense: return "Расход"
        case .transfer: return "Перевод"
        }
    }
}
