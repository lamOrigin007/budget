package com.example.familybudget

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.Divider
import androidx.compose.material3.Checkbox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.request.get
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.serialization.kotlinx.json.json
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Locale

class MainActivity : ComponentActivity() {
    private val client = HttpClient(OkHttp) {
        install(ContentNegotiation) {
            json()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                    BudgetScreen(client)
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BudgetScreen(client: HttpClient) {
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var name by remember { mutableStateOf("") }
    var familyName by remember { mutableStateOf("") }
    var familyId by remember { mutableStateOf("") }
    var currency by remember { mutableStateOf("RUB") }
    var status by remember { mutableStateOf("Создайте владельца семьи") }
    var user by remember { mutableStateOf<User?>(null) }
    var family by remember { mutableStateOf<Family?>(null) }
    var categories by remember { mutableStateOf(listOf<Category>()) }
    var accounts by remember { mutableStateOf(listOf<Account>()) }
    var familyMembers by remember { mutableStateOf(listOf<FamilyMember>()) }
    var membersMessage by remember { mutableStateOf("") }
    var isMembersLoading by remember { mutableStateOf(false) }
    var categoryName by remember { mutableStateOf("") }
    var categoryType by remember { mutableStateOf("expense") }
    var categoryColor by remember { mutableStateOf("#0EA5E9") }
    var categoryDescription by remember { mutableStateOf("") }
    var categoryParentId by remember { mutableStateOf<String?>(null) }
    var editingCategoryId by remember { mutableStateOf<String?>(null) }
    var categoryMessage by remember { mutableStateOf("") }
    var isCategoryLoading by remember { mutableStateOf(false) }
    var accountName by remember { mutableStateOf("") }
    var accountType by remember { mutableStateOf("cash") }
    var accountCurrency by remember { mutableStateOf("") }
    var accountInitial by remember { mutableStateOf("") }
    var accountShared by remember { mutableStateOf(true) }
    var accountMessage by remember { mutableStateOf("") }
    var isAccountLoading by remember { mutableStateOf(false) }
    var transactions by remember { mutableStateOf(listOf<Transaction>()) }
    var transactionsMessage by remember { mutableStateOf("") }
    var isTransactionsLoading by remember { mutableStateOf(false) }
    var transactionMemberFilter by remember { mutableStateOf<String?>(null) }
    var plannedOperations by remember { mutableStateOf(listOf<PlannedOperation>()) }
    var completedPlannedOperations by remember { mutableStateOf(listOf<PlannedOperation>()) }
    var plannedMessage by remember { mutableStateOf("") }
    var isPlannedLoading by remember { mutableStateOf(false) }
    var isPlannedSaving by remember { mutableStateOf(false) }
    var completingPlanId by remember { mutableStateOf<String?>(null) }
    var plannedType by remember { mutableStateOf("expense") }
    var plannedAccountId by remember { mutableStateOf<String?>(null) }
    var plannedCategoryId by remember { mutableStateOf<String?>(null) }
    var plannedTitle by remember { mutableStateOf("") }
    var plannedAmount by remember { mutableStateOf("") }
    var plannedDue by remember { mutableStateOf(java.time.LocalDate.now().toString()) }
    var plannedComment by remember { mutableStateOf("") }
    var plannedRecurrence by remember { mutableStateOf("") }

    fun register() {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val response: RegisterResponse = client.post("http://10.0.2.2:8080/api/v1/users") {
                    setBody(
                        RegisterRequest(
                            email = email,
                            password = password,
                            name = name,
                            locale = "ru-RU",
                            currency = currency,
                            familyName = familyName,
                            familyId = familyId.ifBlank { null }
                        )
                    )
                }.body()
                withContext(Dispatchers.Main) {
                    user = response.user
                    family = response.family
                    status = "Профиль создан для ${'$'}{response.user.name}"
                    accounts = response.accounts
                    plannedAccountId = response.accounts.firstOrNull()?.id
                    accountCurrency = response.user.currencyDefault
                    familyMembers = response.members
                    membersMessage = ""
                    familyId = ""
                    transactionMemberFilter = null
                    accountShared = true
                }
                loadCategories(response.user.id)
                loadAccounts(response.user.id)
                loadMembers(response.user.id)
                loadTransactions(response.user.id, null)
                loadPlannedOperations(response.user.id)
            } catch (ex: Exception) {
                withContext(Dispatchers.Main) {
                    status = "Ошибка: ${'$'}{ex.message}"
                }
            }
        }
    }

    fun loadCategories(userId: String) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val list: CategoryList = client.get("http://10.0.2.2:8080/api/v1/users/${'$'}userId/categories").body()
                withContext(Dispatchers.Main) {
                    categories = list.categories.sortedWith(compareBy({ it.isArchived }, { it.name }))
                    plannedCategoryId = categories.firstOrNull { !it.isArchived && it.type == plannedType }?.id
                }
            } catch (ex: Exception) {
                withContext(Dispatchers.Main) {
                    categoryMessage = "Не удалось загрузить категории: ${'$'}{ex.message}"
                }
            }
        }
    }

    fun loadAccounts(userId: String) {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val list: AccountList = client.get("http://10.0.2.2:8080/api/v1/users/${'$'}userId/accounts").body()
                withContext(Dispatchers.Main) {
                    accounts = list.accounts.sortedBy { it.name }
                    plannedAccountId = accounts.firstOrNull()?.id
                }
            } catch (ex: Exception) {
                withContext(Dispatchers.Main) {
                    accountMessage = "Не удалось загрузить счета: ${'$'}{ex.message}"
                }
            }
        }
    }

    fun loadMembers(userId: String) {
        CoroutineScope(Dispatchers.IO).launch {
            withContext(Dispatchers.Main) {
                isMembersLoading = true
                membersMessage = ""
            }
            try {
                val list: MemberList = client.get("http://10.0.2.2:8080/api/v1/users/${'$'}userId/members").body()
                withContext(Dispatchers.Main) {
                    familyMembers = list.members.sortedBy { it.name }
                    isMembersLoading = false
                    if (transactionMemberFilter != null && list.members.none { it.id == transactionMemberFilter }) {
                        transactionMemberFilter = null
                        user?.let { loadTransactions(it.id, null) }
                    }
                }
            } catch (ex: Exception) {
                withContext(Dispatchers.Main) {
                    membersMessage = "Не удалось загрузить участников: ${'$'}{ex.message}"
                    isMembersLoading = false
                }
            }
        }
    }

    fun loadTransactions(userId: String, memberId: String?) {
        CoroutineScope(Dispatchers.IO).launch {
            withContext(Dispatchers.Main) {
                isTransactionsLoading = true
                transactionsMessage = ""
            }
            try {
                val response: TransactionList = client.get("http://10.0.2.2:8080/api/v1/users/${'$'}userId/transactions") {
                    if (!memberId.isNullOrBlank()) {
                        url.parameters.append("user_id", memberId)
                    }
                }.body()
                withContext(Dispatchers.Main) {
                    transactions = response.transactions.sortedByDescending { it.occurredAt }
                    isTransactionsLoading = false
                    if (transactions.isEmpty()) {
                        transactionsMessage = "Нет операций в выбранном фильтре"
                    }
                }
            } catch (ex: Exception) {
                withContext(Dispatchers.Main) {
                    transactionsMessage = "Не удалось загрузить операции: ${'$'}{ex.message}"
                    isTransactionsLoading = false
                }
            }
        }
    }

    fun loadPlannedOperations(userId: String) {
        CoroutineScope(Dispatchers.IO).launch {
            withContext(Dispatchers.Main) {
                isPlannedLoading = true
                plannedMessage = ""
            }
            try {
                val response: PlannedOperationsList = client.get("http://10.0.2.2:8080/api/v1/users/${'$'}userId/planned-operations").body()
                withContext(Dispatchers.Main) {
                    plannedOperations = response.planned.sortedBy { it.dueAt }
                    completedPlannedOperations = response.completed.sortedByDescending { it.lastCompletedAt ?: it.updatedAt }
                    isPlannedLoading = false
                }
            } catch (ex: Exception) {
                withContext(Dispatchers.Main) {
                    plannedMessage = "Не удалось загрузить планы: ${'$'}{ex.message}"
                    isPlannedLoading = false
                }
            }
        }
    }

    fun savePlannedOperation() {
        val currentUser = user ?: return
        val accountId = plannedAccountId
        val categoryId = plannedCategoryId
        if (accountId.isNullOrBlank() || categoryId.isNullOrBlank()) {
            plannedMessage = "Выберите счёт и категорию"
            return
        }
        if (plannedTitle.isBlank()) {
            plannedMessage = "Укажите название операции"
            return
        }
        val amountMinor = plannedAmount.toLongOrNull()
        if (amountMinor == null || amountMinor <= 0) {
            plannedMessage = "Введите сумму в минорных единицах"
            return
        }
        val dueIso = try {
            LocalDate.parse(plannedDue.ifBlank { LocalDate.now().toString() })
                .atStartOfDay()
                .atOffset(ZoneOffset.UTC)
                .toString()
        } catch (ex: Exception) {
            plannedMessage = "Некорректная дата"
            return
        }
        val accountCurrency = accounts.find { it.id == accountId }?.currency ?: currentUser.currencyDefault
        val payload = PlannedOperationPayload(
            accountId = accountId,
            categoryId = categoryId,
            type = plannedType,
            title = plannedTitle.trim(),
            amountMinor = amountMinor,
            currency = accountCurrency,
            comment = plannedComment.trim().ifEmpty { null },
            dueAt = dueIso,
            recurrence = plannedRecurrence.trim().ifEmpty { null }
        )
        CoroutineScope(Dispatchers.IO).launch {
            withContext(Dispatchers.Main) {
                isPlannedSaving = true
                plannedMessage = ""
            }
            try {
                val response: PlannedOperationResponse = client.post("http://10.0.2.2:8080/api/v1/users/${'$'}{currentUser.id}/planned-operations") {
                    setBody(payload)
                }.body()
                withContext(Dispatchers.Main) {
                    val created = response.plannedOperation
                    plannedOperations = (plannedOperations + created).sortedBy { it.dueAt }
                    plannedTitle = ""
                    plannedAmount = ""
                    plannedComment = ""
                    plannedMessage = "План сохранён"
                    isPlannedSaving = false
                }
            } catch (ex: Exception) {
                withContext(Dispatchers.Main) {
                    plannedMessage = "Ошибка: ${'$'}{ex.message}"
                    isPlannedSaving = false
                }
            }
        }
    }

    fun completePlannedOperation(plan: PlannedOperation) {
        val currentUser = user ?: return
        CoroutineScope(Dispatchers.IO).launch {
            withContext(Dispatchers.Main) {
                completingPlanId = plan.id
                plannedMessage = ""
            }
            try {
                val response: PlannedOperationCompleteResponse = client.post(
                    "http://10.0.2.2:8080/api/v1/users/${'$'}{currentUser.id}/planned-operations/${'$'}{plan.id}/complete"
                ) {}.body()
                withContext(Dispatchers.Main) {
                    completingPlanId = null
                    val updated = response.plannedOperation
                    plannedOperations = (plannedOperations.filter { it.id != plan.id } + listOfNotNull(if (updated.isCompleted) null else updated)).sortedBy { it.dueAt }
                    completedPlannedOperations = (completedPlannedOperations.filter { it.id != plan.id } + if (updated.isCompleted) listOf(updated) else emptyList()).sortedByDescending { it.lastCompletedAt ?: it.updatedAt }
                    plannedMessage = "Операция выполнена"
                }
                loadTransactions(currentUser.id, transactionMemberFilter)
                loadAccounts(currentUser.id)
            } catch (ex: Exception) {
                withContext(Dispatchers.Main) {
                    completingPlanId = null
                    plannedMessage = "Не удалось завершить операцию: ${'$'}{ex.message}"
                }
            }
        }
    }

    fun resetCategoryForm() {
        categoryName = ""
        categoryType = "expense"
        categoryColor = "#0EA5E9"
        categoryDescription = ""
        categoryParentId = null
        editingCategoryId = null
    }

    fun saveCategory() {
        val currentUser = user ?: return
        if (categoryName.isBlank()) {
            categoryMessage = "Укажите название категории"
            return
        }
        CoroutineScope(Dispatchers.IO).launch {
            isCategoryLoading = true
            val payload = CategoryPayload(
                name = categoryName.trim(),
                type = categoryType,
                color = categoryColor.trim(),
                description = categoryDescription.trim().ifEmpty { null },
                parentId = categoryParentId
            )
            try {
                val response: CategoryResponse = if (editingCategoryId == null) {
                    client.post("http://10.0.2.2:8080/api/v1/users/${'$'}{currentUser.id}/categories") {
                        setBody(payload)
                    }.body()
                } else {
                    client.put("http://10.0.2.2:8080/api/v1/users/${'$'}{currentUser.id}/categories/${'$'}editingCategoryId") {
                        setBody(payload)
                    }.body()
                }
                withContext(Dispatchers.Main) {
                    val updated = response.category
                    categories = categories
                        .filter { it.id != updated.id }
                        .plus(updated)
                        .sortedWith(compareBy({ it.isArchived }, { it.name }))
                    categoryMessage = if (editingCategoryId == null) "Категория создана" else "Категория обновлена"
                    resetCategoryForm()
                }
            } catch (ex: Exception) {
                withContext(Dispatchers.Main) {
                    categoryMessage = "Ошибка: ${'$'}{ex.message}"
                }
            } finally {
                withContext(Dispatchers.Main) {
                    isCategoryLoading = false
                }
            }
        }
    }

    fun createAccount() {
        val currentUser = user ?: return
        if (accountName.isBlank()) {
            accountMessage = "Укажите название счёта"
            return
        }
        CoroutineScope(Dispatchers.IO).launch {
            isAccountLoading = true
            val initialMinor = accountInitial.toLongOrNull()
            val trimmedCurrency = accountCurrency.trim().uppercase()
            val payload = AccountPayload(
                name = accountName.trim(),
                type = accountType,
                currency = if (trimmedCurrency.isBlank()) null else trimmedCurrency,
                initialBalanceMinor = initialMinor,
                shared = accountShared
            )
            try {
                val response: AccountResponse = client.post("http://10.0.2.2:8080/api/v1/users/${'$'}{currentUser.id}/accounts") {
                    setBody(payload)
                }.body()
                withContext(Dispatchers.Main) {
                    accounts = accounts.plus(response.account).sortedBy { it.name }
                    accountName = ""
                    accountInitial = ""
                    accountCurrency = response.account.currency
                    accountType = "cash"
                    accountShared = true
                    accountMessage = "Счёт создан"
                }
                loadAccounts(currentUser.id)
            } catch (ex: Exception) {
                withContext(Dispatchers.Main) {
                    accountMessage = "Ошибка: ${'$'}{ex.message}"
                }
            } finally {
                withContext(Dispatchers.Main) {
                    isAccountLoading = false
                }
            }
        }
    }

    fun archiveCategory(category: Category, archived: Boolean) {
        val currentUser = user ?: return
        CoroutineScope(Dispatchers.IO).launch {
            isCategoryLoading = true
            try {
                val response: CategoryResponse = client.post("http://10.0.2.2:8080/api/v1/users/${'$'}{currentUser.id}/categories/${'$'}{category.id}/archive") {
                    setBody(CategoryArchiveRequest(archived = archived))
                }.body()
                withContext(Dispatchers.Main) {
                    val updated = response.category
                    categories = categories
                        .map { if (it.id == updated.id) updated else it }
                        .sortedWith(compareBy({ it.isArchived }, { it.name }))
                    categoryMessage = if (archived) "Категория отправлена в архив" else "Категория восстановлена"
                    if (editingCategoryId == category.id && archived) {
                        resetCategoryForm()
                    }
                }
            } catch (ex: Exception) {
                withContext(Dispatchers.Main) {
                    categoryMessage = "Ошибка: ${'$'}{ex.message}"
                }
            } finally {
                withContext(Dispatchers.Main) {
                    isCategoryLoading = false
                }
            }
        }
    }

    Surface(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Text(text = "Family Budget", style = MaterialTheme.typography.headlineMedium)
            Text(text = status, style = MaterialTheme.typography.bodyMedium)
            Card(modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    OutlinedTextField(
                        value = name,
                        onValueChange = { name = it },
                        label = { Text("Имя") },
                        modifier = Modifier.fillMaxWidth()
                    )
                    OutlinedTextField(
                        value = email,
                        onValueChange = { email = it },
                        label = { Text("Email") },
                        modifier = Modifier.fillMaxWidth()
                    )
                    OutlinedTextField(
                        value = password,
                        onValueChange = { password = it },
                        label = { Text("Пароль") },
                        visualTransformation = PasswordVisualTransformation(),
                        modifier = Modifier.fillMaxWidth(),
                        colors = TextFieldDefaults.outlinedTextFieldColors()
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                        OutlinedTextField(
                            value = currency,
                            onValueChange = { currency = it.uppercase() },
                            label = { Text("Валюта") },
                            modifier = Modifier.weight(1f)
                        )
                        OutlinedTextField(
                            value = familyName,
                            onValueChange = { familyName = it },
                            label = { Text("Семья") },
                            modifier = Modifier.weight(1f)
                        )
                    }
                    OutlinedTextField(
                        value = familyId,
                        onValueChange = { familyId = it },
                        label = { Text("ID семьи для подключения") },
                        placeholder = { Text("Оставьте пустым, чтобы создать новую") },
                        modifier = Modifier.fillMaxWidth()
                    )
                    Button(
                        onClick = { register() },
                        enabled = email.isNotBlank() && password.isNotBlank() && name.isNotBlank()
                    ) {
                        Text("Создать или присоединиться")
                    }
                }
            }
            if (user != null) {
                Spacer(modifier = Modifier.height(16.dp))
                MembersSection(
                    members = familyMembers,
                    message = membersMessage,
                    isLoading = isMembersLoading,
                    onRefresh = { loadMembers(user!!.id) }
                )
                Spacer(modifier = Modifier.height(16.dp))
                AccountsManager(
                    accounts = accounts,
                    accountName = accountName,
                    accountType = accountType,
                    accountCurrency = accountCurrency,
                    accountInitial = accountInitial,
                    accountShared = accountShared,
                    message = accountMessage,
                    isLoading = isAccountLoading,
                    onNameChange = { accountName = it },
                    onTypeChange = { accountType = it },
                    onCurrencyChange = { accountCurrency = it.uppercase() },
                    onInitialChange = { accountInitial = it },
                    onSharedChange = { accountShared = it },
                    onCreate = { createAccount() }
                )
                Spacer(modifier = Modifier.height(16.dp))
                PlannedOperationsSection(
                    plannedOperations = plannedOperations,
                    completedOperations = completedPlannedOperations,
                    accounts = accounts,
                    categories = categories,
                    plannedType = plannedType,
                    plannedAccountId = plannedAccountId,
                    plannedCategoryId = plannedCategoryId,
                    plannedTitle = plannedTitle,
                    plannedAmount = plannedAmount,
                    plannedDue = plannedDue,
                    plannedComment = plannedComment,
                    plannedRecurrence = plannedRecurrence,
                    message = plannedMessage,
                    isLoading = isPlannedLoading,
                    isSaving = isPlannedSaving,
                    completingPlanId = completingPlanId,
                    onTypeChange = { type ->
                        plannedType = type
                        plannedCategoryId = categories.firstOrNull { !it.isArchived && it.type == type }?.id
                    },
                    onAccountChange = { plannedAccountId = it },
                    onCategoryChange = { plannedCategoryId = it },
                    onTitleChange = { plannedTitle = it },
                    onAmountChange = { plannedAmount = it },
                    onDueChange = { plannedDue = it },
                    onCommentChange = { plannedComment = it },
                    onRecurrenceChange = { plannedRecurrence = it },
                    onSave = { savePlannedOperation() },
                    onComplete = { completePlannedOperation(it) }
                )
                Spacer(modifier = Modifier.height(16.dp))
                TransactionsSection(
                    transactions = transactions,
                    categories = categories,
                    accounts = accounts,
                    members = familyMembers,
                    selectedMember = transactionMemberFilter,
                    isLoading = isTransactionsLoading,
                    message = transactionsMessage,
                    onMemberSelected = { memberId ->
                        transactionMemberFilter = memberId
                        user?.let { loadTransactions(it.id, memberId) }
                    },
                    onRefresh = {
                        user?.let { loadTransactions(it.id, transactionMemberFilter) }
                    }
                )
                Spacer(modifier = Modifier.height(16.dp))
                CategoryManager(
                    categories = categories,
                    categoryName = categoryName,
                    categoryType = categoryType,
                    categoryColor = categoryColor,
                    categoryDescription = categoryDescription,
                    categoryParentId = categoryParentId,
                    editingCategoryId = editingCategoryId,
                    message = categoryMessage,
                    isLoading = isCategoryLoading,
                    onNameChange = { categoryName = it },
                    onTypeChange = { categoryType = it },
                    onColorChange = { categoryColor = it.uppercase() },
                    onDescriptionChange = { categoryDescription = it },
                    onParentChange = { categoryParentId = it },
                    onReset = { resetCategoryForm() },
                    onSubmit = { saveCategory() },
                    onEdit = { category ->
                        editingCategoryId = category.id
                        categoryName = category.name
                        categoryType = category.type
                        categoryColor = category.color
                        categoryDescription = category.description ?: ""
                        categoryParentId = category.parentId
                    },
                    onArchive = { category, archived -> archiveCategory(category, archived) }
                )
            }
            Spacer(modifier = Modifier.height(12.dp))
        }
    }
}

