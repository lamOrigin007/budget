package com.example.familybudget

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
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
    var currency by remember { mutableStateOf("RUB") }
    var status by remember { mutableStateOf("Создайте владельца семьи") }
    var user by remember { mutableStateOf<User?>(null) }
    var family by remember { mutableStateOf<Family?>(null) }
    var categories by remember { mutableStateOf(listOf<Category>()) }
    var categoryName by remember { mutableStateOf("") }
    var categoryType by remember { mutableStateOf("expense") }
    var categoryColor by remember { mutableStateOf("#0EA5E9") }
    var categoryDescription by remember { mutableStateOf("") }
    var categoryParentId by remember { mutableStateOf<String?>(null) }
    var editingCategoryId by remember { mutableStateOf<String?>(null) }
    var categoryMessage by remember { mutableStateOf("") }
    var isCategoryLoading by remember { mutableStateOf(false) }

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
                            familyName = familyName
                        )
                    )
                }.body()
                withContext(Dispatchers.Main) {
                    user = response.user
                    family = response.family
                    status = "Профиль создан для ${'$'}{response.user.name}"
                }
                loadCategories(response.user.id)
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
                }
            } catch (ex: Exception) {
                withContext(Dispatchers.Main) {
                    categoryMessage = "Не удалось загрузить категории: ${'$'}{ex.message}"
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
                    Button(onClick = { register() }, enabled = email.isNotBlank() && password.isNotBlank() && name.isNotBlank()) {
                        Text("Создать семью")
                    }
                }
            }
            if (user != null) {
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
    val family: Family
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
