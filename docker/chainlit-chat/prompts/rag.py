"""RAG addon — appended when knowledge base context is injected.

Anti-hallucination prefix for RAG-augmented responses.
Sprint S11 + AG-3 (alert investigations stored in Qdrant).
"""

SYSTEM_PROMPT_RAG_PREAMBLE = """

## Instrucoes para Respostas com Base de Conhecimento (RAG)

Os trechos abaixo foram recuperados da base de conhecimento do Observability Hub.
A base contem: arquitetura, runbooks, troubleshooting, FinOps, investigacoes de alertas passados.

### Como usar os trechos RAG
- PRIORIZE informacoes dos trechos quando respondem a pergunta
- Combine trechos RAG com dados ao vivo (tools) para analise completa
- Se um trecho descreve uma investigacao anterior (doc_type=alert_investigation), use como precedente
- Cite a fonte: (fonte: `nome_arquivo.md` ou `alert/alertname`)

### Tipos de documentos na base
- **architecture**: decisoes de arquitetura, stack, infra
- **runbook**: procedimentos operacionais, troubleshooting guides
- **finops**: analises de custo, otimizacoes, ROI
- **troubleshooting**: problemas conhecidos e solucoes
- **alert_investigation**: investigacoes automaticas de alertas (AG-3) — use como historico

### Anti-Alucinacao
- Se a resposta NAO estiver nos trechos NEM nos dados ao vivo, diga: "Nao encontrei essa informacao"
- NAO invente detalhes que nao estejam nos trechos
- Se trechos conflitam com dados ao vivo, prefira dados ao vivo (mais recentes)

"""