@Composable
private fun MembersSection(
    members: List<FamilyMember>,
    message: String,
    isLoading: Boolean,
    onRefresh: () -> Unit
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween, modifier = Modifier.fillMaxWidth()) {
                Text("Участники семьи", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                OutlinedButton(onClick = onRefresh, enabled = !isLoading) { Text("Обновить") }
            }
            if (isLoading) {
                Text("Загрузка участников...", style = MaterialTheme.typography.bodySmall)
            }
            if (message.isNotEmpty()) {
                Text(message, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
            }
            if (!isLoading && members.isEmpty() && message.isEmpty()) {
                Text("Пригласите родственников, чтобы вести общий бюджет.", style = MaterialTheme.typography.bodySmall)
            }
            members.forEach { member ->
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(member.name, fontWeight = FontWeight.SemiBold)
                        Text(member.email, style = MaterialTheme.typography.bodySmall)
                        Text("Роль: ${roleTitle(member.role)}", style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
        }
    }
}

@Composable
private fun TransactionsSection(
    transactions: List<Transaction>,
    categories: List<Category>,
    accounts: List<Account>,
    members: List<FamilyMember>,
    selectedMember: String?,
    isLoading: Boolean,
    message: String,
    onMemberSelected: (String?) -> Unit,
    onRefresh: () -> Unit
) {
    val categoriesMap = remember(categories) { categories.associateBy { it.id } }
    val accountsMap = remember(accounts) { accounts.associateBy { it.id } }

    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween, modifier = Modifier.fillMaxWidth()) {
                Text("Операции семьи", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                OutlinedButton(onClick = onRefresh, enabled = !isLoading) { Text("Обновить") }
            }
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (selectedMember == null) {
                    Button(onClick = { onMemberSelected(null) }) { Text("Все участники") }
                } else {
                    OutlinedButton(onClick = { onMemberSelected(null) }) { Text("Все участники") }
                }
                members.forEach { member ->
                    val isSelected = member.id == selectedMember
                    if (isSelected) {
                        Button(onClick = { onMemberSelected(member.id) }) { Text(member.name) }
                    } else {
                        OutlinedButton(onClick = { onMemberSelected(member.id) }) { Text(member.name) }
                    }
                }
            }
            if (isLoading) {
                Text("Загрузка операций...", style = MaterialTheme.typography.bodySmall)
            }
            if (message.isNotEmpty()) {
                val color = if (message.startsWith("Не удалось")) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.secondary
                Text(message, style = MaterialTheme.typography.bodySmall, color = color)
            }
            if (!isLoading && transactions.isEmpty() && message.isEmpty()) {
                Text("Добавьте первую операцию, чтобы увидеть историю.", style = MaterialTheme.typography.bodySmall)
            }
            LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                items(transactions) { transaction ->
                    val category = categoriesMap[transaction.categoryId]
                    val account = accountsMap[transaction.accountId]
                    val amount = transaction.amountMinor / 100.0
                    val amountColor = if (transaction.type == "income") MaterialTheme.colorScheme.tertiary else MaterialTheme.colorScheme.error
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(category?.name ?: "Категория", fontWeight = FontWeight.SemiBold)
                            Text("${formatDateTime(transaction.occurredAt)} · Счёт: ${account?.name ?: "неизвестно"}", style = MaterialTheme.typography.bodySmall)
                            Text("Автор: ${transaction.author.name} (${roleTitle(transaction.author.role)})", style = MaterialTheme.typography.bodySmall)
                            Text(
                                text = String.format("%s%.2f %s", if (transaction.type == "income") "+" else "-", amount, transaction.currency),
                                color = amountColor,
                                style = MaterialTheme.typography.bodyMedium,
                                fontWeight = FontWeight.SemiBold
                            )
                            transaction.comment?.takeIf { it.isNotBlank() }?.let {
                                Text(it, style = MaterialTheme.typography.bodySmall)
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun PlannedOperationsSection(
    plannedOperations: List<PlannedOperation>,
    completedOperations: List<PlannedOperation>,
    accounts: List<Account>,
    categories: List<Category>,
    plannedType: String,
    plannedAccountId: String?,
    plannedCategoryId: String?,
    plannedTitle: String,
    plannedAmount: String,
    plannedDue: String,
    plannedComment: String,
    plannedRecurrence: String,
    message: String,
    isLoading: Boolean,
    isSaving: Boolean,
    completingPlanId: String?,
    onTypeChange: (String) -> Unit,
    onAccountChange: (String) -> Unit,
    onCategoryChange: (String) -> Unit,
    onTitleChange: (String) -> Unit,
    onAmountChange: (String) -> Unit,
    onDueChange: (String) -> Unit,
    onCommentChange: (String) -> Unit,
    onRecurrenceChange: (String) -> Unit,
    onSave: () -> Unit,
    onComplete: (PlannedOperation) -> Unit
) {
    val accountLabel = accounts.find { it.id == plannedAccountId }?.let { "${it.name} · ${it.currency}" } ?: "Не выбран"
    val availableCategories = remember(categories, plannedType) {
        categories.filter { !it.isArchived && it.type == plannedType }
    }
    val categoryLabel = availableCategories.find { it.id == plannedCategoryId }?.name ?: "Не выбрана"
    var accountMenuExpanded by remember { mutableStateOf(false) }
    var categoryMenuExpanded by remember { mutableStateOf(false) }
    val canSave = plannedTitle.isNotBlank() && plannedAmount.isNotBlank() && plannedAccountId != null && plannedCategoryId != null

    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Планирование операций", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            Text(
                "Добавьте регулярные платежи и отмечайте их выполнение — операция попадёт в журнал автоматически.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.secondary
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf("expense" to "Расход", "income" to "Доход").forEach { (value, label) ->
                    OutlinedButton(onClick = { onTypeChange(value) }, enabled = plannedType != value) {
                        Text(label)
                    }
                }
            }
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Box {
                    OutlinedButton(onClick = { accountMenuExpanded = true }, enabled = accounts.isNotEmpty()) {
                        Text("Счёт: ${accountLabel}")
                    }
                    DropdownMenu(expanded = accountMenuExpanded, onDismissRequest = { accountMenuExpanded = false }) {
                        accounts.forEach { account ->
                            androidx.compose.material3.DropdownMenuItem(
                                text = { Text("${account.name} · ${account.currency}") },
                                onClick = {
                                    onAccountChange(account.id)
                                    accountMenuExpanded = false
                                }
                            )
                        }
                    }
                }
                Box {
                    OutlinedButton(onClick = { categoryMenuExpanded = true }, enabled = availableCategories.isNotEmpty()) {
                        Text("Категория: ${categoryLabel}")
                    }
                    DropdownMenu(expanded = categoryMenuExpanded, onDismissRequest = { categoryMenuExpanded = false }) {
                        availableCategories.forEach { category ->
                            androidx.compose.material3.DropdownMenuItem(
                                text = { Text(category.name) },
                                onClick = {
                                    onCategoryChange(category.id)
                                    categoryMenuExpanded = false
                                }
                            )
                        }
                    }
                }
                OutlinedTextField(
                    value = plannedTitle,
                    onValueChange = onTitleChange,
                    label = { Text("Название") },
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = plannedAmount,
                    onValueChange = onAmountChange,
                    label = { Text("Сумма (в копейках)") },
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = plannedDue,
                    onValueChange = onDueChange,
                    label = { Text("Дата исполнения (ГГГГ-ММ-ДД)") },
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    value = plannedComment,
                    onValueChange = onCommentChange,
                    label = { Text("Комментарий") },
                    modifier = Modifier.fillMaxWidth()
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf("" to "Один раз", "weekly" to "Еженедельно", "monthly" to "Ежемесячно", "yearly" to "Ежегодно").forEach { (value, label) ->
                        if (plannedRecurrence == value) {
                            Button(onClick = { onRecurrenceChange(value) }, enabled = false) { Text(label) }
                        } else {
                            OutlinedButton(onClick = { onRecurrenceChange(value) }) { Text(label) }
                        }
                    }
                }
                Button(onClick = onSave, enabled = canSave && !isSaving) {
                    Text(if (isSaving) "Сохранение..." else "Сохранить план")
                }
                if (message.isNotEmpty()) {
                    val color = if (message.startsWith("Ошибка") || message.startsWith("Не удалось")) {
                        MaterialTheme.colorScheme.error
                    } else {
                        MaterialTheme.colorScheme.secondary
                    }
                    Text(message, style = MaterialTheme.typography.bodySmall, color = color)
                }
                if (availableCategories.isEmpty()) {
                    Text(
                        "Добавьте категорию типа «${if (plannedType == "expense") "Расход" else "Доход"}», чтобы планировать операции.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.secondary
                    )
                }
            }
            Text("Ближайшие операции", style = MaterialTheme.typography.titleSmall)
            if (isLoading) {
                Text("Загрузка планов...", style = MaterialTheme.typography.bodySmall)
            } else if (plannedOperations.isEmpty()) {
                Text("Нет запланированных операций", style = MaterialTheme.typography.bodySmall)
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    plannedOperations.forEach { plan ->
                        Card(modifier = Modifier.fillMaxWidth()) {
                            Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                Text(plan.title, fontWeight = FontWeight.SemiBold)
                                Text(
                                    "Счёт: ${accounts.find { it.id == plan.accountId }?.name ?: "неизвестно"}",
                                    style = MaterialTheme.typography.bodySmall
                                )
                                Text(
                                    "Категория: ${categories.find { it.id == plan.categoryId }?.name ?: "неизвестно"}",
                                    style = MaterialTheme.typography.bodySmall
                                )
                                Text(
                                    "Сумма: " + String.format(Locale("ru"), "%.2f %s", plan.amountMinor / 100.0, plan.currency),
                                    style = MaterialTheme.typography.bodyMedium,
                                    fontWeight = FontWeight.SemiBold
                                )
                                Text("К оплате: ${formatPlanDate(plan.dueAt)}", style = MaterialTheme.typography.bodySmall)
                                Text("Повторение: ${formatRecurrenceLabel(plan.recurrence)}", style = MaterialTheme.typography.bodySmall)
                                plan.lastCompletedAt?.let {
                                    Text("Последнее выполнение: ${formatDateTime(it)}", style = MaterialTheme.typography.bodySmall)
                                }
                                Button(
                                    onClick = { onComplete(plan) },
                                    enabled = completingPlanId != plan.id,
                                    modifier = Modifier.align(Alignment.End)
                                ) {
                                    Text(if (completingPlanId == plan.id) "Отмечаем..." else "Отметить выполненной")
                                }
                            }
                        }
                    }
                }
            }
            Text("Завершённые операции", style = MaterialTheme.typography.titleSmall)
            if (isLoading) {
                Text("Загрузка...")
            } else if (completedOperations.isEmpty()) {
                Text("Пока нет завершённых планов", style = MaterialTheme.typography.bodySmall)
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    completedOperations.forEach { plan ->
                        Card(modifier = Modifier.fillMaxWidth()) {
                            Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                Text(plan.title, fontWeight = FontWeight.SemiBold)
                                Text(
                                    "Счёт: ${accounts.find { it.id == plan.accountId }?.name ?: "неизвестно"}",
                                    style = MaterialTheme.typography.bodySmall
                                )
                                Text(
                                    "Категория: ${categories.find { it.id == plan.categoryId }?.name ?: "неизвестно"}",
                                    style = MaterialTheme.typography.bodySmall
                                )
                                Text(
                                    "Сумма: " + String.format(Locale("ru"), "%.2f %s", plan.amountMinor / 100.0, plan.currency),
                                    style = MaterialTheme.typography.bodyMedium,
                                    fontWeight = FontWeight.SemiBold
                                )
                                plan.lastCompletedAt?.let {
                                    Text("Завершено: ${formatDateTime(it)}", style = MaterialTheme.typography.bodySmall)
                                }
                                Text("Повторение: ${formatRecurrenceLabel(plan.recurrence)}", style = MaterialTheme.typography.bodySmall)
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun CategoryManager(
    categories: List<Category>,
    categoryName: String,
    categoryType: String,
    categoryColor: String,
    categoryDescription: String,
    categoryParentId: String?,
    editingCategoryId: String?,
    message: String,
    isLoading: Boolean,
    onNameChange: (String) -> Unit,
    onTypeChange: (String) -> Unit,
    onColorChange: (String) -> Unit,
    onDescriptionChange: (String) -> Unit,
    onParentChange: (String?) -> Unit,
    onReset: () -> Unit,
    onSubmit: () -> Unit,
    onEdit: (Category) -> Unit,
    onArchive: (Category, Boolean) -> Unit
) {
    val active = categories.filter { !it.isArchived }
    val archived = categories.filter { it.isArchived }
    val parentLabel = active.firstOrNull { it.id == categoryParentId }?.name ?: "Без родителя"
    var parentMenuExpanded by remember { mutableStateOf(false) }

    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(
                text = if (editingCategoryId == null) "Новая категория" else "Редактирование категории",
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold
            )
            OutlinedTextField(
                value = categoryName,
                onValueChange = onNameChange,
                label = { Text("Название") },
                modifier = Modifier.fillMaxWidth()
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf("expense" to "Расход", "income" to "Доход", "transfer" to "Перевод").forEach { (value, label) ->
                    OutlinedButton(
                        onClick = { onTypeChange(value) },
                        enabled = categoryType != value
                    ) {
                        Text(label)
                    }
                }
            }
            OutlinedTextField(
                value = categoryColor,
                onValueChange = onColorChange,
                label = { Text("Цвет") },
                modifier = Modifier.fillMaxWidth()
            )
            OutlinedTextField(
                value = categoryDescription,
                onValueChange = onDescriptionChange,
                label = { Text("Описание") },
                modifier = Modifier.fillMaxWidth()
            )
            Box {
                OutlinedButton(onClick = { parentMenuExpanded = true }, enabled = active.isNotEmpty()) {
                    Text("Родительская категория: ${'$'}parentLabel")
                }
                androidx.compose.material3.DropdownMenu(
                    expanded = parentMenuExpanded,
                    onDismissRequest = { parentMenuExpanded = false }
                ) {
                    androidx.compose.material3.DropdownMenuItem(
                        text = { Text("Без родителя") },
                        onClick = {
                            onParentChange(null)
                            parentMenuExpanded = false
                        }
                    )
                    active.filter { it.id != editingCategoryId }.forEach { category ->
                        androidx.compose.material3.DropdownMenuItem(
                            text = { Text(category.name) },
                            onClick = {
                                onParentChange(category.id)
                                parentMenuExpanded = false
                            }
                        )
                    }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Button(onClick = onSubmit, enabled = !isLoading && categoryName.isNotBlank()) {
                    Text(if (editingCategoryId == null) "Создать" else "Сохранить")
                }
                if (editingCategoryId != null) {
                    OutlinedButton(onClick = onReset, enabled = !isLoading) {
                        Text("Отмена")
                    }
                }
            }
            if (message.isNotEmpty()) {
                Text(text = message, style = MaterialTheme.typography.bodySmall)
            }
            Spacer(modifier = Modifier.height(8.dp))
            if (active.isNotEmpty()) {
                Text("Активные категории", style = MaterialTheme.typography.titleSmall)
                LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(active) { category ->
                        CategoryRow(category = category, isLoading = isLoading, onEdit = onEdit, onArchive = onArchive, archived = false)
                    }
                }
            }
            if (archived.isNotEmpty()) {
                Text("Архив", style = MaterialTheme.typography.titleSmall)
                LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(archived) { category ->
                        CategoryRow(category = category, isLoading = isLoading, onEdit = onEdit, onArchive = onArchive, archived = true)
                    }
                }
            }
        }
    }
}

