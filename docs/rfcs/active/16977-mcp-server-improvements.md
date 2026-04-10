- Start Date: 2026-04-10
- RFC PR: https://github.com/datahub-project/datahub/pull/16977
- Discussion Issue: (TBD)
- Implementation PR(s): (leave empty)

# MCP Server Improvements: FastMCP v3, Code Mode, and Enterprise SSO

## Summary

Three coordinated improvements to `acryldata/mcp-server-datahub` to make it
production-ready for enterprise deployments of DataHub MCP behind AI clients
(Claude Code, GitHub Copilot, Copilot Studio, Cursor, …):

1. **Upgrade the server from FastMCP v2 to FastMCP v3** and adopt the idiomatic
   patterns that come with v3 — `ToolError`, dependency injection, per-tool
   timeouts, MCP resources for catalog metadata, strict input validation,
   duplicate-tool detection.
2. **Add a Code Mode transport** built on FastMCP v3's experimental `CodeMode`
   transform. Instead of exposing every tool in the MCP tool list, the server
   exposes two meta-tools — `search_tools` and `execute` — and the agent
   composes short Python snippets that run inside a Monty sandbox. This
   dramatically reduces tool-catalog context bloat and lets agents chain
   multiple DataHub calls in a single sandboxed execution.
3. **Add an OpenID Connect On-Behalf-Of (OBO) authentication provider** so
   that the MCP server can accept OIDC tokens from a calling AI client,
   exchange them for DataHub-scoped tokens, and create per-user DataHub
   clients. The first provider implementation targets Microsoft Entra ID
   (since that is what our users authenticate against today), but the
   abstractions are designed so that additional OIDC providers (Okta, Keycloak,
   Google, Auth0, …) can be plugged in without touching the core server.

