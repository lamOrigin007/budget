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
    @State private var accounts: [Account] = []
    @State private var isLoading = false
    @State private var categoryName = ""
    @State private var categoryType: CategoryType = .expense
    @State private var categoryColor = "#0EA5E9"
    @State private var categoryDescription = ""
    @State private var categoryParentId: String? = nil
    @State private var editingCategoryId: String? = nil
    @State private var categoryMessage = ""
    @State private var isSavingCategory = false
    @State private var accountNameInput = ""
    @State private var accountTypeSelection: AccountKind = .cash
    @State private var accountCurrencyInput = ""
    @State private var accountInitialAmount = ""
    @State private var accountMessage = ""
    @State private var isSavingAccount = false
    @State private var transactions: [Transaction] = []
    @State private var transactionType: TransactionKind = .expense
    @State private var transactionCategoryId: String = ""
    @State private var transactionAccountId: String = ""
    @State private var transactionAmount = ""
    @State private var transactionDate = Date()
    @State private var transactionComment = ""
    @State private var transactionMessage = ""
    @State private var isSavingTransaction = false
    @State private var transactionPeriodStart = localStartOfCurrentMonth()
    @State private var transactionPeriodEnd = Date()
    @State private var isLoadingTransactions = false
    @State private var transactionsError = ""
    @State private var transactionFilterType: TransactionTypeFilter = .all
    @State private var transactionFilterCategoryId: String = ""
    @State private var transactionFilterAccountId: String = ""

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
                    accountsSection(userId: user.id)
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
                accounts = registerResponse.accounts.sorted { $0.createdAt < $1.createdAt }
                ensureTransactionAccountSelection()
                accountCurrencyInput = registerResponse.user.currencyDefault
                refreshTransactionsForCurrentPeriod()
            }

            loadCategories(userId: registerResponse.user.id)
            loadAccounts(userId: registerResponse.user.id)
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

    private func loadAccounts(userId: String) {
        guard let url = URL(string: "http://localhost:8080/api/v1/users/\(userId)/accounts") else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard
                let data = data,
                let response = try? JSONDecoder().decode(AccountList.self, from: data)
            else { return }
            DispatchQueue.main.async {
                accounts = response.accounts.sorted { $0.createdAt < $1.createdAt }
                ensureTransactionAccountSelection()
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

    private func saveAccount(for userId: String) {
        let trimmedName = accountNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            accountMessage = "Название счёта обязательно"
            return
        }

        guard let url = URL(string: "http://localhost:8080/api/v1/users/\(userId)/accounts") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let trimmedCurrency = accountCurrencyInput.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let initialValue = Int64(accountInitialAmount) ?? 0
        let payload = AccountPayload(
            name: trimmedName,
            type: accountTypeSelection.rawValue,
            currency: trimmedCurrency.isEmpty ? nil : trimmedCurrency,
            initialBalanceMinor: initialValue != 0 ? initialValue : nil
        )

        request.httpBody = try? JSONEncoder().encode(payload)
        accountMessage = ""
        isSavingAccount = true

        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                isSavingAccount = false
            }
            if let error = error {
                DispatchQueue.main.async {
                    accountMessage = "Ошибка: \(error.localizedDescription)"
                }
                return
            }
            guard
                let data = data,
                let response = try? JSONDecoder().decode(AccountResponse.self, from: data)
            else {
                DispatchQueue.main.async {
                    accountMessage = "Некорректный ответ сервера"
                }
                return
            }

            DispatchQueue.main.async {
                accountNameInput = ""
                accountInitialAmount = ""
                accountCurrencyInput = response.account.currency
                accountTypeSelection = .cash
                accountMessage = "Счёт добавлен"
                loadAccounts(userId: userId)
                transactionAccountId = response.account.id
            }
        }.resume()
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
        var queryItems = [
            URLQueryItem(name: "start_date", value: isoFormatter.string(from: start)),
            URLQueryItem(name: "end_date", value: isoFormatter.string(from: end))
        ]
        if let apiType = transactionFilterType.apiValue {
            queryItems.append(URLQueryItem(name: "type", value: apiType))
        }
        if !transactionFilterCategoryId.isEmpty {
            queryItems.append(URLQueryItem(name: "category_id", value: transactionFilterCategoryId))
        }
        if !transactionFilterAccountId.isEmpty {
            queryItems.append(URLQueryItem(name: "account_id", value: transactionFilterAccountId))
        }
        components.queryItems = queryItems

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
        guard !accounts.isEmpty else {
            transactionMessage = "Добавьте счёт"
            return
        }
        guard let account = accounts.first(where: { $0.id == transactionAccountId }) else {
            transactionMessage = "Выберите счёт"
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
            accountId: account.id,
            categoryId: categoryId,
            type: transactionType.rawValue,
            amountMinor: amount,
            currency: account.currency,
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
                if isTransactionWithinCurrentPeriod(transaction) && matchesCurrentTransactionFilters(transaction) {
                    transactions.append(transaction)
                    transactions.sort { $0.occurredAt > $1.occurredAt }
                }
                transactionAmount = ""
                transactionComment = ""
                transactionMessage = "Операция сохранена"
                loadAccounts(userId: user.id)
            }
        }.resume()
    }

    private func isTransactionWithinCurrentPeriod(_ transaction: Transaction) -> Bool {
        let start = startOfDayUTC(transactionPeriodStart)
        let end = endOfDayUTC(transactionPeriodEnd)
        return transaction.occurredAt >= start && transaction.occurredAt <= end
    }

    private func matchesCurrentTransactionFilters(_ transaction: Transaction) -> Bool {
        if let kind = transactionFilterType.kind, transaction.type != kind {
            return false
        }
        if !transactionFilterCategoryId.isEmpty, transaction.categoryId != transactionFilterCategoryId {
            return false
        }
        if !transactionFilterAccountId.isEmpty, transaction.accountId != transactionFilterAccountId {
            return false
        }
        return true
    }

    private func ensureTransactionCategorySelection() {
        let activeIds = activeCategories.map(\.id)
        if !transactionCategoryId.isEmpty, activeIds.contains(transactionCategoryId) {
            return
        }
        transactionCategoryId = activeIds.first ?? ""
        if !transactionFilterCategoryId.isEmpty, !categories.contains(where: { $0.id == transactionFilterCategoryId }) {
            transactionFilterCategoryId = ""
        }
    }

    private func ensureTransactionAccountSelection() {
        if !transactionAccountId.isEmpty, accounts.contains(where: { $0.id == transactionAccountId }) {
            return
        }
        transactionAccountId = accounts.first?.id ?? ""
        if !transactionFilterAccountId.isEmpty, !accounts.contains(where: { $0.id == transactionFilterAccountId }) {
            transactionFilterAccountId = ""
        }
    }

    @ViewBuilder
    private func accountsSection(userId: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Счета и кошельки")
                .font(.headline)
            if accounts.isEmpty {
                Text("Создайте первый счёт, чтобы учитывать наличные, карты и вклады.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                ForEach(accounts) { account in
                    Button(action: {
                        transactionAccountId = account.id
                    }) {
                        accountRow(account: account)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            Text("Новый счёт")
                .font(.subheadline)

            TextField("Название", text: $accountNameInput)
                .textFieldStyle(.roundedBorder)

            Picker("Тип", selection: $accountTypeSelection) {
                ForEach(AccountKind.allCases, id: \.self) { kind in
                    Text(kind.localizedTitle).tag(kind)
                }
            }

            TextField("Валюта", text: $accountCurrencyInput)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.characters)

            TextField("Начальный баланс (в минорных единицах)", text: $accountInitialAmount)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numberPad)

            Button(action: { saveAccount(for: userId) }) {
                if isSavingAccount {
                    ProgressView()
                }
                Text("Добавить счёт")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSavingAccount || accountNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if !accountMessage.isEmpty {
                Text(accountMessage)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
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
            Picker("Тип", selection: $transactionFilterType) {
                ForEach(TransactionTypeFilter.allCases) { filter in
                    Text(filter.localizedTitle).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            Picker("Категория", selection: $transactionFilterCategoryId) {
                Text("Все категории").tag("")
                ForEach(categories) { category in
                    let suffix = category.isArchived ? " · архив" : ""
                    Text("\(category.name)\(suffix)").tag(category.id)
                }
            }

            Picker("Счёт", selection: $transactionFilterAccountId) {
                Text("Все счета").tag("")
                ForEach(accounts) { account in
                    Text("\(account.name) · \(account.currency)").tag(account.id)
                }
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
            if accounts.isEmpty {
                Text("Добавьте счёт, чтобы фиксировать операции")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                Picker("Счёт", selection: $transactionAccountId) {
                    ForEach(accounts) { account in
                        Text("\(account.name) · \(account.currency)").tag(account.id)
                    }
                }
            }
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
            .disabled(isSavingTransaction || activeCategories.isEmpty || accounts.isEmpty)

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

    private func accountRow(account: Account) -> some View {
        let amount = Double(account.balanceMinor) / 100.0
        let formatted = String(format: "%.2f %@", abs(amount), account.currency)
        let isSelected = account.id == transactionAccountId

        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(account.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(account.localizedType)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                if isSelected {
                    Label("Используется для операций", systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundColor(.blue)
                }
            }
            Spacer()
            Text("\(amount >= 0 ? "+" : "-")\(formatted)")
                .fontWeight(.semibold)
                .foregroundColor(amount >= 0 ? .green : .red)
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(10)
    }

    private func transactionRow(transaction: Transaction) -> some View {
        let categoryName = categories.first(where: { $0.id == transaction.categoryId })?.name ?? "Категория"
        let accountName = accounts.first(where: { $0.id == transaction.accountId })?.name ?? "Счёт"
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
            Text("Счёт: \(accountName)")
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
    let accounts: [Account]
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

private struct AccountList: Codable {
    let accounts: [Account]
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

private struct Account: Codable, Identifiable {
    let id: String
    let familyId: String
    let name: String
    let type: String
    let currency: String
    let balanceMinor: Int64
    let isArchived: Bool
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case familyId = "family_id"
        case name
        case type
        case currency
        case balanceMinor = "balance_minor"
        case isArchived = "is_archived"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var localizedType: String {
        switch type {
        case "card": return "Карта"
        case "bank": return "Банковский счёт"
        case "deposit": return "Вклад"
        case "wallet": return "Электронный кошелёк"
        default: return "Наличные"
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

private struct AccountPayload: Codable {
    let name: String
    let type: String
    let currency: String?
    let initialBalanceMinor: Int64?

    enum CodingKeys: String, CodingKey {
        case name, type, currency
        case initialBalanceMinor = "initial_balance_minor"
    }
}

private struct CategoryResponse: Codable {
    let category: Category
}

private struct CategoryArchiveRequest: Codable {
    let archived: Bool
}

private struct AccountResponse: Codable {
    let account: Account
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

private enum AccountKind: String, CaseIterable {
    case cash
    case card
    case bank
    case deposit
    case wallet

    var localizedTitle: String {
        switch self {
        case .cash: return "Наличные"
        case .card: return "Карта"
        case .bank: return "Банковский счёт"
        case .deposit: return "Вклад"
        case .wallet: return "Электронный кошелёк"
        }
    }
}

private enum TransactionTypeFilter: String, CaseIterable, Identifiable {
    case all
    case income
    case expense

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .all: return "Все"
        case .income: return "Доходы"
        case .expense: return "Расходы"
        }
    }

    var apiValue: String? {
        switch self {
        case .all: return nil
        case .income: return "income"
        case .expense: return "expense"
        }
    }

    var kind: TransactionKind? {
        switch self {
        case .all: return nil
        case .income: return .income
        case .expense: return .expense
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
    let accountId: String
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
        case accountId = "account_id"
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
        accountId = try container.decode(String.self, forKey: .accountId)
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
    let accountId: String
    let categoryId: String
    let type: String
    let amountMinor: Int64
    let currency: String
    let comment: String?
    let occurredAt: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case accountId = "account_id"
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
