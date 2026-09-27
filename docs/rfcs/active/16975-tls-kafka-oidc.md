- Start Date: 2026-04-10
- Updated: 2026-09-27
- RFC PR: [datahub-project/datahub#16975](https://github.com/datahub-project/datahub/pull/16975)
- Implementation PRs:
  - [datahub-project/datahub#16997](https://github.com/datahub-project/datahub/pull/16997): Java Schema Registry PEM types; open, with review requesting regression coverage.
  - [acryldata/datahub-helm#692](https://github.com/acryldata/datahub-helm/pull/692): earlier chart implementation, closed as stale without merging.
- Related, separate work: [OIDC private_key_jwt #15479](https://github.com/datahub-project/datahub/pull/15479).

# PEM-first TLS for DataHub outbound connections

## Summary

Provide a single, optional Helm `global.tls` object containing references to a CA
bundle and an operator-provided client PEM bundle containing the private key and
certificate chain. Mount those PEM files and translate the settings into each
Java and Python Kafka/Schema Registry client's configuration. Python HTTP trust
remains separately configurable through existing workload volumes and environment
settings.
Existing SASL, JKS and PKCS12 configuration remains supported through the existing
overrides. Enabling TLS must not require patching installed Python packages or
mounting replacement Actions recipes.

## Current upstream status

This assessment uses DataHub master `1bc90368f5978edfa410b075d9b9d4a02f8afda0`
and Helm master `0c96c339750587009b92df36a03ded48e5294c98`.

| Area                              | Status                      | Remaining work                                                                                                                          |
| --------------------------------- | --------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| Java Kafka broker PEM support     | Available                   | Chart wiring only. Kafka client is `8.2.2-ccs`.                                                                                         |
| Java Schema Registry PEM support  | Library supports it         | Bind store types and private-key password; avoid empty defaults overwriting Spring properties. SerDe/Schema Registry client is `8.1.0`. |
| Python Schema Registry CA loading | Fixed by dependency upgrade | Do not apply the historical SSLContext workaround.                                                                                      |
| Python environment configuration  | Missing                     | Bind broker and registry prefixes across the five client construction sites.                                                            |
| DataHub Kafka reader              | Missing                     | Forward all Schema Registry configuration, not only its URL.                                                                            |
| Bundled Actions recipes           | Missing                     | Optional broker/registry TLS settings; configurable GMS protocol for documentation propagation.                                         |
| Unified Helm interface            | Missing                     | Secret mounts, runtime configuration, validation and documented precedence.                                                             |

[PR #19873](https://github.com/datahub-project/datahub/pull/19873) raised the
Kafka ingestion and Actions dependency floor to Confluent Python 2.15.1.
That client creates an SSL context from `ssl.ca.location`, loads client
certificates and supports `ssl.key.password`. Passing an SSLContext as the
location is no longer the correct interface and can cause the intended CA to
be ignored. The standalone `datahub-kafka` sink still permits older clients for
Airflow compatibility; installations using this workflow should use 2.15.1 or
newer. A compatibility change to that extra must be considered separately.

The [patches appendix](./16975-tls-kafka-oidc-patches.md) is historical evidence,
not a patch bundle to apply to current installations.

## Requirements

- Expose additive `global.tls` configuration for Kafka and Schema Registry.
- Preserve Python HTTP trust defaults; operators can explicitly mount a complete
  HTTP CA bundle and set client-native variables through existing workload settings.
- Support server-authentication-only TLS, mutual TLS, and SASL over TLS.
- Keep certificate verification and hostname verification enabled.
- Support unencrypted and encrypted PEM private keys.
- Require operators to supply a complete client PEM bundle for mutual TLS.
- Remain independent of certificate providers; validate Secret references at render
  time and let TLS clients validate the bundle contents at startup.
- Give explicit runtime overrides precedence over values generated from `global.tls`.
- Preserve plaintext defaults when TLS is disabled and existing JKS/PKCS12 overrides.
- Work for GMS, standalone consumers, Actions, ingestion jobs and upgrade/setup jobs.
- Document a repeatable local deployment that exercises real TLS handshakes.

## Non-requirements

- GMS ingress mTLS, tracked separately in issue #15755.
- Replacing SASL or token authentication to GMS.
- Certificate issuance, PEM bundle assembly, automatic CA merging, or JKS-to-PEM conversion.
- A first-class per-endpoint PKI model; explicit overrides remain available.
- Changing frontend/OIDC trust defaults, which continue to use JVM trust.
- OIDC `private_key_jwt`, tracked in #15479, or future RFC 8705 `tls_client_auth`.
- TLS configuration for Elasticsearch, Neo4j and JDBC.

## Operator interface

```yaml
global:
  tls:
    enabled: true
    ca:
      secretName: datahub-ca
      key: ca.crt
    client: # optional; omit for server-authentication-only TLS
      secretName: datahub-client
      key: client.pem # private key followed by the certificate chain
    keyPasswordFile: # optional; the secret value is the private-key password
      secretName: datahub-client-password
      key: password
```

Operators create these Secrets using their existing certificate delivery process.
cert-manager, Vault, External Secrets and CSI integrations are optional providers,
not DataHub chart dependencies. The chart does not own, read during rendering, or
embed their private material. An omitted CA uses the runtime's existing trust
configuration. Each supplied reference must have a secret name and key.
`keyPasswordFile` requires a client bundle.

The client bundle contains a PKCS#8 PEM private key followed by the matching leaf
certificate and intermediate chain. Preparing it is the operator's responsibility;
concatenating existing PEM files is sufficient:

```sh
umask 077
{ cat tls.key; printf '\n'; cat tls.crt; } > client.pem
```

Store the result in the referenced Secret. Keep the CA bundle separate from this
identity file and never include the private key in a CA bundle. Helm validates
references, while the TLS clients validate PEM contents and key/certificate
matching at startup. This replaces the original RFC's open question about
assembling the client bundle inside the pod.

PEM matches Kubernetes certificate delivery and the native Python client interface.
Kafka supports it through KIP-651, and Confluent's
[SslFactory](https://github.com/confluentinc/schema-registry/blob/v8.1.0/client/src/main/java/io/confluent/kafka/schemaregistry/client/security/SslFactory.java)
also supports file-based PEM and encrypted private keys.

### Files and rotation

Project the referenced CA and client bundle into read-only volumes with mode
0440 and a workload `fsGroup` that can read them. Java Kafka and Schema Registry
use the supplied client bundle as `ssl.keystore.location` with type `PEM`.
Python Kafka and Schema Registry use that same mounted file for both
`ssl.certificate.location` and `ssl.key.location`. There is no identity assembly
init container, writable identity volume, or conversion to JKS.

Password values are injected from Secret references into the clients' native
password configuration. A filename is not a substitute for `ssl.key.password`.

Secret updates alone do not guarantee that running clients reload their SSL
contexts. Update the operator-managed bundle and CA Secrets and roll out the
consuming pods. Automatic hot reload is not part of this RFC.

### Runtime configuration

| Connection                    | Configuration                                                                   |
| ----------------------------- | ------------------------------------------------------------------------------- |
| Java Kafka broker             | `SPRING_KAFKA_PROPERTIES_SSL_*`; PEM truststore and combined keystore locations |
| Java external Schema Registry | `KAFKA_SCHEMA_REGISTRY_SSL_*` and Spring `SCHEMA_REGISTRY_SSL_*` properties     |
| Python Kafka broker           | `KAFKA_PROPERTIES_*` mapped to librdkafka properties                            |
| Python Schema Registry        | `KAFKA_SCHEMA_REGISTRY_PROPERTIES_*` mapped to Confluent HTTP-client properties |
| Requests clients to GMS       | `REQUESTS_CA_BUNDLE`                                                            |
| HTTPX clients                 | `SSL_CERT_FILE`                                                                 |
| Frontend to GMS/IdP           | Existing JVM trust configuration; unchanged                                     |

`global.tls` does not set `REQUESTS_CA_BUNDLE` or `SSL_CERT_FILE`. Kafka and Schema
Registry use their dedicated CA settings without changing other HTTP clients'
trust. There is no CA-merging init container or dependency on an image's CA path.

For private-CA HTTP endpoints, operators supply a complete PEM trust bundle in a
ConfigMap or Secret and mount it through `extraVolumes` and `extraVolumeMounts`.
Actions uses `extraEnvs` to set `REQUESTS_CA_BUNDLE` (Requests) and `SSL_CERT_FILE`
(HTTPX); ingestion cron jobs use their per-job `env` map. These replace the default
trust bundle, so operators include public roots when required and restart pods
after rotation. With no override, existing image and operator trust settings
remain in effect. `REQUESTS_CA_BUNDLE` is not an HTTPX or certifi setting.

The DataHub REST emitter already accepts a CA path and uses Requests. Verify the
separate `mcp-server-datahub` client stack before claiming end-to-end coverage there.

TLS defaults select `SSL`; explicit SASL settings select `SASL_SSL` and retain
their mechanisms and credentials. Broker and Schema Registry TLS settings use
distinct namespaces, even when their generated defaults reference the same PEMs.

### Overrides and binding

Retain `global.springKafkaConfigurationOverrides` and
`global.credentialsAndCertsSecrets` for Java. Provide
`global.pythonKafkaConfigurationOverrides`, `global.pythonKafkaSecretsOverrides`
and `global.pythonKafkaSchemaRegistryConfigurationOverrides` for Python.
Explicit overrides win over generated TLS defaults without duplicate env names.
Older charts' Java-only properties must not be handed to librdkafka.

At client construction, a shared Python helper merges the appropriate environment
prefix into the recipe dictionary. Environment values win; the helper does not
mutate the recipe. For example, `KAFKA_PROPERTIES_SSL_CA_LOCATION` maps to
`ssl.ca.location`. Handle the `oauth_cb` spelling, resolve callback paths through
the existing resolver, convert numeric Schema Registry settings, and omit empty
optional TLS paths/passwords from plaintext recipes.

Apply this consistently in `confluent_schema_registry.py`, Kafka connectivity
checks and consumer/admin creation in `kafka.py`, `kafka_emitter.py`,
`datahub_kafka_reader.py`, and Actions' `kafka_event_source.py`. The reader must
forward the complete `schema_registry_config`, including authentication.

### Java Schema Registry factory

Bind and forward `ssl.truststore.type`, `ssl.keystore.type` and
`ssl.key.password` in `KafkaSchemaRegistryFactory`. Forward only non-empty
optional factory values, including existing locations and passwords.

The original diagnosis overstated what `putAll` does: an absent type key does
not erase a Spring-bound type. However, the factory's empty location/password
defaults overwrite corresponding Spring values when merged afterward. Both
the missing factory bindings and this precedence bug need fixing. Do not emit
empty store types: Confluent's default applies to absent types, not empty ones.

### Bundled Actions recipes

Add optional `consumer_config` and `schema_registry_config` TLS fields to
`executor.yaml` and `doc_propagation_action.yaml`. Keep plaintext as the default,
allow SASL overrides, and use distinct broker/registry variables. Documentation
propagation must honor `DATAHUB_GMS_PROTOCOL` like the executor does.

## Local verification

The local lab uses Colima Kubernetes, a Redpanda Helm dependency for Kafka and
Schema Registry, Keycloak for DataHub SSO and Kafka OAuth, and cert-manager for
a private CA and server/client certificates. The example requests a combined
client PEM from its provider and passes the resulting Secret entry to the
provider-independent DataHub chart. Enter through
`scripts/dev/datahub-dev.sh tls`; the lab must use an explicit local context and
must not target the user's active remote cluster. Dependencies and tool versions
are pinned. Local credentials and keys stay in Kubernetes Secrets or ignored
build output.

The `tls verify` command starts an on-demand Job from the Helm-managed ingestion
CronJob. It seeds three Avro records, registers **TLS lab Kafka**, triggers managed
ingestion inside the Actions container, checks persisted schema and sample
profiles, and matches the resulting metadata event in a custom Actions pipeline.
All source execution and verification happen in Kubernetes containers. The host
only issues management commands. The lab Actions image includes the Kafka source
extra and uses the native executor so the working-tree TLS fixes are exercised.

Verify these paths using images built from the working tree:

1. GMS and system-update connect to Redpanda and Schema Registry with PEM TLS.
2. Python ingestion, Kafka emission and Actions connect with the same CA and identity.
3. Keycloak SSO works through the browser; Kafka OAuth obtains and uses a token
   through a verified HTTPS connection to Keycloak.
4. Untrusted CAs and missing required client identities fail rather than
   disabling verification. Incomplete Secret references fail during rendering.
5. Certificate renewal followed by a rollout restores working connections.
6. TLS-disabled rendering remains valid; explicit TLS/SASL overrides win.

Redpanda OIDC uses its built-in 30-day Enterprise evaluation. After expiration,
use a valid license for continued OAuth testing.
The mTLS scenario is independently selectable. The local SSO scenario uses the
existing client-secret OIDC flow; testing #15479 requires that separate branch.

The implementation was exercised locally on 2026-09-26: Keycloak SSO, Java
and Python Kafka OAuth with mTLS, Schema Registry mTLS, an emitted dataset
persisted by GMS, and both bundled Actions consumer groups worked. The
Helm-managed verification Job also passed: a registered Kafka source executed in
Actions, extracted an Avro schema and profiled three messages over OAuth/mTLS;
a custom Actions pipeline logged the fresh dataset's schema event. Public HTTPS
access with Requests, HTTPX and uv was verified. A registry request without a client certificate was
rejected. Encrypted-key and certificate
renewal/rollout scenarios remain to be verified live. The lab guide is in the
Helm repository at `examples/tls-lab/README.md`.

On 2026-09-27, the Kubernetes verification passed again with the CA-merging
init container and automatic HTTP trust variables removed. Requests, HTTPX
and a fresh uv package lookup used the image defaults successfully; Kafka
source ingestion, Schema Registry mTLS and the Actions event pipeline retained
their dedicated TLS settings and passed.

The optional legacy Kafka setup and hourly maintenance templates also needed
repairs: honor an explicit `consolidatedUpgrade: false`, tolerate absent
ZooKeeper settings, avoid duplicate Kafka environment entries, and use the
hourly job's own schedule, resource and sidecar settings.

## Rollout and documentation

Ship backend binding/factory/recipe fixes and chart wiring together as compatible
versions. A chart emitting environment variables cannot enable automatic binding
in older Python images. Update `docs/how/kafka-config.md`, the chart values
reference and local lab instructions. Keep the existing low-level interface
supported; any deprecation needs a separate maintainer decision.

## Future work

- Audit custom-CA handling in `mcp-server-datahub`.
- Decide whether the standalone Kafka sink can raise its dependency floor.
- Add automatic certificate reload only with explicit lifecycle guarantees.
- Consider endpoint-specific PKI and other outbound services separately.
