"""
AWS Account Resolver — 11 contas YOUR_ORG + externas.

Moved from account_resolver.py to core/ for AG-2 package organization.

Maps keywords, aliases and account IDs to account metadata.
Used by the orchestrator to resolve user queries like
"example-api" -> Dev account (YOUR_DEV_ACCOUNT_ID).
"""

import json
import os

# ---------------------------------------------------------------------------
# Account registry (11 contas)
# ---------------------------------------------------------------------------
ACCOUNTS: dict[str, dict] = {
    "YOUR_HUB_ACCOUNT_ID": {
        "name": "Observability Hub",
        "alias": "hub",
        "org": "YOUR_ORG",
        "keywords": ["hub", "observability", "obs", "obs-hub", "monitoramento"],
    },
    "YOUR_DEV_ACCOUNT_ID": {
        "name": "YOUR_ORG-Dev",
        "alias": "dev",
        "org": "YOUR_ORG",
        "keywords": ["dev", "desenvolvimento", "example-api-dev", "solis-dev", "frontconsig-dev"],
    },
    "YOUR_PRD_ACCOUNT_ID": {
        "name": "YOUR_ORG-Prod",
        "alias": "prod",
        "org": "YOUR_ORG",
        "keywords": ["prod", "producao", "example-api", "solis", "frontconsig"],
    },
    "YOUR_HML_ACCOUNT_ID": {
        "name": "YOUR_ORG-Homolog",
        "alias": "homolog",
        "org": "YOUR_ORG",
        "keywords": ["homolog", "hml", "homologacao", "staging"],
    },
    "YOUR_CAPITAL_ACCOUNT_ID": {
        "name": "Capital",
        "alias": "capital",
        "org": "YOUR_ORG",
        "keywords": ["capital", "capitalconsig"],
    },
    "131602690665": {
        "name": "HubDigital",
        "alias": "hubdigital",
        "org": "YOUR_ORG",
        "keywords": ["hubdigital", "hub-digital", "hub digital"],
    },
    "195835301200": {
        "name": "Admin",
        "alias": "admin",
        "org": "YOUR_ORG",
        "keywords": ["admin", "administracao"],
    },
    "YOUR_INFRA_ACCOUNT_ID": {
        "name": "Infra/Kong",
        "alias": "infra",
        "org": "YOUR_ORG",
        "keywords": ["infra", "kong", "gateway", "api-gateway"],
    },
    "823557601977": {
        "name": "CloudTrail",
        "alias": "cloudtrail",
        "org": "YOUR_ORG",
        "keywords": ["cloudtrail", "audit", "trilha"],
    },
    "381491855323": {
        "name": "ABC Card",
        "alias": "abc",
        "org": "Externa",
        "keywords": ["abc", "abc-card", "abccard", "unico"],
    },
    "YOUR_AKRK_ACCOUNT_ID": {
        "name": "akrk-dev",
        "alias": "akrk",
        "org": "Externa",
        "keywords": ["akrk", "akrk-dev"],
    },
}

HUB_ACCOUNT_ID = "YOUR_HUB_ACCOUNT_ID"

# Spoke accounts loaded from env (Terraform injects this)
_spoke_ids: list[str] = []
_raw = os.environ.get("SPOKE_ACCOUNT_IDS", "")
if _raw:
    try:
        _spoke_ids = json.loads(_raw)
    except json.JSONDecodeError:
        _spoke_ids = [s.strip() for s in _raw.split(",") if s.strip()]

SPOKE_ROLE_NAME = os.environ.get("SPOKE_ROLE_NAME", "obs-hub-readonly")
CROSS_ACCOUNT_EXTERNAL_ID = os.environ.get(
    "CROSS_ACCOUNT_EXTERNAL_ID", "teck-observability-hub-2024"
)


def resolve_account(text: str) -> str | None:
    """Resolve a keyword/alias/account_id to an account ID."""
    text_lower = text.strip().lower()

    if text_lower in ACCOUNTS:
        return text_lower

    for account_id, meta in ACCOUNTS.items():
        if text_lower == meta["alias"]:
            return account_id
        if text_lower in meta["keywords"]:
            return account_id

    return None


def get_account_name(account_id: str) -> str:
    """Return human-readable account name."""
    meta = ACCOUNTS.get(account_id)
    return meta["name"] if meta else f"Unknown ({account_id})"


def is_spoke_account(account_id: str) -> bool:
    """Check if account_id is a spoke account (not Hub)."""
    return account_id != HUB_ACCOUNT_ID and account_id in ACCOUNTS


def list_accounts() -> str:
    """Return markdown table of all 11 accounts."""
    lines = ["| Account ID | Nome | Alias | Org |", "|---|---|---|---|"]
    for aid, meta in ACCOUNTS.items():
        marker = " (Hub)" if aid == HUB_ACCOUNT_ID else ""
        lines.append(
            f"| {aid} | {meta['name']}{marker} | {meta['alias']} | {meta['org']} |"
        )
    return "\n".join(lines)
