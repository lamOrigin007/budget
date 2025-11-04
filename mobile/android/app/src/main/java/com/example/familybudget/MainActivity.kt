package com.example.familybudget

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
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
    var categories by remember { mutableStateOf(listOf<String>()) }

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
                val list: CategoryList = client.get("http://10.0.2.2:8080/api/v1/users/${'$'}{response.user.id}/categories").body()
                categories = list.categories.map { it.name }
                status = "Профиль создан для ${'$'}{response.user.name}"
            } catch (ex: Exception) {
                status = "Ошибка: ${'$'}{ex.message}"
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
            if (categories.isNotEmpty()) {
                Card(modifier = Modifier.fillMaxWidth()) {
                    Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text("Базовые категории:")
                        categories.forEach { category ->
                            Text("• ${'$'}category")
                        }
                    }
                }
            }
            Spacer(modifier = Modifier.height(12.dp))
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
    val name: String
)