@Composable
private fun CategoryRow(
    category: Category,
    isLoading: Boolean,
    onEdit: (Category) -> Unit,
    onArchive: (Category, Boolean) -> Unit,
    archived: Boolean
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(text = category.name, fontWeight = FontWeight.SemiBold)
            Text(text = "Тип: " + when (category.type) {
                "income" -> "Доход"
                "transfer" -> "Перевод"
                else -> "Расход"
            })
            category.description?.let {
                if (it.isNotBlank()) {
                    Text(text = it, style = MaterialTheme.typography.bodySmall)
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                if (!archived) {
                    Button(onClick = { onEdit(category) }, enabled = !isLoading) {
                        Text("Изменить")
                    }
                }
                if (!category.isSystem) {
                    Button(
                        onClick = { onArchive(category, !archived) },
                        enabled = !isLoading
                    ) {
                        Text(if (archived) "Вернуть" else "Архивировать")
                    }
                }
            }
        }
    }
}

@Composable
private fun AccountsManager(
    accounts: List<Account>,
    accountName: String,
    accountType: String,
    accountCurrency: String,
    accountInitial: String,
    accountShared: Boolean,
    message: String,
    isLoading: Boolean,
    onNameChange: (String) -> Unit,
    onTypeChange: (String) -> Unit,
    onCurrencyChange: (String) -> Unit,
    onInitialChange: (String) -> Unit,
    onSharedChange: (Boolean) -> Unit,
    onCreate: () -> Unit
) {
    val typeOptions = listOf(
        "cash" to "Наличные",
        "card" to "Карта",
        "bank" to "Банковский счёт",
        "deposit" to "Вклад",
        "wallet" to "Электронный кошелёк"
    )

    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("Счета и кошельки", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
            if (accounts.isEmpty()) {
                Text(
                    text = "Создайте первый счёт, чтобы учитывать наличные, карты и вклады.",
                    style = MaterialTheme.typography.bodySmall
                )
            } else {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    accounts.forEach { account ->
                        AccountRow(account = account)
                    }
                }
            }

            Divider()
            Text("Новый счёт", style = MaterialTheme.typography.titleSmall)
            OutlinedTextField(
                value = accountName,
                onValueChange = onNameChange,
                label = { Text("Название") },
                modifier = Modifier.fillMaxWidth()
            )
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                typeOptions.forEach { (value, label) ->
                    OutlinedButton(onClick = { onTypeChange(value) }, enabled = accountType != value) {
                        Text(label)
                    }
                }
            }
            OutlinedTextField(
                value = accountCurrency,
                onValueChange = onCurrencyChange,
                label = { Text("Валюта") },
                modifier = Modifier.fillMaxWidth()
            )
            OutlinedTextField(
                value = accountInitial,
                onValueChange = onInitialChange,
                label = { Text("Начальный баланс (в минорных единицах)") },
                modifier = Modifier.fillMaxWidth(),
                keyboardOptions = androidx.compose.ui.text.input.KeyboardOptions(keyboardType = androidx.compose.ui.text.input.KeyboardType.Number)
            )
            Row(verticalAlignment = Alignment.CenterVertically) {
                Checkbox(checked = accountShared, onCheckedChange = onSharedChange)
                Column(modifier = Modifier.padding(start = 8.dp)) {
                    Text("Общий счёт семьи", style = MaterialTheme.typography.bodyMedium)
                    Text("Снимите флажок, чтобы сделать счёт личным.", style = MaterialTheme.typography.bodySmall)
                }
            }
            Button(onClick = onCreate, enabled = !isLoading && accountName.isNotBlank()) {
                Text("Создать счёт")
            }
            if (message.isNotEmpty()) {
                Text(text = message, style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}

@Composable
private fun AccountRow(account: Account) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(text = account.name, fontWeight = FontWeight.SemiBold)
            Text(
                text = "Тип: " + when (account.type) {
                    "card" -> "Карта"
                    "bank" -> "Банковский счёт"
                    "deposit" -> "Вклад"
                    "wallet" -> "Электронный кошелёк"
                    else -> "Наличные"
                },
                style = MaterialTheme.typography.bodySmall
            )
            val amount = account.balanceMinor / 100.0
            Text(
                text = String.format("Баланс: %.2f %s", amount, account.currency),
                style = MaterialTheme.typography.bodySmall
            )
            Text(
                text = if (account.isShared) "Общий счёт семьи" else "Личный счёт",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.secondary
            )
            if (account.isArchived) {
                Text("Счёт в архиве", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
            }
        }
    }
}

