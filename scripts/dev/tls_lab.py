"""Manage the local Colima environment used to verify the PEM TLS RFC."""

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
STATE = ROOT / "build/tls-lab"
KUBECONFIG = STATE / "kubeconfig"
NAMESPACE = "datahub-tls"
CONTEXT = "colima"
CERT_MANAGER_VERSION = "v1.21.2"


def run(args: list[str], *, data: str | None = None, capture: bool = False) -> str:
    result = subprocess.run(
        args,
        input=data,
        text=True,
        check=True,
        stdout=subprocess.PIPE if capture else None,
    )
    return result.stdout or ""


def kube(*args: str, data: str | None = None, capture: bool = False) -> str:
    return run(
        [
            "kubectl",
            "--kubeconfig",
            str(KUBECONFIG),
            "--context",
            CONTEXT,
            "--namespace",
            NAMESPACE,
            *args,
        ],
        data=data,
        capture=capture,
    )


def helm(*args: str) -> None:
    run(["helm", "--kubeconfig", str(KUBECONFIG), "--kube-context", CONTEXT, *args])


def check_cluster() -> None:
    if not KUBECONFIG.exists():
        raise RuntimeError("Run 'scripts/dev/datahub-dev.sh tls cluster' first")
    config = json.loads(kube("config", "view", "--minify", "-o", "json", capture=True))
    server = config["clusters"][0]["cluster"]["server"]
    if not server.startswith(("https://127.0.0.1:", "https://localhost:")):
        raise RuntimeError(f"Refusing non-loopback Kubernetes endpoint: {server}")
    nodes = json.loads(kube("get", "nodes", "-o", "json", capture=True))
    if [node["metadata"]["name"] for node in nodes["items"]] != ["colima"]:
        raise RuntimeError("This lab requires the single local Colima node")


def cluster() -> None:
    STATE.mkdir(parents=True, exist_ok=True, mode=0o700)
    env = dict(os.environ, KUBECONFIG=str(KUBECONFIG))
    subprocess.run(
        ["colima", "--profile", "default", "kubernetes", "start"], env=env, check=True
    )
    KUBECONFIG.chmod(0o600)
    check_cluster()


def apply(obj: dict) -> None:
    kube("apply", "-f", "-", data=json.dumps(obj))


def credentials() -> dict[str, str]:
    path = STATE / "credentials.json"
    if path.exists():
        return json.loads(path.read_text())
    values = {
        key: secrets.token_hex(20)
        for key in (
            "KC_BOOTSTRAP_ADMIN_PASSWORD",
            "DATAHUB_SSO_CLIENT_SECRET",
            "DATAHUB_KAFKA_CLIENT_SECRET",
            "DATAHUB_TEST_PASSWORD",
            "MYSQL_ROOT_PASSWORD",
            "REDPANDA_PASSWORD",
        )
    }
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as stream:
        json.dump(values, stream)
    return values


def dependencies(charts: Path) -> None:
    check_cluster()
    namespace = kube(
        "get", "namespace", NAMESPACE, "--ignore-not-found", "-o", "json", capture=True
    )
    if (
        namespace
        and json.loads(namespace)["metadata"]
        .get("labels", {})
        .get("app.kubernetes.io/part-of")
        != "datahub-tls-lab"
    ):
        raise RuntimeError(
            f"Refusing to reuse namespace {NAMESPACE}: it is not owned by this lab"
        )
    apply(
        {
            "apiVersion": "v1",
            "kind": "Namespace",
            "metadata": {
                "name": NAMESPACE,
                "labels": {"app.kubernetes.io/part-of": "datahub-tls-lab"},
            },
        }
    )
    values = credentials()
    apply(
        {
            "apiVersion": "v1",
            "kind": "Secret",
            "metadata": {"name": "tls-lab-credentials"},
            "stringData": values,
        }
    )
    apply(
        {
            "apiVersion": "v1",
            "kind": "Secret",
            "metadata": {"name": "redpanda-users"},
            "stringData": {
                "users.txt": f"lab-admin:{values['REDPANDA_PASSWORD']}:SCRAM-SHA-512\n"
            },
        }
    )
    # cert-manager CRDs must exist before rendering the lab's Certificate resources.
    helm(
        "upgrade",
        "--install",
        "cert-manager",
        "cert-manager",
        "--repo",
        "https://charts.jetstack.io",
        "--version",
        CERT_MANAGER_VERSION,
        "--namespace",
        "cert-manager",
        "--create-namespace",
        "--set",
        "crds.enabled=true",
        "--wait",
        "--timeout",
        "5m",
    )
    lab = str(charts / "examples/tls-lab")
    run(["helm", "dependency", "build", "--skip-refresh", lab])
    if not kube(
        "get",
        "certificate",
        "keycloak-server",
        "--ignore-not-found",
        "-o",
        "name",
        capture=True,
    ):
        helm(
            "upgrade",
            "--install",
            "tls-lab",
            lab,
            "--namespace",
            NAMESPACE,
            "--reset-values",
            "--set",
            "redpandaEnabled=false",
            "--wait",
            "--timeout",
            "8m",
        )
        kube("wait", "--for=condition=Ready", "certificate", "--all", "--timeout=180s")
    helm(
        "upgrade",
        "--install",
        "tls-lab",
        lab,
        "--namespace",
        NAMESPACE,
        "--reset-values",
        "--set",
        "redpandaEnabled=true",
        "--wait",
        "--timeout",
        "8m",
    )
    # The Redpanda chart forces authorization on when SASL is enabled. This lab
    # isolates TLS and OAuth authentication from a separate Kafka ACL policy.
    kube(
        "exec",
        "redpanda-0",
        "-c",
        "redpanda",
        "--",
        "rpk",
        "cluster",
        "config",
        "set",
        "kafka_enable_authorization",
        "false",
    )
    # Export only the public CA for local clients and optional browser trust.
    cert = kube(
        "get", "secret", "lab-ca", "-o", "jsonpath={.data.tls\\.crt}", capture=True
    )
    (STATE / "ca.crt").write_bytes(base64.b64decode(cert))


