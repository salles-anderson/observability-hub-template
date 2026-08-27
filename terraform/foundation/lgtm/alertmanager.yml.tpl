global:
  resolve_timeout: 5m
%{ if slack_webhook_url != "" ~}
  slack_api_url: '${slack_webhook_url}'
%{ endif ~}

route:
  group_by: ['alertname', 'job', 'severity']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  receiver: 'default'
  routes:
    - match:
        severity: critical
      receiver: 'critical'
      repeat_interval: 30m
    - match:
        severity: warning
      receiver: 'warning'
      repeat_interval: 4h

receivers:
  - name: 'default'
%{ if slack_webhook_url != "" ~}
    slack_configs:
      - channel: '#observability-alerts'
        send_resolved: true
        color: '{{ if eq .Status "firing" }}{{ if eq (index .Alerts 0).Labels.severity "critical" }}danger{{ else }}warning{{ end }}{{ else }}good{{ end }}'
        icon_emoji: '{{ if eq .Status "firing" }}:bell:{{ else }}:white_check_mark:{{ end }}'
        title: '{{ if eq .Status "firing" }}:warning: {{ (index .Alerts 0).Labels.severity | toUpper }}{{ else }}:white_check_mark: RESOLVED{{ end }} | {{ .GroupLabels.alertname }}'
        title_link: '{{ .ExternalURL }}/d/{{ (index .Alerts 0).Labels.project }}-api-overview?orgId=1&from=now-1h&to=now'
        text: >-
          {{ range .Alerts }}
          *Service:* `{{ .Labels.job }}`
          *Project:* {{ .Labels.project }}
          *Severity:* {{ .Labels.severity }}
          *Summary:* {{ .Annotations.summary }}
          *Description:* {{ .Annotations.description }}
          {{ if .Annotations.runbook_url }}:book: <{{ .Annotations.runbook_url }}|View Runbook>{{ end }}
          ---
          {{ end }}
        footer: 'AlertManager | {{ .Status | toUpper }} at {{ (index .Alerts 0).StartsAt.Format "2006-01-02 15:04 MST" }}'
        actions:
          - type: button
            text: ':bar_chart: Dashboard'
            url: '{{ .ExternalURL }}/d/{{ (index .Alerts 0).Labels.project }}-api-overview?orgId=1&from=now-1h&to=now'
          - type: button
            text: ':scroll: Logs'
            url: '{{ .ExternalURL }}/d/{{ (index .Alerts 0).Labels.project }}-logs?orgId=1&from=now-1h&to=now'
          - type: button
            text: ':mag: Traces'
            url: '{{ .ExternalURL }}/d/{{ (index .Alerts 0).Labels.project }}-traces?orgId=1&from=now-1h&to=now'
%{ endif ~}
%{ if aiops_webhook_url != "" ~}
    webhook_configs:
      - url: '${aiops_webhook_url}'
        send_resolved: true
        max_alerts: 5
%{ endif ~}

  - name: 'critical'
%{ if slack_webhook_url != "" ~}
    slack_configs:
      - channel: '#observability-alerts'
        send_resolved: true
        color: '{{ if eq .Status "firing" }}danger{{ else }}good{{ end }}'
        icon_emoji: '{{ if eq .Status "firing" }}:rotating_light:{{ else }}:white_check_mark:{{ end }}'
        title: '{{ if eq .Status "firing" }}:fire: CRITICAL{{ else }}:white_check_mark: RESOLVED{{ end }} | {{ .GroupLabels.alertname }}'
        title_link: '{{ .ExternalURL }}/d/{{ (index .Alerts 0).Labels.project }}-api-overview?orgId=1&from=now-1h&to=now'
        text: >-
          {{ range .Alerts }}
          *Service:* `{{ .Labels.job }}`
          *Project:* {{ .Labels.project }}
          *Summary:* {{ .Annotations.summary }}
          *Description:* {{ .Annotations.description }}
          {{ if .Annotations.runbook_url }}:book: <{{ .Annotations.runbook_url }}|View Runbook>{{ end }}
          ---
          {{ end }}
        footer: 'AlertManager | {{ .Status | toUpper }} at {{ (index .Alerts 0).StartsAt.Format "2006-01-02 15:04 MST" }}'
        actions:
          - type: button
            text: ':bar_chart: Dashboard'
            url: '{{ .ExternalURL }}/d/{{ (index .Alerts 0).Labels.project }}-api-overview?orgId=1&from=now-1h&to=now'
          - type: button
            text: ':scroll: Logs'
            url: '{{ .ExternalURL }}/d/{{ (index .Alerts 0).Labels.project }}-logs?orgId=1&from=now-1h&to=now'
          - type: button
            text: ':mag: Traces'
            url: '{{ .ExternalURL }}/d/{{ (index .Alerts 0).Labels.project }}-traces?orgId=1&from=now-1h&to=now'
%{ endif ~}
%{ if aiops_webhook_url != "" ~}
    webhook_configs:
      - url: '${aiops_webhook_url}'
        send_resolved: true
        max_alerts: 5
%{ endif ~}

  - name: 'warning'
%{ if slack_webhook_url != "" ~}
    slack_configs:
      - channel: '#observability-alerts'
        send_resolved: true
        color: '{{ if eq .Status "firing" }}warning{{ else }}good{{ end }}'
        icon_emoji: '{{ if eq .Status "firing" }}:warning:{{ else }}:white_check_mark:{{ end }}'
        title: '{{ if eq .Status "firing" }}:large_orange_diamond: WARNING{{ else }}:white_check_mark: RESOLVED{{ end }} | {{ .GroupLabels.alertname }}'
        title_link: '{{ .ExternalURL }}/d/{{ (index .Alerts 0).Labels.project }}-api-overview?orgId=1&from=now-1h&to=now'
        text: >-
          {{ range .Alerts }}
          *Service:* `{{ .Labels.job }}`
          *Project:* {{ .Labels.project }}
          *Summary:* {{ .Annotations.summary }}
          *Description:* {{ .Annotations.description }}
          {{ if .Annotations.runbook_url }}:book: <{{ .Annotations.runbook_url }}|View Runbook>{{ end }}
          ---
          {{ end }}
        footer: 'AlertManager | {{ .Status | toUpper }} at {{ (index .Alerts 0).StartsAt.Format "2006-01-02 15:04 MST" }}'
        actions:
          - type: button
            text: ':bar_chart: Dashboard'
            url: '{{ .ExternalURL }}/d/{{ (index .Alerts 0).Labels.project }}-api-overview?orgId=1&from=now-1h&to=now'
          - type: button
            text: ':scroll: Logs'
            url: '{{ .ExternalURL }}/d/{{ (index .Alerts 0).Labels.project }}-logs?orgId=1&from=now-1h&to=now'
          - type: button
            text: ':mag: Traces'
            url: '{{ .ExternalURL }}/d/{{ (index .Alerts 0).Labels.project }}-traces?orgId=1&from=now-1h&to=now'
%{ endif ~}
%{ if aiops_webhook_url != "" ~}
    webhook_configs:
      - url: '${aiops_webhook_url}'
        send_resolved: true
        max_alerts: 5
%{ endif ~}

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname']