private fun roleTitle(role: String): String = when (role) {
    "owner" -> "Владелец"
    "adult" -> "Участник"
    "junior" -> "Гость"
    else -> role
}

private val transactionFormatter: DateTimeFormatter =
    DateTimeFormatter.ofPattern("dd MMM HH:mm").withLocale(Locale("ru")).withZone(ZoneId.systemDefault())

private fun formatDateTime(value: String): String = try {
    transactionFormatter.format(Instant.parse(value))
} catch (_: Exception) {
    value
}

private val plannedDateFormatter: DateTimeFormatter =
    DateTimeFormatter.ofPattern("dd MMM yyyy").withLocale(Locale("ru")).withZone(ZoneId.systemDefault())

private fun formatPlanDate(value: String): String = try {
    plannedDateFormatter.format(Instant.parse(value))
} catch (_: Exception) {
    value
}

private fun formatRecurrenceLabel(recurrence: String?): String = when (recurrence) {
    null, "", "none" -> "Единожды"
    "weekly" -> "Еженедельно"
    "monthly" -> "Ежемесячно"
    "yearly" -> "Ежегодно"
    else -> recurrence
}

@Serializable
private data class RegisterRequest(
    val email: String,
    val password: String,
    val name: String,
    val locale: String,
    val currency: String,
    @SerialName("family_name") val familyName: String?
)

