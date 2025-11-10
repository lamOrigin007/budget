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

private let dateOnlyFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
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
    @State private var familyIdInput = ""
    @State private var currency = "RUB"
    @State private var status = "Создайте владельца семьи"
    @State private var user: User? = nil
    @State private var family: Family? = nil
    @State private var categories: [Category] = []
    @State private var accounts: [Account] = []
    @State private var familyMembers: [FamilyMember] = []
    @State private var isMembersLoading = false
    @State private var membersMessage = ""
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
    @State private var accountShared = true
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
    @State private var transactionFilterUserId: String = ""
    @State private var plannedOperations: [PlannedOperation] = []
    @State private var completedPlannedOperations: [PlannedOperation] = []
    @State private var plannedType: TransactionKind = .expense
    @State private var plannedAccountId: String = ""
    @State private var plannedCategoryId: String = ""
    @State private var plannedTitle: String = ""
    @State private var plannedAmount: String = ""
    @State private var plannedDueDate: Date = Date()
    @State private var plannedComment: String = ""
    @State private var plannedRecurrence: PlannedRecurrence = .none
    @State private var plannedMessage: String = ""
    @State private var isPlannedLoading: Bool = false
    @State private var isSavingPlan: Bool = false
    @State private var completingPlanId: String? = nil
    @State private var reportsOverview: ReportsOverview? = nil
    @State private var reportsMessage: String = ""
    @State private var isReportsLoading: Bool = false
    @State private var settingsSummary: UserSettingsSummary? = nil
    @State private var isSettingsLoading = false
    @State private var isSettingsSaving = false
    @State private var settingsMessage: String = ""
    @State private var familyCurrencySetting: String = "RUB"
    @State private var userCurrencySetting: String = "RUB"
    @State private var localeSetting: String = "ru-RU"
    @State private var themeSetting: String = "system"
    @State private var densitySetting: String = "comfortable"
    @State private var showArchivedSetting: Bool = false
    @State private var showTotalsSetting: Bool = true
    @State private var supportedCurrencies: [String] = ["RUB", "USD", "EUR"]

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
            TextField("ID семьи (опционально)", text: $familyIdInput)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .textContentType(.oneTimeCode)
            Text("Оставьте поле пустым, чтобы создать новую семью", style: .footnote)
                .foregroundColor(.secondary)
            Text("После входа вы будете видеть только данные выбранной семьи", style: .footnote)
                .foregroundColor(.secondary)
            Button(action: register) {
                HStack {
                    if isLoading {
                        ProgressView()
                    }
                    Text("Создать или присоединиться")
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
                        if let family = family {
                            Text("Доступ ограничен семьёй \(family.name) (ID \(family.id))", style: .footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                    settingsSection(user: user)
                    membersSection(userId: user.id)
                    accountsSection(userId: user.id)
                    categoryForm(userId: user.id)
                    categoryLists(userId: user.id)
                    plannedOperationsSection(user: user)
                    Divider()
                    transactionFilters()
                    transactionForm(user: user)
                    transactionsHistory()
                    reportsSection()
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
        request.setValue(user.id, forHTTPHeaderField: "X-User-ID")
        request.setValue(userId, forHTTPHeaderField: "X-User-ID")

        let payload = RegisterRequest(
            email: email,
            password: password,
            name: name,
            locale: "ru-RU",
            currency: currency,
            familyName: familyName.isEmpty ? nil : familyName,
            familyId: familyIdInput.isEmpty ? nil : familyIdInput
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
                    categories = registerResponse.categories.sorted { lhs, rhs in
                        if lhs.isArchived == rhs.isArchived {
                            return lhs.name < rhs.name
                        }
                        return !lhs.isArchived && rhs.isArchived
                    }
                    ensureTransactionCategorySelection()
                    familyMembers = registerResponse.members.sorted { $0.name < $1.name }
                    membersMessage = ""
                    familyIdInput = ""
                    accountShared = true
                    plannedAccountId = registerResponse.accounts.first?.id ?? ""
                    plannedOperations = []
                    completedPlannedOperations = []
                    plannedMessage = ""
                    reportsOverview = nil
                    reportsMessage = ""
                    isReportsLoading = false
                    familyCurrencySetting = registerResponse.family.currencyBase
                    userCurrencySetting = registerResponse.user.currencyDefault
                    localeSetting = registerResponse.user.locale
                    themeSetting = registerResponse.user.displaySettings.theme
                    densitySetting = registerResponse.user.displaySettings.density
                    showArchivedSetting = registerResponse.user.displaySettings.showArchived
                    showTotalsSetting = registerResponse.user.displaySettings.showTotalsInFamilyCurrency
                    settingsMessage = ""
                    refreshTransactionsForCurrentPeriod()
                }

                loadCategories(userId: registerResponse.user.id)
                loadAccounts(userId: registerResponse.user.id)
                loadMembers(userId: registerResponse.user.id)
                loadPlannedOperations(for: registerResponse.user.id)
                loadReportsForCurrentPeriod()
                loadSettings(userId: registerResponse.user.id)
        }.resume()
    }

    private func loadCategories(userId: String) {
        guard let url = URL(string: "http://localhost:8080/api/v1/users/\(userId)/categories") else { return }
        var request = URLRequest(url: url)
        request.setValue(userId, forHTTPHeaderField: "X-User-ID")
        URLSession.shared.dataTask(with: request) { data, _, _ in
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
                if plannedCategoryId.isEmpty || !categories.contains(where: { $0.id == plannedCategoryId }) {
                    plannedCategoryId = categories.first { !$0.isArchived && $0.type == plannedType.rawValue }?.id ?? ""
                }
            }
        }.resume()
    }

    private func loadAccounts(userId: String) {
        guard let url = URL(string: "http://localhost:8080/api/v1/users/\(userId)/accounts") else { return }
        var request = URLRequest(url: url)
        request.setValue(userId, forHTTPHeaderField: "X-User-ID")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard
                let data = data,
                let response = try? JSONDecoder().decode(AccountList.self, from: data)
            else { return }
            DispatchQueue.main.async {
                accounts = response.accounts.sorted { $0.createdAt < $1.createdAt }
                ensureTransactionAccountSelection()
                if plannedAccountId.isEmpty || !accounts.contains(where: { $0.id == plannedAccountId }) {
                    plannedAccountId = accounts.first?.id ?? ""
                }
            }
        }.resume()
    }

    private func loadMembers(userId: String) {
        guard let url = URL(string: "http://localhost:8080/api/v1/users/\(userId)/members") else { return }
        DispatchQueue.main.async {
            isMembersLoading = true
            membersMessage = ""
        }
        var request = URLRequest(url: url)
        request.setValue(userId, forHTTPHeaderField: "X-User-ID")
        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                isMembersLoading = false
            }
            if let error = error {
                DispatchQueue.main.async {
                    membersMessage = "Не удалось загрузить участников: \(error.localizedDescription)"
                }
                return
            }
            guard
                let data = data,
                let response = try? JSONDecoder().decode(MemberList.self, from: data)
            else {
                DispatchQueue.main.async {
                    membersMessage = "Некорректный ответ сервера при загрузке участников"
                }
                return
            }
            DispatchQueue.main.async {
                familyMembers = response.members.sorted { $0.name < $1.name }
                if !transactionFilterUserId.isEmpty,
                   !familyMembers.contains(where: { $0.id == transactionFilterUserId }) {
                    transactionFilterUserId = ""
                    refreshTransactionsForCurrentPeriod()
                }
            }
        }.resume()
    }

    private func loadSettings(userId: String) {
        guard let url = URL(string: "http://localhost:8080/api/v1/users/\(userId)/settings") else { return }
        var request = URLRequest(url: url)
        request.setValue(userId, forHTTPHeaderField: "X-User-ID")
        DispatchQueue.main.async {
            isSettingsLoading = true
            settingsMessage = ""
        }
        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                isSettingsLoading = false
            }
            if let error = error {
                DispatchQueue.main.async {
                    settingsMessage = "Не удалось загрузить настройки: \(error.localizedDescription)"
                }
                return
            }
            guard let data = data,
                  let summary = try? JSONDecoder().decode(UserSettingsSummary.self, from: data) else {
                DispatchQueue.main.async {
                    settingsMessage = "Некорректный ответ сервера при загрузке настроек"
                }
                return
            }
            DispatchQueue.main.async {
                applySettingsSummary(summary, message: nil)
            }
        }.resume()
    }

    private func saveSettings(for user: User) {
        guard let url = URL(string: "http://localhost:8080/api/v1/users/\(user.id)/settings") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(user.id, forHTTPHeaderField: "X-User-ID")

        let payload = UpdateUserSettingsPayload(
            familyCurrency: user.role == "owner" ? familyCurrencySetting.uppercased() : nil,
            userCurrency: userCurrencySetting.uppercased(),
            locale: localeSetting,
            display: DisplaySettings(
                theme: themeSetting,
                density: densitySetting,
                showArchived: showArchivedSetting,
                showTotalsInFamilyCurrency: showTotalsSetting
            )
        )

        request.httpBody = try? JSONEncoder().encode(payload)

        DispatchQueue.main.async {
            isSettingsSaving = true
            settingsMessage = ""
        }

        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                isSettingsSaving = false
            }
            if let error = error {
                DispatchQueue.main.async {
                    settingsMessage = "Не удалось сохранить настройки: \(error.localizedDescription)"
                }
                return
            }
            guard let data = data,
                  let summary = try? JSONDecoder().decode(UserSettingsSummary.self, from: data) else {
                DispatchQueue.main.async {
                    settingsMessage = "Некорректный ответ сервера при сохранении настроек"
                }
                return
            }
            DispatchQueue.main.async {
                applySettingsSummary(summary, message: "Настройки обновлены")
            }
        }.resume()
    }

    private func applySettingsSummary(_ summary: UserSettingsSummary, message: String?) {
        settingsSummary = summary
        supportedCurrencies = summary.supportedCurrencies.map { $0.uppercased() }.sorted()
        familyCurrencySetting = summary.family.currencyBase.uppercased()
        userCurrencySetting = summary.user.currencyDefault.uppercased()
        localeSetting = summary.user.locale
        themeSetting = summary.user.display.theme
        densitySetting = summary.user.display.density
        showArchivedSetting = summary.user.display.showArchived
        showTotalsSetting = summary.user.display.showTotalsInFamilyCurrency

        categories = summary.categories.sorted { lhs, rhs in
            if lhs.isArchived == rhs.isArchived {
                return lhs.name < rhs.name
            }
            return !lhs.isArchived && rhs.isArchived
        }
        ensureTransactionCategorySelection()
        if plannedCategoryId.isEmpty || !summary.categories.contains(where: { $0.id == plannedCategoryId && !$0.isArchived && $0.type == plannedType.rawValue }) {
            plannedCategoryId = summary.categories.first { !$0.isArchived && $0.type == plannedType.rawValue }?.id ?? ""
        }

        accounts = summary.accounts.sorted { $0.createdAt < $1.createdAt }
        ensureTransactionAccountSelection()
        if plannedAccountId.isEmpty || !summary.accounts.contains(where: { $0.id == plannedAccountId }) {
            plannedAccountId = summary.accounts.first?.id ?? ""
        }

        accountCurrencyInput = summary.user.currencyDefault

        if let currentUser = user {
            user = User(
                id: currentUser.id,
                familyId: currentUser.familyId,
                email: currentUser.email,
                name: currentUser.name,
                role: currentUser.role,
                locale: summary.user.locale,
                currencyDefault: summary.user.currencyDefault,
                displaySettings: summary.user.display
            )
        } else {
            user = User(
                id: summary.user.id,
                familyId: summary.family.id,
                email: "",
                name: "",
                role: "",
                locale: summary.user.locale,
                currencyDefault: summary.user.currencyDefault,
                displaySettings: summary.user.display
            )
        }

        family = Family(id: summary.family.id, name: summary.family.name, currencyBase: summary.family.currencyBase)

        if let message = message {
            settingsMessage = message
        } else {
            settingsMessage = ""
        }
    }

    @ViewBuilder
    private func settingsSection(user: User) -> some View {
        let presets = Array(Set(supportedCurrencies.map { $0.uppercased() })).sorted()
        let familyCurrencyBinding = Binding(
            get: { familyCurrencySetting },
            set: { familyCurrencySetting = $0.uppercased() }
        )
        let userCurrencyBinding = Binding(
            get: { userCurrencySetting },
            set: { userCurrencySetting = $0.uppercased() }
        )

        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Настройки отображения")
                    .font(.headline)
                Spacer()
                if isSettingsSaving {
                    ProgressView()
                }
            }

            if isSettingsLoading {
                Text("Загрузка текущих параметров…")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            if !settingsMessage.isEmpty {
                Text(settingsMessage)
                    .font(.footnote)
                    .foregroundColor(settingsMessage.hasPrefix("Не удалось") ? .red : .secondary)
            }

            if user.role == "owner" {
                TextField("Базовая валюта семьи", text: familyCurrencyBinding)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isSettingsLoading || isSettingsSaving)
                    .textInputAutocapitalization(.characters)
                if !presets.isEmpty {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(presets, id: \.self) { code in
                            Button(code) {
                                familyCurrencySetting = code
                            }
                            .buttonStyle(.bordered)
                            .disabled(isSettingsLoading || isSettingsSaving)
                        }
                    }
                }
            }

            TextField("Валюта по умолчанию", text: userCurrencyBinding)
                .textFieldStyle(.roundedBorder)
                .disabled(isSettingsLoading || isSettingsSaving)
                .textInputAutocapitalization(.characters)

            TextField("Локаль", text: $localeSetting)
                .textFieldStyle(.roundedBorder)
                .disabled(isSettingsLoading || isSettingsSaving)

            VStack(alignment: .leading, spacing: 8) {
                Text("Тема")
                    .font(.subheadline)
                Picker("Тема", selection: $themeSetting) {
                    Text("Система").tag("system")
                    Text("Светлая").tag("light")
                    Text("Тёмная").tag("dark")
                }
                .pickerStyle(.segmented)
                .disabled(isSettingsLoading || isSettingsSaving)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Плотность")
                    .font(.subheadline)
                Picker("Плотность", selection: $densitySetting) {
                    Text("Комфортная").tag("comfortable")
                    Text("Компактная").tag("compact")
                }
                .pickerStyle(.segmented)
                .disabled(isSettingsLoading || isSettingsSaving)
            }

            Toggle("Показывать архивные категории", isOn: $showArchivedSetting)
                .disabled(isSettingsLoading || isSettingsSaving)
                .onChange(of: showArchivedSetting) { _ in
                    ensureTransactionCategorySelection()
                    ensureTransactionAccountSelection()
                }

            Toggle("Сводные суммы только в валюте семьи", isOn: $showTotalsSetting)
                .disabled(isSettingsLoading || isSettingsSaving)

            Button(action: { saveSettings(for: user) }) {
                Text(isSettingsSaving ? "Сохранение…" : "Сохранить настройки")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSettingsLoading || isSettingsSaving)
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }

    private func membersSection(userId: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Участники семьи")
                    .font(.headline)
                Spacer()
                Button("Обновить") {
                    loadMembers(userId: userId)
                }
                .buttonStyle(.bordered)
                .disabled(isMembersLoading)
            }
            if isMembersLoading {
                ProgressView()
            }
            if !membersMessage.isEmpty {
                Text(membersMessage)
                    .font(.footnote)
                    .foregroundColor(.red)
            }
            if !isMembersLoading && familyMembers.isEmpty && membersMessage.isEmpty {
                Text("Пригласите родственников, чтобы делиться общим бюджетом.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            ForEach(familyMembers) { member in
                VStack(alignment: .leading, spacing: 4) {
                    Text(member.name)
                        .fontWeight(.semibold)
                    Text(member.email)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Text("Роль: \(member.roleTitle)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
            }
        }
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
        request.setValue(userId, forHTTPHeaderField: "X-User-ID")

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
        request.setValue(userId, forHTTPHeaderField: "X-User-ID")
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
            initialBalanceMinor: initialValue != 0 ? initialValue : nil,
            shared: accountShared
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
                accountShared = true
                accountMessage = "Счёт добавлен"
                loadAccounts(userId: userId)
                transactionAccountId = response.account.id
                loadReportsForCurrentPeriod()
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
            reportsMessage = "Дата начала не может быть позже даты окончания"
            reportsOverview = nil
            return
        }

        transactionsError = ""
        isLoadingTransactions = true
        loadReportsForCurrentPeriod(using: (start, end))

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
        if !transactionFilterUserId.isEmpty {
            queryItems.append(URLQueryItem(name: "user_id", value: transactionFilterUserId))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            isLoadingTransactions = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue(user.id, forHTTPHeaderField: "X-User-ID")
        URLSession.shared.dataTask(with: request) { data, _, error in
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

    private func loadReportsForCurrentPeriod(using range: (start: Date, end: Date)? = nil) {
        guard let user = user else { return }
        let start: Date
        let end: Date
        if let range = range {
            start = range.start
            end = range.end
        } else {
            start = startOfDayUTC(transactionPeriodStart)
            end = endOfDayUTC(transactionPeriodEnd)
            guard start <= end else {
                reportsMessage = "Дата начала не может быть позже даты окончания"
                reportsOverview = nil
                return
            }
        }

        guard var components = URLComponents(string: "http://localhost:8080/api/v1/users/\(user.id)/reports/overview") else {
            return
        }
        components.queryItems = [
            URLQueryItem(name: "start_date", value: isoFormatter.string(from: start)),
            URLQueryItem(name: "end_date", value: isoFormatter.string(from: end))
        ]
        guard let url = components.url else { return }

        DispatchQueue.main.async {
            isReportsLoading = true
            reportsMessage = ""
        }

        var request = URLRequest(url: url)
        request.setValue(user.id, forHTTPHeaderField: "X-User-ID")
        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                isReportsLoading = false
            }
            if let error = error {
                DispatchQueue.main.async {
                    reportsMessage = "Не удалось загрузить отчёты: \(error.localizedDescription)"
                    reportsOverview = nil
                }
                return
            }
            guard let data = data,
                  let response = try? JSONDecoder().decode(ReportsOverviewResponse.self, from: data) else {
                DispatchQueue.main.async {
                    reportsMessage = "Некорректный ответ сервера при загрузке отчётов"
                    reportsOverview = nil
                }
                return
            }
            DispatchQueue.main.async {
                reportsOverview = response.reports
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
                loadReportsForCurrentPeriod()
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
        if !transactionFilterUserId.isEmpty, transaction.author.id != transactionFilterUserId {
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
        let preferredAccounts = showArchivedSetting ? accounts : accounts.filter { !$0.isArchived }
        if !transactionAccountId.isEmpty, let current = accounts.first(where: { $0.id == transactionAccountId }) {
            if showArchivedSetting || !current.isArchived {
                // keep current selection
            } else {
                transactionAccountId = preferredAccounts.first?.id ?? accounts.first?.id ?? ""
            }
        } else {
            transactionAccountId = preferredAccounts.first?.id ?? accounts.first?.id ?? ""
        }
        if !transactionFilterAccountId.isEmpty {
            if let filterAccount = accounts.first(where: { $0.id == transactionFilterAccountId }) {
                if !showArchivedSetting && filterAccount.isArchived {
                    transactionFilterAccountId = ""
                }
            } else {
                transactionFilterAccountId = ""
            }
        }
    }

    private func loadPlannedOperations(for userId: String) {
        guard let url = URL(string: "http://localhost:8080/api/v1/users/\(userId)/planned-operations") else { return }
        DispatchQueue.main.async {
            isPlannedLoading = true
            plannedMessage = ""
        }
        var request = URLRequest(url: url)
        request.setValue(userId, forHTTPHeaderField: "X-User-ID")
        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                isPlannedLoading = false
            }
            if let error = error {
                DispatchQueue.main.async {
                    plannedMessage = "Ошибка: \(error.localizedDescription)"
                }
                return
            }
            guard
                let data = data,
                let response = try? JSONDecoder().decode(PlannedOperationsResponse.self, from: data)
            else {
                DispatchQueue.main.async {
                    plannedMessage = "Не удалось загрузить планы"
                }
                return
            }
            DispatchQueue.main.async {
                plannedOperations = response.plannedOperations.sorted { $0.dueAt < $1.dueAt }
                completedPlannedOperations = response.completedOperations.sorted {
                    ($0.lastCompletedAt ?? $0.updatedAt) > ($1.lastCompletedAt ?? $1.updatedAt)
                }
            }
        }.resume()
    }

    private func savePlannedOperation(for user: User) {
        guard let account = accounts.first(where: { $0.id == plannedAccountId }) else {
            plannedMessage = "Выберите счёт"
            return
        }
        let categoryId = plannedCategoryId.isEmpty
            ? activeCategories.first(where: { $0.type == plannedType.rawValue })?.id
            : plannedCategoryId
        guard let category = activeCategories.first(where: { $0.id == categoryId }) else {
            plannedMessage = "Выберите категорию"
            return
        }
        let trimmedTitle = plannedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            plannedMessage = "Укажите название"
            return
        }
        guard let amount = Int64(plannedAmount) else {
            plannedMessage = "Сумма должна быть целым числом"
            return
        }
        let dueDate = utcCalendar.startOfDay(for: plannedDueDate)
        let payload = PlannedOperationPayload(
            accountId: account.id,
            categoryId: category.id,
            type: plannedType.rawValue,
            title: trimmedTitle,
            amountMinor: amount,
            currency: account.currency,
            comment: plannedComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : plannedComment,
            dueAt: isoFormatter.string(from: dueDate),
            recurrence: plannedRecurrence.apiValue
        )

        guard let url = URL(string: "http://localhost:8080/api/v1/users/\(user.id)/planned-operations") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(user.id, forHTTPHeaderField: "X-User-ID")
        request.httpBody = try? JSONEncoder().encode(payload)

        plannedMessage = ""
        isSavingPlan = true
        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                isSavingPlan = false
            }
            if let error = error {
                DispatchQueue.main.async {
                    plannedMessage = "Ошибка: \(error.localizedDescription)"
                }
                return
            }
            guard
                let data = data,
                let response = try? JSONDecoder().decode(PlannedOperationResponse.self, from: data)
            else {
                DispatchQueue.main.async {
                    plannedMessage = "Некорректный ответ сервера"
                }
                return
            }
            DispatchQueue.main.async {
                plannedOperations.append(response.plannedOperation)
                plannedOperations.sort { $0.dueAt < $1.dueAt }
                plannedTitle = ""
                plannedAmount = ""
                plannedComment = ""
                plannedDueDate = Date()
                plannedRecurrence = .none
                plannedMessage = "План сохранён"
            }
        }.resume()
    }

    private func completePlannedOperation(for user: User, plan: PlannedOperation) {
        guard let url = URL(string: "http://localhost:8080/api/v1/users/\(user.id)/planned-operations/\(plan.id)/complete") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(user.id, forHTTPHeaderField: "X-User-ID")

        completingPlanId = plan.id
        plannedMessage = ""
        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                completingPlanId = nil
            }
            if let error = error {
                DispatchQueue.main.async {
                    plannedMessage = "Ошибка: \(error.localizedDescription)"
                }
                return
            }
            guard
                let data = data,
                let response = try? JSONDecoder().decode(PlannedOperationCompleteResponse.self, from: data)
            else {
                DispatchQueue.main.async {
                    plannedMessage = "Некорректный ответ сервера"
                }
                return
            }
            DispatchQueue.main.async {
                let updated = response.plannedOperation
                plannedOperations.removeAll { $0.id == plan.id }
                if !updated.isCompleted {
                    plannedOperations.append(updated)
                    plannedOperations.sort { $0.dueAt < $1.dueAt }
                }
                completedPlannedOperations.removeAll { $0.id == plan.id }
                if updated.isCompleted {
                    completedPlannedOperations.append(updated)
                    completedPlannedOperations.sort { ($0.lastCompletedAt ?? $0.updatedAt) > ($1.lastCompletedAt ?? $1.updatedAt) }
                }
                plannedMessage = "Операция выполнена"
                loadAccounts(userId: user.id)
                refreshTransactionsForCurrentPeriod()
                loadReportsForCurrentPeriod()
            }
        }.resume()
    }

    @ViewBuilder
    private func plannedOperationsSection(user: User) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Запланированные операции")
                    .font(.headline)
                Spacer()
                Button("Обновить") {
                    loadPlannedOperations(for: user.id)
                }
                .buttonStyle(.bordered)
                .disabled(isPlannedLoading)
            }

            if isPlannedLoading {
                ProgressView("Загрузка планов…")
            }

            if accounts.isEmpty {
                Text("Создайте счёт, чтобы планировать будущие операции")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            let availableCategories = activeCategories.filter { $0.type == plannedType.rawValue }
            if availableCategories.isEmpty {
                Text("Добавьте активную категорию выбранного типа, чтобы создать план")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                Picker("Тип", selection: $plannedType) {
                    ForEach(TransactionKind.allCases, id: \.self) { kind in
                        Text(kind.localizedTitle).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: plannedType) { _ in
                    let refreshed = activeCategories.filter { $0.type == plannedType.rawValue }
                    if refreshed.first(where: { $0.id == plannedCategoryId }) == nil {
                        plannedCategoryId = refreshed.first?.id ?? ""
                    }
                }

                Picker("Счёт", selection: $plannedAccountId) {
                    ForEach(accounts) { account in
                        Text("\(account.name) · \(account.currency)").tag(account.id)
                    }
                }

                Picker("Категория", selection: $plannedCategoryId) {
                    ForEach(availableCategories) { category in
                        Text(category.name).tag(category.id)
                    }
                }

                TextField("Название", text: $plannedTitle)
                    .textFieldStyle(.roundedBorder)

                TextField("Сумма в минорных единицах", text: $plannedAmount)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)

                DatePicker(
                    "Дата выполнения",
                    selection: $plannedDueDate,
                    displayedComponents: .date
                )

                Picker("Повторение", selection: $plannedRecurrence) {
                    ForEach(PlannedRecurrence.allCases) { recurrence in
                        Text(recurrence.localizedTitle).tag(recurrence)
                    }
                }

                TextField("Комментарий", text: $plannedComment)
                    .textFieldStyle(.roundedBorder)

                Button(action: { savePlannedOperation(for: user) }) {
                    if isSavingPlan {
                        ProgressView()
                    }
                    Text("Сохранить план")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSavingPlan || accounts.isEmpty || availableCategories.isEmpty)
            }
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(12)

            if !plannedMessage.isEmpty {
                Text(plannedMessage)
                    .font(.footnote)
                    .foregroundColor(plannedMessage.lowercased().contains("ошибка") ? .red : .secondary)
            }

            if !plannedOperations.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Ближайшие операции")
                        .font(.subheadline)
                    ForEach(plannedOperations) { plan in
                        plannedOperationRow(user: user, plan: plan)
                    }
                }
            } else if !isPlannedLoading {
                Text("Нет запланированных операций")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            if !completedPlannedOperations.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Выполненные планы")
                        .font(.subheadline)
                    ForEach(completedPlannedOperations) { plan in
                        plannedOperationRow(user: user, plan: plan, isCompleted: true)
                    }
                }
            }
        }
        .onAppear {
            if activeCategories.first(where: { $0.id == plannedCategoryId && $0.type == plannedType.rawValue }) == nil {
                plannedCategoryId = activeCategories.first { $0.type == plannedType.rawValue }?.id ?? ""
            }
            if accounts.first(where: { $0.id == plannedAccountId }) == nil {
                plannedAccountId = accounts.first?.id ?? ""
            }
        }
    }

    private func plannedOperationRow(user: User, plan: PlannedOperation, isCompleted: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(plan.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text(formatPlanAmount(plan))
                    .font(.subheadline)
                    .foregroundColor(plan.type.tint)
            }

            Text("Счёт: \(accounts.first(where: { $0.id == plan.accountId })?.name ?? "Счёт не найден")")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("Категория: \(categories.first(where: { $0.id == plan.categoryId })?.name ?? "Категория")")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("Создатель: \(plan.creator.name) · \(plan.creator.roleTitle)")
                .font(.caption)
                .foregroundColor(.secondary)

            Text(isCompleted ? completionLabel(for: plan) : dueLabel(for: plan))
                .font(.caption)
                .foregroundColor(isCompleted ? .secondary : (plan.dueAt < Date() ? .red : .secondary))

            Text(plannedRecurrenceLabel(plan.recurrence))
                .font(.caption)
                .foregroundColor(.secondary)

            if let comment = plan.comment?.trimmingCharacters(in: .whitespacesAndNewlines), !comment.isEmpty {
                Text(comment)
                    .font(.footnote)
            }

            if !isCompleted {
                Button(action: { completePlannedOperation(for: user, plan: plan) }) {
                    if completingPlanId == plan.id {
                        ProgressView()
                    }
                    Text("Отметить выполненной")
                }
                .buttonStyle(.borderedProminent)
                .disabled(completingPlanId != nil)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }

    private func dueLabel(for plan: PlannedOperation) -> String {
        let dateText = dateOnlyFormatter.string(from: plan.dueAt)
        if plan.dueAt < Date() {
            return "Просрочено: \(dateText)"
        }
        return "К исполнению: \(dateText)"
    }

    private func completionLabel(for plan: PlannedOperation) -> String {
        guard let completed = plan.lastCompletedAt else {
            return "Отмечено выполненным"
        }
        let dateText = displayFormatter.string(from: completed)
        return "Выполнено: \(dateText)"
    }

    private func plannedRecurrenceLabel(_ recurrence: String?) -> String {
        guard let recurrence, !recurrence.isEmpty else {
            return "Не повторяется"
        }
        switch recurrence.lowercased() {
        case "weekly":
            return "Повторяется еженедельно"
        case "monthly":
            return "Повторяется ежемесячно"
        case "yearly":
            return "Повторяется ежегодно"
        default:
            return recurrence
        }
    }

    private func formatPlanAmount(_ plan: PlannedOperation) -> String {
        let amount = Double(plan.amountMinor) / 100.0
        return String(format: "%@%.2f %@", plan.type.symbol, abs(amount), plan.currency)
    }

    @ViewBuilder
    private func accountsSection(userId: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Счета и кошельки")
                .font(.headline)
            let visibleAccounts = showArchivedSetting ? accounts : accounts.filter { !$0.isArchived }
            if visibleAccounts.isEmpty {
                Text("Создайте первый счёт, чтобы учитывать наличные, карты и вклады.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                ForEach(visibleAccounts) { account in
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

            TextField("Валюта", text: Binding(
                get: { accountCurrencyInput },
                set: { accountCurrencyInput = $0.uppercased() }
            ))
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.characters)

            TextField("Начальный баланс (в минорных единицах)", text: $accountInitialAmount)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.numberPad)

            Toggle("Общий счёт семьи", isOn: $accountShared)
            Text("Снимите флажок, чтобы сделать счёт личным.")
                .font(.footnote)
                .foregroundColor(.secondary)

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
        let archived = showArchivedSetting ? archivedCategories : []
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
            Picker("Участник", selection: $transactionFilterUserId) {
                Text("Все участники").tag("")
                ForEach(familyMembers) { member in
                    Text("\(member.name) · \(member.roleTitle)").tag(member.id)
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
    private func reportsSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Отчёты за период")
                    .font(.headline)
                Spacer()
                Button("Обновить отчёты") {
                    loadReportsForCurrentPeriod()
                }
                .buttonStyle(.bordered)
                .disabled(isReportsLoading)
            }
            Text("Используется выбранный период фильтра операций.")
                .font(.footnote)
                .foregroundColor(.secondary)

            if isReportsLoading {
                ProgressView()
            }

            if !reportsMessage.isEmpty {
                Text(reportsMessage)
                    .font(.footnote)
                    .foregroundColor(reportsMessage.hasPrefix("Не удалось") || reportsMessage.hasPrefix("Дата") ? .red : .secondary)
            }

            if !isReportsLoading && reportsMessage.isEmpty {
                if let overview = reportsOverview {
                    VStack(alignment: .leading, spacing: 12) {
                        movementReportBlock(title: "Расходы по категориям", report: overview.expenses, amountColor: .red)
                        movementReportBlock(title: "Доходы", report: overview.incomes, amountColor: .green)
                        accountBalancesBlock(overview.accountBalances)
                    }
                } else {
                    Text("Добавьте операции, чтобы увидеть распределение доходов, расходов и баланс по счетам семьи.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }

    @ViewBuilder
    private func movementReportBlock(title: String, report: MovementReport, amountColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .fontWeight(.semibold)
            if let totals = formatTotals(report.totals) {
                Text("Итого: \(totals)")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            if report.byCategory.isEmpty {
                Text("Нет данных за выбранный период.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                ForEach(report.byCategory, id: \.identifier) { item in
                    HStack {
                        Text(item.categoryName)
                        Spacer()
                        Text(formatMoney(item.amountMinor, currency: item.currency))
                            .foregroundColor(amountColor)
                            .fontWeight(.semibold)
                    }
                    .font(.footnote)
                }
            }
        }
    }

    @ViewBuilder
    private func accountBalancesBlock(_ balances: [AccountBalanceReport]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Баланс по счетам")
                .fontWeight(.semibold)
            let totalsDict = balances.reduce(into: [String: Int64]()) { result, account in
                result[account.currency, default: 0] += account.balanceMinor
            }
            let totalsList = totalsDict.map { CurrencyAmount(currency: $0.key, amountMinor: $0.value) }
            if let totals = formatTotals(totalsList) {
                Text("Суммарно: \(totals)")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            if balances.isEmpty {
                Text("Добавьте счета, чтобы видеть остатки семьи.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                ForEach(balances, id: \.accountId) { account in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(account.accountName)
                            .fontWeight(.semibold)
                        Text("Тип: \(accountTypeLabel(account.accountType))")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        Text(account.isShared ? "Общий счёт семьи" : "Личный счёт")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        if account.isArchived {
                            Text("Счёт в архиве")
                                .font(.footnote)
                                .foregroundColor(.orange)
                        }
                        Text("Баланс: \(formatMoney(account.balanceMinor, currency: account.currency))")
                            .font(.footnote)
                            .fontWeight(.semibold)
                    }
                    .padding(8)
                    .background(Color.gray.opacity(0.12))
                    .cornerRadius(8)
                }
            }
        }
    }

    private func formatMoney(_ amountMinor: Int64, currency: String) -> String {
        let amount = Double(amountMinor) / 100.0
        return String(format: "%.2f %@", amount, currency)
    }

    private func formatTotals(_ totals: [CurrencyAmount]) -> String? {
        guard !totals.isEmpty else { return nil }
        let familyCurrency = familyCurrencySetting.isEmpty ? family?.currencyBase ?? "" : familyCurrencySetting
        let filtered: [CurrencyAmount]
        if showTotalsSetting, !familyCurrency.isEmpty {
            filtered = totals.filter { $0.currency.caseInsensitiveCompare(familyCurrency) == .orderedSame }
        } else {
            filtered = totals
        }
        guard !filtered.isEmpty else { return nil }
        return filtered
            .map { formatMoney($0.amountMinor, currency: $0.currency.uppercased()) }
            .joined(separator: " · ")
    }

    private func accountTypeLabel(_ type: String) -> String {
        if let kind = AccountKind(rawValue: type) {
            return kind.localizedTitle
        }
        return type
    }

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
                Text(account.isShared ? "Общий счёт семьи" : "Личный счёт")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                if account.isArchived {
                    Text("Счёт в архиве")
                        .font(.footnote)
                        .foregroundColor(.orange)
                }
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
            Text("Автор: \(transaction.author.name) · \(transaction.author.roleTitle)")
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

private struct ReportsOverviewResponse: Decodable {
    let reports: ReportsOverview
}

private struct ReportsOverview: Decodable {
    let period: ReportPeriod
    let expenses: MovementReport
    let incomes: MovementReport
    let accountBalances: [AccountBalanceReport]

    enum CodingKeys: String, CodingKey {
        case period
        case expenses
        case incomes
        case accountBalances = "account_balances"
    }
}

private struct ReportPeriod: Decodable {
    let startDate: Date?
    let endDate: Date?

    enum CodingKeys: String, CodingKey {
        case startDate = "start_date"
        case endDate = "end_date"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let rawStart = try container.decodeIfPresent(String.self, forKey: .startDate) {
            startDate = isoFormatter.date(from: rawStart)
        } else {
            startDate = nil
        }
        if let rawEnd = try container.decodeIfPresent(String.self, forKey: .endDate) {
            endDate = isoFormatter.date(from: rawEnd)
        } else {
            endDate = nil
        }
    }
}

private struct MovementReport: Decodable {
    let totals: [CurrencyAmount]
    let byCategory: [CategoryReportItem]

    enum CodingKeys: String, CodingKey {
        case totals
        case byCategory = "by_category"
    }
}

private struct CurrencyAmount: Decodable {
    let currency: String
    let amountMinor: Int64

    enum CodingKeys: String, CodingKey {
        case currency
        case amountMinor = "amount_minor"
    }
}

private struct CategoryReportItem: Decodable {
    let categoryId: String
    let categoryName: String
    let categoryColor: String
    let currency: String
    let amountMinor: Int64

    var identifier: String { "\(categoryId)-\(currency)" }

    enum CodingKeys: String, CodingKey {
        case categoryId = "category_id"
        case categoryName = "category_name"
        case categoryColor = "category_color"
        case currency
        case amountMinor = "amount_minor"
    }
}

private struct AccountBalanceReport: Decodable {
    let accountId: String
    let accountName: String
    let accountType: String
    let currency: String
    let balanceMinor: Int64
    let isShared: Bool
    let isArchived: Bool

    enum CodingKeys: String, CodingKey {
        case accountId = "account_id"
        case accountName = "account_name"
        case accountType = "account_type"
        case currency
        case balanceMinor = "balance_minor"
        case isShared = "is_shared"
        case isArchived = "is_archived"
    }
}

private struct RegisterRequest: Codable {
    let email: String
    let password: String
    let name: String
    let locale: String
    let currency: String
    let familyName: String?
    let familyId: String?

    enum CodingKeys: String, CodingKey {
        case email, password, name, locale, currency
        case familyName = "family_name"
        case familyId = "family_id"
    }
}

private struct RegisterResponse: Codable {
    let user: User
    let family: Family
    let accounts: [Account]
    let members: [FamilyMember]
    let categories: [Category]
}

private struct DisplaySettings: Codable {
    let theme: String
    let density: String
    let showArchived: Bool
    let showTotalsInFamilyCurrency: Bool

    enum CodingKeys: String, CodingKey {
        case theme
        case density
        case showArchived = "show_archived"
        case showTotalsInFamilyCurrency = "show_totals_in_family_currency"
    }
}

private struct User: Codable {
    let id: String
    let familyId: String
    let email: String
    let name: String
    let role: String
    let locale: String
    let currencyDefault: String
    let displaySettings: DisplaySettings

    enum CodingKeys: String, CodingKey {
        case id
        case familyId = "family_id"
        case email
        case name
        case role
        case locale
        case currencyDefault = "currency_default"
        case displaySettings = "display_settings"
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

private struct FamilySettings: Decodable {
    let id: String
    let name: String
    let currencyBase: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case currencyBase = "currency_base"
    }
}

private struct UserSettingsSummary: Decodable {
    let supportedCurrencies: [String]
    let family: FamilySettings
    let user: UserSettings
    let categories: [Category]
    let accounts: [Account]

    enum CodingKeys: String, CodingKey {
        case supportedCurrencies = "supported_currencies"
        case family
        case user
        case categories
        case accounts
    }
}

private struct UserSettings: Decodable {
    let id: String
    let locale: String
    let currencyDefault: String
    let display: DisplaySettings

    enum CodingKeys: String, CodingKey {
        case id
        case locale
        case currencyDefault = "currency_default"
        case display
    }
}

private struct UpdateUserSettingsPayload: Encodable {
    let familyCurrency: String?
    let userCurrency: String
    let locale: String
    let display: DisplaySettings

    enum CodingKeys: String, CodingKey {
        case familyCurrency = "family_currency"
        case userCurrency = "user_currency"
        case locale
        case display
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
    let isShared: Bool
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
        case isShared = "is_shared"
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
    let shared: Bool?

    enum CodingKeys: String, CodingKey {
        case name, type, currency, shared
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

private struct MemberList: Codable {
    let members: [FamilyMember]
}

private struct FamilyMember: Codable, Identifiable {
    let id: String
    let name: String
    let email: String
    let role: String

    var roleTitle: String {
        switch role {
        case "owner": return "Владелец"
        case "adult": return "Участник"
        case "junior": return "Гость"
        default: return role
        }
    }
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

private enum PlannedRecurrence: String, CaseIterable, Identifiable {
    case none
    case weekly
    case monthly
    case yearly

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .none: return "Не повторяется"
        case .weekly: return "Еженедельно"
        case .monthly: return "Ежемесячно"
        case .yearly: return "Ежегодно"
        }
    }

    var apiValue: String? {
        switch self {
        case .none: return nil
        case .weekly, .monthly, .yearly: return rawValue
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
    let author: FamilyMember

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
        case author
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
        author = try container.decode(FamilyMember.self, forKey: .author)

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

private struct PlannedOperation: Decodable, Identifiable {
    let id: String
    let familyId: String
    let userId: String
    let accountId: String
    let categoryId: String
    let type: TransactionKind
    let title: String
    let amountMinor: Int64
    let currency: String
    let comment: String?
    let dueAt: Date
    let recurrence: String?
    let isCompleted: Bool
    let lastCompletedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let creator: FamilyMember

    enum CodingKeys: String, CodingKey {
        case id
        case familyId = "family_id"
        case userId = "user_id"
        case accountId = "account_id"
        case categoryId = "category_id"
        case type
        case title
        case amountMinor = "amount_minor"
        case currency
        case comment
        case dueAt = "due_at"
        case recurrence
        case isCompleted = "is_completed"
        case lastCompletedAt = "last_completed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case creator
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        familyId = try container.decode(String.self, forKey: .familyId)
        userId = try container.decode(String.self, forKey: .userId)
        accountId = try container.decode(String.self, forKey: .accountId)
        categoryId = try container.decode(String.self, forKey: .categoryId)
        type = try container.decode(TransactionKind.self, forKey: .type)
        title = try container.decode(String.self, forKey: .title)
        amountMinor = try container.decode(Int64.self, forKey: .amountMinor)
        currency = try container.decode(String.self, forKey: .currency)
        comment = try container.decodeIfPresent(String.self, forKey: .comment)
        recurrence = try container.decodeIfPresent(String.self, forKey: .recurrence)
        isCompleted = try container.decode(Bool.self, forKey: .isCompleted)
        creator = try container.decode(FamilyMember.self, forKey: .creator)

        func decodeDate(_ key: CodingKeys) throws -> Date {
            let value = try container.decode(String.self, forKey: key)
            if let date = isoFormatter.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Некорректный формат даты")
        }

        dueAt = try decodeDate(.dueAt)
        createdAt = try decodeDate(.createdAt)
        updatedAt = try decodeDate(.updatedAt)

        if let rawCompleted = try container.decodeIfPresent(String.self, forKey: .lastCompletedAt) {
            lastCompletedAt = isoFormatter.date(from: rawCompleted)
        } else {
            lastCompletedAt = nil
        }
    }
}

private struct PlannedOperationPayload: Encodable {
    let accountId: String
    let categoryId: String
    let type: String
    let title: String
    let amountMinor: Int64
    let currency: String
    let comment: String?
    let dueAt: String
    let recurrence: String?

    enum CodingKeys: String, CodingKey {
        case accountId = "account_id"
        case categoryId = "category_id"
        case type
        case title
        case amountMinor = "amount_minor"
        case currency
        case comment
        case dueAt = "due_at"
        case recurrence
    }
}

private struct PlannedOperationsResponse: Decodable {
    let plannedOperations: [PlannedOperation]
    let completedOperations: [PlannedOperation]

    enum CodingKeys: String, CodingKey {
        case plannedOperations = "planned_operations"
        case completedOperations = "completed_operations"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        plannedOperations = try container.decodeIfPresent([PlannedOperation].self, forKey: .plannedOperations) ?? []
        completedOperations = try container.decodeIfPresent([PlannedOperation].self, forKey: .completedOperations) ?? []
    }
}

private struct PlannedOperationResponse: Decodable {
    let plannedOperation: PlannedOperation

    enum CodingKeys: String, CodingKey {
        case plannedOperation = "planned_operation"
    }
}

private struct PlannedOperationCompleteResponse: Decodable {
    let plannedOperation: PlannedOperation
    let transaction: Transaction?

    enum CodingKeys: String, CodingKey {
        case plannedOperation = "planned_operation"
        case transaction
    }
}
