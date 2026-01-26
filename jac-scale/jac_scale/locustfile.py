from locust import HttpUser, task, between
import uuid


class UserAuthLoadTest(HttpUser):
    wait_time = between(1, 3)

    def on_start(self):
        self.username = f"user_{uuid.uuid4().hex}"
        self.password = "Test@12345"

        # Register user once
        self.client.post(
            "/user/register",
            json={
                "username": self.username,
                "password": self.password
            },
            name="/user/register"
        )

        # Login once (if your backend sets session/cookies)
        self.client.post(
            "/user/login",
            json={
                "username": self.username,
                "password": self.password
            },
            name="/user/login"
        )

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

    @task(1)
    def create_todo(self):
        self.client.post(
            "/walker/create_todo",
            json={
                "text": "my name is Jusail"
            },
            name="/walker/create_todo"
        )
