import SwiftUI

private let isoFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter
}()

private let displayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
}()

private let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .iso8601)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    return calendar
}()

private func localStartOfCurrentMonth() -> Date {
    let calendar = Calendar.current
    let components = calendar.dateComponents([.year, .month], from: Date())
    return calendar.date(from: components) ?? Date()
}

private func startOfDayUTC(_ date: Date) -> Date {
    utcCalendar.startOfDay(for: date)
}

private func endOfDayUTC(_ date: Date) -> Date {
    let start = utcCalendar.startOfDay(for: date)
    let nextDay = utcCalendar.date(byAdding: .day, value: 1, to: start) ?? start
    return nextDay.addingTimeInterval(-0.001)
}

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
    @State private var transactions: [Transaction] = []
    @State private var transactionType: TransactionKind = .expense
    @State private var transactionCategoryId: String = ""
    @State private var transactionAmount = ""
    @State private var transactionDate = Date()
    @State private var transactionComment = ""
    @State private var transactionMessage = ""
    @State private var isSavingTransaction = false
    @State private var transactionPeriodStart = localStartOfCurrentMonth()
    @State private var transactionPeriodEnd = Date()
    @State private var isLoadingTransactions = false
    @State private var transactionsError = ""

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
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(family?.name ?? "")
                            .font(.headline)
                        if let currency = family?.currencyBase {
                            Text("Валюта семьи: \(currency)")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                    categoryForm(userId: user.id)
                    categoryLists(userId: user.id)
                    Divider()
                    transactionFilters()
                    transactionForm(user: user)
                    transactionsHistory()
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
                refreshTransactionsForCurrentPeriod()
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
                ensureTransactionCategorySelection()
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
                ensureTransactionCategorySelection()
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
                ensureTransactionCategorySelection()
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

    private func refreshTransactionsForCurrentPeriod() {
        guard let user = user else { return }
        let start = startOfDayUTC(transactionPeriodStart)
        let end = endOfDayUTC(transactionPeriodEnd)
        guard start <= end else {
            transactionsError = "Дата начала не может быть позже даты окончания"
            transactions = []
            return
        }

        transactionsError = ""
        isLoadingTransactions = true

        guard var components = URLComponents(string: "http://localhost:8080/api/v1/users/\(user.id)/transactions") else {
            isLoadingTransactions = false
            return
        }
        components.queryItems = [
            URLQueryItem(name: "start_date", value: isoFormatter.string(from: start)),
            URLQueryItem(name: "end_date", value: isoFormatter.string(from: end))
        ]

        guard let url = components.url else {
            isLoadingTransactions = false
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, error in
            DispatchQueue.main.async {
                isLoadingTransactions = false
            }
            if let error = error {
                DispatchQueue.main.async {
                    transactionsError = "Ошибка: \(error.localizedDescription)"
                }
                return
            }
            guard
                let data = data,
                let response = try? JSONDecoder().decode(TransactionList.self, from: data)
            else {
                DispatchQueue.main.async {
                    transactionsError = "Не удалось загрузить операции"
                }
                return
            }
            DispatchQueue.main.async {
                transactions = response.transactions.sorted { $0.occurredAt > $1.occurredAt }
            }
        }.resume()
    }

    private func saveTransaction(for user: User) {
        let selectedCategory = transactionCategoryId.isEmpty ? activeCategories.first?.id : transactionCategoryId
        guard let categoryId = selectedCategory else {
            transactionMessage = "Выберите категорию"
            return
        }
        guard let amount = Int64(transactionAmount) else {
            transactionMessage = "Сумма должна быть целым числом"
            return
        }
        guard amount != 0 else {
            transactionMessage = "Сумма не может быть нулевой"
            return
        }

        guard let url = URL(string: "http://localhost:8080/api/v1/transactions") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = TransactionRequest(
            userId: user.id,
            categoryId: categoryId,
            type: transactionType.rawValue,
            amountMinor: amount,
            currency: user.currencyDefault,
            comment: transactionComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : transactionComment,
            occurredAt: isoFormatter.string(from: transactionDate)
        )

        request.httpBody = try? JSONEncoder().encode(payload)
        transactionMessage = ""
        isSavingTransaction = true

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isSavingTransaction = false
            }
            if let error = error {
                DispatchQueue.main.async {
                    transactionMessage = "Ошибка: \(error.localizedDescription)"
                }
                return
            }
            guard
                let data = data,
                let response = try? JSONDecoder().decode(TransactionResponse.self, from: data)
            else {
                DispatchQueue.main.async {
                    transactionMessage = "Некорректный ответ сервера"
                }
                return
            }

            DispatchQueue.main.async {
                let transaction = response.transaction
                if isTransactionWithinCurrentPeriod(transaction) {
                    transactions.append(transaction)
                    transactions.sort { $0.occurredAt > $1.occurredAt }
                }
                transactionAmount = ""
                transactionComment = ""
                transactionMessage = "Операция сохранена"
            }
        }.resume()
    }

    private func isTransactionWithinCurrentPeriod(_ transaction: Transaction) -> Bool {
        let start = startOfDayUTC(transactionPeriodStart)
        let end = endOfDayUTC(transactionPeriodEnd)
        return transaction.occurredAt >= start && transaction.occurredAt <= end
    }

    private func ensureTransactionCategorySelection() {
        let activeIds = activeCategories.map(\.id)
        if !transactionCategoryId.isEmpty, activeIds.contains(transactionCategoryId) {
            return
        }
        transactionCategoryId = activeIds.first ?? ""
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

    @ViewBuilder
    private func transactionFilters() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Период операций")
                .font(.headline)
            HStack {
                DatePicker(
                    "Начало",
                    selection: $transactionPeriodStart,
                    displayedComponents: .date
                )
                DatePicker(
                    "Конец",
                    selection: $transactionPeriodEnd,
                    displayedComponents: .date
                )
            }
            Button(action: refreshTransactionsForCurrentPeriod) {
                if isLoadingTransactions {
                    ProgressView()
                }
                Text("Обновить период")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoadingTransactions)

            if !transactionsError.isEmpty {
                Text(transactionsError)
                    .font(.footnote)
                    .foregroundColor(.red)
            }
        }
    }

    @ViewBuilder
    private func transactionForm(user: User) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Новая операция")
                .font(.headline)
            Picker("Тип", selection: $transactionType) {
                ForEach(TransactionKind.allCases, id: \.self) { kind in
                    Text(kind.localizedTitle).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            if activeCategories.isEmpty {
                Text("Добавьте хотя бы одну активную категорию для создания операции")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                Picker("Категория", selection: $transactionCategoryId) {
                    ForEach(activeCategories) { category in
                        Text(category.name).tag(category.id)
                    }
                }
            }

            TextField("Сумма в минорных единицах", text: $transactionAmount)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numberPad)

            DatePicker(
                "Дата и время",
                selection: $transactionDate,
                displayedComponents: [.date, .hourAndMinute]
            )

            TextField("Комментарий", text: $transactionComment)
                .textFieldStyle(.roundedBorder)

            Button(action: { saveTransaction(for: user) }) {
                if isSavingTransaction {
                    ProgressView()
                }
                Text("Сохранить операцию")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSavingTransaction || activeCategories.isEmpty)

            if !transactionMessage.isEmpty {
                Text(transactionMessage)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private func transactionsHistory() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("История операций")
                .font(.headline)

            if isLoadingTransactions {
                ProgressView("Загрузка операций…")
            }

            if transactions.isEmpty && !isLoadingTransactions && transactionsError.isEmpty {
                Text("За выбранный период операций нет")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            ForEach(transactions) { transaction in
                transactionRow(transaction: transaction)
            }
        }
    }

    private func transactionRow(transaction: Transaction) -> some View {
        let categoryName = categories.first(where: { $0.id == transaction.categoryId })?.name ?? "Категория"
        let amount = Double(transaction.amountMinor) / 100.0
        let amountText = String(format: "%@%.2f %@", transaction.type.symbol, abs(amount), transaction.currency)
        let comment = transaction.comment?.trimmingCharacters(in: .whitespacesAndNewlines)

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(categoryName)
                    .font(.subheadline)
                    .bold()
                Spacer()
                Text(amountText)
                    .font(.subheadline)
                    .foregroundColor(transaction.type.tint)
            }
            Text(displayFormatter.string(from: transaction.occurredAt))
                .font(.caption)
                .foregroundColor(.secondary)
            if let comment, !comment.isEmpty {
                Text(comment)
                    .font(.footnote)
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
    let familyId: String
    let email: String
    let name: String
    let role: String
    let locale: String
    let currencyDefault: String

    enum CodingKeys: String, CodingKey {
        case id
        case familyId = "family_id"
        case email
        case name
        case role
        case locale
        case currencyDefault = "currency_default"
    }
}

private struct Family: Codable {
    let id: String
    let name: String
    let currencyBase: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case currencyBase = "currency_base"
    }
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

private enum TransactionKind: String, CaseIterable, Codable {
    case income
    case expense

    var localizedTitle: String {
        switch self {
        case .income: return "Доход"
        case .expense: return "Расход"
        }
    }

    var symbol: String {
        switch self {
        case .income: return "+"
        case .expense: return "-"
        }
    }

    var tint: Color {
        switch self {
        case .income: return .green
        case .expense: return .red
        }
    }
}

private struct TransactionList: Decodable {
    let transactions: [Transaction]
}

private struct Transaction: Decodable, Identifiable {
    let id: String
    let familyId: String
    let userId: String
    let categoryId: String
    let type: TransactionKind
    let amountMinor: Int64
    let currency: String
    let comment: String?
    let occurredAt: Date
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case familyId = "family_id"
        case userId = "user_id"
        case categoryId = "category_id"
        case type
        case amountMinor = "amount_minor"
        case currency
        case comment
        case occurredAt = "occurred_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        familyId = try container.decode(String.self, forKey: .familyId)
        userId = try container.decode(String.self, forKey: .userId)
        categoryId = try container.decode(String.self, forKey: .categoryId)
        type = try container.decode(TransactionKind.self, forKey: .type)
        amountMinor = try container.decode(Int64.self, forKey: .amountMinor)
        currency = try container.decode(String.self, forKey: .currency)
        comment = try container.decodeIfPresent(String.self, forKey: .comment)

        func decodeDate(_ key: CodingKeys) throws -> Date {
            let value = try container.decode(String.self, forKey: key)
            if let date = isoFormatter.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Некорректный формат даты")
        }

        occurredAt = try decodeDate(.occurredAt)
        createdAt = try decodeDate(.createdAt)
        updatedAt = try decodeDate(.updatedAt)
    }
}

private struct TransactionRequest: Encodable {
    let userId: String
    let categoryId: String
    let type: String
    let amountMinor: Int64
    let currency: String
    let comment: String?
    let occurredAt: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case categoryId = "category_id"
        case type
        case amountMinor = "amount_minor"
        case currency
        case comment
        case occurredAt = "occurred_at"
    }
}

private struct TransactionResponse: Decodable {
    let transaction: Transaction
}
