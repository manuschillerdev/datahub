- Start Date: 2026-04-10
- RFC PR: https://github.com/datahub-project/datahub/pull/16977
- Discussion Issue: (TBD)
- Implementation PR(s):
  - https://github.com/datahub-project/datahub/pull/16652
  - https://github.com/acryldata/mcp-server-datahub/pull/109

# MCP Server Improvements: FastMCP v3, Code Mode, and Enterprise SSO

## Summary

Two features we need for our DataHub MCP deployment, plus the framework
upgrade that both of them require:

1. **OIDC authentication with an On-Behalf-Of (OBO) token-exchange flow.**
   The MCP server accepts an OIDC token from the calling AI client,
   validates it, exchanges it for a DataHub-scoped token, and runs each
   request as the calling user. Without this, every DataHub mutation
   initiated through MCP is attributed to a shared service account, which
   defeats DataHub's audit trail and per-user policies in our environment.

   The only provider implemented today is **Microsoft Entra ID**, because
   that is the IdP our users authenticate against. The implementation is
   a single `TokenVerifier` subclass (`EntraOBOVerifier`) that composes
   FastMCP v3's shipped `AzureJWTVerifier` with an MSAL-backed OBO
   exchange — we do not invent a new auth framework. Adding Okta,
   Keycloak, Google, or Auth0 later means writing sibling
   `TokenVerifier` subclasses against whichever FastMCP verifier ships
   for that IdP; no abstract base class in our repo.

2. **Code Mode transport** built on FastMCP's `CodeMode` transform.
   Instead of exposing ~20 DataHub tool schemas in every request (which
   currently costs 8–12k tokens of context before the user has even typed
   a question), the server exposes two meta-tools (`search_tools`,
   `execute`) and the agent composes short Python snippets that run
   inside a sandbox. This is the context-usage improvement we want for
   agent workflows that mount DataHub alongside several other MCP servers.

Both features depend on primitives that only exist in **FastMCP v3**
(per-request dependency injection, the `CodeMode` transform, multi-auth),
so the RFC also includes a **mechanical v3 upgrade** of the server. The
upgrade is a prerequisite, not an independent goal — we are not upgrading
for its own sake.

