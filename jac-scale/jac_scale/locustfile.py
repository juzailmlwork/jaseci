from locust import HttpUser, task, between
import uuid


class UserAuthLoadTest(HttpUser):
    wait_time = between(1, 3)

    def on_start(self):
        self.username = f"user_{uuid.uuid4().hex}"
        self.password = "Test@12345"

        self.client.post(
            "/user/register",
            json={
                "username": self.username,
                "password": self.password
            },
            name="/user/register"
        )

        self.client.post(
            "/user/login",
            json={
                "username": self.username,
                "password": self.password
            },
            name="/user/login"
        )

    # 🔁 Frontend page load (random like walkers)
    @task(1)
    def load_frontend(self):
        with self.client.get(
            "/",
            name="Frontend Load",
            catch_response=True
        ) as response:
            if response.status_code != 200:
                response.failure(f"Frontend down ({response.status_code})")
            elif "text/html" not in response.headers.get("Content-Type", ""):
                response.failure("Frontend did not return HTML")
            else:
                response.success()

    # 🔐 Login happens more frequently
    @task(2)
    def login_user(self):
        self.client.post(
            "/user/login",
            json={
                "username": self.username,
                "password": self.password
            },
            name="/user/login"
        )

    # 📝 Normal app action
    @task(2)
    def create_todo(self):
        self.client.post(
            "/walker/create_todo",
            json={
                "text": "my name is Jusail"
            },
            name="/walker/create_todo"
        )