def build() -> None:
    check_cluster()
    revision = run(
        ["git", "-C", str(ROOT), "rev-parse", "--short=10", "HEAD"], capture=True
    ).strip()
    diff = run(
        [
            "git",
            "-C",
            str(ROOT),
            "diff",
            "--binary",
            "--",
            "metadata-service",
            "metadata-ingestion",
            "datahub-actions",
            "docker",
        ],
        capture=True,
    )
    tag = revision + "-" + hashlib.sha256(diff.encode()).hexdigest()[:10]
    run(
        [
            str(ROOT / "gradlew"),
            "--max-workers=3",
            "-PuseSystemNode=true",
            ":metadata-service:war:dockerPrepare",
            ":datahub-upgrade:dockerPrepare",
            ":datahub-actions:dockerPrepare",
            ":datahub-frontend:dockerPrepare",
        ]
    )
    images = {}
    for component in (
        "datahub-gms",
        "datahub-upgrade",
        "datahub-actions",
        "datahub-frontend",
    ):
        name = (
            "datahub-frontend-react" if component == "datahub-frontend" else component
        )
        image = f"datahub-tls/{name}:{tag}"
        command = [
            "docker",
            "--context",
            CONTEXT,
            "build",
            "-f",
            str(ROOT / "docker" / component / "Dockerfile"),
            "-t",
            image,
        ]
        if component == "datahub-actions":
            match = re.search(
                r'cliVersion\s*=\s*"([^"]+)"',
                (ROOT / "gradle/versioning/cliVersion.gradle").read_text(),
            )
            if match is None:
                raise RuntimeError("Cannot determine bundled CLI version")
            command.extend(
                [
                    "--target",
                    "final-slim",
                    "--build-arg",
                    "APP_ENV=slim",
                    "--build-arg",
                    "BUNDLED_CLI_VERSION=" + match.group(1),
                    "--build-arg",
                    "BUNDLED_VENV_SLIM_MODE=true",
                    "--build-arg",
                    "RELEASE_VERSION=1!0.0.0+tls." + revision,
                ]
            )
        command.append(str(ROOT))
        run(command)
        images[name] = image
    (STATE / "images.json").write_text(json.dumps(images, indent=2) + "\n")