@Serializable
private data class RegisterResponse(
    val user: User,
    val family: Family,
    val accounts: List<Account>
)

@Serializable
private data class User(
    val id: String,
    val name: String
)

@Serializable
private data class Family(
    val id: String,
    val name: String
)

@Serializable
private data class CategoryList(
    val categories: List<Category>
)

@Serializable
private data class Category(
    val id: String,
    @SerialName("family_id") val familyId: String,
    @SerialName("parent_id") val parentId: String? = null,
    val name: String,
    val type: String,
    val color: String,
    val description: String? = null,
    @SerialName("is_system") val isSystem: Boolean,
    @SerialName("is_archived") val isArchived: Boolean,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String
)

@Serializable
private data class CategoryPayload(
    val name: String,
    val type: String,
    val color: String,
    val description: String? = null,
    @SerialName("parent_id") val parentId: String? = null
)

@Serializable
private data class CategoryResponse(
    val category: Category
)

@Serializable
private data class CategoryArchiveRequest(
    val archived: Boolean
)

@Serializable
private data class AccountList(
    val accounts: List<Account>
)

@Serializable
private data class Account(
    val id: String,
    @SerialName("family_id") val familyId: String,
    val name: String,
    val type: String,
    val currency: String,
    @SerialName("balance_minor") val balanceMinor: Long,
    @SerialName("is_shared") val isShared: Boolean,
    @SerialName("is_archived") val isArchived: Boolean,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String
)