A working implementation already exists at
[`manuschillerdev/mcp-server-datahub`](https://github.com/manuschillerdev/mcp-server-datahub)
(10 commits ahead of `acryldata/mcp-server-datahub:main`). This RFC
proposes upstreaming it so we don't have to maintain a permanent fork.

## Basic example

### 1. FastMCP v3 — idiomatic tool definition

```python
from fastmcp import FastMCP, Context
from fastmcp.exceptions import ToolError
from fastmcp.server.dependencies import Depends

mcp = FastMCP(
    "datahub",
    strict_input_validation=True,
    on_duplicate_tools="error",
)

@mcp.tool(
    annotations={"readOnlyHint": True, "idempotentHint": True},
    timeout_seconds=60,
)
async def search(
    query: str,
    *,
    ctx: Context,
    client: DataHubGraph = Depends(get_datahub_client),
) -> SearchResult:
    await ctx.report_progress(0, 1, "querying datahub")
    try:
        return await _search_implementation(client, query)
    except DataHubError as e:
        raise ToolError(f"DataHub search failed: {e}") from e
```

Key v3 affordances used here, none of which exist in v2:

- `ToolError` produces a structured, agent-friendly error instead of a Python
  traceback serialized into the response body.
- `Depends(get_datahub_client)` replaces the v2 pattern of a module-level
  global plus a threading lock. In OBO mode this is what resolves to the
  _per-user_ DataHub client on each request.
- `timeout_seconds` is enforced by the framework, so a single slow GraphQL
  query can no longer hang the entire server.
- `strict_input_validation=True` + `on_duplicate_tools="error"` catch schema
  drift and accidental double-registration at startup.
- `Context` lets us emit progress events and structured logs that clients
  like Claude Code surface inline.

Catalog metadata (entity types, platforms, supported filter keys) is exposed
as MCP _resources_ instead of being crammed into tool docstrings:

```python
@mcp.resource("datahub://catalog/entity-types")
def entity_types() -> list[str]:
    return SUPPORTED_ENTITY_TYPES
```

### 2. Code Mode

```
$ mcp-server-datahub --transport http --code-mode
```

The agent now only sees two meta-tools:

```
search_tools(query: str) -> list[ToolDescriptor]
execute(code: str, timeout_seconds: int = 30) -> ExecutionResult
```

Example agent turn:

```python
# code sent to execute()
hits = search(query="pet adoptions", filter="platform = snowflake")
urns = [h.urn for h in hits.results[:5]]
entities = get_entities(urns=urns, include=["properties", "schema"])
return {
    "candidates": [
        {"urn": e.urn, "fields": [f.name for f in e.schema.fields]}
        for e in entities
    ],
}
```

The sandbox (Monty) enforces a 30-second wall-clock timeout, ~50 MB memory
cap, and recursion depth 50. Only the DataHub tool surface is exposed — no
filesystem, no network, no `os`, no `subprocess`.

The benefit is twofold: (a) the tool catalog the agent has to hold in context
shrinks from ~20 tool schemas (currently ~8–12k tokens) to 2 meta-tools, and
(b) the agent can express "search → rank → fetch details → build answer"
as a single code block instead of 4 sequential tool calls with the MCP client
round-tripping in between.

### 3. OIDC On-Behalf-Of

Deployment runs behind an HTTP transport, reachable by an AI client that
authenticates the end user with an OIDC provider.

```bash
mcp-server-datahub --transport http
# env vars
DATAHUB_MCP_AUTH_ENABLED=true
MCP_OIDC_PROVIDER=entra
AZURE_TENANT_ID=<tenant-guid>
MCP_OAUTH_CLIENT_ID=<app-reg-client-id>
MCP_OAUTH_CLIENT_SECRET=<app-reg-secret>   # or use Managed Identity
DATAHUB_OAUTH_SCOPE=api://<datahub-app-id>/.default
MCP_SERVER_BASE_URL=https://mcp.example.com
```

Request flow:

1. GitHub Copilot / Claude / Copilot Studio authenticates the end user against
   Entra ID and calls the MCP server with the user's Entra access token as
   the `Authorization: Bearer …` header.
2. The server's `OIDCOboProvider` validates the JWT signature, issuer,
   audience, expiry, and (optionally) required scopes.
3. The provider calls MSAL `acquire_token_on_behalf_of(...)` to exchange the
   user JWT for a DataHub-scoped access token.
4. `PerUserClientMiddleware` stores that token in request state and
   `get_datahub_client()` (the DI provider from improvement #1) returns a
   DataHub client configured with the per-user token.
5. All subsequent mutation tools — `add_tags`, `set_domains`,
   `update_description`, … — are attributed to the calling user in DataHub's
   audit log, not the service account.
6. If `MCP_SERVER_BASE_URL` is set, the server publishes
   `/.well-known/oauth-protected-resource` so MCP clients can auto-discover
   the authorization server.

A PAT-only fallback path is preserved through FastMCP's multi-auth: if the
incoming bearer token is not a valid JWT, the server falls back to verifying
it as a DataHub PAT against `/me`. This lets a single deployment serve both
Copilot-like clients (OBO) and script/CLI clients (PAT).

## Motivation

### Why FastMCP v3?

The upstream server is pinned to FastMCP v2 and has grown several local
workarounds that v3 makes obsolete:

- A module-level threading lock around the DataHub client, because v2 has no
  per-request DI.
- Ad-hoc `ValueError` / `RuntimeError` raising, which surfaces Python
  tracebacks to the agent.
- No per-tool timeouts, so a slow lineage traversal can stall the server.
- Tool-catalog metadata duplicated into every tool's docstring because v2
  has no first-class resource concept.

Adopting v3 is not about chasing a version number — each of those
workarounds has caused real operational pain in our deployment, and v3 gives
us the primitives to remove them all in one pass.

### Why Code Mode?

A fully configured DataHub MCP server currently ships ~20 tools. For an agent
running Claude, each tool schema costs ~300–700 tokens in the system prompt,
which means the DataHub tool catalog alone consumes 8–12k tokens _before_
the user asks a question. On smaller context windows, or when multiple MCP
servers are mounted at once, this is prohibitive.

Code Mode collapses the catalog to two tools and lets the agent discover the
rest on demand. Empirically in our testing, a typical "find a dataset and
summarise it" turn drops from 4 MCP tool calls (each paying full
serialization overhead) to a single `execute()` call with a 10-line Python
snippet.

### Why OIDC + OBO?

The upstream server has one authentication story: a single DataHub PAT,
shared by every user of the server. That is acceptable for a personal
stdio-mode deployment but not for a multi-tenant HTTP deployment where:

- Mutations must be attributed to the real user for audit & compliance.
- The AI client (GitHub Copilot, Copilot Studio, a corporate chatbot) already
  holds an OIDC token for the user — forcing the user to _also_ manage a
  DataHub PAT negates the SSO experience.
- Fine-grained DataHub policies (per-domain, per-platform) cannot apply if
  everything runs as the service account.

OBO is the standard OAuth 2.0 pattern for this: the intermediate service (us)
exchanges the caller's user token for a token scoped to the downstream API
(DataHub).

## Requirements

### FastMCP v3 upgrade

- The server MUST run on FastMCP ≥ 3.0.
- All tool errors MUST use `ToolError` (or subclasses), never bare
  `ValueError`/`RuntimeError`.
- Every tool MUST declare a timeout. Defaults: read-only tools 60 s,
  mutations 30 s.
- The DataHub client MUST be resolved via a DI provider so OBO can swap in a
  per-user client without a threading lock.
- Catalog metadata (entity types, platforms, filter grammar) MUST be exposed
  as MCP resources in addition to, or in place of, tool docstring padding.
- The server MUST start with `strict_input_validation=True` and
  `on_duplicate_tools="error"`.
- The upgrade MUST be a no-op from the agent's point of view: tool names,
  parameters, and response shapes stay identical.

### Code Mode

- Code Mode MUST be opt-in via `--code-mode` CLI flag or
  `DATAHUB_MCP_CODE_MODE=true` env var. Default remains the normal tool-list
  transport.
- When enabled, the server MUST expose exactly the meta-tools defined by
  FastMCP's `CodeMode` transform (`search_tools`, `execute`).
- Sandbox limits MUST be enforced: wall-clock timeout (default 30 s),
  memory cap (~50 MB), recursion depth (50). Values MUST be overridable via
  env vars for operators who need to tune.
- The sandbox MUST NOT expose filesystem, network, `os`, `subprocess`, or
  any module beyond the DataHub tool surface.
- Code Mode MUST be orthogonal to authentication: OBO/PAT both work.
- The `code-mode` dependency group MUST be optional so that users who do not
  enable Code Mode do not pay the install cost of the sandbox runtime.

### OIDC + OBO

- The implementation MUST extend FastMCP v3's shipped primitives
  (`TokenVerifier`, `AzureJWTVerifier`, `RemoteAuthProvider`,
  `Middleware`) rather than defining a parallel auth framework.
- JWT validation (signature via JWKS, issuer, audience, expiry,
  optional `required_scopes`) MUST be delegated to FastMCP's
  `AzureJWTVerifier` — not reimplemented.
- JWKS caching MUST come from FastMCP's verifier as well (we do not
  manage a cache ourselves).