def deploy(charts: Path, mode: str) -> None:
    check_cluster()
    images = json.loads((STATE / "images.json").read_text())
    values: dict = {"global": {}, "datahubSystemUpdate": {}}
    components = {
        "datahub-gms": "datahub-gms",
        "datahub-frontend": "datahub-frontend-react",
        "acryl-datahub-actions": "datahub-actions",
        "datahubSystemUpdate": "datahub-upgrade",
    }
    for component, image_name in components.items():
        repository, tag = images[image_name].rsplit(":", 1)
        values[component] = {
            "image": {"repository": repository, "tag": tag, "pullPolicy": "Never"}
        }
    values["datahub-frontend"]["extraInitContainers"] = [
        {
            "name": "import-lab-ca",
            "image": images["datahub-frontend-react"],
            "imagePullPolicy": "Never",
            "command": [
                "/bin/sh",
                "-ec",
                'exec "$(dirname "$(readlink -f "$(command -v java)")")/keytool" "$@"',
                "keytool",
                "-importcert",
                "-noprompt",
                "-alias",
                "lab-ca",
                "-file",
                "/lab-ca/ca.crt",
                "-keystore",
                "/lab-trust/truststore.p12",
                "-storetype",
                "PKCS12",
                "-storepass",
                "changeit",
            ],
            "securityContext": {
                "runAsUser": 1000,
                "runAsGroup": 1000,
                "runAsNonRoot": True,
            },
            "volumeMounts": [
                {"name": "lab-ca", "mountPath": "/lab-ca", "readOnly": True},
                {"name": "lab-trust", "mountPath": "/lab-trust"},
            ],
        }
    ]
    if mode == "oauth":
        token_url = "https://keycloak/realms/datahub/protocol/openid-connect/token"
        secret = credentials()["DATAHUB_KAFKA_CLIENT_SECRET"]
        jaas = (
            'org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginModule required clientId="datahub-kafka" clientSecret="'
            + secret
            + '" scope="openid" ssl.truststore.type="PEM" ssl.truststore.location="/mnt/datahub/tls/ca.pem";'
        )
        apply(
            {
                "apiVersion": "v1",
                "kind": "Secret",
                "metadata": {"name": "tls-lab-java"},
                "stringData": {"jaas.conf": jaas},
            }
        )
        values["global"] = {
            "kafka": {
                "bootstrap": {
                    "server": "redpanda-0.redpanda.datahub-tls.svc.cluster.local:9094"
                }
            },
            "credentialsAndCertsSecrets": {
                "name": "tls-lab-java",
                "path": "/mnt/lab-kafka",
                "secureEnv": {"sasl.jaas.config": "jaas.conf"},
            },
            "springKafkaConfigurationOverrides": {
                "security.protocol": "SASL_SSL",
                "sasl.mechanism": "OAUTHBEARER",
                "sasl.login.callback.handler.class": "org.apache.kafka.common.security.oauthbearer.OAuthBearerLoginCallbackHandler",
                "sasl.oauthbearer.token.endpoint.url": token_url,
            },
            "pythonKafkaConfigurationOverrides": {
                "security.protocol": "SASL_SSL",
                "sasl.mechanism": "OAUTHBEARER",
                "sasl.oauthbearer.method": "oidc",
                "sasl.oauthbearer.client.id": "datahub-kafka",
                "sasl.oauthbearer.token.endpoint.url": token_url,
                "sasl.oauthbearer.scope": "openid",
                "https.ca.location": "/mnt/datahub/tls/ca.pem",
            },
            "pythonKafkaSecretsOverrides": {
                "sasl.oauthbearer.client.secret": {
                    "secretRef": "tls-lab-credentials",
                    "secretKey": "DATAHUB_KAFKA_CLIENT_SECRET",
                }
            },
        }
    path = STATE / "datahub-values.json"
    path.write_text(json.dumps(values, indent=2))
    run(
        [
            "helm",
            "dependency",
            "build",
            "--skip-refresh",
            str(charts / "charts/datahub"),
        ]
    )
    helm(
        "upgrade",
        "--install",
        "datahub",
        str(charts / "charts/datahub"),
        "--namespace",
        NAMESPACE,
        "--reset-values",
        "--values",
        str(charts / "examples/tls-lab/datahub-values.yaml"),
        "--values",
        str(path),
        "--wait",
        "--timeout",
        "15m",
    )
    (STATE / "mode").write_text(mode)


def forward() -> None:
    check_cluster()
    processes = []
    try:
        for service, ports in (
            ("keycloak", "9443:443"),
            ("datahub-datahub-frontend", "9002:9002"),
            ("datahub-datahub-gms", "18080:8080"),
        ):
            processes.append(
                subprocess.Popen(
                    [
                        "kubectl",
                        "--kubeconfig",
                        str(KUBECONFIG),
                        "--context",
                        CONTEXT,
                        "--namespace",
                        NAMESPACE,
                        "port-forward",
                        "--address",
                        "127.0.0.1",
                        "service/" + service,
                        ports,
                    ]
                )
            )
        print(
            "DataHub: http://localhost:9002 | Keycloak: https://localhost:9443 | GMS: http://localhost:18080",
            flush=True,
        )
        print("Keep this command running; Ctrl-C closes the forwards.", flush=True)
        while all(process.poll() is None for process in processes):
            time.sleep(1)
        raise RuntimeError("A port forward stopped; check the service and local port")
    except KeyboardInterrupt:
        pass
    finally:
        for process in processes:
            if process.poll() is None:
                process.terminate()
            process.wait()


def login() -> None:
    values = credentials()
    print(
        "DataHub SSO username: tls-user\nPassword: " + values["DATAHUB_TEST_PASSWORD"]
    )
    print(
        "Keycloak administrator: admin\nPassword: "
        + values["KC_BOOTSTRAP_ADMIN_PASSWORD"]
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "command",
        choices=[
            "cluster",
            "dependencies",
            "build",
            "deploy",
            "status",
            "forward",
            "login",
        ],
    )
    parser.add_argument("--mode", choices=["mtls", "oauth"], default="oauth")
    parser.add_argument(
        "--helm-dir",
        type=Path,
        default=ROOT.parent / ("datahub-helm" + ROOT.name.removeprefix("datahub")),
    )
    args = parser.parse_args()
    STATE.mkdir(parents=True, exist_ok=True, mode=0o700)
    if args.command == "cluster":
        cluster()
    elif args.command == "dependencies":
        dependencies(args.helm_dir)
    elif args.command == "build":
        build()
    elif args.command == "deploy":
        deploy(args.helm_dir, args.mode)
    elif args.command == "forward":
        forward()
    elif args.command == "login":
        login()
    else:
        check_cluster()
        kube("get", "pods,certificates,services")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, subprocess.CalledProcessError) as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
