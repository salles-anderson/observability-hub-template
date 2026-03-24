"""
Teck Observability Assistant — Chainlit Chat UI (Sprint 9A)

Conversational interface for the Teck Observability Hub.
Connects to Claude Agent SDK + mcp-grafana to answer
natural language questions with real observability data.
"""

# ---------------------------------------------------------------------------
# Workaround: Chainlit OAuth state parameter bug — the generated token can
# contain '^' which breaks the OAuth flow. Patch before importing chainlit.
# ---------------------------------------------------------------------------
import secrets as _secrets

_original_token_urlsafe = _secrets.token_urlsafe


def _patched_token_urlsafe(nbytes=None):
    token = _original_token_urlsafe(nbytes)
    return token.replace("^", "")


_secrets.token_urlsafe = _patched_token_urlsafe

import json
import os
import logging

import bcrypt
import boto3
import chainlit as cl

from agent import run_chat_query

logger = logging.getLogger("chainlit-app")
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(name)s %(levelname)s %(message)s",
)

# ---------------------------------------------------------------------------
# Users — loaded from SSM Parameter Store (SecureString, KMS encrypted)
# Format in SSM: JSON object
# {
#   "anderson.sales": {"hash": "$2b$12$...", "name": "Anderson Sales", "role": "admin"},
#   "fulano.silva": {"hash": "$2b$12$...", "name": "Fulano Silva", "role": "user"}
# }
#
# Generate hash:
#   python -c "import bcrypt; print(bcrypt.hashpw(b'SuaSenha123', bcrypt.gensalt()).decode())"
#
# Update users (AWS CLI):
#   aws ssm put-parameter --name /obs-hub-prod/chainlit/users \
#     --type SecureString --overwrite --value '{"anderson.sales": {...}}'
# ---------------------------------------------------------------------------
USERS_SSM_PARAM = os.environ.get(
    "USERS_SSM_PARAM", "/obs-hub-prod/chainlit/users"
)


def _load_users() -> dict[str, dict]:
    """Load user registry from SSM Parameter Store."""
    try:
        ssm = boto3.client("ssm", region_name=os.environ.get("AWS_REGION", "us-east-1"))
        resp = ssm.get_parameter(Name=USERS_SSM_PARAM, WithDecryption=True)
        users = json.loads(resp["Parameter"]["Value"])
        logger.info(f"Loaded {len(users)} users from SSM ({USERS_SSM_PARAM})")
        return users
    except Exception as e:
        logger.error(f"Failed to load users from SSM: {e}")
        return {}


USERS = _load_users()

WELCOME_MESSAGE = """
## Bem-vindo ao Assistente AI Teck

Eu sou seu assistente inteligente — posso ajudar com **qualquer assunto tecnico**:
programacao, DevOps, SRE, FinOps, seguranca, arquitetura e muito mais.

Alem disso, tenho **acesso direto ao Grafana** para consultar metricas, logs e traces em tempo real.

### Exemplos de perguntas:

| Categoria | Pergunta |
|-----------|----------|
| **Observabilidade** | Qual a latencia p95 do example-api? |
| **Logs** | Mostre os logs de erro dos ultimos 30 minutos |
| **SRE** | Quanto do error budget foi consumido? |
| **Coding** | Como criar um endpoint REST no NestJS com validacao? |
| **Laravel** | Como configurar Queue com SQS no Laravel? |
| **DevOps** | Como configurar um pipeline CI/CD no GitHub Actions? |
| **AWS** | Como otimizar custos de ECS Fargate? |
| **Seguranca** | Como configurar IAM least privilege para ECS? |
| **Conceitos** | O que e um service mesh e quando usar? |

Faca sua pergunta abaixo!
"""


# ---------------------------------------------------------------------------
# Auth
# ---------------------------------------------------------------------------
@cl.password_auth_callback
async def auth_user(username: str, password: str):
    """Validate user credentials against bcrypt hashes from SSM."""
    user_data = USERS.get(username)
    if not user_data:
        return None

    stored_hash = user_data.get("hash", "")
    if not stored_hash:
        return None

    try:
        if bcrypt.checkpw(password.encode("utf-8"), stored_hash.encode("utf-8")):
            return cl.User(
                identifier=username,
                metadata={
                    "name": user_data.get("name", username),
                    "role": user_data.get("role", "user"),
                },
            )
    except Exception as e:
        logger.error(f"Auth error for {username}: {e}")

    return None


@cl.oauth_callback
async def oauth_callback(
    provider_id: str, token: str, raw_user_data: dict, default_user: cl.User
):
    """Handle Cognito OAuth callback — extract user info and role from OIDC claims."""
    if provider_id == "aws-cognito":
        # Extract role from Cognito groups (first group = role)
        groups = raw_user_data.get("cognito:groups", [])
        role = groups[0] if groups else "dev"
        return cl.User(
            identifier=raw_user_data.get("email", default_user.identifier),
            metadata={
                "name": raw_user_data.get("name", raw_user_data.get("email", "")),
                "role": role,
                "provider": "cognito",
            },
        )
    return None


# ---------------------------------------------------------------------------
# Chat lifecycle
# ---------------------------------------------------------------------------
@cl.on_chat_start
async def on_chat_start():
    """Send welcome message and initialize session."""
    # Semantic cache — create collection in background (never blocks chat)
    try:
        import asyncio
        import semantic_cache
        asyncio.create_task(semantic_cache.ensure_collection())
    except Exception as e:
        logger.warning(f"Semantic cache init: {e}")
    user = cl.user_session.get("user")
    name = user.metadata.get("name", user.identifier) if user else "Usuario"

    cl.user_session.set("history", [])

    await cl.Message(content=f"Ola, **{name}**!\n{WELCOME_MESSAGE}").send()


@cl.on_message
async def on_message(message: cl.Message):
    """Process user message: call Agent SDK with MCP and stream response."""
    history = cl.user_session.get("history", [])

    # Add user message to history
    history.append({"role": "user", "content": message.content})

    # Create response message for streaming
    msg = cl.Message(content="")
    await msg.send()

    # Get user role for RBAC guardrails
    user = cl.user_session.get("user")
    role = user.metadata.get("role", "dev") if user else "dev"

    # Stream response from Agent with guardrails
    full_response = ""
    async for chunk in run_chat_query(message.content, history=history, role=role):
        await msg.stream_token(chunk)
        full_response += chunk

    await msg.update()

    # Add assistant response to history
    history.append({"role": "assistant", "content": full_response})

    # Keep only last 20 messages in session
    if len(history) > 20:
        history = history[-20:]
    cl.user_session.set("history", history)


# ---------------------------------------------------------------------------
# AG-3: Proactive Alert Investigation (webhook endpoint)
# ---------------------------------------------------------------------------
if os.environ.get("ENABLE_ALERT_INVESTIGATION", "false").lower() == "true":
    from starlette.routing import Route
    from alert_investigator import handle_alert_webhook, health_ag3

    cl.server.app.routes.insert(
        0, Route("/api/alert-investigate", handle_alert_webhook, methods=["POST"])
    )
    cl.server.app.routes.insert(
        0, Route("/api/alert-investigate/health", health_ag3, methods=["GET"])
    )
    logger.info("AG-3: Alert investigation endpoint enabled at /api/alert-investigate")