A working implementation of all three changes already exists at
[`manuschillerdev/mcp-server-datahub`](https://github.com/manuschillerdev/mcp-server-datahub)
(10 commits ahead of `acryldata/mcp-server-datahub:main`). This RFC proposes
upstreaming it.

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

- An `AuthProvider` abstraction MUST exist so that OIDC providers other than
  Entra ID can be added without touching the server core. The initial
  implementation only ships an Entra provider; the abstraction is the
  extensibility point.
- The provider MUST validate incoming JWTs fully: signature against JWKS,
  issuer, audience, expiry, and optionally `required_scopes`.
- JWKS MUST be cached with a reasonable TTL and refreshed on kid-miss.
- The provider MUST support the OAuth 2.0 On-Behalf-Of flow (RFC 8693 token
  exchange in spirit; MSAL in practice for Entra).
- Multi-auth MUST be supported: if OIDC/OBO is configured and the incoming
  bearer token is not a valid JWT, the server MUST fall back to DataHub PAT
  verification. This is what allows one deployment to serve both Copilot
  clients and CLI/script clients.
- When `MCP_SERVER_BASE_URL` is set, the server MUST publish
  `/.well-known/oauth-protected-resource` per the MCP auth discovery spec.
- When no OIDC env vars are set, the server MUST behave exactly as it does
  today — this is a pure additive change for existing deployments.
- STDIO transport is out of scope: it continues to use the service-account
  client unconditionally, since there is no HTTP request to attach a token to.

### Extensibility

- The `AuthProvider` interface is the primary extension point. Expected
  near-future providers: Okta, Keycloak, Google, Auth0. Each is ~100 LOC of
  provider-specific code (JWKS URL, token-exchange call) and zero changes to
  the server core.
- Code Mode's sandbox is extensible via FastMCP's `CodeMode` transform — as
  new DataHub tools are added, they automatically appear inside the sandbox
  without additional wiring.

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

#### 3.1 Provider interface

```python
# _auth/base.py
class OIDCOboProvider(TokenVerifier):
    """Validate an incoming OIDC JWT and exchange it for a DataHub token."""

    async def verify_token(self, token: str) -> AccessToken | None:
        claims = await self._validate_jwt(token)
        if claims is None:
            return None
        datahub_token = await self._exchange_obo(token, claims)
        return AccessToken(
            token=token,
            client_id=claims["aud"],
            scopes=claims.get("scp", "").split(),
            claims={**claims, "datahub_token": datahub_token},
        )

    async def _validate_jwt(self, token: str) -> dict | None: ...
    async def _exchange_obo(self, token: str, claims: dict) -> str: ...

    def well_known_metadata(self) -> dict | None:
        """Return .well-known/oauth-protected-resource payload, or None."""
```

Concrete providers subclass this and implement `_validate_jwt` and
`_exchange_obo`. JWKS caching, `.well-known` discovery, and the
`PerUserClientMiddleware` wiring live in the base class.

#### 3.2 Entra ID provider

```python
# _auth/entra.py
class EntraOboProvider(OIDCOboProvider):
    def __init__(self, config: EntraConfig):
        self._jwt_verifier = AzureJWTVerifier(
            tenant_id=config.tenant_id,
            audience=config.client_id,
            required_scopes=config.required_scopes,
        )
        self._msal = msal.ConfidentialClientApplication(
            client_id=config.client_id,
            client_credential=config.client_secret,
            authority=f"https://login.microsoftonline.com/{config.tenant_id}",
        )
        self._datahub_scope = config.datahub_scope

    async def _validate_jwt(self, token: str) -> dict | None:
        return await self._jwt_verifier.verify(token)

    async def _exchange_obo(self, token: str, claims: dict) -> str:
        result = await asyncio.to_thread(
            self._msal.acquire_token_on_behalf_of,
            user_assertion=token,
            scopes=[self._datahub_scope],
        )
        if "access_token" not in result:
            raise ToolError(
                f"OBO exchange failed: {result.get('error_description')}",
                code="obo_failure",
            )
        return result["access_token"]
```

Configured via the environment variables listed in the README sketch above.

#### 3.3 Middleware

```python
# _auth/middleware.py
class PerUserClientMiddleware:
    async def __call__(self, request, call_next):
        token = request.state.access_token  # set by FastMCP auth layer
        if token is not None and "datahub_token" in token.claims:
            request.state.datahub_client = DataHubGraph(
                config=DatahubClientConfig(
                    server=_GMS_URL,
                    token=token.claims["datahub_token"],
                ),
            )
        else:
            request.state.datahub_client = None  # falls back to service account
        return await call_next(request)
```

The DI provider `get_datahub_client()` from §1.2 reads this.

#### 3.4 Multi-auth fallback

```python
auth = MultiAuth(
    providers=[
        EntraOboProvider(entra_config),          # tries JWT first
        DataHubPatVerifier(gms_url=_GMS_URL),    # falls back to PAT
    ],
    # fail_fast=False — a non-JWT token is not an error, it's a PAT attempt
)
mcp = FastMCP("datahub", auth=auth)
```

The OBO provider rejects non-JWTs cheaply (no network call), so the PAT
path does not pay an OBO penalty.

#### 3.5 `.well-known/oauth-protected-resource`

When `MCP_SERVER_BASE_URL` is set, FastMCP's `RemoteAuthProvider` wrapper
serves the discovery document, e.g.:

```json
{
  "resource": "https://mcp.example.com",
  "authorization_servers": ["https://login.microsoftonline.com/<tenant>/v2.0"],
  "bearer_methods_supported": ["header"],
  "scopes_supported": ["api://<datahub-app-id>/.default"]
}
```

This is what lets GitHub Copilot auto-discover the auth server for the MCP
server URL the user typed in.

#### 3.6 Security considerations

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
- The generic interface is named `OIDCOboProvider`, not `AzureAuthProvider`.
  The Entra-specific class is `EntraOboProvider`. A future Okta
  implementation would be `OktaOboProvider`, reusing the same base.

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

### Instead of FastMCP v3

- **Stay on v2 and patch.** Rejected: every local workaround we have is
  already something v3 solves upstream, and v2 is no longer actively
  developed. Patching is a dead-end road.
- **Write our own MCP server framework.** Rejected: reinvents the wheel,
  and the MCP spec is still evolving — tracking it ourselves is expensive.

### Instead of Code Mode

- **Tool sharding by env var** (`TOOLS_IS_LINEAGE_ENABLED=true` etc.,
  already partially in the tree). Reduces the catalog but forces the
  operator to pick which tools the agent can use and fragments
  configuration across deployments. Code Mode lets the agent pick
  per-question.
- **Compressing tool descriptions / using MCP resources for docs.** Helps
  (and we do this in #1.5), but the structural savings are O(30%), not the
  O(90%) that Code Mode delivers.
- **Anthropic's Agent SDK "computer use" style."** Different problem — that
  targets arbitrary desktop automation, not metadata querying. Overkill for
  DataHub.

### Instead of OIDC OBO

- **Always use a service-account PAT.** The status quo. Fails the audit and
  fine-grained-policy requirements outlined in Motivation.
- **Ask users to provide a DataHub PAT alongside their SSO login.** Poor
  UX, doubles credential management, defeats SSO.
- **Proxy auth through DataHub's existing frontend session.** DataHub's
  session cookie is not reachable from an MCP client running inside an
  agent environment; cross-origin and cookie-jar constraints make this
  impractical.
- **SAML.** Out of step with where MCP clients are going — Copilot, Claude,
  Cursor all speak OIDC.

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
