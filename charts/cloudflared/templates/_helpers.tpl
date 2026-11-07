{{/*
Chart name, optionally overridden.
*/}}
{{- define "cloudflared.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Full resource name.
*/}}
{{- define "cloudflared.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
helm.sh/chart label.
*/}}
{{- define "cloudflared.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels.
*/}}
{{- define "cloudflared.labels" -}}
helm.sh/chart: {{ include "cloudflared.chart" . }}
{{ include "cloudflared.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels (stable over time).
*/}}
{{- define "cloudflared.selectorLabels" -}}
app.kubernetes.io/name: {{ include "cloudflared.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
ServiceAccount name.
*/}}
{{- define "cloudflared.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "cloudflared.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Tunnel operating mode: "token" or "config".
*/}}
{{- define "cloudflared.mode" -}}
{{- if or .Values.tunnel.token .Values.tunnel.existingSecret -}}
token
{{- else if or .Values.config.enabled .Values.config.existingConfigMap -}}
config
{{- else -}}
invalid
{{- end -}}
{{- end }}

{{/*
Name of the Secret holding the tunnel token.
*/}}
{{- define "cloudflared.tokenSecretName" -}}
{{- default (printf "%s-token" (include "cloudflared.fullname" .)) .Values.tunnel.existingSecret }}
{{- end }}

{{/*
Name of the Secret holding the tunnel credentials.
*/}}
{{- define "cloudflared.credentialsSecretName" -}}
{{- default (printf "%s-credentials" (include "cloudflared.fullname" .)) .Values.config.credentials.existingSecret }}
{{- end }}

{{/*
Name of the ConfigMap holding config.yaml.
*/}}
{{- define "cloudflared.configMapName" -}}
{{- default (printf "%s-config" (include "cloudflared.fullname" .)) .Values.config.existingConfigMap }}
{{- end }}

{{/*
Grafana dashboard UID, unique per release (Grafana limits UIDs to 40 characters).
The default release name "cloudflared" yields "cloudflared-overview".
*/}}
{{- define "cloudflared.dashboardUID" -}}
{{- $uid := printf "%s-overview" (include "cloudflared.fullname" .) -}}
{{- if gt (len $uid) 40 -}}
{{- printf "%s-%s" (trunc 31 $uid | trimSuffix "-") (sha256sum $uid | trunc 8) -}}
{{- else -}}
{{- $uid -}}
{{- end -}}
{{- end }}

{{/*
Grafana dashboard title, unique per release.
*/}}
{{- define "cloudflared.dashboardTitle" -}}
{{- if eq (include "cloudflared.fullname" .) .Chart.Name -}}
Cloudflared / Tunnel overview
{{- else -}}
Cloudflared / Tunnel overview ({{ include "cloudflared.fullname" . }})
{{- end -}}
{{- end }}
