import tarfile
from pathlib import Path
from types import SimpleNamespace
from typing import Any
from unittest.mock import MagicMock

import pytest
from kubernetes.client.exceptions import ApiException
from pytest import MonkeyPatch

from jac_scale.kubernetes import utils
from jac_scale.kubernetes.utils import (
    check_deployment_status,
    create_tarball,
    delete_if_exists,
    ensure_pvc_exists,
    load_env_variables,
    parse_cpu_quantity,
    parse_memory_quantity,
    validate_resource_limits,
)


@pytest.mark.parametrize(
    "raw,expected",
    [
        ("500m", 0.5),
        ("2", 2.0),
        (" 250 ", 250.0),
    ],
)
def test_parse_cpu_quantity_valid(raw: str, expected: float) -> None:
    assert parse_cpu_quantity(raw) == pytest.approx(expected)


@pytest.mark.parametrize("raw", ["", "m", " m "])
def test_parse_cpu_quantity_invalid(raw: str) -> None:
    with pytest.raises(ValueError):
        parse_cpu_quantity(raw)


@pytest.mark.parametrize(
    "raw,expected",
    [
        ("256Mi", float(256 * 1024**2)),
        ("1Gi", float(1024**3)),
        ("2", 2.0),
    ],
)
def test_parse_memory_quantity_valid(raw: str, expected: float) -> None:
    assert parse_memory_quantity(raw) == pytest.approx(expected)


@pytest.mark.parametrize("raw", ["", "Mi", " Gi "])
def test_parse_memory_quantity_invalid(raw: str) -> None:
    with pytest.raises(ValueError):
        parse_memory_quantity(raw)


def test_load_env_variables_reads_env_file(tmp_path: Path) -> None:
    env_dir = tmp_path / "app"
    env_dir.mkdir()
    env_file = env_dir / ".env"
    env_file.write_text("FOO=1\nBAR=two\n")

    env_vars = load_env_variables(str(env_dir))

    assert {"name": "FOO", "value": "1"} in env_vars
    assert {"name": "BAR", "value": "two"} in env_vars


def test_ensure_pvc_exists_skips_when_present() -> None:
    core_v1 = MagicMock()
    core_v1.read_namespaced_persistent_volume_claim.return_value = object()

    ensure_pvc_exists(core_v1, "test-ns", "test-pvc", "5Gi")

    core_v1.create_namespaced_persistent_volume_claim.assert_not_called()


def test_ensure_pvc_exists_creates_when_missing() -> None:
    core_v1 = MagicMock()
    core_v1.read_namespaced_persistent_volume_claim.side_effect = ApiException(
        status=404
    )

    ensure_pvc_exists(
        core_v1,
        namespace="test-ns",
        pvc_name="test-pvc",
        storage_size="10Gi",
        storage_class="fast",
    )

    call_args = core_v1.create_namespaced_persistent_volume_claim.call_args
    assert call_args is not None
    args, kwargs = call_args
    assert kwargs == {}
    assert args[0] == "test-ns"
    body = args[1]
    assert body["metadata"]["name"] == "test-pvc"
    assert body["spec"]["accessModes"] == ["ReadWriteOnce"]
    assert body["spec"]["resources"]["requests"]["storage"] == "10Gi"
    assert body["spec"]["storageClassName"] == "fast"


def test_check_deployment_status_eventual_success(monkeypatch: MonkeyPatch) -> None:
    attempts: list[str] = []

    def fake_sleep(*args: Any, **kwargs: Any) -> None:
        return None

    def fake_get(url: str, timeout: int) -> SimpleNamespace:
        attempts.append(url)
        if len(attempts) < 3:
            raise RequestException("Service unavailable")
        return SimpleNamespace(status_code=200)

    monkeypatch.setattr(utils.time, "sleep", fake_sleep)
    monkeypatch.setattr(utils.requests, "get", fake_get)

    ok = check_deployment_status(
        node_port=30051,
        path="/health",
        initial_wait=0,
        interval=0,
        max_retries=5,
    )

    assert ok is True
    assert len(attempts) == 3


def test_check_deployment_status_eventual_failure(monkeypatch: MonkeyPatch) -> None:
    def fake_sleep(*args: Any, **kwargs: Any) -> None:
        return None

    def fake_get(url: str, timeout: int) -> SimpleNamespace:
        return SimpleNamespace(status_code=503)

    monkeypatch.setattr(utils.time, "sleep", fake_sleep)
    monkeypatch.setattr(utils.requests, "get", fake_get)

    ok = check_deployment_status(
        node_port=30051,
        path="/health",
        initial_wait=0,
        interval=0,
        max_retries=2,
    )

    assert ok is False


def test_delete_if_exists_handles_404() -> None:
    recorded: list[tuple[str, str]] = []

    def delete_func(name: str, namespace: str) -> None:
        recorded.append((name, namespace))
        raise ApiException(status=404)

    delete_if_exists(delete_func, "demo", "demo-ns", "Deployment")

    assert recorded == [("demo", "demo-ns")]


def test_delete_if_exists_raises_on_other_errors() -> None:
    def delete_func(name: str, namespace: str) -> None:
        raise ApiException(status=500)

    with pytest.raises(ApiException):
        delete_if_exists(delete_func, "demo", "demo-ns", "Deployment")


def test_validate_resource_limits_accepts_valid_pairs() -> None:
    validate_resource_limits("250m", "500m", "256Mi", "512Mi")


def test_validate_resource_limits_rejects_lower_limits() -> None:
    with pytest.raises(ValueError):
        validate_resource_limits("500m", "250m", None, None)


def test_validate_resource_limits_rejects_invalid_quantity() -> None:
    with pytest.raises(ValueError):
        validate_resource_limits("abc", "1", None, None)


def test_cluster_type_detects_aws_by_provider(monkeypatch: MonkeyPatch) -> None:
    class Node:
        def __init__(self, provider_id: str) -> None:
            self.spec = SimpleNamespace(provider_id=provider_id)
            self.metadata = SimpleNamespace(labels={})

    class Response:
        def __init__(self) -> None:
            self.items = [Node("aws://12345")]  # type: ignore[arg-type]

    class FakeApi:
        def list_node(self) -> Response:
            return Response()

    monkeypatch.setattr(utils.client, "CoreV1Api", lambda: FakeApi())

    assert utils.cluster_type() == "aws"


def test_cluster_type_returns_local_on_error(monkeypatch: MonkeyPatch) -> None:
    def failing_core_v1() -> None:
        raise RuntimeError("boom")

    monkeypatch.setattr(utils.client, "CoreV1Api", failing_core_v1)

    assert utils.cluster_type() == "local"


def test_create_tarball_captures_files(tmp_path: Path) -> None:
    source_dir = tmp_path / "src"
    source_dir.mkdir()
    file_path = source_dir / "hello.txt"
    file_path.write_text("hello")
    tar_path = tmp_path / "archive.tar.gz"

    create_tarball(str(source_dir), str(tar_path))

    assert tar_path.exists()
    with tarfile.open(tar_path, "r:gz") as tar:
        member_names = tar.getnames()
    assert "./hello.txt" in member_names


def test_create_tarball_missing_source(tmp_path: Path) -> None:
    tar_path = tmp_path / "archive.tar.gz"

    with pytest.raises(FileNotFoundError):
        create_tarball(str(tmp_path / "missing"), str(tar_path))