@Serializable
private data class AccountPayload(
    val name: String,
    val type: String,
    val currency: String? = null,
    @SerialName("initial_balance_minor") val initialBalanceMinor: Long? = null,
    val shared: Boolean? = null
)

@Serializable
private data class AccountResponse(
    val account: Account
)

@Serializable
private data class MemberList(
    val members: List<FamilyMember>
)

@Serializable
private data class FamilyMember(
    val id: String,
    val name: String,
    val email: String,
    val role: String
)

@Serializable
private data class TransactionList(
    val transactions: List<Transaction>
)

@Serializable
private data class Transaction(
    val id: String,
    @SerialName("family_id") val familyId: String,
    @SerialName("user_id") val userId: String,
    @SerialName("account_id") val accountId: String,
    @SerialName("category_id") val categoryId: String,
    val type: String,
    @SerialName("amount_minor") val amountMinor: Long,
    val currency: String,
    val comment: String? = null,
    @SerialName("occurred_at") val occurredAt: String,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    val author: FamilyMember
)

@Serializable
private data class PlannedOperationsList(
    @SerialName("planned_operations") val planned: List<PlannedOperation>,
    @SerialName("completed_operations") val completed: List<PlannedOperation>
)

@Serializable
private data class PlannedOperationResponse(
    @SerialName("planned_operation") val plannedOperation: PlannedOperation
)

@Serializable
private data class PlannedOperation(
    val id: String,
    @SerialName("family_id") val familyId: String,
    @SerialName("user_id") val userId: String,
    @SerialName("account_id") val accountId: String,
    @SerialName("category_id") val categoryId: String,
    val type: String,
    val title: String,
    @SerialName("amount_minor") val amountMinor: Long,
    val currency: String,
    val comment: String? = null,
    @SerialName("due_at") val dueAt: String,
    val recurrence: String? = null,
    @SerialName("is_completed") val isCompleted: Boolean,
    @SerialName("last_completed_at") val lastCompletedAt: String? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("updated_at") val updatedAt: String,
    val creator: FamilyMember
)

@Serializable
private data class PlannedOperationPayload(
    @SerialName("account_id") val accountId: String,
    @SerialName("category_id") val categoryId: String,
    val type: String,
    val title: String,
    @SerialName("amount_minor") val amountMinor: Long,
    val currency: String,
    val comment: String? = null,
    @SerialName("due_at") val dueAt: String,
    val recurrence: String? = null
)

@Serializable
private data class PlannedOperationCompleteResponse(
    @SerialName("planned_operation") val plannedOperation: PlannedOperation,
    val transaction: Transaction
)
