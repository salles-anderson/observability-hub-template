# =============================================================================
# Grafana Customizado - Teck Solucoes
# =============================================================================
# Build: docker build -t grafana-teck:11.4.0 .
# =============================================================================

ARG GRAFANA_VERSION=11.4.0
FROM grafana/grafana:${GRAFANA_VERSION}

# -----------------------------------------------------------------------------
# Metadata
# -----------------------------------------------------------------------------
LABEL maintainer="DevOps <devops@tecksolucoes.com.br>"
LABEL description="Grafana customizado com branding Teck Solucoes"

# Switch to root for modifications
USER root

# -----------------------------------------------------------------------------
# Copiar assets customizados
# -----------------------------------------------------------------------------
# Logo SVG (fallback - substitui o icone padrao do Grafana)
COPY img/teck-logo.svg /usr/share/grafana/public/img/grafana_icon.svg

# Logos PNG oficiais da Teck Solucoes
COPY img/teck-logo-white.png /usr/share/grafana/public/img/teck-logo-white.png
COPY img/teck-logo-color.png /usr/share/grafana/public/img/teck-logo-color.png

# Favicon customizado (logo colorido)
COPY img/teck-logo-color.png /usr/share/grafana/public/img/fav32.png
COPY img/teck-logo-color.png /usr/share/grafana/public/img/apple-touch-icon.png

# CSS Customizado
COPY css/teck-theme.css /usr/share/grafana/public/css/teck-theme.css

# Injetar CSS no arquivo principal do dark theme
RUN MAIN_CSS=$(find /usr/share/grafana/public/build -name "grafana.dark.*.css" | head -1) && \
    if [ -n "$MAIN_CSS" ]; then \
        cat /usr/share/grafana/public/css/teck-theme.css >> "$MAIN_CSS"; \
    fi

# -----------------------------------------------------------------------------
# Configuracoes de branding via grafana.ini
# -----------------------------------------------------------------------------
COPY grafana-custom.ini /etc/grafana/grafana-custom.ini
RUN cat /etc/grafana/grafana-custom.ini >> /etc/grafana/grafana.ini

# Fix permissions
RUN chown -R grafana:root /usr/share/grafana/public/img/ && \
    chown grafana:root /etc/grafana/grafana.ini

# Switch back to grafana user
USER grafana

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD wget -q --spider http://localhost:3000/api/health || exit 1

EXPOSE 3000