- The Entra OBO exchange MUST use MSAL's
  `ConfidentialClientApplication.acquire_token_on_behalf_of` —
  the same call pattern used by Microsoft's own published reference
  ([Pamela Fox, _Using on-behalf-of flow for Entra-based MCP servers_](https://blog.pamelafox.org/2026/01/using-on-behalf-of-flow-for-entra-based.html))
  and documented in Microsoft's OAuth 2.0 OBO protocol reference.
- The exchanged DataHub token MUST be written into
  `AccessToken.claims["datahub_token"]` so that a single
  `PerUserClientMiddleware` can install a per-request `DataHubClient`
  without touching any tool definitions.
- Multi-auth MUST be supported: if OIDC/OBO is configured and the
  incoming bearer token is not a valid Entra JWT, the server MUST fall
  back to DataHub PAT verification. This is what allows one deployment
  to serve both Copilot-style clients and CLI/script clients.
- When `MCP_SERVER_BASE_URL` is set, the server MUST publish
  `/.well-known/oauth-protected-resource` by wrapping the verifier in
  FastMCP's `RemoteAuthProvider` (no custom discovery code).
- When no OIDC env vars are set, the server MUST behave exactly as it
  does today — this is a pure additive change for existing deployments.
- STDIO transport is out of scope: it continues to use the
  service-account client unconditionally, since there is no HTTP
  request to attach a token to.

### Extensibility

- The extension point for additional IdPs is **FastMCP's
  `TokenVerifier`** — not a bespoke base class in this repo. Adding an
  Okta / Keycloak / Auth0 / Google provider means either (a) reusing
  FastMCP's corresponding verifier if it ships one (as we do for
  `AzureJWTVerifier`) or (b) writing a new `TokenVerifier` subclass
  that composes that IdP's JWT verification with its OBO exchange.
  Either way, no changes to the server core are needed.
- Code Mode's sandbox is extensible via FastMCP's `CodeMode` transform —
  as new DataHub tools are added, they automatically appear inside the
  sandbox without additional wiring.

## Non-Requirements

- **Replacing the existing tool-list transport.** Code Mode is additive. The
  default transport stays as it is today.
- **Supporting non-OIDC SSO.** SAML, LDAP, mTLS, Kerberos are out of scope.
  OIDC is where the MCP client ecosystem is converging.
- **Token caching / refresh tokens across requests.** Each request does an
  OBO exchange. MSAL's in-process cache is sufficient for our scale;
  distributed caching is left for a future RFC.
- **Authorization beyond authentication.** This RFC ensures the _caller_ is
  identified and a DataHub client is created on their behalf. Authorization
  decisions (which tags can this user set? which datasets can they see?) are
  already enforced by DataHub itself and are intentionally not duplicated in
  the MCP server.
- **Migrating existing DataHub Cloud hosted deployments.** This RFC targets
  the open-source server; the hosted offering may layer its own auth on top.

## Detailed design

### 1. FastMCP v3 upgrade

#### 1.1 Dependency and compatibility

- Bump `fastmcp` to `>=3.0,<4`.
- Drop the v2 compat shims in `mcp_server.py`: module-level `_datahub_client`
  global, threading lock, duplicate-registration guards.
- Keep the file structure that already exists upstream (`tools/search.py`,
  `tools/entities.py`, …). The refactor is additive.

#### 1.2 Dependency injection

Introduce a single DI provider:

```python
# dependencies.py
from fastmcp.server.dependencies import get_http_request

def get_datahub_client() -> DataHubGraph:
    """Return the DataHub client for the current request.

    Resolution order:
      1. Per-user client attached by PerUserClientMiddleware (OBO or PAT).
      2. Service-account client (fallback; only path for STDIO).
    """
    request = get_http_request()
    if request is not None:
        per_user = request.state.datahub_client  # may be None
        if per_user is not None:
            return per_user
    return _service_account_client
```

Every tool that talks to DataHub takes
`client: DataHubGraph = Depends(get_datahub_client)` instead of reading a
module-level global. This is the single change that makes the OBO flow work
cleanly — the same DI hook that swaps in a test client also swaps in a
per-user client.

#### 1.3 Errors

A small adapter wraps DataHub exceptions:

```python
def _to_tool_error(exc: Exception) -> ToolError:
    if isinstance(exc, GmsUnauthorizedError):
        return ToolError("Not authorized in DataHub", code="unauthorized")
    if isinstance(exc, GmsNotFoundError):
        return ToolError(str(exc), code="not_found")
    return ToolError(f"DataHub error: {exc}", code="internal")
```

All `tools/*.py` modules use this adapter in their `except` blocks. No bare
`raise` of arbitrary Python exceptions.

#### 1.4 Timeouts

Two presets, applied via the `@mcp.tool` decorator:

| Preset   | Timeout | Applies to                                         |
| -------- | ------- | -------------------------------------------------- |
| `READ`   | 60 s    | `search`, `get_entities`, `get_lineage`, …         |
| `MUTATE` | 30 s    | `add_tags`, `set_domains`, `update_description`, … |

Tunable via `TOOL_READ_TIMEOUT_SECONDS` / `TOOL_MUTATE_TIMEOUT_SECONDS` env
vars for operators with unusually slow DataHub backends.

#### 1.5 Resources

Three initial resources:

| URI                                | Content                                          |
| ---------------------------------- | ------------------------------------------------ |
| `datahub://catalog/entity-types`   | JSON list of supported entity types              |
| `datahub://catalog/platforms`      | JSON list of known platforms in this DataHub     |
| `datahub://catalog/filter-grammar` | The SQL-like filter grammar reference (markdown) |

The filter grammar resource replaces ~1 KB of boilerplate currently inlined
into every search-related tool's docstring. Clients that don't read MCP
resources are unaffected — tool docstrings still contain a short pointer.

### 2. Code Mode

#### 2.1 Transport activation

```python
# __main__.py
if args.code_mode or get_boolean_env_variable("DATAHUB_MCP_CODE_MODE"):
    from fastmcp.contrib.code_mode import CodeMode
    mcp = CodeMode(
        mcp,
        sandbox="monty",
        default_timeout_seconds=_env_int("CODE_MODE_TIMEOUT_SECONDS", 30),
        memory_limit_mb=_env_int("CODE_MODE_MEMORY_MB", 50),
        max_recursion_depth=_env_int("CODE_MODE_MAX_RECURSION", 50),
    )
```

`CodeMode` is a FastMCP v3 transform: it wraps an existing `FastMCP` server
and rewrites the exposed tool list to `(search_tools, execute)`. The
underlying tools are not removed — they are registered inside the sandbox's
Python namespace and callable as plain functions from agent-supplied code.

#### 2.2 Sandbox

Monty is a constrained Python subset (bytecode-level sandbox, no `eval`,
no imports beyond an allowlist, no syscall access). The DataHub tools are
injected into the namespace as callables that dispatch back through the
FastMCP tool registry, which in turn runs each call through the normal
middleware stack — so authentication, logging, and per-user client
resolution all still apply inside Code Mode. There is no auth bypass.

#### 2.3 Packaging

Code Mode ships as an optional dependency group:

```toml
[project.optional-dependencies]
code-mode = ["fastmcp[code-mode]>=3.0"]
```

Users who never enable Code Mode never install the sandbox runtime, keeping
`pip install mcp-server-datahub` lean.

#### 2.4 Operational concerns

- **Observability:** each `execute()` call is logged as a single MCP request
  with a `code_mode=true` tag. Tool calls _inside_ the sandbox are logged as
  child spans so existing dashboards still show per-tool metrics.
- **Rate limiting:** the sandbox timeout is the only limit today. Operators
  who need per-user quotas should put the server behind a gateway (out of
  scope for this RFC).
- **Error surface:** sandbox exceptions bubble up as `ToolError` with
  `code="sandbox_error"`.

### 3. OIDC On-Behalf-Of

#### 3.0 Building on FastMCP v3's shipped primitives

The design below is **not a custom OAuth framework**. It reuses four
classes that ship with FastMCP v3 (`fastmcp[azure]`) as-is and adds one
thin composition class. The shipped primitives are:

| Class                | Source module                         | What we use it for                                    |
| -------------------- | ------------------------------------- | ----------------------------------------------------- |
| `TokenVerifier`      | `fastmcp.server.auth.auth`            | Base class for our custom verifiers                   |
| `AccessToken`        | `fastmcp.server.auth.auth`            | Result type returned by `verify_token`                |
| `RemoteAuthProvider` | `fastmcp.server.auth.auth`            | Wraps the verifier to publish `.well-known` metadata  |
| `AzureJWTVerifier`   | `fastmcp.server.auth.providers.azure` | JWT signature / issuer / audience / expiry validation |
| `Middleware`         | `fastmcp.server.middleware`           | Base class for `PerUserClientMiddleware`              |

We deliberately do **not** use FastMCP's `EntraOBOToken` dependency.
`EntraOBOToken` is designed for the per-tool-call case (a single tool
needs to call, e.g., Microsoft Graph). In our case _every_ DataHub tool
talks to GMS with the user-scoped token, so it is much cleaner to do
the OBO exchange once at auth-verification time and stash the exchanged
DataHub token in `AccessToken.claims["datahub_token"]` — the per-request
middleware then resolves the user-scoped `DataHubClient` without any
tool-level plumbing.

Prior art for the overall pattern:

- **FastMCP itself** documents Azure/Entra integration and ships
  `AzureProvider`, `AzureJWTVerifier`, `RemoteAuthProvider`, and
  `EntraOBOToken` as first-class features — see the
  [FastMCP Azure integration docs](https://gofastmcp.com/integrations/azure).
- **Pamela Fox (Microsoft)** published a working reference
  implementation of an Entra-authenticated MCP server that performs OBO
  via MSAL's `acquire_token_on_behalf_of`, which is the exact call
  pattern used below —
  [_Using on-behalf-of flow for Entra-based MCP servers_](https://blog.pamelafox.org/2026/01/using-on-behalf-of-flow-for-entra-based.html).
- **Microsoft's OAuth 2.0 On-Behalf-Of protocol reference** is the
  canonical spec for the exchange —
  [_Microsoft identity platform and OAuth 2.0 On-Behalf-Of flow_](https://learn.microsoft.com/en-us/entra/identity-platform/v2-oauth2-on-behalf-of-flow).

So the OBO pattern proposed here is a documented, supported, and
already-implemented-by-others primitive — not a design we invented.

#### 3.1 `EntraOBOVerifier`

A single `TokenVerifier` subclass composes FastMCP's `AzureJWTVerifier`
(for the validation half) with an MSAL-backed token exchanger (for the
OBO half), and writes the exchanged DataHub token into
`AccessToken.claims["datahub_token"]`:

```python
# _auth_obo.py (abridged)
from fastmcp.server.auth.auth import AccessToken, TokenVerifier
from fastmcp.server.auth.providers.azure import AzureJWTVerifier

class EntraOBOVerifier(TokenVerifier):
    def __init__(self, config: OBOConfig) -> None:
        super().__init__(
            base_url=config.base_url,
            required_scopes=config.required_scopes,
        )
        self._jwt_verifier = AzureJWTVerifier(
            client_id=config.client_id,
            tenant_id=config.tenant_id,
            required_scopes=config.required_scopes,
        )
        self._exchanger = OBOTokenExchanger(
            tenant_id=config.tenant_id,
            client_id=config.client_id,
            client_secret=config.client_secret,
            datahub_scope=config.datahub_scope,
        )

    async def verify_token(self, token: str) -> AccessToken | None:
        # 1. Validate the Entra JWT using FastMCP's built-in verifier.
        access_token = await self._jwt_verifier.verify_token(token)
        if access_token is None:
            return None

        # 2. Exchange the user assertion for a DataHub-scoped token via OBO.
        try:
            datahub_token = await asyncio.to_thread(
                self._exchanger.exchange, token
            )
        except RuntimeError:
            logger.warning("OBO token exchange failed", exc_info=True)
            return None

        # 3. Return an AccessToken carrying the exchanged DataHub token.
        claims = dict(access_token.claims)
        claims["datahub_token"] = datahub_token
        claims["auth_method"] = "entra_obo"
        return AccessToken(
            token=datahub_token,
            client_id=access_token.client_id,
            scopes=access_token.scopes,
            expires_at=access_token.expires_at,
            claims=claims,
        )
```

`OBOTokenExchanger` is a ~40-line wrapper around
`msal.ConfidentialClientApplication.acquire_token_on_behalf_of`. This
MSAL call is what performs the actual RFC-compliant OBO exchange
documented in Microsoft's OAuth 2.0 OBO reference.

There is **no abstract `OIDCOboProvider` base class**. If/when we want
to support a non-Azure IdP (Okta, Keycloak, …), one of two things
happens:

1. FastMCP ships a provider for it (e.g. if FastMCP adds `OktaProvider`
   we reuse it the same way we reuse `AzureJWTVerifier` here), or
2. We add a second `TokenVerifier` subclass analogous to
   `EntraOBOVerifier`, wiring that IdP's JWT verifier to its OBO
   equivalent.

Either way, the extension point is already FastMCP's `TokenVerifier`
interface. We do not need our own abstraction.

#### 3.2 `.well-known/oauth-protected-resource` discovery

When `MCP_SERVER_BASE_URL` is set, the verifier is wrapped in FastMCP's
`RemoteAuthProvider`, which publishes the standard discovery metadata so
that MCP clients like GitHub Copilot can auto-discover the authorization
server:

```python
# _auth_obo.py (factory)
from fastmcp.server.auth.auth import RemoteAuthProvider

def build_obo_auth(config: OBOConfig):
    verifier = EntraOBOVerifier(config)
    if config.base_url:
        return RemoteAuthProvider(
            token_verifier=verifier,
            authorization_servers=[
                AnyHttpUrl(
                    f"https://login.microsoftonline.com/{config.tenant_id}/v2.0"
                )
            ],
            base_url=config.base_url,
            resource_name="DataHub MCP Server",
        )
    return verifier
```

Resulting discovery document:

```json
{
  "resource": "https://mcp.example.com",
  "authorization_servers": ["https://login.microsoftonline.com/<tenant>/v2.0"],
  "bearer_methods_supported": ["header"],
  "scopes_supported": ["api://<datahub-app-id>/.default"]
}
```

#### 3.3 `PerUserClientMiddleware`

A thin subclass of FastMCP's `Middleware` reads the verified
`AccessToken` from the auth context, picks up the exchanged DataHub
token out of `claims["datahub_token"]`, and installs a per-request
`DataHubClient` via the existing `with_datahub_client` context manager:

```python
# _auth.py (abridged)
from fastmcp.server.middleware import CallNext, Middleware
from mcp.server.auth.middleware.auth_context import get_access_token

class PerUserClientMiddleware(Middleware):
    def __init__(self, gms_url: str) -> None:
        self._gms_url = gms_url.rstrip("/")

    async def on_message(self, context, call_next: CallNext):
        access_token = get_access_token()
        if access_token and access_token.claims.get("datahub_token"):
            user_client = DataHubClient(
                config=DatahubClientConfig(
                    server=self._gms_url,
                    token=access_token.claims["datahub_token"],
                    client_mode=ClientMode.SDK,
                ),
                datahub_component=f"mcp-server-datahub/{__version__}",
            )
            with with_datahub_client(user_client):
                return await call_next(context)
        return await call_next(context)
```

When no access token is present (STDIO transport, or auth disabled),
the middleware is a no-op and the existing service-account client is
used.

#### 3.4 Multi-auth fallback (OBO + PAT)

A single deployment can serve both Copilot-style clients (presenting an
Entra JWT) and script/CLI clients (presenting a DataHub PAT) by chaining
two `TokenVerifier`s — the `EntraOBOVerifier` first, with a
`DataHubTokenVerifier` (which calls GMS's `me` query) as the fallback.
FastMCP's multi-auth support picks the first verifier that returns a
non-`None` `AccessToken`; the OBO verifier rejects non-JWT tokens
cheaply (local signature check, no network call), so the PAT path does
not pay an OBO penalty.

#### 3.5 Security considerations

- JWKS keys are cached with TTL = 1 hour, refreshed on `kid` miss to handle
  key rotation without restart.
- Client secrets should be provisioned via a secret manager or Entra
  Managed Identity; the server never logs them.
- All auth failures log `sub`, `aud`, `tid`, `reason` — never the token
  itself.
- OBO-issued DataHub tokens are held only for the lifetime of a single
  request. They are not written to disk, not cached across requests, and not
  attached to any logging record.
- If OBO exchange fails, the server returns `401` — it does NOT fall back to
  the service account. Silent privilege escalation would be a security bug.

## How we teach this

### Naming

- "Code Mode" keeps FastMCP's upstream terminology so users who are already
  familiar with FastMCP's Code Mode transform recognise it immediately.
- "On-Behalf-Of" is the standard OAuth 2.0 / Microsoft Identity Platform
  term. We keep it even though it is Microsoft-flavoured, because there is
  no vendor-neutral industry term for this pattern and the MCP spec itself
  uses "token exchange" inconsistently.
- The concrete verifier class is named `EntraOBOVerifier`, not
  `AzureAuthProvider` or the like, because it is specifically the
  Entra + OBO composition. A future Okta implementation would be a
  sibling `OktaOBOVerifier` — also a direct `TokenVerifier` subclass,
  no shared abstract base in our code.

### Documentation

New sections in the MCP server README:

1. **Authentication** (rewritten): Service Account → DataHub PAT →
   OIDC/OBO → Multi-auth, in order of sophistication.
2. **Code Mode**: a one-page guide with a worked example and the sandbox
   limits table.
3. **Provider Reference**: one subsection per OIDC provider with the exact
   env vars. Starts with Entra; placeholders invite community PRs for Okta,
   Keycloak, etc.

DataHub's existing MCP feature guide
(`docs.datahub.com/docs/features/feature-guides/mcp`) gets two new links:
"Running behind an enterprise SSO" and "Reducing context usage with Code
Mode". Neither supersedes the existing stdio-mode quickstart.

### Audience

- **DataHub backend developers**: new in this RFC are the DI hook, the
  `AuthProvider` interface, and the error adapter. All three are small,
  well-contained, and do not touch GMS at all.
- **MCP server operators / platform teams**: this is the primary audience.
  They get Code Mode and OBO and need the new env-var matrix.
- **Agent authors / end users**: mostly unaffected — the tool surface is
  unchanged. Code Mode users see two meta-tools instead of twenty.
- **DataHub Cloud operations**: can evaluate whether to enable OBO in hosted
  deployments once the OSS path is proven.

## Drawbacks

- **Dependency surface grows.** MSAL and the Monty sandbox (optional) are
  new dependencies. MSAL in particular pulls in cryptography transitive
  deps. Mitigation: Code Mode is opt-in via an extras group; MSAL only loads
  if OIDC env vars are set.
- **FastMCP v3 is a major upgrade.** Some downstream forks or private
  plugins pinned to v2 will need to move. Mitigation: v3 is the active
  upstream branch and v2 is in maintenance; this is a delay, not a
  different direction.
- **Code Mode's sandbox is not a security boundary against malicious code
  the agent chooses to run.** It is a resource boundary: CPU/memory/time,
  not a confinement from, e.g., data exfiltration through legitimate
  DataHub calls. Operators enabling Code Mode need to understand this.
- **The first OIDC provider is Entra-only.** Until at least one additional
  provider lands, there is a risk the abstraction calcifies around Entra's
  quirks. Mitigation: we sketched the Okta provider while designing the
  interface to validate it generalises; the interface avoids MSAL-specific
  types.
- **More env vars.** The configuration matrix roughly doubles. Mitigation:
  everything defaults off; a PAT-only deployment is unchanged.

## Alternatives

### Process alternative — maintain a long-lived fork

Not shipping these features upstream is **not** an alternative from our
side: we need OIDC OBO and Code Mode in our DataHub MCP deployment, so
the work exists either way. The real process-level alternative is
whether the work lives upstream or in our fork.

- **Upstream (this RFC).** Everyone benefits from Code Mode and the
  `OIDCOboProvider` abstraction. Future OIDC providers (Okta, Keycloak,
  …) can plug in without touching the core. We stop carrying a fork.
- **Stay on a long-lived fork of `acryldata/mcp-server-datahub`.** We
  keep our 10-commit lead, rebase on upstream releases, and diverge
  further over time. This is what we are doing today. It works, but it
  means the community never gets Code Mode or OIDC OBO from us, and we
  pay a rebase cost on every upstream release. We would rather not.

This RFC therefore exists primarily to validate the design with upstream
maintainers, not to justify the features themselves — those are already
decided on our side.

### Technical alternative to OIDC OBO — pass-through user PATs

Instead of validating an OIDC token and exchanging it for a DataHub token
via OBO, we could require every end user to create a personal DataHub PAT
and configure their MCP client to send it as the bearer token. The MCP
server would forward this token verbatim to DataHub.

- **Pros.** No OIDC integration code, no MSAL dependency, no token
  exchange. The MCP server stays close to what it is today.
- **Cons.** Terrible UX for our users: every user has to log in to
  DataHub, generate a PAT, copy it into their agent client, and rotate
  it manually. That is exactly the SSO bypass we are trying to avoid —
  the user already has a valid Entra token through their normal
  corporate login; forcing them to also manage a DataHub PAT negates
  the single-sign-on experience and adds a per-user credential store to
  operate. Rejected on UX grounds, not technical ones.
- **Variant: user PAT configured once on the server** (the status quo
  service-account model). Fails the audit and per-user-policy
  requirements — every mutation is attributed to the service account.

### Instead of FastMCP v3

- **Stay on v2 and patch.** Rejected: the primitives we need for OBO
  (per-request DI, multi-auth) and Code Mode (the `CodeMode` transform)
  do not exist in v2 and are not going to be backported. Patching v2
  would mean reimplementing both upstream.
- **Write our own MCP server framework.** Rejected: reinvents the wheel,
  and the MCP spec is still evolving — tracking it ourselves is
  expensive.

## Rollout / Adoption Strategy

### Release plan

1. **0.7.0 — FastMCP v3 upgrade.** Mechanical upgrade, adoption of v3
   idioms, no behaviour change visible to agents. Released first, shipped
   independently so we can catch v3 regressions in isolation from the
   auth/Code Mode changes.
2. **0.8.0 — OIDC OBO provider (Entra).** Additive. Default behaviour
   unchanged (no env vars set → pure PAT). Operators opt in by setting
   `DATAHUB_MCP_AUTH_ENABLED=true` and the Entra env vars.
3. **0.9.0 — Code Mode.** Opt-in via `--code-mode` flag. Optional
   dependency group.

Each release ships with the previous release's deployment guide still
valid. There is no flag day.

### Migration notes

- **Existing stdio users:** no change. They do not see any new env vars.
- **Existing HTTP-transport users with a service-account PAT:** no change.
  They run 0.7.0 with zero config changes.
- **New HTTP deployments that want OBO:** set the four Entra env vars and
  flip `DATAHUB_MCP_AUTH_ENABLED=true`. Multi-auth ensures a botched OBO
  config falls back to PAT rather than breaking the deployment, as long as
  a PAT is configured.
- **Code Mode users:** install with `pip install "mcp-server-datahub[code-mode]"`
  and pass `--code-mode`.

### Backwards compatibility

- MCP tool names, parameters, and response shapes are unchanged.
- Environment variables are all additive; none are renamed or removed.
- CLI: one new flag (`--code-mode`). Existing `--transport` and `--debug`
  flags are unchanged.
- Python API (for embedders): the DI hook is additive. Embedders that
  previously set a module-level client can keep doing so; the fallback path
  preserves that behaviour.

## Future Work

- **Additional OIDC providers:** Okta, Keycloak, Auth0, Google. Each ~100
  LOC of provider-specific code behind the `OIDCOboProvider` interface.
- **Per-user quota / rate limiting** integrated with the OIDC `sub` claim,
  once OBO is in place and we have a stable identity to key on.
- **Streaming tool results** using FastMCP v3's streaming primitives, for
  long-running lineage traversals.
- **Code Mode recipes resource** — publish vetted snippets (top-N popular
  datasets, impact analysis for a column change, etc.) as MCP resources so
  agents can paste a known-good snippet instead of synthesising from
  scratch. Improves reliability for common questions.
- **Token exchange cache** (distributed, Redis-backed) if OBO exchange
  latency becomes a bottleneck at scale.
- **Generalised audit trail** emitting per-request user identity to
  DataHub's platform event stream, so that DataHub's existing audit UI
  shows MCP-originated mutations alongside UI/API ones.

## Unresolved questions

- **Where should the `OIDCOboProvider` interface live?** In this server
  (`_auth/base.py`), or upstreamed into FastMCP itself as a generic
  contribution? The latter benefits the whole MCP ecosystem but adds a
  FastMCP PR to the critical path.
- **Should Code Mode be the default once it stabilises?** Making it the
  default would maximise the context-usage win, but it changes the
  observable tool surface for every agent. Likely answer: no, keep it
  opt-in for the 0.x series and reassess for 1.0.
- **JWKS caching TTL and refresh semantics.** 1 hour is a reasonable
  default, but operators in high-rotation environments may want this
  configurable. Needs field data.
- **What happens when the service-account fallback is unavailable and
  OBO fails?** Current design: return 401. Alternative: return a structured
  `ToolError` describing the misconfiguration. The former is standards-
  compliant, the latter is friendlier to debugging. Probably both, gated on
  whether the failure is auth-time or config-time.
- **Sandbox language surface.** Monty is a Python subset; some standard
  library idioms (e.g., `dataclasses`, `itertools.groupby`) may or may not
  be available. We need an explicit allowlist published as part of the
  Code Mode docs so agents don't waste cycles on unsupported imports.
