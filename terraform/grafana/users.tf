# -----------------------------------------------------------------------------
# Grafana Users
# -----------------------------------------------------------------------------
# Users are managed via Grafana Admin API (basic auth), NOT Terraform.
#
# Reason: grafana provider v3.25.9 has a bug with grafana_user resource
# that causes "TextConsumer" parse errors. Users created successfully
# via API but provider fails to read the response.
#
# Current users are created via:
#   curl -X POST -u "admin:PASSWORD" \
#     -H "Content-Type: application/json" \
#     "$GRAFANA_URL/api/admin/users" \
#     -d '{"name":"...","login":"...","email":"...","password":"..."}'
#
# Team membership via:
#   curl -X POST -u "admin:PASSWORD" \
#     -H "Content-Type: application/json" \
#     "$GRAFANA_URL/api/teams/TEAM_ID/members" \
#     -d '{"userId": USER_ID}'
#
# TODO: Re-enable grafana_user resource when provider fixes the bug
# or migrate to Cognito OAuth SSO (eliminates local user management)
# -----------------------------------------------------------------------------
