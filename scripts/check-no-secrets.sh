#!/usr/bin/env bash
# Gate de sanitizacao do template publico.
#
# Este repositorio espelha uma plataforma real. Ele NAO pode conter identificadores
# da organizacao de origem. Rode antes de todo commit:
#     ./scripts/check-no-secrets.sh
#
# Sai 1 se achar qualquer dado real, e sai 1 tambem se nao conseguir varrer.
# Um gate que aprova por ausencia de resposta e pior que nenhum gate.
set -uo pipefail

cd "$(dirname "$0")/.." || { echo "FALHA: nao consegui entrar na raiz do repo"; exit 1; }
[ -d .git ] || { echo "FALHA: raiz do repo nao encontrada (sem .git)"; exit 1; }

falhas=0
relata() { echo "FALHA [$1]"; shift; printf '   %s\n' "$@"; falhas=$((falhas + 1)); }

# Placeholders aceitos. Qualquer outro numero de 12 digitos e suspeito.
PLACEHOLDERS='111111111111|222222222222|333333333333|444444444444|555555555555|666666666666|777777777777|888888888888|999999999999|121212121212|131313131313|141414141414|123456789012|000000000000'

alvos=$(git ls-files) || { echo "FALHA: git ls-files nao funcionou"; exit 1; }
[ -n "$alvos" ] || { echo "FALHA: nenhum arquivo versionado encontrado"; exit 1; }

# 1) AWS account IDs que nao sejam placeholder
achados=$(echo "$alvos" | xargs grep -EohI '\b[0-9]{12}\b' 2>/dev/null | sort -u | grep -Ev "^($PLACEHOLDERS)$" || true)
[ -n "$achados" ] && relata "account id real" $achados

# 2) IDs de recurso AWS. Placeholder = digito/letra repetidos (ex: 0a1a1a1a...).
recursos=$(echo "$alvos" | xargs grep -EohI '\b(vpc|subnet|sg|tgw|tgw-attach|tgw-rtb|rtb|eni|ami|eipalloc|nat|igw|fs|fsap|pcx|acl)-[0-9a-f]{8,17}\b' 2>/dev/null | sort -u || true)
for r in $recursos; do
  sufixo="${r##*-}"
  # heuristica: placeholder tem no maximo 4 caracteres distintos no sufixo
  distintos=$(echo "$sufixo" | fold -w1 | sort -u | wc -l)
  [ "$distintos" -gt 4 ] && relata "id de recurso real" "$r"
done

# 3) Dominios e e-mails da organizacao de origem
dominios=$(echo "$alvos" | xargs grep -EohI '[a-z0-9.-]+\.(com\.br|com)\b' 2>/dev/null | sort -u \
  | grep -Evf <(cat <<'ALLOW'
# placeholders do proprio template
yourorg\.com\.br$
yourorg\.com$
yourdomain\.com$
example\.com$
exemplo\.com$
example-api\.com\.br$
sua-api\.com$
# provedores e servicos externos, legitimos numa doc de plataforma
github\.com$
amazonaws\.com$
amazoncognito\.com$
amazon\.com$
google\.com$
slack\.com$
deepseek\.com$
anthropic\.com$
grafana\.com$
docker\.com$
hashicorp\.com$
terraform\.io$
fluentbit\.io$
cncf\.io$
opentelemetry\.io$
shields\.io$
ALLOW
) || true)
[ -n "$dominios" ] && relata "dominio suspeito" $dominios

# 4) Credenciais obvias
creds=$(echo "$alvos" | xargs grep -EohI '(AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|ghp_[0-9A-Za-z]{36}|glpat-[0-9A-Za-z_-]{20}|xox[baprs]-[0-9A-Za-z-]{10,})' 2>/dev/null | sort -u || true)
[ -n "$creds" ] && relata "credencial" $creds

# 5) Termos proibidos definidos por quem mantem o fork.
#    Este script NAO carrega o nome de nenhuma organizacao: se carregasse, o proprio
#    gate viraria o vazamento que ele tenta impedir. Coloque um termo por linha em
#    .sanitize-denylist (arquivo ignorado pelo git) com o nome da sua empresa,
#    codinomes de cliente, dominios internos, o que for.
DENY=".sanitize-denylist"
if [ -f "$DENY" ]; then
  while IFS= read -r termo; do
    [ -z "$termo" ] && continue
    case "$termo" in \#*) continue;; esac
    hits=$(echo "$alvos" | xargs grep -lFiI -- "$termo" 2>/dev/null | grep -v "^$DENY$" || true)
    [ -n "$hits" ] && relata "termo proibido: $termo" $hits
  done < "$DENY"
else
  echo "AVISO: $DENY nao existe. Crie-o com os termos da sua organizacao;"
  echo "       sem ele este gate nao tem como saber o que e nome interno seu."
fi

zonas=$(echo "$alvos" | xargs grep -EohI '\bZ[A-Z0-9]{12,21}\b' 2>/dev/null | sort -u | grep -v 'EXAMPLE' || true)
[ -n "$zonas" ] && relata "route53 hosted zone id" $zonas

if [ "$falhas" -gt 0 ]; then
  echo
  echo "REPROVADO: $falhas categoria(s) com dado real. Nao commite."
  exit 1
fi
echo "OK: $(echo "$alvos" | wc -l) arquivos varridos, nenhum identificador real encontrado."
